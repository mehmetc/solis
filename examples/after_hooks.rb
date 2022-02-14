# $LOAD_PATH << '.' << './lib'
require 'bundler'
Bundler.require

require 'solis'
require 'pp'
require 'json'

Solis::ConfigFile.path = './'
g = Solis::Graph.new(Solis::Shape::Reader::File.read(Solis::ConfigFile[:solis][:shacl]),
                     Solis::ConfigFile[:solis][:env].merge(
                       hooks: {
                         create: { before: lambda { |m, d| puts "before-=-=-=-=-=->"},
                                   after: lambda { |m, d| puts "after-=-=-=-=->" } }
                       })
)

# Skill.model_before_create do |model, graph|
#   puts "---------BEFORE"
# end

s = Skill.new({ id: 5, short_label: 'a short label', label: 'a label' })

s.save