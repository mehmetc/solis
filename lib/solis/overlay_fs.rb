require 'pathname'
require 'fileutils'
require 'set'
require 'digest'
require 'monitor'
require 'tempfile'
require 'forwardable'

module Solis
  class OverlayFS
    WHITEOUT_PREFIX = '.wh.'
    OPAQUE_MARKER = '.wh..wh..opq'

    class Error < StandardError; end
    class LayerError < Error; end
    class ReadOnlyError < Error; end

    # IO wrapper that handles copy-up on write
    class OverlayIO
      extend Forwardable

      def_delegators :@io, :read, :gets, :getc, :getbyte, :readlines, :readline,
                     :each, :each_line, :each_byte, :each_char, :eof?, :eof,
                     :pos, :pos=, :seek, :rewind, :tell, :lineno, :lineno=,
                     :sync, :sync=, :binmode, :binmode?, :close_read,
                     :external_encoding, :internal_encoding, :set_encoding

      def initialize(io, overlay_fs: nil, relative_path: nil, mode: 'r')
        @io = io
        @overlay_fs = overlay_fs
        @relative_path = relative_path
        @mode = mode
        @copied_up = false
      end

      def write(data)
        ensure_copy_up if @overlay_fs && !@copied_up
        @io.write(data)
      end

      def puts(*args)
        ensure_copy_up if @overlay_fs && !@copied_up
        @io.puts(*args)
      end

      def print(*args)
        ensure_copy_up if @overlay_fs && !@copied_up
        @io.print(*args)
      end

      def printf(*args)
        ensure_copy_up if @overlay_fs && !@copied_up
        @io.printf(*args)
      end

      def <<(data)
        ensure_copy_up if @overlay_fs && !@copied_up
        @io << data
        self
      end

      def flush
        @io.flush
      end

      def close
        @io.close
      end

      def closed?
        @io.closed?
      end

      def close_write
        @io.close_write
      end

      def path
        @io.respond_to?(:path) ? @io.path : nil
      end

      def to_io
        @io
      end

      private

      def ensure_copy_up
        return if @copied_up
        return unless @overlay_fs && @relative_path

        current_pos = @io.pos rescue 0
        @io.close unless @io.closed?

        new_path = @overlay_fs.copy_up(@relative_path)
        @io = File.open(new_path, @mode)
        @io.pos = current_pos
        @copied_up = true
      end
    end

    # Stat wrapper for overlay files
    class OverlayStat
      attr_reader :layer, :real_path, :relative_path

      def initialize(real_stat, layer:, real_path:, relative_path:)
        @stat = real_stat
        @layer = layer
        @real_path = real_path
        @relative_path = relative_path
      end

      # Delegate all stat methods
      %i[
        atime blksize blockdev? blocks chardev? ctime dev dev_major dev_minor
        directory? executable? executable_real? file? ftype gid grpowned? ino
        mode mtime nlink owned? pipe? rdev rdev_major rdev_minor readable?
        readable_real? setgid? setuid? size size? socket? sticky? symlink?
        uid world_readable? world_writable? writable? writable_real? zero?
      ].each do |method|
        define_method(method) { @stat.send(method) }
      end

      def to_s
        "#<OverlayStat #{@relative_path} (#{@layer})>"
      end
      alias inspect to_s
    end

    # Directory entry for enumeration
    Entry = Struct.new(:name, :path, :relative_path, :layer, :type, keyword_init: true) do
      def file?
        type == :file
      end

      def directory?
        type == :directory
      end

      def symlink?
        type == :symlink
      end
    end

    # Event hooks
    class Hooks
      def initialize
        @callbacks = Hash.new { |h, k| h[k] = [] }
      end

      def on(event, &block)
        @callbacks[event] << block
      end

      def trigger(event, **args)
        @callbacks[event].each { |cb| cb.call(**args) }
      end

      def clear(event = nil)
        event ? @callbacks.delete(event) : @callbacks.clear
      end
    end

    attr_reader :layers, :hooks

    def initialize(cache: true)
      @layers = []
      @cache_enabled = cache
      @resolve_cache = {}
      @stat_cache = {}
      @monitor = Monitor.new
      @hooks = Hooks.new
    end

    # --- Layer Management ---

    def add_layer(path, writable: false, label: nil)
      @monitor.synchronize do
        path = Pathname.new(path).expand_path

        layer = {
          path: path,
          writable: writable,
          label: label || path.basename.to_s
        }

        writable ? @layers.unshift(layer) : @layers.push(layer)
        clear_cache
      end
      self
    end

    def remove_layer(label_or_path)
      @monitor.synchronize do
        @layers.reject! do |layer|
          layer[:label] == label_or_path || layer[:path].to_s == label_or_path.to_s
        end
        clear_cache
      end
      self
    end

    def writable_layer
      @layers.find { |l| l[:writable] }
    end

    def readonly_layers
      @layers.reject { |l| l[:writable] }
    end

    # --- Path Resolution ---

    def resolve(relative_path)
      relative_path = normalize_path(relative_path)

      return @resolve_cache[relative_path] if @cache_enabled && @resolve_cache.key?(relative_path)

      result = @monitor.synchronize do
        @layers.each do |layer|
          # Check for whiteout first
          whiteout_path = layer[:path] / whiteout_name(relative_path)
          return nil if whiteout_path.exist?

          # Check for opaque parent directory
          return nil if opaque_parent?(layer, relative_path)

          full_path = layer[:path] / relative_path
          return full_path if full_path.exist? || full_path.symlink?
        end
        nil
      end

      @resolve_cache[relative_path] = result if @cache_enabled
      result
    end

    def writable_path(relative_path)
      layer = writable_layer
      raise ReadOnlyError, "No writable layer configured" unless layer
      layer[:path] / normalize_path(relative_path)
    end

    def real_path(relative_path)
      resolve(relative_path)&.realpath
    end

    # --- File Operations ---

    def read(relative_path, **options)
      path = resolve(relative_path)
      raise Errno::ENOENT, relative_path unless path
      hooks.trigger(:before_read, path: relative_path)
      content = File.read(path, **options)
      hooks.trigger(:after_read, path: relative_path, content: content)
      content
    end

    def read_binary(relative_path)
      read(relative_path, mode: 'rb')
    end

    def write(relative_path, content, **options)
      relative_path = normalize_path(relative_path)
      hooks.trigger(:before_write, path: relative_path, content: content)

      path = writable_path(relative_path)
      ensure_directory(path.dirname)
      remove_whiteout(relative_path)

      File.write(path, content, **options)
      clear_cache_for(relative_path)

      hooks.trigger(:after_write, path: relative_path, real_path: path)
      path
    end

    def write_binary(relative_path, content)
      write(relative_path, content, mode: 'wb')
    end

    def append(relative_path, content)
      if exist?(relative_path)
        copy_up(relative_path)
      end

      path = writable_path(relative_path)
      ensure_directory(path.dirname)
      File.open(path, 'a') { |f| f.write(content) }
      clear_cache_for(relative_path)
      path
    end

    def atomic_write(relative_path, content, **options)
      relative_path = normalize_path(relative_path)
      path = writable_path(relative_path)
      ensure_directory(path.dirname)

      temp_path = "#{path}.tmp.#{Process.pid}.#{Thread.current.object_id}"
      begin
        File.write(temp_path, content, **options)
        File.rename(temp_path, path)
        remove_whiteout(relative_path)
        clear_cache_for(relative_path)
        hooks.trigger(:after_write, path: relative_path, real_path: path)
        path
      rescue
        File.unlink(temp_path) if File.exist?(temp_path)
        raise
      end
    end

    def open(relative_path, mode = 'r', **options, &block)
      relative_path = normalize_path(relative_path)
      writing = mode_writable?(mode)

      if writing
        if exist?(relative_path) && !in_writable_layer?(relative_path)
          # Copy-up needed, but defer until actual write
          path = resolve(relative_path)
          io = OverlayIO.new(
            File.open(path, readable_mode(mode), **options),
            overlay_fs: self,
            relative_path: relative_path,
            mode: mode
          )
        else
          path = writable_path(relative_path)
          ensure_directory(path.dirname)
          remove_whiteout(relative_path)
          io = OverlayIO.new(File.open(path, mode, **options))
        end
      else
        path = resolve(relative_path)
        raise Errno::ENOENT, relative_path unless path
        io = OverlayIO.new(File.open(path, mode, **options))
      end

      if block_given?
        begin
          yield io
        ensure
          io.close unless io.closed?
          clear_cache_for(relative_path) if writing
        end
      else
        io
      end
    end

    # --- Existence & Type Checks ---

    def exist?(relative_path)
      !resolve(relative_path).nil?
    end
    alias exists? exist?

    def file?(relative_path)
      path = resolve(relative_path)
      path&.file?
    end

    def directory?(relative_path)
      relative_path = normalize_path(relative_path)

      @layers.any? do |layer|
        whiteout = layer[:path] / whiteout_name(relative_path)
        next false if whiteout.exist?

        dir_path = layer[:path] / relative_path
        dir_path.directory?
      end
    end

    def symlink?(relative_path)
      path = resolve(relative_path)
      path&.symlink?
    end

    def readable?(relative_path)
      path = resolve(relative_path)
      path&.readable?
    end

    def writable?(relative_path)
      return false unless writable_layer

      if exist?(relative_path)
        in_writable_layer?(relative_path) || copy_up_possible?(relative_path)
      else
        true  # Can create new file
      end
    end

    def executable?(relative_path)
      path = resolve(relative_path)
      path&.executable?
    end

    def empty?(relative_path)
      if directory?(relative_path)
        entries(relative_path).empty?
      elsif file?(relative_path)
        size(relative_path) == 0
      else
        raise Errno::ENOENT, relative_path
      end
    end

    # --- File Info ---

    def stat(relative_path)
      relative_path = normalize_path(relative_path)

      return @stat_cache[relative_path] if @cache_enabled && @stat_cache.key?(relative_path)

      @layers.each do |layer|
        whiteout = layer[:path] / whiteout_name(relative_path)
        return nil if whiteout.exist?

        full_path = layer[:path] / relative_path
        if full_path.exist? || full_path.symlink?
          stat = OverlayStat.new(
            full_path.stat,
            layer: layer[:label],
            real_path: full_path,
            relative_path: relative_path
          )
          @stat_cache[relative_path] = stat if @cache_enabled
          return stat
        end
      end
      nil
    end

    def lstat(relative_path)
      relative_path = normalize_path(relative_path)

      @layers.each do |layer|
        whiteout = layer[:path] / whiteout_name(relative_path)
        return nil if whiteout.exist?

        full_path = layer[:path] / relative_path
        if full_path.exist? || full_path.symlink?
          return OverlayStat.new(
            full_path.lstat,
            layer: layer[:label],
            real_path: full_path,
            relative_path: relative_path
          )
        end
      end
      nil
    end

    def size(relative_path)
      stat(relative_path)&.size || raise(Errno::ENOENT, relative_path)
    end

    def mtime(relative_path)
      stat(relative_path)&.mtime || raise(Errno::ENOENT, relative_path)
    end

    def atime(relative_path)
      stat(relative_path)&.atime || raise(Errno::ENOENT, relative_path)
    end

    def ctime(relative_path)
      stat(relative_path)&.ctime || raise(Errno::ENOENT, relative_path)
    end

    def ftype(relative_path)
      path = resolve(relative_path)
      raise Errno::ENOENT, relative_path unless path
      path.ftype
    end

    def extname(relative_path)
      File.extname(relative_path)
    end

    def basename(relative_path, suffix = nil)
      suffix ? File.basename(relative_path, suffix) : File.basename(relative_path)
    end

    def dirname(relative_path)
      File.dirname(relative_path)
    end

    def checksum(relative_path, algorithm: :sha256)
      content = read_binary(relative_path)
      case algorithm
      when :md5    then Digest::MD5.hexdigest(content)
      when :sha1   then Digest::SHA1.hexdigest(content)
      when :sha256 then Digest::SHA256.hexdigest(content)
      when :sha512 then Digest::SHA512.hexdigest(content)
      else raise ArgumentError, "Unknown algorithm: #{algorithm}"
      end
    end

    # --- Directory Operations ---

    def mkdir(relative_path, mode: 0755)
      relative_path = normalize_path(relative_path)
      path = writable_path(relative_path)

      raise Errno::EEXIST, relative_path if directory?(relative_path)

      remove_whiteout(relative_path)
      FileUtils.mkdir_p(path, mode: mode)
      clear_cache_for(relative_path)
      hooks.trigger(:after_mkdir, path: relative_path)
      path
    end

    def mkdir_p(relative_path, mode: 0755)
      relative_path = normalize_path(relative_path)
      path = writable_path(relative_path)

      remove_whiteout(relative_path)
      FileUtils.mkdir_p(path, mode: mode)
      clear_cache_for(relative_path)
      path
    end

    def rmdir(relative_path)
      relative_path = normalize_path(relative_path)

      raise Errno::ENOENT, relative_path unless directory?(relative_path)
      raise Errno::ENOTEMPTY, relative_path unless empty?(relative_path)

      if in_writable_layer?(relative_path)
        FileUtils.rmdir(writable_path(relative_path))
      end

      # If exists in lower layers, create whiteout
      if exists_in_lower_layers?(relative_path)
        create_whiteout(relative_path)
      end

      clear_cache_for(relative_path)
      hooks.trigger(:after_rmdir, path: relative_path)
    end

    def entries(relative_path = '.')
      relative_path = normalize_path(relative_path)
      seen = Set.new
      whiteouts = Set.new
      result = []

      @layers.each do |layer|
        dir_path = layer[:path] / relative_path
        next unless dir_path.directory?

        # Check if this directory is opaque - if so, don't descend to lower layers
        opaque = (dir_path / OPAQUE_MARKER).exist?

        dir_path.children.each do |child|
          name = child.basename.to_s

          # Track whiteouts
          if name.start_with?(WHITEOUT_PREFIX)
            if name == OPAQUE_MARKER
              next
            else
              whiteouts << name.sub(WHITEOUT_PREFIX, '')
              next
            end
          end

          next if seen.include?(name)
          next if whiteouts.include?(name)

          seen << name
          result << Entry.new(
            name: name,
            path: child,
            relative_path: "#{relative_path}/#{name}".sub(%r{^\.?/}, ''),
            layer: layer[:label],
            type: entry_type(child)
          )
        end

        break if opaque
      end

      result.sort_by(&:name)
    end

    def children(relative_path = '.')
      entries(relative_path).map(&:name)
    end

    def glob(pattern, flags: 0)
      pattern = normalize_path(pattern)
      seen = Set.new
      whiteouts = collect_whiteouts
      results = []

      @layers.each do |layer|
        Dir.glob(layer[:path] / pattern, flags).each do |full_path|
          relative = Pathname.new(full_path).relative_path_from(layer[:path]).to_s

          next if seen.include?(relative)
          next if whiteouts.include?(relative)
          next if File.basename(relative).start_with?(WHITEOUT_PREFIX)

          seen << relative
          results << relative
        end
      end

      results.sort
    end

    def find(relative_path = '.', &block)
      results = []
      _find_recursive(normalize_path(relative_path), results, &block)
      results
    end

    def each_file(pattern = '**/*', &block)
      return enum_for(:each_file, pattern) unless block_given?

      glob(pattern).each do |relative_path|
        next unless file?(relative_path)
        yield relative_path, resolve(relative_path)
      end
    end

    def each_directory(relative_path = '.', &block)
      return enum_for(:each_directory, relative_path) unless block_given?

      entries(relative_path).each do |entry|
        yield entry if entry.directory?
      end
    end

    # --- File Manipulation ---

    def copy_up(relative_path)
      relative_path = normalize_path(relative_path)

      return writable_path(relative_path) if in_writable_layer?(relative_path)

      source = resolve(relative_path)
      raise Errno::ENOENT, relative_path unless source

      dest = writable_path(relative_path)
      ensure_directory(dest.dirname)

      if source.directory?
        FileUtils.mkdir_p(dest)
        # Copy directory metadata
        FileUtils.chmod(source.stat.mode, dest)
      elsif source.symlink?
        FileUtils.ln_s(File.readlink(source), dest)
      else
        FileUtils.cp(source, dest, preserve: true)
      end

      clear_cache_for(relative_path)
      hooks.trigger(:after_copy_up, path: relative_path, from: source, to: dest)
      dest
    end

    def copy(source, destination, preserve: true)
      source = normalize_path(source)
      destination = normalize_path(destination)

      source_path = resolve(source)
      raise Errno::ENOENT, source unless source_path

      dest_path = writable_path(destination)
      ensure_directory(dest_path.dirname)
      remove_whiteout(destination)

      if source_path.directory?
        copy_directory(source, destination, preserve: preserve)
      else
        FileUtils.cp(source_path, dest_path, preserve: preserve)
      end

      clear_cache_for(destination)
      dest_path
    end

    def move(source, destination)
      source = normalize_path(source)
      destination = normalize_path(destination)

      copy(source, destination, preserve: true)
      delete(source)

      writable_path(destination)
    end
    alias rename move

    def delete(relative_path, force: false)
      relative_path = normalize_path(relative_path)

      unless exist?(relative_path)
        raise Errno::ENOENT, relative_path unless force
        return
      end

      hooks.trigger(:before_delete, path: relative_path)

      if in_writable_layer?(relative_path)
        full_path = writable_path(relative_path)
        if full_path.directory?
          FileUtils.rm_rf(full_path)
        else
          FileUtils.rm(full_path)
        end
      end

      # Create whiteout if exists in lower layers
      if exists_in_lower_layers?(relative_path)
        create_whiteout(relative_path)
      end

      clear_cache_for(relative_path)
      hooks.trigger(:after_delete, path: relative_path)
    end
    alias rm delete
    alias unlink delete

    def delete_recursive(relative_path)
      relative_path = normalize_path(relative_path)

      if directory?(relative_path)
        entries(relative_path).each do |entry|
          delete_recursive(entry.relative_path)
        end
      end

      delete(relative_path)
    end
    alias rm_rf delete_recursive

    # --- Symlinks ---

    def symlink(target, link_path)
      link_path = normalize_path(link_path)
      path = writable_path(link_path)

      ensure_directory(path.dirname)
      remove_whiteout(link_path)

      FileUtils.ln_s(target, path)
      clear_cache_for(link_path)
      path
    end
    alias ln_s symlink

    def readlink(relative_path)
      path = resolve(relative_path)
      raise Errno::ENOENT, relative_path unless path
      raise Errno::EINVAL, relative_path unless path.symlink?
      File.readlink(path)
    end

    def realpath(relative_path)
      path = resolve(relative_path)
      raise Errno::ENOENT, relative_path unless path
      path.realpath
    end

    # --- Whiteouts & Opaque Directories ---

    def whiteout?(relative_path)
      relative_path = normalize_path(relative_path)

      @layers.any? do |layer|
        (layer[:path] / whiteout_name(relative_path)).exist?
      end
    end

    def create_whiteout(relative_path)
      relative_path = normalize_path(relative_path)
      whiteout = writable_path(whiteout_name(relative_path))
      ensure_directory(whiteout.dirname)
      FileUtils.touch(whiteout)
      clear_cache_for(relative_path)
    end

    def remove_whiteout(relative_path)
      relative_path = normalize_path(relative_path)
      whiteout = writable_path(whiteout_name(relative_path))
      FileUtils.rm(whiteout) if whiteout.exist?
      clear_cache_for(relative_path)
    end

    def make_opaque(relative_path)
      relative_path = normalize_path(relative_path)
      dir_path = writable_path(relative_path)

      ensure_directory(dir_path)
      FileUtils.touch(dir_path / OPAQUE_MARKER)
      clear_cache_for(relative_path)
    end

    def remove_opaque(relative_path)
      relative_path = normalize_path(relative_path)
      opaque = writable_path(relative_path) / OPAQUE_MARKER
      FileUtils.rm(opaque) if opaque.exist?
      clear_cache_for(relative_path)
    end

    def opaque?(relative_path)
      relative_path = normalize_path(relative_path)

      @layers.any? do |layer|
        (layer[:path] / relative_path / OPAQUE_MARKER).exist?
      end
    end

    # --- Permissions ---

    def chmod(mode, relative_path)
      relative_path = normalize_path(relative_path)
      copy_up(relative_path) unless in_writable_layer?(relative_path)
      FileUtils.chmod(mode, writable_path(relative_path))
      clear_cache_for(relative_path)
    end

    def chown(user, group, relative_path)
      relative_path = normalize_path(relative_path)
      copy_up(relative_path) unless in_writable_layer?(relative_path)
      FileUtils.chown(user, group, writable_path(relative_path))
      clear_cache_for(relative_path)
    end

    def touch(relative_path, mtime: nil)
      relative_path = normalize_path(relative_path)

      if exist?(relative_path)
        copy_up(relative_path) unless in_writable_layer?(relative_path)
        path = writable_path(relative_path)
      else
        path = writable_path(relative_path)
        ensure_directory(path.dirname)
        remove_whiteout(relative_path)
      end

      if mtime
        FileUtils.touch(path, mtime: mtime)
      else
        FileUtils.touch(path)
      end

      clear_cache_for(relative_path)
      path
    end

    # --- Comparison ---

    def identical?(path1, path2)
      resolved1 = resolve(path1)
      resolved2 = resolve(path2)

      return false unless resolved1 && resolved2
      FileUtils.identical?(resolved1, resolved2)
    end

    def diff(relative_path)
      relative_path = normalize_path(relative_path)
      versions = []

      @layers.each do |layer|
        full_path = layer[:path] / relative_path
        if full_path.exist? && full_path.file?
          versions << {
            layer: layer[:label],
            path: full_path,
            content: full_path.read,
            mtime: full_path.mtime,
            size: full_path.size
          }
        end
      end

      versions
    end

    # --- Cache Management ---

    def clear_cache
      @monitor.synchronize do
        @resolve_cache.clear
        @stat_cache.clear
      end
    end

    def clear_cache_for(relative_path)
      @monitor.synchronize do
        relative_path = normalize_path(relative_path)
        @resolve_cache.delete(relative_path)
        @stat_cache.delete(relative_path)

        # Also clear parent directories
        parts = relative_path.split('/')
        parts.length.times do |i|
          parent = parts[0...i].join('/')
          @resolve_cache.delete(parent)
          @stat_cache.delete(parent)
        end
      end
    end

    def cache_stats
      {
        resolve_cache_size: @resolve_cache.size,
        stat_cache_size: @stat_cache.size,
        cache_enabled: @cache_enabled
      }
    end

    # --- Layer Inspection ---

    def which_layer(relative_path)
      relative_path = normalize_path(relative_path)

      @layers.each do |layer|
        whiteout = layer[:path] / whiteout_name(relative_path)
        return nil if whiteout.exist?

        full_path = layer[:path] / relative_path
        return layer[:label] if full_path.exist?
      end
      nil
    end

    def in_writable_layer?(relative_path)
      layer = writable_layer
      return false unless layer
      (layer[:path] / normalize_path(relative_path)).exist?
    end

    def exists_in_lower_layers?(relative_path)
      relative_path = normalize_path(relative_path)

      readonly_layers.any? do |layer|
        (layer[:path] / relative_path).exist?
      end
    end

    def all_versions(relative_path)
      relative_path = normalize_path(relative_path)

      @layers.filter_map do |layer|
        full_path = layer[:path] / relative_path
        next unless full_path.exist?

        {
          layer: layer[:label],
          path: full_path,
          writable: layer[:writable]
        }
      end
    end

    # --- Utility ---

    def to_s
      layers_desc = @layers.map { |l| "#{l[:label]}#{l[:writable] ? ' (rw)' : ''}" }
      "#<OverlayFS layers=[#{layers_desc.join(' -> ')}]>"
    end
    alias inspect to_s

    def [](relative_path)
      resolve(relative_path)
    end

    def tree(relative_path = '.', depth: nil, prefix: '')
      output = []
      _tree_recursive(normalize_path(relative_path), output, depth, prefix, 0)
      output.join("\n")
    end

    private

    def normalize_path(path)
      path.to_s.sub(%r{^\.?/}, '').sub(%r{/$}, '')
    end

    def whiteout_name(relative_path)
      dir = File.dirname(relative_path)
      name = File.basename(relative_path)
      dir == '.' ? "#{WHITEOUT_PREFIX}#{name}" : "#{dir}/#{WHITEOUT_PREFIX}#{name}"
    end

    def ensure_directory(path)
      FileUtils.mkdir_p(path) unless path.exist?
    end

    def entry_type(path)
      if path.symlink?
        :symlink
      elsif path.directory?
        :directory
      else
        :file
      end
    end

    def mode_writable?(mode)
      mode.include?('w') || mode.include?('a') || mode.include?('+')
    end

    def readable_mode(mode)
      mode.gsub(/[wa+]/, 'r').gsub(/rr+/, 'r')
    end

    def opaque_parent?(layer, relative_path)
      parts = relative_path.split('/')
      parts[0...-1].each_with_index do |_, i|
        parent = parts[0..i].join('/')
        return true if (layer[:path] / parent / OPAQUE_MARKER).exist?
      end
      false
    end

    def collect_whiteouts
      whiteouts = Set.new

      @layers.each do |layer|
        Dir.glob(layer[:path] / '**' / "#{WHITEOUT_PREFIX}*").each do |path|
          name = File.basename(path)
          next if name == OPAQUE_MARKER

          relative_dir = Pathname.new(path).dirname.relative_path_from(layer[:path]).to_s
          original_name = name.sub(WHITEOUT_PREFIX, '')

          whiteouts << (relative_dir == '.' ? original_name : "#{relative_dir}/#{original_name}")
        end
      end

      whiteouts
    end

    def copy_up_possible?(relative_path)
      resolve(relative_path) && writable_layer
    end

    def copy_directory(source, destination, preserve: true)
      mkdir_p(destination)

      entries(source).each do |entry|
        src_path = "#{source}/#{entry.name}"
        dst_path = "#{destination}/#{entry.name}"

        if entry.directory?
          copy_directory(src_path, dst_path, preserve: preserve)
        else
          copy(src_path, dst_path, preserve: preserve)
        end
      end
    end

    def _find_recursive(relative_path, results, &block)
      entries(relative_path).each do |entry|
        if block_given?
          next unless yield(entry)
        end

        results << entry.relative_path

        if entry.directory?
          _find_recursive(entry.relative_path, results, &block)
        end
      end
    end

    def _tree_recursive(relative_path, output, max_depth, prefix, current_depth)
      return if max_depth && current_depth >= max_depth

      items = entries(relative_path)
      items.each_with_index do |entry, index|
        is_last = index == items.length - 1
        connector = is_last ? '└── ' : '├── '
        layer_info = " (#{entry.layer})"

        output << "#{prefix}#{connector}#{entry.name}#{layer_info}"

        if entry.directory?
          next_prefix = prefix + (is_last ? '    ' : '│   ')
          _tree_recursive(entry.relative_path, output, max_depth, next_prefix, current_depth + 1)
        end
      end
    end
  end
end