require "bundler"
Bundler.require

require 'ostruct'
require 'logger'
require "solis/version"
require 'solis/config_file'
require "solis/error"
require 'solis/rdf_edtf_literal'
require 'solis/graph'
require 'solis/shape'

module Solis
  LOGGER = Logger.new(STDOUT)
end
