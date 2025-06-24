require_relative 'model/reader'
require_relative 'model/writer'
require_relative "validator/validatorV1"
require_relative "validator/validatorV2"
require_relative "model/literals/edtf"
require_relative "model/literals/iso8601"
require_relative "utils/rdf"
require_relative "model/parser/shacl"
require_relative "utils/namespace"
require_relative "utils/prefix_resolver"
require_relative "utils/jsonld"

module Solis
  class Model

    attr_reader :store, :graph, :namespace, :prefix, :uri, :content_type, :logger
    attr_reader :shapes, :validator, :hash_validator_literals, :namespace, :hierarchy
    attr_reader :plurals

    def initialize(params = {})
      raise Solis::Error::BadParameter, "Please provide a {model: {prefix: 'ex', namespace: 'http://example.com/', uri: 'file://cars.ttl', content_type: 'text/turtle'}}" unless params[:model]
      model = params[:model]
      raise Solis::Error::BadParameter, "One of :prefix, :namespace, :uri is missing" unless (model.keys & [:prefix, :namespace, :uri]).size == 3
      @logger = params[:logger] || Solis.logger([STDOUT])
      @logger.level = Logger::INFO
      @namespace = model[:namespace] || Solis::Utils::Namespace.detect_primary_namespace(@graph)
      @prefix = model[:prefix] || Solis::Utils::PrefixResolver.resolve_prefix(@namespace)
      @context = {
        "@vocab" => @namespace,
        prefix => @namespace
      }
      @uri = model[:uri]
      @content_type = model[:content_type]
      @store = params[:store] || nil

      @title= model[:title] || "No Title"
      @version = model[:version] || "0.1"
      @description = model[:description]

      @plurals = model[:plurals] || {}

      @graph = Solis::Model::Reader.from_uri(model)

      @parser = SHACLParser.new(@graph)
      @shapes = @parser.parse_shapes
      @validator = Solis::SHACLValidatorV2.new(@graph, :graph, {
        path_dir: params[:tmp_dir]
      }) rescue Solis::SHACLValidatorV1.new(@graph, :graph, {})
      @hierarchy = model[:hierarchy] || {}
      add_hierarchy_to_shapes
      add_plurals_to_shapes
    end

    def entity
      class << self
        def new(name, data = {})
          Solis::Model::Entity.new(data, self, name, @store)
        end
        def all
          Solis::Utils::Namespace.extract_entities_for_namespace(@graph, @namespace)
        end
        def exists?(name)
          all.include?(name.classify)
        end
      end

      self
    end

    ## Export model as a shacl, mermaid, plantuml diagram
    def writer(content_type = 'text/turtle', options = {})
      options[:namespace] ||= @namespace
      options[:prefix] ||= @prefix
      options[:model] ||= @graph
      options[:title] ||= title
      options[:version] ||= version
      options[:description] ||= description
      options[:shapes] ||= @shapes

      case content_type
      when 'text/vnd.mermaid'
        options[:uri] = "mermaid://#{@prefix}"
        Solis::Model::Writer.to_uri(options)
      when 'text/vnd.plantuml'
        options[:uri] = "plantuml://#{@prefix}"
        Solis::Model::Writer.to_uri(options)
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
        options[:uri] = shacl
        options[:content_type] = content_type
        Solis::Model::Writer.to_uri(options)
        shacl.rewind
        shacl.read
      end
    end

    #attr_accessor :title, :version, :description, :creator
    def title
      _get_object_for_preficate(RDF::Vocab::DC.title) || Solis::Utils::Namespace.detect_primary_namespace(@graph, @namespace)
    end

    def title=(title)
      _set_object_for_preficate(RDF::Vocab::DC.title, title)
    end

    def description
      _get_object_for_preficate(RDF::Vocab::DC.description) || ''
    end

    def description=(description)
      _set_object_for_preficate(RDF::Vocab::DC.description, description)
    end

    def version
      _get_object_for_preficate(RDF::Vocab::OWL.versionInfo) || ''
    end

    def version=(version)
      _set_object_for_preficate(RDF::Vocab::OWL.versionInfo, version)
    end

    def creator
      _get_object_for_preficate(RDF::Vocab::DC.creator, false)
    end

    def creator=(creator)
      _set_object_for_preficate(RDF::Vocab::DC.creator, creator)
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

    def get_shape_for_entity(name_entity)
      name_shape = Shapes.get_shape_for_class(@shapes, name_entity)
      deep_copy(@shapes[name_shape])
    end

    def get_properties_info_for_entity(name_entity)
      name_shape = Shapes.get_shape_for_class(@shapes, name_entity)
      properties = deep_copy(@shapes[name_shape][:properties])
      names_entities_parents = get_all_parent_entities_for_entity(name_entity)
      names_entities_parents.each do |name_entity_parent|
        name_shape_parent = Shapes.get_shape_for_class(@shapes, name_entity_parent)
        properties.merge!(deep_copy(@shapes[name_shape_parent][:properties]))
      end
      properties
    end

    def find_entity_by_plural(plural)
      res = @shapes.select { |k,v| v[:plural] == plural }
      res[res.keys.first][:target_class] if res.keys.first
    end

    def generate_restful_api
      unless defined?(MainController)
        begin
          require_relative "model/restful_api/controllers/main_controller"
        rescue LoadError
          raise LoadError, "MainController is unavailable to load"
        end
      end

      MainController.model = self
      MainController.store = @store
      MainController
    end

    private

    def _ontology
      @graph.query([nil, RDF.type, RDF::Vocab::OWL.Ontology])
    end

    def _get_object_for_preficate(predicate, singleton = true)
      statements = @graph.query([RDF::URI(@namespace), predicate, nil])
      return nil if statements.empty?
      if singleton
        statements.each_statement do |statement|
          return statement&.object.value
        end
      else
        values = []
        statements.each_statement do |statement|
          values << statement&.object.value
        end
        return values
      end
    end

    def _set_object_for_preficate(predicate, object)
      #TODO: set a default working language
      language = nil
      ontology_uri = RDF::URI(@namespace)
      @graph << [ontology_uri, RDF.type, RDF::Vocab::OWL.Ontology] if _ontology.size == 0
      @graph.delete([ontology_uri, predicate, nil])
      object = [object] unless object.is_a?(Array)

      object.each do |o|
        if o =~ /^http/
          object = RDF::URI(o)
        else
          object = language ? RDF::Literal(o, language: language) : RDF::Literal(o)
        end
        @graph << [ontology_uri, predicate, object]
      end
    end

    def deep_copy(obj)
      Marshal.load(Marshal.dump(obj))
    end

    def _get_embedded_entity_type_for_entity(name_entity, name_attr)
      res = nil
      # first check directly in shape
      name_shape = Shapes.get_shape_for_class(@shapes, name_entity)
      res = Shapes.get_property_class_for_shape(@shapes, name_shape, name_attr)
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
      name_shape = Shapes.get_shape_for_class(@shapes, name_entity)
      res = Shapes.get_property_datatype_for_shape(@shapes, name_shape, name_attr)
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
      name_shape = Shapes.get_shape_for_class(@shapes, name_entity)
      names_nodes_parents = Shapes.get_parent_shapes_for_shape(@shapes, name_shape)
      names_entities_parents += names_nodes_parents.map do |uri|
        res = @shapes.select { |k,v| v[:uri] == uri }
        res[uri][:target_class] rescue nil
      end.compact
      names_entities_parents
    end

    def add_plurals_to_shapes
      keys_transform = {}
      @plurals.each_key do |name_base_entity|
        name_entity = Solis::Utils::JSONLD.expand_term(name_base_entity, @context)
        keys_transform[name_base_entity] = name_entity
      end
      plurals = @plurals.transform_keys(keys_transform)
      @shapes.each_key do |name_shape|
        name_entity = Shapes.get_target_class_for_shape(@shapes, name_shape)
        name_plural = plurals[name_entity]
        @shapes[name_shape][:plural] = name_plural
      end
    end

    def add_hierarchy_to_shapes
      @hierarchy.each do |name_base_entity, names_base_entities_parents|
        name_entity = Solis::Utils::JSONLD.expand_term(name_base_entity, @context)
        name_shape = Shapes.get_shape_for_class(@shapes, name_entity)
        if name_shape.nil?
          name_shape = "#{name_entity}Shape"
          @shapes[name_shape] = {properties: {}, uri: name_shape, target_class: name_entity, nodes: [], closed: false, plural: nil}
        end
        names_base_entities_parents.each do |name_base_entity_parent|
          name_entity_parent = Solis::Utils::JSONLD.expand_term(name_base_entity_parent, @context)
          name_shape_parent = Shapes.get_shape_for_class(@shapes, name_entity_parent)
          @shapes[name_shape][:nodes] << @shapes[name_shape_parent][:uri]
        end
      end
    end
  end
end
