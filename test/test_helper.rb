$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "solis"
Solis::ConfigFile.path = './test/resources'
require "minitest/autorun"
#require 'webmock/minitest'
