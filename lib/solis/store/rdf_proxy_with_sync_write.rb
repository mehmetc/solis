

require 'sparql'

require_relative 'rdf_operations_runner'
require_relative 'operations_collector'



module Solis
  class Store

    class RDFProxyWithSyncWrite

      include Solis::Store::OperationsCollector

      def initialize(repository, name_graph)
        # all the rest:
        @repository = repository
        @name_graph = name_graph
        # following also for:
        # - Solis::Store::RDFOperationsRunner
        @client_sparql = SPARQL::Client.new(repository, graph: name_graph)
        # following also for:
        # - Solis::Store::OperationsCollector
        @ops = []
      end

      def write
        run_operations_as_rdf(@ops)
        @ops = []
      end


      private

      include Solis::Store::RDFOperationsRunner

    end

  end
end