require_relative 'sparql_adaptor'

module Solis
  class Resource < ::Graphiti::Resource

    self.abstract_class = true
    self.adapter = Solis::SparqlAdaptor
    self.endpoint_namespace = ''
    self.validate_endpoints = true

    def self.sparql_endpoint
      @sparql_endpoint
    end

    def self.sparql_endpoint=(sparql_endpoint)
      @sparql_endpoint = sparql_endpoint
    end
  end

  class NoopEndpoint
    def initialize(path, action)
      @path = path
      @action = action
    end

    def sideload_allowlist
      @allow_list
    end

    def sideload_allowlist=(val)
      @allow_list = JSONAPI::IncludeDirective.new(val).to_hash
      super(@allow_list)
    end
  end
end
