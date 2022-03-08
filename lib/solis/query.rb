# frozen_string_literal: true

require 'moneta'

module Solis
  class Query
    include Enumerable

    def initialize(model)
      @construct_cache = File.absolute_path(Solis::ConfigFile[:solis][:cache])
      @model = model
      @shapes = @model.class.shapes
      @metadata = @model.class.metadata
      @sparql_endpoint = @model.class.sparql_endpoint
      @sparql_client = SPARQL::Client.new(@sparql_endpoint, graph: @model.class.graph_name)
      @filter = ''
      @sort = 'ORDER BY ?s'
      @sort_select = ''
      @moneta = Moneta.new(:File, dir: @construct_cache, expires: Solis::ConfigFile[:solis][:query_cache_expire])
    end

    def each(&block)
      data = query
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
          @sort_select += "?concept <#{path}> ?__#{attribute} . "
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
      @language = language || ConfigFile[:solis][:env][:language] || 'en'
      self
    end

    def filter(params)
      #FILTER(LANG(?label) = "" || LANGMATCHES(LANG(?label), "fr"))
      #
      #
      #
      @filter = ''
      if params.key?(:filters)
        filters = params[:filters]
        if filters.is_a?(String)
          contains = filters.split(',').map { |m| "CONTAINS(LCASE(str(?__search)), LCASE(\"#{m}\"))" }.join(' || ')
          @filter = "?concept (#{@metadata[:attributes].map { |_, m| "(<#{m[:path]}>)" }.join('|')}) ?__search FILTER CONTAINS(LCASE(str(?__search)), LCASE(\"#{contains}\")) ."
        else
          i = 0
          filters.each do |key, value|
            if  @metadata[:attributes].key?(key.to_s) && @metadata[:attributes][key.to_s][:node_kind] && @metadata[:attributes][key.to_s][:node_kind]&.vocab == RDF::Vocab::SH
              values_model = @model.class.graph.shape_as_model(@metadata[:attributes][key.to_s][:datatype].to_s)&.new
              @filter = "VALUES ?filter_by_id{#{value.split(',').map {|v| target_class_by_model(values_model, v)}.join(' ')}}\n" if values_model
              filter_predicate = URI.parse(@metadata[:attributes][key.to_s][:path])
              filter_predicate.path = "/#{key.to_s.downcase}"

              @filter += "?concept <#{filter_predicate.to_s}> ?filter_by_id ."
            else
              unless value.is_a?(Hash) && value.key?(:value)
                #TODO: only handles 'eq' for now
                value = { value: value.first, operator: '=', is_not: false }
              end

              if value[:value].is_a?(String)
                contains = value[:value].split(',').map { |m| "CONTAINS(LCASE(str(?__search#{i})), LCASE(\"#{m}\"))" }.join(' || ')
              else
                value[:value] = [value[:value]] unless value[:value].is_a?(Array)
                value[:value].flatten!
                contains = value[:value].map { |m| "CONTAINS(LCASE(str(?__search#{i})), LCASE(\"#{m}\"))" }.join(' || ')
              end

              metadata = @metadata[:attributes][key.to_s]
              if metadata
                if metadata[:path] =~ %r{/id$}
                  if value[:value].is_a?(String)
                    contains = value[:value].split(',').map { |m| "\"#{m}\"" }.join(',')
                  else
                    value[:value].flatten!
                    contains = value[:value].map { |m| "\"#{m}\"" }.join(',')
                  end
                  if value[:is_not]
                    value[:value].each do |v|
                      @filter += "filter( !exists {?concept <#{@model.class.graph_name}id> \"#{v}\"})"
                    end
                  else
                    @filter += "?concept <#{@model.class.graph_name}id> ?__search FILTER (?__search IN(#{contains})) .\n"
                  end
                else
                  if ["=", "<", ">"].include?(value[:operator])
                    not_operator = value[:is_not] ? '!' : ''
                    value[:value].each do |v|
                      @filter += "?concept <#{metadata[:path]}> ?__search#{i} FILTER(?__search#{i} #{not_operator}#{value[:operator]} \"#{v}\") .\n"
                    end
                  else
                    @filter += "?concept <#{metadata[:path]}> ?__search#{i} FILTER(#{contains.empty? ? '""' : contains}) .\n"
                  end
                end
              end
              i += 1
            end
          end
        end
      end

      self
    rescue StandardError => e
      LOGGER.error(e.message)
      LOGGER.error(e.backtrace.join("\n"))
      raise Error::GeneralError, e.message
    end

    def count
      sparql_client = @sparql_client
      if model_construct?
        sparql_client = run_construct
      end

      relationship = ''
      core_query = core_query(relationship)
      count_query = core_query.gsub(/SELECT .* WHERE/, 'SELECT COUNT(distinct ?concept) as ?count WHERE')

      result = sparql_client.query(count_query)
      solution = result.first
      solution[:count].object || 0
    end

    private

    def model_construct?
      File.exist?("#{ConfigFile.path}/constructs/#{@model.name.tableize.singularize}.sparql")
    end

    def load_construct
      File.read("#{ConfigFile.path}/constructs/#{@model.name.tableize.singularize}.sparql")
      # query.gsub!('##filter##', @filter)
    end

    def run_construct
      created_at = nil
      parsed_graph_name = URI.parse(@model.class.graph_name)
      construct_graph_name = "#{parsed_graph_name.scheme}://#{@model.name.underscore}.#{parsed_graph_name.host}/"

      #check construct validity
      #result = @sparql_client.query("clear graph <#{construct_graph_name}>")
      result = @sparql_client.query("select * from <#{construct_graph_name}> where {<#{construct_graph_name}_metadata> <#{construct_graph_name}created_at> ?_created_at}")
      unless result.empty?
        created_at = result[0]._created_at.object
      end

      if created_at.nil? || (Time.now - created_at) > 1.day
        #result = @sparql_client.query("with <#{construct_graph_name}> delete {?s ?p ?o} where{?s ?p ?o}")
        result = @sparql_client.query("clear graph <#{construct_graph_name}>")
        LOGGER.info(result[0]['callret-0'].value)

        begin
          construct_query = load_construct
          result = @sparql_client.query(construct_query)
          LOGGER.info(result[0]['callret-0'].value)
        rescue Solis::Error::QueryError => e
          raise e
        else
          result = @sparql_client.query("insert into <#{construct_graph_name}> { <#{construct_graph_name}_metadata> <#{construct_graph_name}created_at> \"#{Time.now.xmlschema}\"^^xsd:dateTime}")
          LOGGER.info(result[0]['callret-0'].value)
        end

      end

      SPARQL::Client.new(@sparql_endpoint, { graph: construct_graph_name })
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

      sparql_client = model_construct? ? run_construct : @sparql_client
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
    end

    def core_query(relationship)
      core_query = %(
SELECT distinct (?concept AS ?s) WHERE {
  VALUES ?type {#{target_class}}
  ?concept ?role ?objects.
  #{relationship}
  ?concept a ?type .
  #{@sort_select}
  #{@filter}
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

              unless solution_model.metadata[:attributes][attribute][:node_kind].nil?
                node_class = solution_model.metadata[:attributes][attribute][:class].value.split('/').last
                object = solution_model.graph.shape_as_model(node_class).new({ id: object.split('/').last })
              end

              if data.key?(attribute)
                raise "Cardinality error, max = #{solution_model.metadata[:attributes][attribute][:maxcount]}" if solution_model.metadata[:attributes][attribute][:maxcount] == 0
                if solution_model.metadata[:attributes][attribute][:maxcount] == 1
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

    def graph_to_json(graph)
      parsed_json = ::JSON.parse(graph.dump(:jsonld))
      result = []
      parsed_json.map do |m|
        result << build_object(m)
      end
      result
    end

    def build_object(m)
      klass_metadata = @shapes.select do |_, v|
        if m.key?('@type')
          m['@type'].first.eql?(v[:target_class].value)
        else
          m.keys.select { |s| s =~ /^http/ }.first.eql?(v[:target_class].value)
        end
      end.first || nil
      if klass_metadata.nil?
        klass_metadata = @shapes.select { |_, v| @model.class.metadata[:target_class].value.eql?(v[:target_class].value) }.to_a.flatten
      end

      if klass_metadata
        klass_name = klass_metadata[0]
        data = {}
        klass_metadata[1][:attributes].each do |attribute, metadata|
          if metadata.key?(:node_kind) && !metadata[:node_kind].nil?
            internal_result = []
            next unless m.key?(metadata[:path])

            m[metadata[:path]].map { |s| s.transform_keys { |k| k.gsub(/^@/, '') } }.select { |s| s.keys.first.eql?('id') }.map { |m| m['id'] }.each do |id|
              if metadata[:node_kind].nil?
                internal_result << @model.class.graph.shape_as_model(attribute.classify).new({ id: id.split('/').last })
                # internal_result << @model.class.graph.shape_as_model(attribute.classify).new.query.filter({ filters: { id: id.split('/').last } }).find_all.map { |a| a }
              else
                internal_result << @model.class.graph.shape_as_model(metadata[:datatype].to_s).new({ id: id.split('/').last })
                # internal_result << @model.class.graph.shape_as_model(metadata[:datatype].to_s).new.query.filter({ filters: { id: id.split('/').last } }).find_all.map { |a| a }
              end
            end
            data[attribute] = internal_result.flatten
          elsif m.key?(metadata[:path])
            data_attribute = m[metadata[:path]].map { |s| s['@value'] }.compact
            data_attribute = data_attribute.size == 1 ? data_attribute.first : data_attribute
            data[attribute] = data_attribute
          end
        end
        data['id'] = begin
                       m[klass_metadata[1][:attributes]['id'][:path]].map { |s| s['@value'] }.first
                     rescue StandardError
                       m['@id']
                     end
      end

      data&.delete_if { |_k, v| v.nil? || v.try(:empty?) }
      @model.class.graph.shape_as_model(klass_name).new(data)
    end
  end
end
