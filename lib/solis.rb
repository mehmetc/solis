require "bundler"
Bundler.require

require 'logger'
require "solis/version"
require "solis/error"
require 'solis/graph'
require 'solis/shape'
require 'solis/config_file'

module Solis
  LOGGER = Logger.new(STDOUT)
end
