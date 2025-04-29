# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "solis"
require "solis/model/writer"
require "solis/validator/validatorV1"
require "solis/validator/validatorV2"
require "solis/utils/jsonld"
require "solis/model/mock"
require "solis/model/entity"
require "solis/store/rdf_proxy_with_sync_write"

require "minitest/autorun"
