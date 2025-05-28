# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "solis"
require "solis/model/writer"
require "solis/validator/validatorV1"
require "solis/validator/validatorV2"
require "solis/utils/jsonld"
require "solis/utils/json"
require "solis/utils/rdf"
require "solis/model/entity"
require "solis/store/rdf_proxy"
require "solis/mock/sparql_client"

require "minitest/autorun"
