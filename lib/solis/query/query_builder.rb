require_relative '../utils/string'

module Solis
  class Query
    class QueryBuilder

      include Enumerable

      attr_reader :namespace, :entity_name, :query_runner, :conditions, :order_values, :limit_value, :offset_value

      def initialize(namespace, entity_name, query_runner, conditions = {}, options = {})
        @namespace = namespace
        @entity_name = entity_name
        @query_runner = query_runner
        @conditions = conditions
        @order_values = options[:order] || []
        @limit_value = options[:limit]
        @offset_value = options[:offset]
        @loaded = false
        @records = []
      end

      # Chainable query methods
      def where(new_conditions)
        if new_conditions.is_a?(String)
          # Handle string conditions like "age > 21"
          # This would need conversion in query-specific language
          self.class.new(@namespace, @entity_name, @query_runner, @conditions, {
            order: @order_values,
            limit: @limit_value,
            offset: @offset_value,
            string_conditions: new_conditions
          })
        else
          # Merge hash conditions
          merged_conditions = @conditions.merge(new_conditions)
          self.class.new(@namespace, @entity_name, @query_runner, merged_conditions, {
            order: @order_values,
            limit: @limit_value,
            offset: @offset_value
          })
        end
      end

      def order(field, direction = :asc)
        new_order = @order_values + [[field, direction]]
        self.class.new(@namespace, @entity_name, @query_runner, @conditions, {
          order: new_order,
          limit: @limit_value,
          offset: @offset_value
        })
      end

      def limit(num)
        self.class.new(@namespace, @entity_name, @query_runner, @conditions, {
          order: @order_values,
          limit: num,
          offset: @offset_value
        })
      end

      def offset(num)
        self.class.new(@namespace, @entity_name, @query_runner, @conditions, {
          order: @order_values,
          limit: @limit_value,
          offset: num
        })
      end

      # Finder methods
      def find_by(attributes)
        where(attributes).first
      end

      def find_by!(attributes)
        find_by(attributes) || raise("Couldn't find #{@entity_name} with #{attributes.inspect}")
      end

      def first(num = nil)
        if num
          limit(num).to_a
        else
          load_records.first
        end
      end

      def last(num = nil)
        if num
          load_records.last(num)
        else
          load_records.last
        end
      end

      def exists?(conditions = {})
        if conditions.any?
          where(conditions).count > 0
        else
          count > 0
        end
      end

      # Calculation methods
      def count
        if loaded?
          @records.size
        else
          execute_count_records_query
        end
      end

      def size
        loaded? ? @records.size : count
      end

      def empty?
        count == 0
      end

      def any?
        count > 0
      end

      # Array-like methods
      def each(&block)
        load_records.each(&block)
      end

      def map(&block)
        load_records.map(&block)
      end

      def select(&block)
        load_records.select(&block)
      end

      def to_a
        load_records
      end

      alias_method :all, :to_a

      # Loading
      def loaded?
        @loaded
      end

      def reload
        @loaded = false
        @records = []
        load_records
        self
      end

      # Batching
      def find_each(batch_size: 1000)
        offset = 0
        loop do
          batch = limit(batch_size).offset(offset).to_a
          break if batch.empty?

          batch.each { |record| yield record }

          break if batch.size < batch_size
          offset += batch_size
        end
      end

      def find_in_batches(batch_size: 1000)
        offset = 0
        loop do
          batch = limit(batch_size).offset(offset).to_a
          break if batch.empty?

          yield batch

          break if batch.size < batch_size
          offset += batch_size
        end
      end

      private

      def load_records
        return @records if loaded?

        @records = execute_find_records_query
        @loaded = true
        @records
      end

      # Below query lang-specific code

      def error_if_query_lang_not_supported
        unless @query_runner.query_langs.include?('SPARQL')
          raise NoMethodError.new("query_runner does not support SPARQL.")
        end
      end

      def execute_find_records_query
        error_if_query_lang_not_supported
        query = build_sparql_find_records_query
        @query_runner.run_find_records(query)
      end

      def execute_count_records_query
        error_if_query_lang_not_supported
        query = build_sparql_count_records_query
        @query_runner.run_count_records(query)
      end

      def build_sparql_find_records_query
        # This is a simplified version - real implementation would be more complex
        type_uri = Solis::Utils::String.prepend_namespace_if_not_uri(@namespace, @entity_name)

        sparql = "SELECT DISTINCT ?s WHERE {\n"
        sparql += "  ?s a <#{type_uri}> .\n"

        # Add conditions
        @conditions.each do |property, value|
          prop_uri = Solis::Utils::String.prepend_namespace_if_not_uri(@namespace, property)
          if value.is_a?(String)
            sparql += "  ?s <#{prop_uri}> \"#{value}\" .\n"
          elsif value.is_a?(Integer) || value.is_a?(Float)
            sparql += "  ?s <#{prop_uri}> #{value} .\n"
          elsif value.is_a?(Array)
            # IN clause
            values = value.map { |v| v.is_a?(String) ? "\"#{v}\"" : v }.join(", ")
            sparql += "  ?s <#{prop_uri}> ?#{property}_value .\n"
            sparql += "  FILTER(?#{property}_value IN (#{values})) .\n"
          end
        end

        sparql += "}\n"

        # Add ORDER BY
        @order_values.each do |field, direction|
          sparql += "ORDER BY #{direction.to_s.upcase}(?#{field})\n"
        end

        # Add LIMIT and OFFSET
        sparql += "LIMIT #{@limit_value}\n" if @limit_value
        sparql += "OFFSET #{@offset_value}\n" if @offset_value

        sparql
      end

      def build_sparql_count_records_query
        type_uri = Solis::Utils::String.prepend_namespace_if_not_uri(@namespace, @entity_name)

        sparql = "SELECT (COUNT(DISTINCT ?s) AS ?count) WHERE {\n"
        sparql += "  ?s a <#{type_uri}> .\n"

        # Add conditions (same as build_sparql_query)
        @conditions.each do |property, value|
          # prop_uri = "#{@namespace}#{property}"
          prop_uri = Solis::Utils::String.prepend_namespace_if_not_uri(@namespace, property)
          if value.is_a?(String)
            sparql += "  ?s <#{prop_uri}> \"#{value}\" .\n"
          elsif value.is_a?(Integer) || value.is_a?(Float)
            sparql += "  ?s <#{prop_uri}> #{value} .\n"
          end
        end

        sparql += "}"
        sparql
      end

    end
  end
end