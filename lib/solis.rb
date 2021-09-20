require "bundler"
Bundler.require

require 'logger'
require "solis/version"
require "solis/error"
require 'solis/graph'
require 'solis/shape'

module Solis
  LOGGER = Logger.new(STDOUT)
end
