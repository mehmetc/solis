require_relative 'rdf_operations_runner'
require_relative 'operations_collector'

module Solis
  class Store
    class Memory
      include Solis::Store::OperationsCollector
      include Solis::Store::RDFOperationsRunner
      def initialize(graph = "http://example.com/")
        @graph = graph
        @store = RDF::Repository.new(graph: @graph)

        @client_sparql = SPARQL::Client.new(@store, graph: @graph)
        @logger = Solis.logger
        @ops = []
      end
    end
  end
end