require 'securerandom'
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

          value = {
            "@language" => @language,
            "@value" => value
          } if self.class.metadata[:attributes][attribute.to_s][:datatype_rdf].eql?('http://www.w3.org/1999/02/22-rdf-syntax-ns#langString')
          value = value.first if value.is_a?(Array) && (attribute.eql?('id') || attribute.eql?(:id))

          instance_variable_set("@#{attribute}", value)
        else
          raise Solis::Error::InvalidAttributeError, "'#{attribute}' is not part of the definition of #{@model_name}"
        end
      end

      id = instance_variable_get("@id")
      if id.nil? || (id.is_a?(String) && id&.empty?)
        instance_variable_set("@id", SecureRandom.uuid)
      end
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

      #before_read_proc&.call(self)
      result = Solis::Query.new(self)
      #after_read_proc&.call(result)
      result
    end

    def to_ttl(resolve_all=true)
      graph = as_graph(self, resolve_all)
      graph.dump(:ttl)
    end

    def dump(format=:ttl, resolve_all=true)
      graph = as_graph(self, resolve_all)
      graph.dump(format)
    end

    def to_graph(resolve_all=true)
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
      before_delete_proc&.call(self)

      sparql = SPARQL::Client.new(self.class.sparql_endpoint)
      graph = as_graph(klass=self, resolve_all=false)
      Solis::LOGGER.info graph.dump(:ttl) if ConfigFile[:debug]

      result = sparql.delete_data(graph, graph: graph.name)
      after_delete_proc&.call(result)
      result
    end

    def save(validate_dependencies=true)
      raise "I need a SPARQL endpoint" if self.class.sparql_endpoint.nil?

      before_create_proc&.call(self)
      sparql = SPARQL::Client.new(self.class.sparql_endpoint)
      graph = as_graph(self, validate_dependencies)

      # File.open('/Users/mehmetc/Dropbox/AllSources/LP/graphiti-api/save.ttl', 'wb') do |file|
      #   file.puts graph.dump(:ttl)
      # end
      Solis::LOGGER.info SPARQL::Client::Update::InsertData.new(graph, graph: graph.name).to_s if ConfigFile[:debug]

      result = sparql.insert_data(graph, graph: graph.name)
      after_create_proc&.call(result)
      result
    end

    def update(data, validate_dependencies=true)
      raise Solis::Error::GeneralError, "I need a SPARQL endpoint" if self.class.sparql_endpoint.nil?
      #raise Solis::Error::InvalidAttributeError,"data must contain attributes" unless data.keys.include?('attributes')
      #raise Solis::Error::GeneralError,"data must have a type" unless data.keys.include?('type')

      attributes = data.include?('attributes') ? data['attributes'] : data
      raise "id is mandatory in attributes" unless attributes.keys.include?('id')

      id = attributes.delete('id')

      sparql = SPARQL::Client.new(self.class.sparql_endpoint)

      original_klass = self.query.filter({ filters: { id: [id] } }).find_all.map { |m| m }&.first
      raise Solis::Error::NotFoundError if original_klass.nil?
      updated_klass = original_klass.deep_dup

      attributes.each_pair do |key, value|
        updated_klass.send(:"#{key}=", value)
      end

      before_update_proc&.call(original_klass, updated_klass)

      delete_graph = as_graph(original_klass, false)
      where_graph = RDF::Graph.new
      where_graph.name = RDF::URI(self.class.graph_name)
      if id.is_a?(Array)
        id.each do |i|
          where_graph << [RDF::URI("#{self.class.graph_name}#{self.name.tableize}/#{i}"), :p, :o]
        end
      else
        where_graph << [RDF::URI("#{self.class.graph_name}#{self.name.tableize}/#{id}"), :p, :o]
      end

      insert_graph = as_graph(updated_klass, validate_dependencies)

      Solis::LOGGER.info delete_graph.dump(:ttl) if ConfigFile[:debug]
      Solis::LOGGER.info insert_graph.dump(:ttl) if ConfigFile[:debug]
      Solis::LOGGER.info where_graph.dump(:ttl) if ConfigFile[:debug]


      sparql.delete_insert(delete_graph, insert_graph, where_graph, graph: insert_graph.name)
      data = self.query.filter({ filters: { id: [id] } }).find_all.map { |m| m }&.first
      if data.nil?
        sparql.insert_data(insert_graph, graph: insert_graph.name)
        data = self.query.filter({ filters: { id: [id] } }).find_all.map { |m| m }&.first
      end

      after_update_proc&.call(updated_klass, data)
      data
    rescue StandardError => e
      original_graph = as_graph(original_klass, false)
      Solis::LOGGER.error(e.message)
      Solis::LOGGER.error original_graph.dump(:ttl)
      sparql.insert_data(original_graph, graph: original_graph.name)

      raise e
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
      @language
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

      #load existing object and overwrite
      original_klass = klass.query.filter({ filters: { id: [uuid] } }).find_all { |f| f.id == uuid }.first || nil

      if original_klass.nil?
        original_klass = klass
      else
        klass.instance_variables.map{|m| m.to_s.gsub(/^@/,'')}
             .select{|s| !["model_name", "model_plural_name"]
             .include?(s)}.each do |attribute, value|
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


        raise Solis::Error::InvalidAttributeError,
              "#{hierarchy.join('.')}.#{attribute} min=#{metadata[:mincount]} and max=#{metadata[:maxcount]}" if data.nil? &&
                          metadata[:mincount] > 0 &&
                          graph.query(RDF::Query.new({attribute.to_sym => {RDF.type => metadata[:node]}})).size == 0

        # skip if nil or an object that is empty
        next if data.nil? || ([Hash, Array, String].include?(data.class) && data&.empty?)

        case metadata[:datatype_rdf]
        when 'http://www.w3.org/2001/XMLSchema#boolean'
          data = false if data.nil?
        when 'http://www.w3.org/1999/02/22-rdf-syntax-ns#JSON'
          data = data.to_json
        end

        #make it an object
        unless metadata[:node_kind].nil?
          model = self.class.graph.shape_as_model(metadata[:datatype].to_s)
          if data.is_a?(Hash)
            data = model.new(data)
          elsif data.is_a?(Array)
            data = data.map{|m| m.is_a?(Hash) ? model.new(m) : m}
          end
        end

        data = [data] unless data.is_a?(Array)

        data.each do |d|
          if defined?(d.name) && self.class.graph.shape?(d.name)
            if resolve_all
              d = build_ttl_objekt2(graph, d, hierarchy, false)
            else
              d = "#{klass.class.graph_name}#{attribute.tableize}/#{d.id}"
            end
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
                  RDF::Literal.new(d, language: self.class.language)
                end
              else
                if metadata[:datatype_rdf].eql?('http://www.w3.org/2001/XMLSchema#anyURI') || metadata[:node].is_a?(RDF::URI)
                  RDF::URI(d)
                else
                  datatype = RDF::Vocabulary.find_term(metadata[:datatype_rdf])
                  datatype = metadata[:node] if datatype.nil?
                  RDF::Literal.new(d, datatype: datatype)
                end
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
            #TODO: figure out in what use case we need the parent_model
            # model_instance = if parent_model
            #                     parent_model.new(d)
            #                  else
            #                     model.new(d)
            #                  end

            # model_instance = model.new(d)
            model_instance = model.descendants.map{|m| m&.new(d) rescue nil}.compact.first || nil
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
  end
end