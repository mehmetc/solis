
require 'linkeddata'
require 'iso8601'

ISO8601i = ISO8601

module Solis
  class Model
    module Literal
      module ISO8601

        class TimeInterval < RDF::Literal
          DATATYPE = RDF::URI('http://www.w3.org/2006/time#DateTimeInterval')
          def valid?
            begin
              ISO8601i::TimeInterval.parse(value)
              true
            rescue
              false
            end
          end
        end

        class Duration < RDF::Literal
          DATATYPE = RDF::URI('http://www.w3.org/2006/time#Duration')
          def valid?
            begin
              ISO8601i::Duration.new(value)
              true
            rescue
              false
            end
          end
        end

      end
    end
  end
end

