module Solis
  module Store
    module Sparql
      class Client
        class Query
          def initialize(client)
            @client = client
          end

          def run(query)
            result = @client.query(query)

            if is_construct?(query)
              repository = RDF::Repository.new
              result.each { |s| repository << [s[:s], s[:p], s[:o]] }
              result = SPARQL::Client.new(repository)
            end

            result
          end

          private

          def is_construct?(query)
            query =~ /construct/i
          end

          def is_insert?(query)
            query =~ /insert/i
          end
        end
      end
    end
  end
end