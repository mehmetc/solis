# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "solis"
require "solis/model/writer"
require "solis/validator"
require "solis/utils/jsonld"

require "minitest/autorun"
