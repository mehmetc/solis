# $LOAD_PATH << '.' << './lib'
require 'bundler'
Bundler.require

require 'solis'
require 'pp'
require 'json'

Solis::ConfigFile.path = './'
g = Solis::Graph.new(Solis::Shape::Reader::File.read(Solis::ConfigFile[:solis][:shacl]), Solis::ConfigFile[:solis][:env])

schedule = g.shape_as_model('Schedule')
schedule_resource = g.shape_as_resource('Schedule')
puts schedule.model_template.to_json
begin
  s = schedule_resource.find({id: 123})
  pp s.to_jsonapi
rescue Graphiti::Errors::RecordNotFound
  puts "record not found"
end


