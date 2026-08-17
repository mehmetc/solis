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

    # XSD numeric datatypes must be ordered by value; wrapping them in STR() would sort
    # them lexically ("100" < "9"). Every other datatype is STR()-wrapped in the outer
    # ORDER BY (see #sort_key_expression) to dodge a Virtuoso collation bug.
    XSD_NUMERIC_DATATYPES = %w[
      integer decimal float double long int short byte
      nonNegativeInteger nonPositiveInteger negativeInteger positiveInteger
      unsignedLong unsignedInt unsignedShort unsignedByte
    ].map { |t| "http://www.w3.org/2001/XMLSchema##{t}" }.freeze

    def self.run(entity, query, options = {})
      Solis::Query::Runner.run(entity, query, options)
    end

    def self.run_construct_with_file(filename, id_name, entity, ids, from_cache = '1')
      f = File.read(filename)
      run_construct(f, id_name, entity, ids, from_cache)
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
            "<#{graph_name}#{entity.tableize}/#{m}>"
          else
            "<#{m}>"
          end
        end
        ids = ids.join(" ")

        language = Graphiti.context[:object]&.language || Solis::Options.instance.get[:language] || 'en'
        q = query.gsub(/{ ?{ ?VALUES ?} ?}/, "VALUES ?#{id_name} { #{ids} }").gsub(/{ ?{ ?LANGUAGE ?} ?}/, "bind(\"#{language}\" as ?filter_language).").gsub(/{ ?{ ?ENTITY ?} ?}/, "<#{graph_name}#{entity.classify}>")

        result = Solis::Query.run(entity, q)
      end
      result
    rescue StandardError => e
      puts e.message
      raise e
    end

    def self.graph_name
      Solis::Options.instance.get.key?(:graphs) ? Solis::Options.instance.get[:graphs].select{|s| s['type'].eql?(:main)}&.first['name'] : ''
    end

    # Shared class-level query cache to ensure consistent reads/writes/invalidations
    def self.shared_query_cache
      cache_dir = File.absolute_path(Solis::Options.instance.get[:cache])
      @shared_query_cache ||= Moneta.new(:HashFile, dir: cache_dir)
    end

    # Reset the shared cache (useful when config changes, e.g., in tests)
    def self.reset_shared_query_cache!
      @shared_query_cache = nil
    end

    # Invalidate all cached query results for a given model type.
    def self.invalidate_cache_for(model_class_name, cache_dir = nil)
      cache = shared_query_cache
      tag_key = "TAG:#{model_class_name}"
      if cache.key?(tag_key)
        cache[tag_key].each { |key| cache.delete(key) }
        cache.delete(tag_key)
        Solis::LOGGER.info("CACHE: invalidated entries for #{model_class_name}") if ConfigFile[:debug]
      end
    rescue StandardError => e
      Solis::LOGGER.warn("CACHE: invalidation failed for #{model_class_name}: #{e.message}")
    end

    def initialize(model)
      @construct_cache = File.absolute_path(Solis::Options.instance.get[:cache])
      @model = model
      @shapes = @model.class.shapes
      @metadata = @model.class.metadata
      @sparql_endpoint = @model.class.sparql_endpoint
      if Solis::Options.instance.get.key?(:graphs) && Solis::Options.instance.get[:graphs].size > 0
        @sparql_client = Solis::Store::Sparql::Client.new(@sparql_endpoint)
      else
        @sparql_client = Solis::Store::Sparql::Client.new(@sparql_endpoint, graph: @model.class.graph_name)
      end
      @filter = {values: ["VALUES ?type {#{target_class}}"], concepts: ['?concept a ?type .'] }
      @sort = 'ORDER BY ?concept'
      @sort_select = ''
      # @sort_project carries the sort key(s) out of the inner (paginated) subquery so the
      # outer query can re-sort on them; @sort_outer is that outer ORDER BY. A subquery's
      # ORDER BY only decides which rows survive LIMIT/OFFSET — it does NOT propagate
      # through the enclosing join — so the outer query must sort too. See #sort for the
      # datatype-aware STR() handling that the outer ORDER BY needs.
      @sort_project = ''
      @sort_outer = ''
      @language = Graphiti.context[:object]&.language || Solis::Options.instance.get[:language] || 'en'
      @query_cache = self.class.shared_query_cache
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
      @sort_project = ''
      @sort_outer = ''
      if params.key?(:sort)
        i = 0
        outer = ''
        params[:sort].each do |attribute, direction|
          meta = @model.class.metadata[:attributes][attribute.to_s]
          path = meta[:path]
          @sort_select += "optional {\n" if meta[:mincount] == 0
          @sort_select += "?concept <#{path}> ?__#{attribute} . "
          @sort_select += "}\n" if meta[:mincount] == 0
          @sort += ',' if i.positive?
          @sort += "#{direction.to_s.upcase}(?__#{attribute})"
          # Carry the sort key out of the subquery so the outer query can re-sort on it.
          @sort_project += " ?__#{attribute}"
          outer += ',' if i.positive?
          outer += "#{direction.to_s.upcase}(#{sort_key_expression(attribute, meta)})"
          i += 1
        end

        if i.positive?
          @sort = "ORDER BY #{@sort}"
          # ?s tiebreaker keeps each subject's triples contiguous and ties deterministic.
          @sort_outer = "ORDER BY #{outer} ?s"
        end
      end

      self
    end

    def paging(params = {})
      current_page = params[:current_page] || 1
      per_page = params[:per_page] || 10

      @offset = 0
      @offset = (current_page - 1) * per_page if current_page > 1
      @limit = per_page
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

      # count_query = count_query.split('a ?type')[0]+'a ?type }'
      result = sparql_client.query(count_query)
      solution = result.first
      solution.nil? ? 0 : solution[:count].object || 0
    end

    private

    # Track a cache key under its model type tag for targeted invalidation
    def track_cache_key(query_key)
      tag_key = "TAG:#{@model.model_class_name}"
      existing_keys = @query_cache.key?(tag_key) ? @query_cache[tag_key] : []
      unless existing_keys.include?(query_key)
        existing_keys << query_key
        @query_cache[tag_key] = existing_keys
      end
    end

    def model_construct?
      construct_name = @model.model_class_name.tableize.singularize rescue @model.class.name.tableize.singularize
      File.exist?("#{ConfigFile.path}/constructs/#{construct_name}.sparql")
    rescue StandardError => e
      false
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

      # ?o is bound via BIND(?o_raw AS ?o) instead of being projected directly from the
      # triple pattern. Some Virtuoso builds (e.g. 08.03.3335) mis-bind ?o to the wrong
      # object when the open `?s ?p ?o` pattern is combined with the disjunctive
      # language_filter, returning the rdf:type object for every row. Aliasing through
      # BIND blocks that optimizer rewrite and is a no-op on engines without the bug.
      # Outer ordering: the inner subquery's ORDER BY only selects which rows survive
      # LIMIT/OFFSET; it does NOT propagate through the enclosing join. The outer query
      # therefore re-sorts on the same key(s) (@sort_outer, datatype-aware STR()). When
      # no sort is requested, `order by ?s` gives a cheap deterministic default order.
      outer_order = @sort_outer.empty? ? 'order by ?s' : @sort_outer
      query = %(
      #{prefixes}
SELECT ?s ?p ?o WHERE {
 ?s ?p ?o_raw .
 BIND(?o_raw AS ?o)
{
  #{core_query}
}
#{language_filter}
}
#{outer_order}
)

      Solis::LOGGER.info(query) if ConfigFile[:debug]

      query_key = "#{@model.model_class_name}-#{Digest::MD5.hexdigest(query)}"

      result = nil

      from_cache = Graphiti.context[:object]&.from_cache || '0'
      if @query_cache.key?(query_key) && from_cache.eql?('1')
        result = @query_cache[query_key]
        Solis::LOGGER.info("CACHE: from #{query_key}") if ConfigFile[:debug]
      else
        result = graph_to_object(sparql_client.query(query))
        @query_cache[query_key] = result unless result.nil? || result.empty?
        Solis::LOGGER.info("CACHE: to #{query_key}") if ConfigFile[:debug]
      end

      # Always ensure the cache key is tracked under its model type tag
      track_cache_key(query_key)

      result
    rescue StandardError => e
      Solis::LOGGER.error(e.message)
      Solis::LOGGER.error(e.backtrace.join("\n"))
    end

    def language_filter
      if @language.nil?
        ''
      else
        %(
        filter (
            !isLiteral(?o) ||
            langmatches(lang(?o), "#{@language}")
            || (langmatches(lang(?o), "") && not exists {
                    ?s ?p ?other.
                    filter(isLiteral(?other) && langmatches(lang(?other), "#{@language}"))
                }))
        )
      end
    end

    def core_query(relationship)
      # @sort_project re-exposes the sort key(s) bound in @sort_select so the OUTER query
      # can ORDER BY them. NB: for a multi-valued sort attribute this turns DISTINCT into
      # one row per (concept, value) pair, which would skew LIMIT/OFFSET — sort attributes
      # are expected to be single-valued.
      core_query = %(
  SELECT distinct (?concept AS ?s)#{@sort_project} WHERE {
    #{@filter[:values].join("\n")}
    #{relationship}
    #{@filter[:concepts].join("\n")}

    #{@sort_select}
  }
#{@sort}
)
    end

    # SPARQL expression to sort an attribute by in the OUTER query.
    #
    # The outer (post-join) ORDER BY on this Virtuoso build (08.03.3335) mis-collates
    # language-tagged literals, so string-ish keys are wrapped in STR() — which fixes the
    # ordering and is order-preserving for xsd:string, dates, gYear, booleans and EDTF.
    # Numeric keys must NOT be wrapped: STR() would order them lexically ("100" < "9"),
    # and numbers carry no language tag so they are unaffected by the collation bug.
    def sort_key_expression(attribute, meta = @model.class.metadata[:attributes][attribute.to_s])
      if XSD_NUMERIC_DATATYPES.include?(meta[:datatype_rdf].to_s)
        "?__#{attribute}"
      else
        "STR(?__#{attribute})"
      end
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

              unless solution_model.metadata[:attributes].key?(attribute)
                Solis::LOGGER.error "Attribute found in data that is not part of the model model #{solution_model.model_class_name}(#{record_uri.split('/').last}).#{attribute}"
                next
              end

              if statement.o.valid?
                if statement.o.is_a?(RDF::URI)
                  object = statement.o.canonicalize.value
                else
                  object = statement.o.canonicalize.object
                end
              else
                object = Integer(statement.o.value) if Integer(statement.o.value) rescue nil
                object = Float(statement.o.value) if object.nil? && Float(statement.o.value) rescue nil
                object = statement.o.value if object.nil?
              end

              begin
                datatype = RDF::Vocabulary.find_term(@model.class.metadata[:attributes][attribute][:datatype_rdf])
                if RDF::Literal(statement.o).datatype.value != datatype
                  if statement.o.is_a?(RDF::URI)
                    object = RDF::Literal.new(statement.o.canonicalize.value, datatype: RDF::URI).object
                  else
                    object = RDF::Literal.new(statement.o.canonicalize.object, datatype: datatype).object
                  end
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
                if solution_model.metadata[:attributes][attribute][:maxcount] == 1 && data.key?(attribute) && data[attribute].is_a?(Array) && data[attribute].length > 1
                  raise "Cardinality error, max = #{solution_model.metadata[:attributes][attribute][:maxcount]}"
                elsif solution_model.metadata[:attributes][attribute][:maxcount] == 1
                  data[attribute] = object
                else
                  data[attribute] = [data[attribute]] unless data[attribute].is_a?(Array)
                  data[attribute] << object
                end
              else
                if solution_model.metadata[:attributes][attribute][:maxcount].nil? || solution_model.metadata[:attributes][attribute][:maxcount] > 1
                  if data.include?(attribute)
                    data[attribute] << object
                  else
                    data[attribute] = [object]
                  end
                else
                  data[attribute] = object
                end
              end
            rescue StandardError => e
              unless solution_model.metadata[:attributes].key?(attribute)
                Solis::LOGGER.error("#{record_uri} - graph_to_object - #{attribute} - #{e.message}")
                raise  "'#{attribute}' not in model"
              end
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
