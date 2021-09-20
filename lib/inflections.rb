require 'active_support/all'
require 'json'
require 'lib/config_file'

JSON.parse(File.read(ConfigFile[:inflections])).each do |s,p|
  ActiveSupport::Inflector.inflections.irregular(s, p)
end
