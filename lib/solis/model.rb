require_relative 'model/reader'
require_relative 'model/writer'
require_relative "validator/validatorV1"
require_relative "validator/validatorV2"
require_relative "model/literals/edtf"
require_relative "model/literals/iso8601"

module Solis
  class Model

    attr_accessor :title, :version, :description
    attr_reader :graph, :namespace, :prefix, :uri, :content_type, :logger
    attr_reader :shapes, :validator, :hash_validator_literals, :namespace, :hierarchy
    attr_reader :plurals

    def initialize(params = {})
      raise Solis::Error::BadParameter, "Please provide a {model: {prefix: 'ex', namespace: 'http://example.com/', uri: 'file://cars.ttl', content_type: 'text/turtle'}}" unless params[:model]
      model = params[:model]
      raise Solis::Error::BadParameter, "One of :prefix, :namespace, :uri is missing" unless (model.keys & [:prefix, :namespace, :uri]).size == 3
      @logger = params[:logger] || Solis.logger([STDOUT])
      @logger.level = Logger::INFO
      @namespace = model[:namespace]
      @prefix = model[:prefix]
      @uri = model[:uri]
      @content_type = model[:content_type]
      @store = params[:store] || nil

      @title= model[:title] || "No Title"
      @version = model[:version] || "0.1"
      @description = model[:description]

      @plurals = model[:plurals] || {}

      @graph = Solis::Model::Reader.from_uri(model)
      inject_plurals_to_shapes_graph

      @parser = SHACLParser.new(@graph)
      @shapes = @parser.parse_shapes
      @validator = Solis::SHACLValidatorV2.new(@graph, :graph, {
        path_dir: params[:tmp_dir]
      }) rescue Solis::SHACLValidatorV1.new(@graph, :graph, {})
      @hierarchy = model[:hierarchy] || {}
      add_hierarchy_to_shapes
    end

    def entity
      class << self
        def new(name, data = {})
          Solis::Model::Entity.new(data, self, name, @store)
        end
        def list(options={namespace: false})
          data = @graph.query([nil, RDF::Vocab::SHACL.targetClass, nil]).map do |klass|
            options.key?(:namespace) && options[:namespace].eql?(true) ? klass.object.to_s : klass.object.to_s.gsub(@namespace,'')
          end
        end
      end

      self
    end

    ## Export model as a shacl, mermaid, plantuml diagram
    def writer(content_type = 'text/turtle', options = {})
      options[:namespace] ||= @namespace
      options[:prefix] ||= @prefix
      options[:model] ||= @graph
      options[:title] ||= @title
      options[:version] ||= @version
      options[:description] ||= @description

      case content_type
      when 'text/vnd.mermaid'
        options[:uri] = "mermaid://#{@prefix}"
        Solis::Model::Writer.to_uri(options)
      when 'text/vnd.plantuml'
        Solis::Model::Writer.to_uri(uri: "plantuml://#{@prefix}", namespace: @namespace, prefix: @prefix, model: @graph)
      when 'application/schema+json'
        options[:uri] = "jsonschema://#{@prefix}"
        Solis::Model::Writer.to_uri(options)
      when 'application/form'
        options[:uri] = "form://#{@prefix}"
        Solis::Model::Writer.to_uri(options)
      when 'application/openapi.json'
        options[:uri] = "openapi://#{@prefix}"
        Solis::Model::Writer.to_uri(options)
      else
        shacl = StringIO.new
        Solis::Model::Writer.to_uri(uri: shacl, namespace: @namespace, prefix: @prefix, model: @graph, content_type: content_type)
        shacl.rewind
        shacl.read
      end
    end

    def get_embedded_entity_type_for_entity(name_entity, name_attr)
      _get_embedded_entity_type_for_entity(name_entity, name_attr)
    end

    def get_datatype_for_entity(name_entity, name_attr)
      _get_datatype_for_entity(name_entity, name_attr)
    end

    def get_parent_entities_for_entity(name_entity)
      _get_parent_entities_for_entity(name_entity)
    end

    def get_all_parent_entities_for_entity(name_entity)
      list = [name_entity]
      idx = 0
      while true
        if idx >= list.length
          break
        end
        list += _get_parent_entities_for_entity(list[idx])
        idx += 1
      end
      list[1..]
    end

    def get_info_for_entity(name_entity)
      @shapes[name_entity]
    end

    def get_properties_info_for_entity(name_entity)
      properties = @shapes[name_entity][:properties]
      names_entities_parents = get_all_parent_entities_for_entity(name_entity)
      names_entities_parents.each do |name_entity_parent|
        properties.merge!(@shapes[name_entity_parent][:properties])
      end
      properties
    end

    private

    def _get_embedded_entity_type_for_entity(name_entity, name_attr)
      res = nil
      # first check directly in shape
      if SHACLSHapes.shape_exists?(@shapes, name_entity)
        res = SHACLSHapes.get_property_class_for_shape(@shapes, name_entity, name_attr)
      end
      if res.nil?
        # otherwise navigate classes hierarchy up and try again
        names_entities_parents = get_parent_entities_for_entity(name_entity)
        names_entities_parents.each do |name_entity_parent|
          next unless res.nil?
          res = _get_embedded_entity_type_for_entity(name_entity_parent, name_attr)
        end unless names_entities_parents.nil?
      end
      res
    end

    def _get_datatype_for_entity(name_entity, name_attr)
      res = nil
      # first check directly in shape
      if SHACLSHapes.shape_exists?(@shapes, name_entity)
        res = SHACLSHapes.get_property_datatype_for_shape(@shapes, name_entity, name_attr)
      end
      if res.nil?
        # otherwise navigate classes hierarchy up and try again
        names_entities_parents = get_parent_entities_for_entity(name_entity)
        names_entities_parents.each do |name_entity_parent|
          next unless res.nil?
          res = _get_datatype_for_entity(name_entity_parent, name_attr)
        end unless names_entities_parents.nil?
      end
      res
    end

    def _get_parent_entities_for_entity(name_entity)
      names_entities_parents = []
      names_nodes_parents = SHACLSHapes.get_parent_shapes_for_shape(@shapes, name_entity)
      names_entities_parents += names_nodes_parents.map do |uri|
        res = nil
        @shapes.each do |k, v|
          next unless v[:uri] == uri
          res = k
        end
        res
      end.compact
      names_entities_parents
    end

    def inject_plurals_to_shapes_graph
      @graph.query([nil, RDF.type, RDF::Vocab::SHACL.NodeShape]) do |shape|
        shape_name = @graph.query([shape.subject, RDF::Vocab::SHACL.name, nil]).first_object.to_s
        plural_name = @plurals[shape_name]
        unless plural_name.nil?
          # this one seems more specific: https://oscaf.sourceforge.net/nao.html#nao:pluralPrefLabel.
          # for now uses skos:altLabel: https://www.w3.org/2012/09/odrl/semantic/draft/doco/skos_altLabel.html
          @graph << [shape.subject, RDF::Vocab::SKOS.altLabel, plural_name]
        end
      end
    end

    def add_hierarchy_to_shapes
      @hierarchy.each do |name_entity, names_entities_parents|
        unless @shapes.key?(name_entity)
          @shapes[name_entity] = {properties: {}, uri: "#{name_entity}Shape", nodes: [], closed: false, plural: nil}
        end
        names_entities_parents.each do |name_entity_parent|
          @shapes[name_entity][:nodes] << @shapes[name_entity_parent][:uri]
        end
      end
    end

  end
end
