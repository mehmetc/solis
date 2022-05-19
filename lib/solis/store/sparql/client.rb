require 'connection_pool'
require 'sparql'
require_relative 'client/query'

module Solis
  module Store
    module Sparql
      class Client
        def initialize(endpoint, graph_name)
          @endpoint = endpoint
          @graph_name = graph_name

          @pool = ConnectionPool.new(size:5, timeout: 30) do
            SPARQL::Client.new(@endpoint, graph: @graph_name)
            #SPARQL::Client.new(@endpoint)
          end
        end

        def up?
          result = nil
          @pool.with do |c|
            result = c.query("ASK WHERE { ?s ?p ?o }")
          end
          result
        rescue HTTP::Error => e
          return false
        end

        def query(query)
          raise Solis::Error::NotFoundError, "Server or graph(#{@graph_name} not found" unless up?
          result = nil
          @pool.with do |c|
            result = Query.new(c).run(query)
          end
          result
        end
      end
    end
  end
end