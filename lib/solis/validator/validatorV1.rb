
require 'linkeddata'
require 'shacl'
require 'json/ld'

module Solis
  class SHACLValidatorV1

    def initialize(shacl, format)
      if format.eql?(:ttl)
        graph_shacl = RDF::Graph.new
        graph_shacl.from_ttl(shacl)
      elsif format.eql?(:graph)
        graph_shacl = shacl
      end
      @graph_shacl = graph_shacl
      @validator = SHACL.get_shapes(@graph_shacl)
    end

    def execute(data, format)
      if format.eql?(:jsonld)
        graph_data = RDF::Graph.new << JSON::LD::API.toRdf(data)
      elsif format.eql?(:graph)
        graph_data = data
      end
      report = @validator.execute(graph_data)
      errors = report.results
      messages = errors.map do |e|
        "#{e.focus}, #{e.path}: #{e.message}"
      end
      [report.conform?, messages]
    end

  end
end