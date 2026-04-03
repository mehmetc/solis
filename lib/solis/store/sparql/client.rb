require 'http'
require 'connection_pool'
require 'sparql'
require_relative 'client/query'

module Solis
  module Store
    module Sparql
      class Client
        def initialize(endpoint, options = {})
          @endpoint = endpoint
          @graph_name = options[:graph_name] || ''
          @read_timeout = options[:read_timeout] || 120
          @logger = options[:logger] || Solis::LOGGER

            @pool = ConnectionPool.new(size:5, timeout: 160) do
              Solis::LOGGER.level = Logger::DEBUG if ConfigFile[:debug]

              if @graph_name
                client = SPARQL::Client.new(@endpoint, graph: @graph_name, read_timeout: @read_timeout, logger: @logger)
              else
                client = SPARQL::Client.new(@endpoint, read_timeout: @read_timeout, logger: @logger)
              end

              client
          end
        end

        def up?
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          if @up_checked_at && (now - @up_checked_at) < 30
            return @up_result
          end
          @up_result = nil
          @pool.with do |c|
            @up_result = c.query("ASK WHERE { ?s ?p ?o }")
          end
          @up_checked_at = now
          @up_result
        rescue HTTP::Error => e
          @up_checked_at = nil
          return false
        end

        def query(query, options = {})
          raise Solis::Error::NotFoundError, "Server or graph(#{@graph_name} not found" unless up?
          result = nil
          @pool.with do |c|
            result = Query.new(c).run(query, options)
          end
          result
        end
      end
    end
  end
end