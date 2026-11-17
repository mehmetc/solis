require 'http'
require 'connection_pool'
require 'sparql'
require_relative 'client/query'

module Solis
  module Store
    module Sparql
      # Thin wrapper around a process-wide pool of SPARQL::Client instances.
      #
      # Every SPARQL::Client over HTTP owns a Net::HTTP::Persistent keep-alive
      # connection that is only closed by #close or by the garbage collector.
      # Creating clients per request therefore leaks idle connections to the triple
      # store (Virtuoso: "number of licensed connections exceeded"). All instances
      # of this class share one bounded pool per endpoint/graph/read_timeout, so a
      # process never holds more than `pool_size` connections per pool.
      #
      # Pool size: Solis::Options[:sparql_pool_size], else ENV['SOLIS_SPARQL_POOL_SIZE'], else 5.
      # Keep it at or slightly above the number of request threads (e.g. Puma max threads).
      # connection_pool >= 2.5 rebuilds pools in forked children (Puma workers).
      class Client
        DEFAULT_POOL_SIZE = 5
        DEFAULT_POOL_TIMEOUT = 160
        DEFAULT_READ_TIMEOUT = 120
        UP_CHECK_INTERVAL = 30

        @pools = {}
        @up_checks = {}
        @mutex = Mutex.new

        class << self
          # Shared pool for an endpoint. graph_name nil means: no graph option on the client.
          def pool_for(endpoint, graph_name: nil, read_timeout: DEFAULT_READ_TIMEOUT, logger: nil)
            key = pool_key(endpoint, graph_name, read_timeout)
            @mutex.synchronize do
              @pools[key] ||= ConnectionPool.new(size: pool_size, timeout: DEFAULT_POOL_TIMEOUT) do
                Solis::LOGGER.level = Logger::DEBUG if ConfigFile[:debug]
                options = { read_timeout: read_timeout, logger: logger || Solis::LOGGER }
                options[:graph] = graph_name unless graph_name.nil?
                SPARQL::Client.new(endpoint, **options)
              end
            end
          end

          # Borrow a raw SPARQL::Client from the shared pool. Re-entrant per thread.
          def with(endpoint, graph_name: nil, read_timeout: DEFAULT_READ_TIMEOUT, &block)
            pool_for(endpoint, graph_name: graph_name, read_timeout: read_timeout).with(&block)
          end

          # Close every pooled connection (e.g. on shutdown or in tests).
          def shutdown_all
            pools = @mutex.synchronize do
              current = @pools.values
              @pools = {}
              @up_checks = {}
              current
            end
            pools.each { |pool| pool.shutdown { |client| client.close rescue nil } }
          end

          def pool_count
            @mutex.synchronize { @pools.size }
          end

          def pool_size
            configured = (Solis::Options.instance.get[:sparql_pool_size] rescue nil) || ENV['SOLIS_SPARQL_POOL_SIZE']
            size = configured.to_i
            size > 0 ? size : DEFAULT_POOL_SIZE
          end

          def cached_up(key)
            @mutex.synchronize do
              check = @up_checks[key]
              check && (monotonic_now - check[:at]) < UP_CHECK_INTERVAL ? check : nil
            end
          end

          def store_up(key, result)
            @mutex.synchronize { @up_checks[key] = { at: monotonic_now, result: result } }
          end

          def clear_up(key)
            @mutex.synchronize { @up_checks.delete(key) }
          end

          def pool_key(endpoint, graph_name, read_timeout)
            [endpoint.to_s, graph_name.nil? ? nil : graph_name.to_s, read_timeout.to_i]
          end

          def monotonic_now
            Process.clock_gettime(Process::CLOCK_MONOTONIC)
          end
        end

        def initialize(endpoint, options = {})
          @endpoint = endpoint
          @graph_name = options[:graph_name] || ''
          @read_timeout = options[:read_timeout] || DEFAULT_READ_TIMEOUT
          @logger = options[:logger] || Solis::LOGGER
          @key = self.class.pool_key(@endpoint, @graph_name, @read_timeout)
          @pool = self.class.pool_for(@endpoint, graph_name: @graph_name, read_timeout: @read_timeout, logger: @logger)
        end

        def with(&block)
          @pool.with(&block)
        end

        # The result is cached per pool for UP_CHECK_INTERVAL seconds across all instances,
        # so a request no longer pays an extra ASK round trip.
        def up?
          cached = self.class.cached_up(@key)
          return cached[:result] if cached

          result = nil
          @pool.with do |c|
            result = c.query("ASK WHERE { ?s ?p ?o }")
          end
          self.class.store_up(@key, result)
          result
        rescue HTTP::Error => e
          self.class.clear_up(@key)
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
