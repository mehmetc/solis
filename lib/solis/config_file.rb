#encoding: UTF-8

require 'yaml'

module Solis
class ConfigFile
  @config = {}
  @config_file_path = ''
  @config_file_name = 'config.yml'

  def self.version
    "0.0.4"
  end

  def self.name
    @config_file_name
  end

  def self.name=(config_file_name)
    @config_file_name = config_file_name
  end

  def self.path
    @config_file_path
  end

  def self.path=(config_file_path)
    @config_file_path = File.absolute_path(config_file_path)
  end

  def self.[](key)
    init
    @config[key]
  end

  def self.[]=(key,value)
    init
    @config[key] = value
    File.open("#{path}/#{name}", 'w') do |f|
      f.puts @config.to_yaml
    end
  end

  def self.include?(key)
    init
    @config.include?(key)
  end

  def self.config
    init
    @config
  end

  def self.keys
    init
    @config.keys
  end

  private

  def self.init
    discover_config_file_path
    if @config.empty?
      config = YAML::load_file("#{path}/#{name}", aliases: true)
      @config = process(config)
    end
  end

  def self.discover_config_file_path
    @config_file_path = ENV['CONFIG_FILE_PATH'] || '' if path.nil? || path.empty?
    if @config_file_path.nil? || @config_file_path.empty?
      if File.exist?(@config_file_name)
        @config_file_path = '.'
      elsif File.exist?("config/#{@config_file_name}")
        @config_file_path = 'config'
      end
    end

    @config_file_path = File.expand_path(@config_file_path)
    #puts "#{@config_file_name} found at #{@config_file_path}"
  end

  def self.process(config)
    new_config = {}
    config.each do |k,v|

      if config[k].is_a?(Hash)
        v = process(v)
      end
#      config.delete(k)      
      new_config.store(k.to_sym, v)
    end

    new_config
  end
end
end