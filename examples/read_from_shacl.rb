# $LOAD_PATH << '.' << './lib'
require 'bundler'
Bundler.require

require 'solis'
require 'pp'

Solis::ConfigFile.path = './'
g = Solis::Graph.new(Solis::Shape::Reader::File.read(Solis::ConfigFile[:shape]), Solis::ConfigFile[:solis])

