#encoding: UTF-8

require 'yaml'

class ConfigFile
  @config = {}
  @config_file_path = ''
  @config_file_name = 'config.yml'

  def self.version
    "0.0.2"
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
    @config_file_path = config_file_path
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

  private

  def self.init
    discover_config_file_path
    if @config.empty?
      config = YAML::load_file("#{path}/#{name}")
      @config = process(config)
    end
  end

  def self.discover_config_file_path
    if @config_file_path.nil? || @config_file_path.empty?
      if File.exist?(@config_file_name)
        @config_file_path = '.'
      elsif File.exist?("config/#{@config_file_name}")
        @config_file_path = 'config'
      end
    end
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