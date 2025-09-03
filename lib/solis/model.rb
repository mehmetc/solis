require_relative 'model/reader'
require_relative 'model/writer'
require_relative "validator/validatorV1"
require_relative "validator/validatorV2"
require_relative "model/literals/edtf"
require_relative "model/literals/iso8601"
require_relative "model/parser/shacl"
require_relative "utils/namespace"
require_relative "utils/prefix_resolver"
require_relative "utils/jsonld"
require_relative "utils/string"
require 'tsort'
require 'active_support/core_ext/string/inflections'

module Solis
  class Model

    attr_reader :store, :graph, :namespace, :prefix, :uri, :content_type, :logger
    attr_reader :shapes, :validator, :hash_validator_literals, :namespace, :context, :context_inv
    attr_reader :hierarchy_ext, :hierarchy, :hierarchy_full
    attr_reader :dependencies, :sorted_dependencies
    attr_reader :plurals

    def initialize(params = {})
      raise Solis::Error::BadParameter, "Please provide a {model: {prefix: 'ex', namespace: 'http://example.com/', uri: 'file://cars.ttl', content_type: 'text/turtle'}}" unless params[:model]
      model = params[:model]
      raise Solis::Error::BadParameter, "One of :prefix, :namespace, :uri is missing" unless (model.keys & [:prefix, :namespace, :uri]).size == 3
      @logger = params[:logger] || Solis.logger([STDOUT])
      @logger.level = Logger::INFO
      @graph = Solis::Model::Reader.from_uri(model)
      @namespace = model[:namespace] || Solis::Utils::Namespace.detect_primary_namespace(@graph)
      @prefix = model[:prefix] || Solis::Utils::PrefixResolver.resolve_prefix(@namespace)
      @context = {
        "@vocab" => @namespace
      }
      context = {
        prefix => @namespace
      }
      namespaces = Solis::Utils::Namespace.extract_unique_namespaces(@graph)
      namespaces.each do |namespace|
        next if namespace.eql?(@namespace)
        prefix = Solis::Utils::PrefixResolver.resolve_prefix(namespace)
        context[prefix] = namespace
      end
      @context.merge!(context)
      @context_inv = context.invert
      @uri = model[:uri]
      @content_type = model[:content_type]
      @store = params[:store] || nil

      @title ||= model[:title] || "No Title"
      @version ||= model[:version] || "0.1"
      @version_counter ||= model[:version_counter] || 0
      @description ||= model[:description] || "No description"

      puts @graph.dump(:ttl)

      @plurals = model[:plurals] || {}

      @parser = SHACLParser.new(@graph)
      @shapes = @parser.parse_shapes
      @validator = Solis::SHACLValidatorV2.new(@graph, :graph, {
        path_dir: params[:tmp_dir]
      }) rescue Solis::SHACLValidatorV1.new(@graph, :graph, {})
      @hierarchy_ext = model[:hierarchy] || {}
      add_hierarchy_ext_to_shapes
      add_plurals_to_shapes
      @hierarchy = {}
      @hierarchy_full = {}
      make_hierarchy
      @dependencies = {}
      make_dependencies
      @sorted_dependencies = []
      make_sorted_dependencies
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
      options[:model] = self
      options[:namespace] ||= @namespace
      options[:prefix] ||= @prefix
      options[:graph] ||= @graph
      options[:title] ||= title
      options[:version] ||= version
      options[:description] ||= description
      options[:shapes] ||= @shapes
      options[:dependencies] ||= @dependencies
      options[:sorted_dependencies] ||= @sorted_dependencies

      case content_type
      when 'text/vnd.mermaid'
        options[:uri] = "mermaid://#{@prefix}"
        Solis::Model::Writer.to_uri(options)
      when 'text/vnd.plantuml'
        options[:uri] = "plantuml://#{@prefix}"
        Solis::Model::Writer.to_uri(options)
      when 'application/schema+json'
        options[:entities] = writer('application/entities+json', raw: true)[:entities]
        options[:uri] = "jsonschema://#{@prefix}"
        Solis::Model::Writer.to_uri(options)
      when 'application/entities+json'
        options[:uri] = "jsonentities://#{@prefix}"
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
      _get_object_for_preficate(RDF::Vocab::DC.title)# || Solis::Utils::Namespace.detect_primary_namespace(@graph, @namespace)
    end

    def title=(title)
      _set_object_for_preficate(RDF::Vocab::DC.title, title)
    end

    def description
      _get_object_for_preficate(RDF::Vocab::DC.description)
    end

    def description=(description)
      _set_object_for_preficate(RDF::Vocab::DC.description, description)
    end

    def version
      _get_object_for_preficate(RDF::Vocab::OWL.versionInfo)# || ''
    end

    def version_counter
      _get_object_for_preficate(RDF::URI(Solis::Model::Entity::URI_DB_OPTIMISTIC_LOCK_VERSION))# || 0
    end

    def version_counter=(version_counter)
      _set_object_for_preficate(RDF::URI(Solis::Model::Entity::URI_DB_OPTIMISTIC_LOCK_VERSION), version_counter)
    end

    def creator
      _get_object_for_preficate(RDF::Vocab::DC.creator, false)
    end

    def creator=(creator)
      _set_object_for_preficate(RDF::Vocab::DC.creator, creator)
    end

    def get_property_entity_for_entity(name_entity, name_attr)
      _get_property_entity_for_entity(name_entity, name_attr)
    end

    def get_property_datatype_for_entity(name_entity, name_attr)
      _get_property_datatype_for_entity(name_entity, name_attr)
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
      list[1..].uniq
    end

    def get_shape_for_entity(name_entity)
      name_shape = Shapes.get_shape_for_class(@shapes, name_entity)
      deep_copy(@shapes[name_shape])
    end

    def get_properties_info_for_entity(name_entity)
      properties = {}
      names_shapes = Shapes.get_shapes_for_class(@shapes, name_entity)
      names_shapes.each do |name_shape|
        property_shapes = deep_copy(@shapes[name_shape][:properties])
        merge_info_entity_properties!(properties, property_shapes_as_entity_properties(property_shapes))
      end
      names_entities_parents = get_all_parent_entities_for_entity(name_entity)
      names_entities_parents.each do |name_entity_parent|
        names_shapes_parent = Shapes.get_shapes_for_class(@shapes, name_entity_parent)
        names_shapes_parent.each do |name_shape_parent|
          property_shapes_parent = deep_copy(@shapes[name_shape_parent][:properties])
          properties_parent = property_shapes_as_entity_properties(property_shapes_parent)
          merge_info_entity_properties!(properties, properties_parent)
        end
      end
      properties
    end

    def get_own_properties_list_for_entity(name_entity)
      list_properties = []
      names_shapes = Shapes.get_shapes_for_class(@shapes, name_entity)
      names_shapes.each do |name_shape|
        property_shapes = deep_copy(@shapes[name_shape][:properties])
        list_properties.concat(property_shapes.values.map { |v| v[:path] })
      end
      list_properties
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

    def _get_property_entity_for_entity(name_entity, name_attr)
      res = nil
      # first check directly in shape
      name_shape = Shapes.get_shape_for_class(@shapes, name_entity)
      res = Shapes.get_property_class_for_shape(@shapes, name_shape, name_attr)
      if res.nil?
        # otherwise navigate classes hierarchy up and try again
        names_entities_parents = get_parent_entities_for_entity(name_entity)
        names_entities_parents.each do |name_entity_parent|
          next unless res.nil?
          res = _get_property_entity_for_entity(name_entity_parent, name_attr)
        end unless names_entities_parents.nil?
      end
      res
    end

    def _get_property_datatype_for_entity(name_entity, name_attr)
      res = nil
      # first check directly in shape
      name_shape = Shapes.get_shape_for_class(@shapes, name_entity)
      res = Shapes.get_property_datatype_for_shape(@shapes, name_shape, name_attr)
      if res.nil?
        # otherwise navigate classes hierarchy up and try again
        names_entities_parents = get_parent_entities_for_entity(name_entity)
        names_entities_parents.each do |name_entity_parent|
          next unless res.nil?
          res = _get_property_datatype_for_entity(name_entity_parent, name_attr)
        end unless names_entities_parents.nil?
      end
      res
    end

    def _get_parent_entities_for_entity(name_entity)
      names_entities_parents = []
      names_shapes = Shapes.get_shapes_for_class(@shapes, name_entity)
      names_shapes.each do |name_shape|
        names_nodes_parents = Shapes.get_parent_shapes_for_shape(@shapes, name_shape)
        names_entities_parents += names_nodes_parents.map do |uri|
          res = @shapes.select { |k,v| v[:uri] == uri }
          res[uri][:target_class] rescue nil
        end.compact.uniq
      end
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
        @shapes[name_shape][:plural] = name_plural unless name_plural.nil?
        snake_case_name_entity = Solis::Utils::String.camel_to_snake(Solis::Utils::String.extract_name_from_uri(name_entity))
        @shapes[name_shape][:plural] ||= snake_case_name_entity.pluralize
      end
    end

    def add_hierarchy_ext_to_shapes
      @hierarchy_ext.each do |name_base_entity, names_base_entities_parents|
        name_entity = Solis::Utils::JSONLD.expand_term(name_base_entity, @context)
        names_shapes = Shapes.get_shapes_for_class(@shapes, name_entity)
        if names_shapes.empty?
          name_shape = "#{name_entity}Shape"
          @shapes[name_shape] = {properties: {}, uri: name_shape, target_class: name_entity, nodes: [], closed: false, plural: nil}
          names_shapes = [name_shape]
        end
        names_base_entities_parents.each do |name_base_entity_parent|
          name_entity_parent = Solis::Utils::JSONLD.expand_term(name_base_entity_parent, @context)
          names_shapes_parent = Shapes.get_shapes_for_class(@shapes, name_entity_parent)
          names_shapes_parent.each do |name_shape_parent|
            names_shapes.each do |name_shape|
              @shapes[name_shape][:nodes] << @shapes[name_shape_parent][:uri]
            end
          end
        end
      end
    end

    def property_shapes_as_entity_properties(property_shapes)
      properties = {}
      property_shapes.each_value do |shape|
        unless properties.key?(shape[:path])
          properties[shape[:path]] = { constraints: [] }
        end
        constraints = deep_copy(shape[:constraints])
        if constraints.key?(:or)
          constraints[:or].map! do |o|
            h = {
              o[:path] => o
            }
            property_shapes_as_entity_properties(h).values[0]
          end
        end
        properties[shape[:path]][:constraints] << {
          description: shape[:description],
          data: constraints
        }
      end
      properties
    end

    def merge_info_entity_properties!(properties_1, properties_2)
      properties_2.each do |k, v|
        if properties_1.key?(k)
          properties_1[k][:constraints].concat(v[:constraints])
        else
          properties_1[k] = v
        end
      end
    end

    def make_hierarchy
      names_entities = Shapes.get_all_classes(@shapes)
      names_entities.each do |name_entity|
        @hierarchy[name_entity] = get_parent_entities_for_entity(name_entity)
        @hierarchy_full[name_entity] = get_all_parent_entities_for_entity(name_entity)
      end
    end

    def make_dependencies
      @dependencies = {}
      append_to_deps = lambda do |name_entity, data_property, dependencies|
        data_property[:constraints].each do |constraint|
          info = constraint[:data]
          if info.key?(:class)
            dependencies[name_entity] << info[:class]
          end
          if info.key?(:or)
            info[:or].each do |data_property_or|
              append_to_deps.call(name_entity, data_property_or, dependencies)
            end
          end
        end
      end
      entities = writer('application/entities+json', raw: true)[:entities]
      entities.each do |name_entity, data_entity|
        @dependencies[name_entity] = []
        data_entity[:own_properties].each do |name_property|
          data_property = data_entity[:properties][name_property]
          append_to_deps.call(name_entity, data_property, @dependencies)
        end
        @dependencies[name_entity].uniq!
      end
    end

    def make_sorted_dependencies
      begin
        @sorted_dependencies = TSortableHash[@dependencies].tsort
      rescue
        puts "circular deps found in @dependencies"
        @sorted_dependencies = @dependencies.keys
      end
    end

  end
end
