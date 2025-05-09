

require 'sparql'

require_relative 'rdf_operations_runner'
require_relative 'operations_collector'



module Solis
  class Store

    class RDFProxy

      include Solis::Store::OperationsCollector
      include Solis::Store::RDFOperationsRunner

      def initialize(repository, name_graph)
        # all the rest:
        @repository = repository
        @name_graph = name_graph
        # following also for:
        # - Solis::Store::RDFOperationsRunner
        @client_sparql = SPARQL::Client.new(repository, graph: name_graph)
        # following also for:
        # - Solis::Store::OperationsCollector
        # - Solis::Store::RDFOperationsRunner
        @ops = []
      end

    end

  end
end