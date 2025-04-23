# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "solis"
require "solis/model/writer"
require "solis/validator/validatorV1"
require "solis/utils/jsonld"
require "solis/model/mock"
require "solis/model/entity"
require "solis/store/proxy"

require "minitest/autorun"
