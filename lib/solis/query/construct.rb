module Solis
  class Query
    class Construct
      def initialize(model)
        @model = model
        @sparql_endpoint = @model.class.sparql_endpoint
        @sparql_client = SPARQL::Client.new(@sparql_endpoint, graph: @model.class.graph_name, read_timeout: 120)
      end

      def exists?
        File.exist?("#{ConfigFile.path}/constructs/#{@model.name.tableize.singularize}.sparql")
      end

      def load
        construct_path = "#{ConfigFile.path}/constructs/#{@model.name.tableize.singularize}.sparql"
        raise Solis::Error::NotFoundError, "Construct not found at #{construct_path} " unless exists?
        File.read(construct_path)
      end

      def run
        construct_query = load

        if construct_query && construct_query =~ /construct/
          @sparql_client = SPARQL::Client.new(@sparql_endpoint, read_timeout: 120)
          result = @sparql_client.query(construct_query)
          repository=RDF::Repository.new
          result.each {|s| repository << [s[:s], s[:p], s[:o]]}
          return SPARQL::Client.new(repository)
        elsif construct_query && construct_query =~ /insert/
          if created_at.nil? || (Time.now - created_at) > 1.day
            clear_construct
            result = @sparql_client.query(construct_query)
            LOGGER.info(result[0]['callret-0'].value) unless result.empty?
            set_metadata
          end
          return SPARQL::Client.new(@sparql_endpoint, { graph: construct_graph_name, read_timeout: 120 })
        end

        SPARQL::Client.new(@sparql_endpoint, graph: @model.class.graph_name, read_timeout: 120)
      end

      private

      def parsed_graph_name
        URI.parse(@model.class.graph_name)
      end

      def construct_graph_name
        "#{parsed_graph_name.scheme}://#{@model.name.underscore}.#{parsed_graph_name.host}/"
      end

      def created_at
        created_at = nil
        result = @sparql_client.query("select * from <#{construct_graph_name}> where {<#{construct_graph_name}_metadata> <#{construct_graph_name}created_at> ?_created_at}")
        unless result.empty?
          created_at = result[0]._created_at.object
        end

        created_at
      end

      def clear_construct
        result = @sparql_client.query("clear graph <#{construct_graph_name}>")
        LOGGER.info(result[0]['callret-0'].value)
      end

      def set_metadata
        result = @sparql_client.query("insert into <#{construct_graph_name}> { <#{construct_graph_name}_metadata> <#{construct_graph_name}created_at> \"#{Time.now.xmlschema}\"^^xsd:dateTime}")
        LOGGER.info(result[0]['callret-0'].value)
      end

    end
  end
end
