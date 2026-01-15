require 'rdf'
require 'edtf'

module RDF
  class Literal
    ##
    # Extended Date/Time Format (EDTF) literal for RDF 3.x
    #
    # This class provides RDF literal support for EDTF dates, implementing
    # the Library of Congress Extended Date/Time Format specification.
    #
    # @see https://www.loc.gov/standards/datetime/
    # @see https://github.com/inukshuk/edtf-ruby
    class EDTF < Literal
      DATATYPE = RDF::URI('http://id.loc.gov/datatypes/edtf')

      # Grammar pattern for EDTF validation
      # Supports Level 0, 1, and 2 expressions
      # This is a simplified pattern - the edtf gem handles full validation
      GRAMMAR = /^[\d\-\/\?\~\.\[\]\{\}XuU\^%\,\+\:\s]+$/

      ##
      # @param  [Object] value
      # @param  [Hash{Symbol => Object}] options
      # @option options [String] :lexical (nil)
      def initialize(value, datatype: nil, lexical: nil, **options)
        @edtf_value = parse_edtf(value)

        # Use EDTF string representation as the lexical form
        lexical_value = @edtf_value.respond_to?(:edtf) ? @edtf_value.edtf : value.to_s

        super(lexical_value, datatype: DATATYPE, lexical: lexical, **options)
      end

      ##
      # Returns the EDTF object value
      #
      # @return [EDTF::Date, EDTF::Interval, EDTF::Season, EDTF::Set, etc.]
      def object
        @edtf_value
      end

      alias_method :to_edtf, :object

      ##
      # Validates the EDTF literal
      #
      # @return [Boolean]
      def valid?
        return false if @edtf_value.nil?
        # EDTF values are valid if they were successfully parsed
        true
      rescue
        false
      end

      ##
      # Returns the canonical string representation
      #
      # @return [String]
      def canonicalize
        return self if @edtf_value.nil?
        self.class.new(@edtf_value.edtf)
      end

      ##
      # Converts to a human-readable string
      #
      # @return [String]
      def humanize
        return to_s unless @edtf_value.respond_to?(:humanize)
        @edtf_value.humanize
      rescue
        to_s
      end

      ##
      # Returns true if this is an uncertain date
      #
      # @return [Boolean]
      def uncertain?
        @edtf_value.respond_to?(:uncertain?) && @edtf_value.uncertain?
      end

      ##
      # Returns true if this is an approximate date
      #
      # @return [Boolean]
      def approximate?
        @edtf_value.respond_to?(:approximate?) && @edtf_value.approximate?
      end

      ##
      # Returns true if this is an interval
      #
      # @return [Boolean]
      def interval?
        @edtf_value.is_a?(::EDTF::Interval)
      end

      ##
      # Returns true if this is a season
      #
      # @return [Boolean]
      def season?
        @edtf_value.is_a?(::EDTF::Season)
      end

      ##
      # Returns true if this is a set
      #
      # @return [Boolean]
      def set?
        @edtf_value.is_a?(::EDTF::Set)
      end

      private

      ##
      # Parses input value to EDTF object
      #
      # @param  [Object] value
      # @return [EDTF::Date, EDTF::Interval, EDTF::Season, EDTF::Set, etc.]
      def parse_edtf(value)
        case value
        when ::EDTF::Interval, ::EDTF::Season, ::EDTF::Set, ::EDTF::Epoch
          value
        when ::Date, ::DateTime, ::Time
          # For Ruby Date/DateTime/Time, try to parse as EDTF
          ::Date.edtf(value.to_s) || value
        when String
          # Parse EDTF string
          ::Date.edtf(value) || ::EDTF.parse(value)
        else
          ::EDTF.parse(value.to_s)
        end
      rescue StandardError => e
        Solis::LOGGER.warn("Failed to parse EDTF value '#{value}': #{e.message}") if defined?(Solis::LOGGER)
        nil
      end
    end
  end
end
