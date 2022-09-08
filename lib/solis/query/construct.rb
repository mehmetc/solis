require 'uuidtools'

module Solis
  class Query
    class Construct
      def initialize(model)
        @model = model
        @sparql_endpoint = @model.class.sparql_endpoint
        @sparql_client = SPARQL::Client.new(@sparql_endpoint, graph: @model.class.graph_name, read_timeout: 120)
        @construct_cache = File.absolute_path(Solis::Options.instance.get[:cache])
        @moneta = Moneta.new(:File, dir: "#{@construct_cache}/construct", expires: Solis::Options.instance.get[:cache_expire])
      end

      def exists?
        File.exist?(file_path)
      end

      def load
        construct_path = file_path
        raise Solis::Error::NotFoundError, "Construct not found at #{construct_path} " unless exists?
        File.read(construct_path)
      end

      def file_path
        "#{ConfigFile.path}/constructs/#{@model.name.tableize.singularize}.sparql"
      end

      def file_path_hash
        UUIDTools::UUID.sha1_create(UUIDTools::UUID_URL_NAMESPACE, file_path).to_s
      end

      def run
        construct_query = load
        sparql_repository = @sparql_endpoint

        from_cache = Graphiti.context[:object].from_cache || '1'
        if construct_query && construct_query =~ /construct/
          if @moneta.key?(file_path_hash) && from_cache.eql?('1')
            sparql_repository = @moneta[file_path_hash]
          else
            @sparql_client = SPARQL::Client.new(@sparql_endpoint, read_timeout: 120)
            result = @sparql_client.query(construct_query)
            repository=RDF::Repository.new
            result.each {|s| repository << [s[:s], s[:p], s[:o]]}
            sparql_repository = repository
            @moneta.store(file_path_hash, repository, expires: ConfigFile[:solis][:cache_expire] || 86400)
          end
        elsif construct_query && construct_query =~ /insert/
          unless @moneta.key?(file_path_hash)
            clear_construct
            result = @sparql_client.query(construct_query)
            LOGGER.info(result[0]['callret-0'].value) unless result.empty?
            @moneta.store(file_path_hash, repository, expires: ConfigFile[:solis][:cache_expire] || 86400) unless result[0]['callret-0'].value =~ /0 triples/
          end
        end

        #SPARQL::Client.new(@sparql_endpoint, graph: @model.class.graph_name, read_timeout: 120)
        SPARQL::Client.new(sparql_repository, read_timeout: 120)
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
