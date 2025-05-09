
require 'sparql'

module Solis
  module Mock

    class SPARQLClientForRollbackTest < SPARQL::Client

      def initialize(repository, graph: nil)
        super(repository, graph: graph)
        @idx = 0
      end

      def insert_data(graph)
        puts "[sparql-client-for-rollback-test] inserting graph at time #{@idx} ..."
        begin
          if @idx == 0
            raise RuntimeError, "[sparql-client-for-rollback-test] cannot insert graph"
          else
            super(graph)
            @idx = 0
          end
        rescue RuntimeError => e
          @idx += 1
          raise RuntimeError, e
        end
      end

    end

  end
end


