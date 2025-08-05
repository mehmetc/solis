
module Solis
  class Query
    class QueryRunner

      # Tiny wrapper around store operations.

      attr_reader :model, :store

      def initialize(model, store)
        @model = model
        @store = store
      end

      def query_langs
        @store.query_langs
      end

      def run_find_records(query)
        id_op = @store.run_raw_query(query, 'find_records')
        results = @store.run_operations([id_op])[id_op]
        convert_records(results)
      end

      def run_count_records(query)
        id_op = @store.run_raw_query(query, 'count_records')
        count = @store.run_operations([id_op])[id_op]
        count
      end

      private

      # can be overwritten for custom conversions
      def convert_records(records)
        records.map do |entry|
          id = entry
          data = { '_id' => id }
          entity = Solis::Model::Entity.new(data, @model, nil, @store)
          entity.load(deep = true)
          entity
        end.compact
      end

    end
  end
end