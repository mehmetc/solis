# frozen_string_literal: true

require 'moneta'
require 'solis/query/filter'
require 'solis/query/construct'
require 'solis/query/run'
require 'uuidtools'

module Solis
  class Query
    include Enumerable
    include Solis::QueryFilter

    def self.run(entity, query)
      Solis::Query::Runner.run(entity, query)
    end

    def self.run_construct_with_file(filename, id_name, entity, ids)
      f = File.read(filename)
      run_construct(f, id_name, entity, ids)
    end

    def self.uuid(key)
      UUIDTools::UUID.sha1_create(UUIDTools::UUID_URL_NAMESPACE, key).to_s
    end

    def self.run_construct(query, id_name, entity, ids, from_cache = '1')
      raise 'Please supply one or more uuid\'s' if ids.nil? || ids.empty?

      result = {}

      key = uuid("#{entity}-#{ids}")

      if result.nil? || result.empty? || (from_cache.eql?('0'))
        ids = ids.split(',') if ids.is_a?(String)
        ids = [ids] unless ids.is_a?(Array)
        ids = ids.map do |m|
          if URI(m).class.eql?(URI::Generic)
            "<#{Solis::Options.instance.get[:graph_name]}#{entity.tableize}/#{m}>"
          else
            "<#{m}>"
          end
        end
        ids = ids.join(" ")

        #q = query.gsub('{{VALUES}}', "VALUES ?#{id_name} { #{ids} }")
        q = query.gsub(/{ ?{ ?VALUES ?} ?}/, "VALUES ?#{id_name} { #{ids} }")

        result = Solis::Query.run(entity, q)
      end
      result
    rescue StandardError => e
      puts e.message
      raise e
    end

    def initialize(model)
      @construct_cache = File.absolute_path(Solis::Options.instance.get[:cache])
      @model = model
      @shapes = @model.class.shapes
      @metadata = @model.class.metadata
      @sparql_endpoint = @model.class.sparql_endpoint
      @sparql_client = SPARQL::Client.new(@sparql_endpoint, graph: @model.class.graph_name)
      @filter = {values: ["VALUES ?type {#{target_class}}"], concepts: ['?concept a ?type .'] }
      @sort = 'ORDER BY ?s'
      @sort_select = ''
    end

    def each(&block)
      data = query
      return unless data.methods.include?(:each)
      data.each(&block)
    rescue StandardError => e
      message = "Unable to get next record: #{e.message}"
      LOGGER.error(message)
      raise Error::CursorError, message
    end

    def sort(params)
      @sort = ''
      @sort_select = ''
      if params.key?(:sort)
        i = 0
        params[:sort].each do |attribute, direction|
          path = @model.class.metadata[:attributes][attribute.to_s][:path]
          @sort_select += "optional {\n" if @model.class.metadata[:attributes][attribute.to_s][:mincount] == 0
          @sort_select += "?concept <#{path}> ?__#{attribute} . "
          @sort_select += "}\n" if @model.class.metadata[:attributes][attribute.to_s][:mincount] == 0
          @sort += ',' if i.positive?
          @sort += "#{direction.to_s.upcase}(?__#{attribute})"
          i += 1
        end

        @sort = "ORDER BY #{@sort}" if i.positive?
      end

      self
    end

    def paging(params = {})
      current_page = params[:current_page] || 1
      per_page = params[:per_page] || 10

      @offset = 0
      @offset = current_page * per_page if current_page > 1
      @limit = per_page
      self
    end

    def language(language = nil)
      @language = language || Graphiti.context[:object]&.language || Solis::Options.instance.get[:language] || 'en'
      self
    end

    def count
      sparql_client = @sparql_client
      if model_construct?
        sparql_client = Solis::Query::Construct.new(@model).run
      end

      relationship = ''
      core_query = core_query(relationship)
      count_query = core_query.gsub(/SELECT .* WHERE/, 'SELECT (COUNT(distinct ?concept) as ?count) WHERE')

      result = sparql_client.query(count_query)
      solution = result.first
      solution.nil? ? 0 : solution[:count].object || 0
    end

    private

    def model_construct?
      File.exist?("#{ConfigFile.path}/constructs/#{@model.name.tableize.singularize}.sparql")
    end

    def target_class
      #      descendants = ObjectSpace.each_object(Class).select { |klass| klass < @model.class }.map { |m| m.class.name.eql?('Class') ? m.superclass : m }.map { |m| m.metadata[:target_class].value }
      descendants = ObjectSpace.each_object(Class).select { |klass| klass < @model.class }.reject { |m| m.metadata.nil? }.map { |m| m.metadata[:target_class].value }
      descendants << @model.class.metadata[:target_class].value
      descendants.map { |m| "<#{m}>" }.join(' ')
    end

    def target_class_by_model(model, id=nil)
      descendants = ObjectSpace.each_object(Class).select { |klass| klass < model.class }.reject { |m| m.metadata.nil? }.map { |m| m.metadata[:target_class].value.tableize }
      descendants << model.class.metadata[:target_class].value.tableize
      if id.nil?
        descendants.map { |m| "<#{m}>" }.join(' ')
      else
        descendants.map { |m| "<#{m}/#{id}>" }.join(' ')
      end
    end


    def query(options = {})
      limit = @limit || 10
      offset = @offset || 0

      sparql_client = model_construct? ? Solis::Query::Construct.new(@model).run : @sparql_client
      #sparql_client = model_construct? ? SPARQL::Client.new(run_construct) : @sparql_client

      relationship = ''
      if options.key?(:relationship)
        link = "#{@model.class.graph_name}#{ActiveSupport::Inflector.pluralize(@klass.name).downcase}/#{id}"
        path = @model.class.metadata[:attributes][options[:relationship]][:path]
        relationship = "<#{link}> <#{path}> ?o ."
      end

      core_query = core_query(relationship)
      if core_query =~ /IN\((.*?)\)/
        #limit = $1.gsub('"','').split(',').length
      else
        core_query += " LIMIT #{limit} OFFSET #{offset}"
      end

      query = %(
      #{prefixes}
SELECT ?s ?p ?o WHERE {
 ?s ?p ?o
{
  #{core_query}
}
}
order by ?s
)

      Solis::LOGGER.info(query) if ConfigFile[:debug]

      graph_to_object(sparql_client.query(query))
    rescue StandardError => e
      Solis::LOGGER.error(e.message)
      Solis::LOGGER.error(e.backtrace.join("\n"))
    end

    def core_query(relationship)
      core_query = %(
  SELECT distinct (?concept AS ?s) WHERE {
    #{@filter[:values].join("\n")}
    ?concept ?role ?objects.
    #{relationship}
    #{@filter[:concepts].join("\n")}

    #{@sort_select}
  }
#{@sort}
)
    end

    def prefixes
      "
PREFIX sh: <http://www.w3.org/ns/shacl#>
PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
PREFIX schema: <http://schema.org/>
PREFIX rdfv: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX foaf: <http://xmlns.com/foaf/0.1/>
PREFIX #{@model.class.graph_prefix}: <#{@model.class.graph_name}>"
    end

    def graph_to_object(solutions)
      return [] if solutions.empty?
      target_class = @model.class.metadata[:target_class].value.split('/').last
      result = []
      record_uri = ''

      begin
        # solutions.sort! { |x, y| x.s.value <=> y.s.value }.map { |m| m.s.value }
        solution_types = solutions.dup.filter!(p: RDF::RDFV.type)
        solution_types.each do |type|
          solution_model = @model.class.graph.shape_as_model(type.o.value.split('/').last)
          data = {}
          statements = solutions.dup.filter!(s: type.s)
          statements.each do |statement|
            next if statement.p.eql?(RDF::RDFV.type)

            begin
              record_uri = statement.s.value
              attribute = statement.p.value.split('/').last.underscore

              if statement.o.valid?
                object = statement.o.canonicalize.object
              else
                object = Integer(statement.o.value) if Integer(statement.o.value) rescue nil
                object = Float(statement.o.value) if object.nil? && Float(statement.o.value) rescue nil
                object = statement.o.value if object.nil?
              end

              begin
                datatype = RDF::Vocabulary.find_term(@model.class.metadata[:attributes][attribute][:datatype_rdf])
                if statement.o.datatype != datatype
                  object = RDF::Literal.new(statement.o.canonicalize.object, datatype: datatype).object
                end
              rescue StandardError => e
                if object.is_a?(Hash)
                  object = if object.key?(:fragment) && !object[:fragment].nil?
                             "#{object[:path]}##{object[:fragment]}"
                           else
                             object[:path]
                           end
                end
              end

              # fix non matching attributes by data type
              if solution_model.metadata[:attributes][attribute].nil?
                candidates = solution_model.metadata[:attributes].select { |_k, s| s[:class] == statement.p }.keys - data.keys
                attribute = candidates.first unless candidates.empty?
              end

              begin
                unless solution_model.metadata[:attributes][attribute][:node_kind].nil?
                  node_class = solution_model.metadata[:attributes][attribute][:class].value.split('/').last
                  object = solution_model.graph.shape_as_model(node_class).new({ id: object.split('/').last })
                end
              rescue StandardError => e
                puts e.message
              end

              if data.key?(attribute) # attribute exists
                raise "Cardinality error, max = #{solution_model.metadata[:attributes][attribute][:maxcount]}" if solution_model.metadata[:attributes][attribute][:maxcount] == 0
                if solution_model.metadata[:attributes][attribute][:maxcount] == 1 && data.key?(attribute)
                  raise "Cardinality error, max = #{solution_model.metadata[:attributes][attribute][:maxcount]}"
                elsif solution_model.metadata[:attributes][attribute][:maxcount] == 1
                  data[attribute] = object
                else
                  data[attribute] = [data[attribute]] unless data[attribute].is_a?(Array)
                  data[attribute] << object
                end
              else
                if solution_model.metadata[:attributes][attribute][:maxcount].nil? || solution_model.metadata[:attributes][attribute][:maxcount] > 1
                  data[attribute] = [object]
                else
                  data[attribute] = object
                end
              end
            rescue StandardError => e
              puts e.backtrace.first
              Solis::LOGGER.error("#{record_uri} - graph_to_object - #{attribute} - #{e.message}")
              g = RDF::Graph.new
              g << [statement.s, statement.p, statement.o]
              Solis::LOGGER.error(g.dump(:ttl).to_s)
            end
          end
          result << solution_model.new(data) unless data.empty?
        end
      rescue StandardError => e
        Solis::LOGGER.error("#{record_uri} - graph_to_object - #{e.message}")
      end

      # result << solution_model.new(data) unless data.empty?
      result
    end
  end
end
