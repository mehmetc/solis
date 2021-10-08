# $LOAD_PATH << '.' << './lib'
require 'bundler'
Bundler.require

require 'solis'
require 'pp'
require 'json'

Solis::ConfigFile.path = './'
g = Solis::Graph.new(Solis::Shape::Reader::File.read(Solis::ConfigFile[:solis][:shacl]), Solis::ConfigFile[:solis][:env])

schedule = g.shape_as_model('Schedule')

puts schedule.model_template.to_json
