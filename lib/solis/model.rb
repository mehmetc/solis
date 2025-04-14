require 'securerandom'
require 'iso8601'
require 'hashdiff'
require_relative 'query'

module Solis
  class Model

    class_attribute :before_read_proc, :after_read_proc, :before_create_proc, :after_create_proc, :before_update_proc, :after_update_proc, :before_delete_proc, :after_delete_proc

    def initialize(attributes = {})
      @model_name = self.class.name
      @model_plural_name = @model_name.pluralize
      @language = Graphiti.context[:object]&.language || Solis::Options.instance.get[:language] || 'en'

      raise "Please look at /#{@model_name.tableize}/model for structure to supply" if attributes.nil?

      attributes.each do |attribute, value|
        if self.class.metadata[:attributes].keys.include?(attribute.to_s)
          if !self.class.metadata[:attributes][attribute.to_s][:node_kind].nil? && !(value.is_a?(Hash) || value.is_a?(Array) || value.class.ancestors.include?(Solis::Model))
            raise Solis::Error::InvalidAttributeError, "'#{@model_name}.#{attribute}' must be an object"
          end

          if self.class.metadata[:attributes][attribute.to_s][:node_kind].is_a?(RDF::URI) && value.is_a?(Hash)
            inner_model = self.class.graph.shape_as_model(self.class.metadata[:attributes][attribute.to_s][:datatype].to_s)
            value = inner_model.new(value)
          elsif self.class.metadata[:attributes][attribute.to_s][:node_kind].is_a?(RDF::URI) && value.is_a?(Array)
            new_value = []
            value.each do |v|
              if v.is_a?(Hash)
                inner_model = self.class.graph.shape_as_model(self.class.metadata[:attributes][attribute.to_s][:datatype].to_s)
                new_value << inner_model.new(v)
              else
                new_value << v
              end
            end
            value = new_value
          end

          # switched off. currently language query parameters returns the value
          # value = {
          #   "@language" => @language,
          #   "@value" => value
          # } if self.class.metadata[:attributes][attribute.to_s][:datatype_rdf].eql?('http://www.w3.org/1999/02/22-rdf-syntax-ns#langString')

          value = value.first if value.is_a?(Array) && (attribute.eql?('id') || attribute.eql?(:id))

          instance_variable_set("@#{attribute}", value)
        else
          raise Solis::Error::InvalidAttributeError, "'#{attribute}' is not part of the definition of #{@model_name}"
        end
      end

      self.class.make_id_for(self)
      # id = instance_variable_get("@id")
      # if id.nil? || (id.is_a?(String) && id&.empty?)
      #   instance_variable_set("@id", SecureRandom.uuid)
      # end
    rescue StandardError => e
      Solis::LOGGER.error(e.message)
      raise Solis::Error::GeneralError, "Unable to create entity #{@model_name}"
    end

    def name(plural = false)
      if plural
        @model_plural_name
      else
        @model_name
      end
    end

    def query
      raise "I need a SPARQL endpoint" if self.class.sparql_endpoint.nil?

      # before_read_proc&.call(self)
      result = Solis::Query.new(self)
      # after_read_proc&.call(result)
      result
    end

    def to_ttl(resolve_all = true)
      graph = as_graph(self, resolve_all)
      graph.dump(:ttl)
    end

    def dump(format = :ttl, resolve_all = true)
      graph = as_graph(self, resolve_all)
      graph.dump(format)
    end

    def to_graph(resolve_all = true)
      as_graph(self, resolve_all)
    end

    def valid?
      begin
        graph = as_graph(self, false)
      rescue Solis::Error::InvalidAttributeError => e
        Solis::LOGGER.error(e.message)
      end

      shacl = SHACL.get_shapes(self.class.graph.instance_variable_get(:"@graph"))
      report = shacl.execute(graph)

      report.conform?
    rescue StandardError => e
      false
    end

    def destroy
      raise "I need a SPARQL endpoint" if self.class.sparql_endpoint.nil?
      sparql = SPARQL::Client.new(self.class.sparql_endpoint)

      raise Solis::Error::QueryError, "#{self.id} is still referenced, refusing to delete" if is_referenced?(sparql)
      # sparql.query('delete{}')
      before_delete_proc&.call(self)
      #      graph = as_graph(self, false)
      #      Solis::LOGGER.info graph.dump(:ttl) if ConfigFile[:debug]

      query = %(
with <#{self.class.graph_name}>
delete {?s ?p ?o}
where {
values ?s {<#{self.graph_id}>}
?s ?p ?o }
      )
      result = sparql.query(query)

      #      result = sparql.delete_data(graph, graph: graph.name)
      after_delete_proc&.call(result)
      result
    end

    def save(validate_dependencies = true, top_level = true)
      raise "I need a SPARQL endpoint" if self.class.sparql_endpoint.nil?
      sparql = SPARQL::Client.new(self.class.sparql_endpoint)

      before_create_proc&.call(self)

      if self.exists?(sparql)
        data = properties_to_hash(self)

        result = update(data)
      else
        data = properties_to_hash(self)
        attributes = data.include?('attributes') ? data['attributes'] : data
        attributes.each_pair do |key, value| # check each key. if it is an entity process it
          unless self.class.metadata[:attributes][key][:node].nil? #is it an entity
            value = [value] unless value.is_a?(Array)
            value.each do |sub_value|
              embedded = self.class.graph.shape_as_model(self.class.metadata[:attributes][key][:datatype].to_s).new(sub_value)
              embedded_readonly_entities = Solis::Options.instance.get[:embedded_readonly].map{|s| s.to_s} || []

              if (embedded.class.ancestors.map{|s| s.to_s} & embedded_readonly_entities).empty? || top_level
                if embedded.exists?(sparql)
                  embedded_data = properties_to_hash(embedded)
                  embedded.update(embedded_data, validate_dependencies, false)
                else
                  embedded.save(validate_dependencies, false)
                end
              else
                Solis::LOGGER.info("#{embedded.class.name} is embedded not allowed to change. Skipping")
              end
            end
          end
        end

        graph = as_graph(self, validate_dependencies)

        # File.open('/Users/mehmetc/Dropbox/AllSources/LP/graphiti-api/save.ttl', 'wb') do |file|
        #   file.puts graph.dump(:ttl)
        # end
        Solis::LOGGER.info SPARQL::Client::Update::InsertData.new(graph, graph: graph.name).to_s if ConfigFile[:debug]

        result = sparql.insert_data(graph, graph: graph.name)
      end

      after_create_proc&.call(self)
      self
    rescue StandardError => e
      Solis::LOGGER.error e.message
      Solis::LOGGER.error e.message
      raise e
    end

    def update(data, validate_dependencies = true, top_level = true)
      raise Solis::Error::GeneralError, "I need a SPARQL endpoint" if self.class.sparql_endpoint.nil?

      attributes = data.include?('attributes') ? data['attributes'] : data
      raise "id is mandatory when updating" unless attributes.keys.include?('id')

      id = attributes.delete('id')

      sparql = SPARQL::Client.new(self.class.sparql_endpoint)
      #sparql = Solis::Store::Sparql::Client.new(self.class.sparql_endpoint, self.class.graph_name)

      original_klass = self.query.filter({ language: nil, filters: { id: [id] } }).find_all.map { |m| m }&.first
      raise Solis::Error::NotFoundError if original_klass.nil?
      updated_klass = original_klass.deep_dup

      attributes.each_pair do |key, value| # check each key. if it is an entity process it
        unless original_klass.class.metadata[:attributes][key][:node].nil? #it is an entity
          value = [value] unless value.is_a?(Array)
          value.each do |sub_value|
            embedded = self.class.graph.shape_as_model(original_klass.class.metadata[:attributes][key][:datatype].to_s).new(sub_value)

            embedded_readonly_entities = Solis::Options.instance.get[:embedded_readonly].map{|s| s.to_s} || []

            if (embedded.class.ancestors.map{|s| s.to_s} & embedded_readonly_entities).empty? || top_level
              if embedded.exists?(sparql)
                embedded_data = properties_to_hash(embedded)
                embedded.update(embedded_data, validate_dependencies, false)
              else
                embedded_value = embedded.save(validate_dependencies, false)
                value = updated_klass.instance_variable_get("@#{key}").deep_dup
                if value.is_a?(Array)
                  value << embedded_value
                else
                  value = embedded_value
                end
              end
            else
              Solis::LOGGER.info("#{embedded.class.name} is embedded not allowed to change. Skipping")
            end
          end
        end

        updated_klass.instance_variable_set("@#{key}", value)
      end

      before_update_proc&.call(original_klass, updated_klass)

      properties_orignal_klass = properties_to_hash(original_klass)
      properties_updated_klass = properties_to_hash(updated_klass)

      if Hashdiff.best_diff(properties_orignal_klass, properties_updated_klass).empty?
        Solis::LOGGER.info("#{original_klass.class.name} unchanged, skipping")
        data = self.query.filter({ filters: { id: [id] } }).find_all.map { |m| m }&.first
      else

        delete_graph = as_graph(original_klass, false)

        where_graph = RDF::Graph.new(graph_name: RDF::URI("#{self.class.graph_name}#{self.name.tableize}/#{id}"), data: RDF::Repository.new)

        if id.is_a?(Array)
          id.each do |i|
            where_graph << [RDF::URI("#{self.class.graph_name}#{self.name.tableize}/#{i}"), :p, :o]
          end
        else
          where_graph << [RDF::URI("#{self.class.graph_name}#{self.name.tableize}/#{id}"), :p, :o]
        end

        insert_graph = as_graph(updated_klass, true)

        # puts delete_graph.dump(:ttl) if ConfigFile[:debug]
        # puts insert_graph.dump(:ttl) if ConfigFile[:debug]
        # puts where_graph.dump(:ttl) if ConfigFile[:debug]

        # if ConfigFile[:debug]
        delete_insert_query = SPARQL::Client::Update::DeleteInsert.new(delete_graph, insert_graph, where_graph, graph: insert_graph.name).to_s
        delete_insert_query.gsub!('_:p', '?p')
        # puts delete_insert_query
        data = sparql.query(delete_insert_query)
        # pp data
        # end

        #      sparql.delete_insert(delete_graph, insert_graph, where_graph, graph: insert_graph.name)

        data = self.query.filter({ filters: { id: [id] } }).find_all.map { |m| m }&.first
        if data.nil?
          sparql.insert_data(insert_graph, graph: insert_graph.name)
          data = self.query.filter({ filters: { id: [id] } }).find_all.map { |m| m }&.first
        end
      end
      after_update_proc&.call(updated_klass, data)

      data
      #rescue EOFError => e
    rescue StandardError => e
      original_graph = as_graph(original_klass, false)
      Solis::LOGGER.error(e.message)
      Solis::LOGGER.error original_graph.dump(:ttl)
      Solis::LOGGER.error delete_insert_query
      sparql.insert_data(original_graph, graph: original_graph.name)

      raise e
    end

    def graph_id
      "#{self.class.graph_name}#{self.name.tableize}/#{self.id}"
    end

    def is_referenced?(sparql)
      sparql.query("ASK WHERE { ?s ?p <#{self.graph_id}>. filter (!contains(str(?p), '_audit'))}")
    end

    def exists?(sparql)
      sparql.query("ASK WHERE { <#{self.graph_id}> ?p ?o }")
    end

    def self.make_id_for(model)
      raise "I need a SPARQL endpoint" if self.sparql_endpoint.nil?
      sparql = SPARQL::Client.new(self.sparql_endpoint)
      id = model.instance_variable_get("@id")
      if id.nil? || (id.is_a?(String) && id&.empty?)
        id_retries = 0

        while id.nil? || sparql.query("ASK WHERE { ?s <#{self.graph_name}id>  \"#{id}\" }")
          id = SecureRandom.uuid
          id_retries+=1
        end
        LOGGER.info("ID(#{id}) generated for #{self.name} in #{id_retries} retries") if ConfigFile[:debug]
        model.instance_variable_set("@id", id)
      elsif id.to_s =~ /^https?:\/\//
        id = id.to_s.split('/').last
        LOGGER.info("ID(#{id}) normalised for #{self.name}") if ConfigFile[:debug]
        model.instance_variable_set("@id", id)
      end
      model
    rescue StandardError => e
      Solis::LOGGER.error(e.message)
      raise Solis::Error::GeneralError, "Error generating id for #{@model_name}"
    end

    def self.metadata
      @metadata
    end

    def self.metadata=(m)
      @metadata = m
    end

    def self.shapes=(s)
      @shapes = s
    end

    def self.shapes
      @shapes
    end

    def self.graph_name
      @graph_name
    end

    def self.graph_name=(graph_name)
      @graph_name = graph_name
    end

    def self.graph_prefix=(graph_prefix)
      @graph_prefix = graph_prefix
    end

    def self.graph_prefix
      @graph_prefix
    end

    def self.sparql_endpoint
      @sparql_endpoint
    end

    def self.sparql_endpoint=(sparql_endpoint)
      @sparql_endpoint = sparql_endpoint
    end

    def self.graph
      @graph
    end

    def self.graph=(graph)
      @graph = graph
    end

    def self.language
      Graphiti.context[:object]&.language || Solis::Options.instance.get[:language] || @language || 'en'
    end

    def self.language=(language)
      @language = language
    end

    def self.model(level = 0)
      m = { type: self.name.tableize, attributes: {} }
      self.metadata[:attributes].each do |attribute, attribute_metadata|

        if attribute_metadata.key?(:class) && !attribute_metadata[:class].nil? && attribute_metadata[:class].value =~ /#{self.graph_name}/ && level == 0
          cm = self.graph.shape_as_model(self.metadata[:attributes][attribute][:datatype].to_s).model(level + 1)
          m[:attributes][attribute.to_sym] = cm[:attributes]
        else
          m[:attributes][attribute.to_sym] = { description: attribute_metadata[:comment]&.value,
                                               mandatory: (attribute_metadata[:mincount].to_i > 0),
                                               data_type: attribute_metadata[:datatype] }
        end
      end

      m
    end

    def self.model_template(level = 0)
      m = { type: self.name.tableize, attributes: {} }
      self.metadata[:attributes].each do |attribute, attribute_metadata|

        if attribute_metadata.key?(:class) && !attribute_metadata[:class].nil? && attribute_metadata[:class].value =~ /#{self.graph_name}/ && level == 0
          cm = self.graph.shape_as_model(self.metadata[:attributes][attribute][:datatype].to_s).model_template(level + 1)
          m[:attributes][attribute.to_sym] = cm[:attributes]
        else
          m[:attributes][attribute.to_sym] = ''
        end
      end

      m
    end

    def self.construct(level = 0)
      raise 'to bo implemented'
    end

    def self.model_before_read(&blk)
      self.before_read_proc = blk
    end

    def self.model_after_read(&blk)
      self.after_read_proc = blk
    end

    def self.model_before_create(&blk)
      self.before_create_proc = blk
    end

    def self.model_after_create(&blk)
      self.after_create_proc = blk
    end

    def self.model_before_update(&blk)
      self.before_update_proc = blk
    end

    def self.model_after_update(&blk)
      self.after_update_proc = blk
    end

    def self.model_before_delete(&blk)
      self.before_delete_proc = blk
    end

    def self.model_after_delete(&blk)
      self.after_delete_proc = blk
    end

    private

    def as_graph(klass = self, resolve_all = true)
      graph = RDF::Graph.new
      graph.name = RDF::URI(self.class.graph_name)
      id = build_ttl_objekt2(graph, klass, [], resolve_all)

      graph
    end

    def build_ttl_objekt2(graph, klass, hierarchy = [], resolve_all = true)
      hierarchy.push("#{klass.name}(#{klass.instance_variables.include?(:@id) ? klass.instance_variable_get("@id") : ''})")

      graph_name = self.class.graph_name
      klass_name = klass.class.name
      klass_metadata = klass.class.metadata
      uuid = klass.instance_variable_get("@id") || SecureRandom.uuid
      id = RDF::URI("#{graph_name}#{klass_name.tableize}/#{uuid}")

      graph << [id, RDF::RDFV.type, klass_metadata[:target_class]]

      # load existing object and overwrite
      original_klass = klass.query.filter({ filters: { id: [uuid] } }).find_all { |f| f.id == uuid }.first || nil

      if original_klass.nil?
        original_klass = klass
      else
        resolve_all = false
        klass.instance_variables.map { |m| m.to_s.gsub(/^@/, '') }
             .select { |s| !["model_name", "model_plural_name"]
                              .include?(s) }.each do |attribute, value|
          data = klass.instance_variable_get("@#{attribute}")
          original_data = original_klass.instance_variable_get("@#{attribute.to_s}")
          original_klass.instance_variable_set("@#{attribute}", data) unless original_data.eql?(data)
        end
      end

      make_graph(graph, hierarchy, id, original_klass, klass_metadata, resolve_all)

      hierarchy.pop
      id
    end

    def make_graph(graph, hierarchy, id, klass, klass_metadata, resolve_all)
      klass_metadata[:attributes].each do |attribute, metadata|
        data = klass.instance_variable_get("@#{attribute}")

        if data.nil? && metadata.key?(:mincount) && ( metadata[:mincount].nil? || metadata[:mincount] > 0) && graph.query(RDF::Query.new({ attribute.to_sym => { RDF.type => metadata[:node] } })).size == 0
          if data.nil?
            uuid = id.value.split('/').last
            original_klass = klass.query.filter({ filters: { id: [ uuid ] } }).find_all { |f| f.id == uuid }.first || nil
            unless original_klass.nil?
              klass = original_klass
              data = klass.instance_variable_get("@#{attribute}")
            end
          end
          #if data is still nil
          raise Solis::Error::InvalidAttributeError, "#{hierarchy.join('.')}~#{klass.name}.#{attribute} min=#{metadata[:mincount]} and max=#{metadata[:maxcount]}" if data.nil?
        end

        if data && metadata.key?(:maxcount) && ( metadata[:maxcount] && metadata[:maxcount] > 0) && graph.query(SPARQL.parse("select (count(?s) as ?max_subject) where { ?s #{self.class.graph_prefix}:#{attribute} ?p}")).first.max_subject > metadata[:maxcount].to_i
          raise Solis::Error::InvalidAttributeError, "#{hierarchy.join('.')}~#{klass.name}.#{attribute} min=#{metadata[:mincount]} and max=#{metadata[:maxcount]}" if data.nil?
        end

        # skip if nil or an object that is empty
        next if data.nil? || ([Hash, Array, String].include?(data.class) && data&.empty?)

        case metadata[:datatype_rdf]
        when 'http://www.w3.org/2001/XMLSchema#boolean'
          data = false if data.nil?
        when 'http://www.w3.org/1999/02/22-rdf-syntax-ns#JSON'
          data = data.to_json
        end

        # make it an object
        unless metadata[:node_kind].nil?
          model = self.class.graph.shape_as_model(metadata[:datatype].to_s)
          if data.is_a?(Hash)
            data = model.new(data)
          elsif data.is_a?(Array)
            data = data.map { |m| m.is_a?(Hash) ? model.new(m) : m }
          end
        end

        data = [data] unless data.is_a?(Array)

        data.each do |d|
          if defined?(d.name) && self.class.graph.shape?(d.name) && resolve_all
            if self.class.graph.shape_as_model(d.name.to_s).metadata[:attributes].select { |_, v| v[:node_kind].is_a?(RDF::URI) }.size > 0 &&
              hierarchy.select { |s| s =~ /^#{d.name.to_s}/ }.size == 0
              internal_resolve = false
              d = build_ttl_objekt2(graph, d, hierarchy, internal_resolve)
            elsif self.class.graph.shape_as_model(d.name.to_s) && hierarchy.select { |s| s =~ /^#{d.name.to_s}/ }.size == 0
              internal_resolve = false
              d = build_ttl_objekt2(graph, d, hierarchy, internal_resolve)
            else
              # d = "#{klass.class.graph_name}#{attribute.tableize}/#{d.id}"
              d = "#{klass.class.graph_name}#{d.name.tableize}/#{d.id}"
            end
          elsif defined?(d.name) && self.class.graph.shape?(d.name)
            d = "#{klass.class.graph_name}#{d.name.tableize}/#{d.id}"
          end

          if d.is_a?(Array) && d.length == 1
            d = d.first
          end

          d = if metadata[:datatype_rdf].eql?('http://www.w3.org/1999/02/22-rdf-syntax-ns#langString')
                if d.is_a?(Hash) && (d.keys - ["@language", "@value"]).size == 0
                  if d['@value'].is_a?(Array)
                    d_r = []
                    d['@value'].each do |v|
                      d_r << RDF::Literal.new(v, language: d['@language'])
                    end
                    d_r
                  else
                    RDF::Literal.new(d['@value'], language: d['@language'])
                  end
                else
                  RDF::Literal.new(d, language: @language)
                end
              elsif metadata[:datatype_rdf].eql?('http://www.w3.org/2001/XMLSchema#anyURI') || metadata[:node].is_a?(RDF::URI)
                RDF::URI(d)
              elsif metadata[:datatype_rdf].eql?('http://www.w3.org/2006/time#DateTimeInterval')
                begin
                  datatype = metadata[:datatype_rdf]
                  RDF::Literal.new(ISO8601::TimeInterval.parse(d).to_s, datatype: datatype)
                rescue StandardError => e
                  raise Solis::Error::InvalidDatatypeError, "#{hierarchy.join('.')}.#{attribute}: #{e.message}"
                end
              else
                datatype = RDF::Vocabulary.find_term(metadata[:datatype_rdf])
                datatype = metadata[:node] if datatype.nil?
                datatype = metadata[:datatype_rdf] if datatype.nil?
                RDF::Literal.new(d, datatype: datatype)
              end

          unless d.valid?
            LOGGER.warn("Invalid datatype for #{hierarchy.join('.')}.#{attribute}")
          end

          if d.is_a?(Array)
            d.each do |v|
              graph << [id, RDF::URI("#{metadata[:path]}"), v]
            end
          else
            graph << [id, RDF::URI("#{metadata[:path]}"), d]
          end
        end
      end
    rescue StandardError => e
      Solis::LOGGER.error(e.message)
      raise e
    end

    def build_ttl_objekt(graph, klass, hierarchy = [], resolve_all = true)
      hierarchy.push("#{klass.name}(#{klass.instance_variables.include?(:@id) ? klass.instance_variable_get("@id") : ''})")
      sparql_endpoint = self.class.sparql_endpoint
      if klass.instance_variables.include?(:@id) && hierarchy.length > 1
        unless sparql_endpoint.nil?
          existing_klass = klass.query.filter({ filters: { id: [klass.instance_variable_get("@id")] } }).find_all { |f| f.id == klass.instance_variable_get("@id") }
          if !existing_klass.nil? && !existing_klass.empty? && existing_klass.first.is_a?(klass.class)
            klass = existing_klass.first
          end
        end
      end

      uuid = klass.instance_variable_get("@id") || SecureRandom.uuid
      id = RDF::URI("#{self.class.graph_name}#{klass.class.name.tableize}/#{uuid}")
      graph << [id, RDF::RDFV.type, klass.class.metadata[:target_class]]

      klass.class.metadata[:attributes].each do |attribute, metadata|
        data = klass.instance_variable_get("@#{attribute}")
        if data.nil? && metadata[:datatype_rdf].eql?('http://www.w3.org/2001/XMLSchema#boolean')
          data = false
        end

        if metadata[:datatype_rdf].eql?("http://www.w3.org/1999/02/22-rdf-syntax-ns#JSON")
          data = data.to_json
        end

        if data.nil? && metadata[:mincount] > 0
          raise Solis::Error::InvalidAttributeError, "#{hierarchy.join('.')}.#{attribute} min=#{metadata[:mincount]} and max=#{metadata[:maxcount]}"
        end

        next if data.nil? || ([Hash, Array, String].include?(data.class) && data&.empty?)

        data = [data] unless data.is_a?(Array)
        model = nil
        model = klass.class.graph.shape_as_model(klass.class.metadata[:attributes][attribute][:datatype].to_s) unless klass.class.metadata[:attributes][attribute][:node_kind].nil?

        data.each do |d|
          original_d = d
          if model
            target_node = model.metadata[:target_node].value.split('/').last.gsub(/Shape$/, '')
            if model.ancestors[0..model.ancestors.find_index(Solis::Model) - 1].map { |m| m.name }.include?(target_node)
              parent_model = model.graph.shape_as_model(target_node)
            end
          end

          if model && d.is_a?(Hash)
            # TODO: figure out in what use case we need the parent_model
            # model_instance = if parent_model
            #                     parent_model.new(d)
            #                  else
            #                     model.new(d)
            #                  end

            # model_instance = model.new(d)
            model_instance = model.descendants.map { |m| m&.new(d) rescue nil }.compact.first || nil
            model_instance = model.new(d) if model_instance.nil?

            if resolve_all
              d = build_ttl_objekt(graph, model_instance, hierarchy, false)
            else
              real_model = model_instance.query.filter({ filters: { id: model_instance.id } }).find_all { |f| f.id == model_instance.id }&.first
              d = RDF::URI("#{self.class.graph_name}#{real_model ? real_model.name.tableize : model_instance.name.tableize}/#{model_instance.id}")
            end
          elsif model && d.is_a?(model)
            if resolve_all
              if parent_model
                model_instance = parent_model.new({ id: d.id })
                d = build_ttl_objekt(graph, model_instance, hierarchy, false)
              else
                d = build_ttl_objekt(graph, d, hierarchy, false)
              end
            else
              real_model = model.new.query.filter({ filters: { id: d.id } }).find_all { |f| f.id == d.id }&.first
              d = RDF::URI("#{self.class.graph_name}#{real_model ? real_model.name.tableize : model.name.tableize}/#{d.id}")
            end
          else
            datatype = RDF::Vocabulary.find_term(metadata[:datatype_rdf] || metadata[:node])
            if datatype && datatype.datatype?
              d = if metadata[:datatype_rdf].eql?('http://www.w3.org/1999/02/22-rdf-syntax-ns#langString')
                    RDF::Literal.new(d, language: self.class.language)
                  else
                    if metadata[:datatype_rdf].eql?('http://www.w3.org/2001/XMLSchema#anyURI')
                      RDF::URI(d)
                    else
                      RDF::Literal.new(d, datatype: datatype)
                    end
                  end
              d = (d.object.value rescue d.object) unless d.valid?
            end
          end

          graph << [id, RDF::URI("#{self.class.graph_name}#{attribute}"), d]
        end
      end
      hierarchy.pop
      id
    end

    def properties_to_hash(model)
      n = {}
      model.class.metadata[:attributes].each_key do |m|
        if model.instance_variable_get("@#{m}").is_a?(Array)
          n[m] = model.instance_variable_get("@#{m}").map { |iv| iv.class.ancestors.include?(Solis::Model) ? properties_to_hash(iv) : iv }
        elsif model.instance_variable_get("@#{m}").class.ancestors.include?(Solis::Model)
          n[m] = properties_to_hash(model.instance_variable_get("@#{m}"))
        else
          n[m] = model.instance_variable_get("@#{m}")
        end
      end

      n.compact!
      n
    end
  end
end