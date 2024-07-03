require 'graphiti'
require 'moneta'
require 'active_support/all'
require 'uri'

require_relative 'shape'
require_relative 'model'
require_relative 'resource'
require_relative 'options'

module Solis
  class Graph
    attr_accessor :options, :default_before_read, :default_after_read, :default_before_create, :default_after_create, :default_before_update, :default_after_update, :default_before_delete, :default_after_delete

    def initialize(graph, options = {})
      raise "Please provide a graph_name, graph_prefix and sparql_endpoint option" if options.nil? || options.empty?
      cloned_options = options.clone

      Solis::Options.instance.set = options

      @global_resource_stack = []
      @graph = graph
      @graph_name = cloned_options.delete(:graph_name) || '/'
      @graph_prefix = cloned_options.delete(:graph_prefix) || 'pf0'
      @sparql_endpoint = cloned_options.delete(:sparql_endpoint) || nil

      if cloned_options&.key?(:hooks) && cloned_options[:hooks].is_a?(Hash)
        hooks = cloned_options[:hooks]

        if hooks.key?(:read)
          if hooks[:read].key?(:before)
            @default_before_read = hooks[:read][:before]
          end

          if hooks[:read].key?(:after)
            @default_after_read = hooks[:read][:after]
          end
        end

        if hooks.key?(:create)
          if hooks[:create].key?(:before)
            @default_before_create = hooks[:create][:before]
          end

          if hooks[:create].key?(:after)
            @default_after_create = hooks[:create][:after]
          end
        end

        if hooks.key?(:update)
          if hooks[:update].key?(:before)
            @default_before_update = hooks[:update][:before]
          end

          if hooks[:update].key?(:after)
            @default_after_update = hooks[:update][:after]
          end
        end

        if hooks.key?(:delete)
          if hooks[:delete].key?(:before)
            @default_before_delete = hooks[:delete][:before]
          end
          if hooks[:delete].key?(:after)
            @default_after_delete = hooks[:delete][:after]
          end
        end
      end

      unless @sparql_endpoint.nil?
        uri = URI.parse(@sparql_endpoint)
        @sparql_endpoint = RDF::Repository.new(uri: RDF::URI(@graph_name), title: uri.host) if uri.scheme.eql?('repository')
      end

      @inflections = cloned_options.delete(:inflections) || nil
      @shapes = Solis::Shape.from_graph(graph)
      @language = cloned_options.delete(:language) || 'en'

      unless @inflections.nil?
        raise "Inflection file not found #{File.absolute_path(@inflections)}" unless File.exist?(@inflections)
        JSON.parse(File.read(@inflections)).each do |s, p|
          raise "No plural found" if s.nil? && p.nil?
          raise "No plural found for #{p}" if s.nil?
          raise "No plural found for #{s}" if p.nil?
          ActiveSupport::Inflector.inflections.irregular(s, p)
        end
      end

      @shape_tree = {}
      shape_keys = @shapes.map do |shape_name, _|
        if shape_name.empty?
          LOGGER.warn("Dangling entity found #{_[:target_class].to_s} removing")
          next
        end
        #@shapes[shape_name][:attributes].select { |_, metadata| metadata.key?(:node_kind) && !metadata[:node_kind].nil? }.values.map { |m| m[:datatype].to_s.split('#').last }
        @shapes[shape_name][:attributes].select { |_, metadata| metadata.key?(:node_kind) && !metadata[:node_kind].nil? }.values.map { |m| m[:datatype].to_s }
      end
      shape_keys += @shapes.keys
      shape_keys = shape_keys.flatten.compact.sort.uniq

      shape_keys.each do |shape_name|
        d = @shape_tree.key?(shape_name) ? @shape_tree[shape_name] : 0
        d += 1
        @shape_tree[shape_name] = d
      end

      @shape_tree = @shape_tree.sort_by(&:last).reverse.to_h

      shape_keys.each do |s|
        shape_as_model(s)
      end

      @shape_tree.each do |shape_name, _|
        shape_as_resource(shape_name)
      end

      Graphiti.configure do |config|
        config.pagination_links = true
        config.context_for_endpoint= ->(path, action) {
          Solis::NoopEndpoint.new(path, action)
        }
      end

      Graphiti.setup!
    end

    def list_shapes
      @shapes.keys.sort
    end

    def shape?(key)
      @shapes.key?(key)
    end

    def jsonapi_schema
      Graphiti::Schema.generate.to_json
    end

    def shape_as_model(shape_name)
      raise Solis::Error::NotFoundError, "'#{shape_name}' not found. Available classes are #{list_shapes.join(', ')}" unless shape?(shape_name)
      return Object.const_get(shape_name) if Object.const_defined?(shape_name)

      LOGGER.info("Creating model #{shape_name}")
      attributes = @shapes[shape_name][:attributes].keys.map { |m| m.to_sym }

      model = nil
      parent_model = nil
      if @shapes[shape_name].key?(:target_node) && @shapes[shape_name][:target_node].value =~ /^#{@graph_name}(.*)Shape$/
        parent_shape_model = $1
        parent_model = shape_as_model(parent_shape_model)

        model = Object.const_set(shape_name, ::Class.new(parent_model) do
          attr_accessor(*attributes)
        end)
      else
        model = Object.const_set(shape_name, ::Class.new(Solis::Model) do
          attr_accessor(*attributes)
        end)
      end

      model.graph_name = @graph_name
      model.graph_prefix = @graph_prefix
      model.shapes = @shapes
      model.metadata = @shapes[shape_name]
      #model.language = Graphiti.context[:object]&.language || Solis::Options.instance.get[:language] || @language || 'en'
      unless parent_model.nil?
        parent_model.metadata[:attributes].each do |k, v|
          unless model.metadata[:attributes].key?(k)
            model.metadata[:attributes][k] = v
          end
        end
      end
      model.sparql_endpoint = @sparql_endpoint
      model.graph = self

      model.model_before_read do |original_class|
        @default_before_read.call(original_class)
      end if @default_before_read

      model.model_after_read do |persisted_class|
        @default_after_read.call(persisted_class)
      end if @default_after_read

      model.model_before_create do |original_class|
        @default_before_create.call(original_class)
      end if @default_before_create

      model.model_after_create do |persisted_class|
        @default_after_create.call(persisted_class)
      end if @default_after_create

      model.model_before_update do |original_class, updated_class|
        @default_before_update.call(original_class, updated_class)
      end if @default_before_update

      model.model_after_update do |updated_class, persisted_class|
        @default_after_update.call(updated_class, persisted_class)
      end if @default_after_update

      model.model_before_delete do |updated_class|
        @default_before_delete.call(updated_class)
      end if @default_before_delete

      model.model_after_delete do |persisted_class|
        @default_after_delete.call(persisted_class)
      end if @default_after_delete

      model
    end

    def shape_as_resource(shape_name, stack_level = [])
      model = shape_as_model(shape_name)
      resource_name = "#{shape_name}Resource"

      raise Solis::Error::NotFoundError, "#{shape_name} not found. Available classes are #{list_shapes.join(', ')}" unless shape?(shape_name)
      return Object.const_get(resource_name) if Object.const_defined?(resource_name)

      LOGGER.info("Creating resource #{resource_name}")

      attributes = @shapes[shape_name][:attributes].select { |_, metadata| metadata.key?(:node_kind) && metadata[:node_kind].nil? }

      relations = @shapes[shape_name][:attributes].select { |_, metadata| metadata.key?(:node_kind) && !metadata[:node_kind].nil? }

      @global_resource_stack << resource_name
      relations.each_key do |k|
        next if relations[k][:node_kind].is_a?(RDF::URI) && relations[k][:class].value.gsub(@graph_name, '').gsub('Shape', '').eql?(shape_name)
        relation_shape = relations[k][:class].value.gsub(@graph_name, '').gsub('Shape', '')
        if relation_shape =~ /\//
          relation_shape = relations[k][:class].value.split('/').last.gsub('Shape','')
        end

        shape_as_resource(relation_shape, stack_level << relation_shape) unless stack_level.include?(relation_shape)
      end

      description = @shapes[shape_name][:comment]
      parent_resource = Resource
      descendants = ObjectSpace.each_object(Class).select { |klass| klass < model }.map { |m| "#{m.to_s}Resource" }

      graph = self

      #Resource
      if Object.const_defined?(resource_name)
        resource = Object.const_get(resource_name)
      else
        ###################
        # Define new resource
        resource = Object.const_set(resource_name, ::Class.new(Resource) do
          if descendants.length > 0
            self.polymorphic = descendants
            self.polymorphic << resource_name
            self.polymorphic.uniq!
          end

          self.model = model
          self.type = model.name.demodulize.underscore.pluralize.to_sym
          self.description = description

          attributes.each do |key, metadata|
            next if key.nil? || key.empty?
            if key.eql?('id')
              attribute key.to_sym, :uuid, description: metadata[:comment]
            else
              if (metadata[:maxcount] && metadata[:maxcount] > 1 || metadata[:maxcount].nil?) && ![:boolean, :hash, :array].include?(metadata[:datatype])
                datatype = "array_of_#{metadata[:datatype]}s".to_sym
              else
                datatype = metadata[:datatype]
              end
              LOGGER.info "\t#{resource_name}.#{key}(#{datatype})"
              attribute key.to_sym, datatype, description: metadata[:comment]
            end
          end
        end)

        relations.each do |key, value|
          #          next if value[:datatype].to_s.classify.eql?(shape_name) #why skip self relations...
          if (value[:mincount] && value[:mincount] > 1 || value[:mincount].nil?) || (value[:maxcount] && value[:maxcount] > 1 || value[:maxcount].nil?)
            belongs_to_resource_name = value[:datatype].nil? ? value[:class].value.gsub(self.model.graph_name, '') : value[:datatype].to_s.tableize.classify
            LOGGER.info "\t\t\t#{resource_name}(#{resource_name.gsub('Resource','').tableize.singularize}) belongs_to #{belongs_to_resource_name}(#{key})"
            resource.belongs_to(key.to_sym, foreign_key: :id, resource: graph.shape_as_resource("#{belongs_to_resource_name}", stack_level << belongs_to_resource_name)) do
              #resource.attribute key.to_sym, :string, only: [:filterable]

              link do |resource|
                remote_resources = resource.instance_variable_get("@#{key}")
                if remote_resources
                  remote_resources = [remote_resources] unless remote_resources.is_a?(Array)
                  resource_ids = remote_resources.map do |remote_resource|
                    remote_resource.id =~ /^http/ ? remote_resource.id.split('/').last : remote_resource.id
                  end

                end

                "#{resource.class.graph_name.gsub(/\/$/,'')}/#{belongs_to_resource_name.tableize}?filter[id]=#{resource_ids.join(',')}" unless remote_resources.nil? || resource_ids.empty?
              end
            end
          else
            has_many_resource_name = value[:datatype].nil? ? value[:class].gsub(self.model.graph_name, '') : value[:datatype].to_s.classify
            LOGGER.info "\t\t\t#{resource_name}(#{resource_name.gsub('Resource','').tableize.singularize}) has_many #{has_many_resource_name}(#{key})"
            resource.has_many(key.to_sym, foreign_key: :id, primary_key: :id, resource: graph.shape_as_resource("#{has_many_resource_name}", stack_level << has_many_resource_name)) do

              belongs_to_resource = graph.shape_as_resource("#{has_many_resource_name}")

              belongs_to_resource.belongs_to(resource.model.name.tableize.singularize, foreign_key: :id, primary_key: :id, resource: graph.shape_as_resource(resource.model.name)) do
                link do |resource|
                  ids=[]
                  remote_resources = resource.instance_variable_get("@#{shape_name.tableize.singularize}")
                  if remote_resources
                    remote_resources = [remote_resources] unless remote_resources.is_a?(Array)
                    resource_ids = remote_resources.map do |remote_resource|
                      remote_resource.id =~ /^http/ ? remote_resource.id.split('/').last : remote_resource.id
                    end
                  end
                  #"#{resource.class.graph_name.gsub(/\/$/,'')}/#{belongs_to_resource.name.tableize}?filter[id]=#{resource_ids.join(',')}" unless remote_resources.nil? || resource_ids.empty?
                  "#{resource.class.graph_name.gsub(/\/$/,'')}/#{remote_resources.first.name.tableize}?filter[id]=#{resource_ids.join(',')}" unless remote_resources.nil? || resource_ids.empty?
                end
              end
              #
              link do |resource|
                remote_resources = resource.instance_variable_get("@#{key}")
                if remote_resources
                  remote_resources = [remote_resources] unless remote_resources.is_a?(Array)
                  resource_ids = remote_resources.map do |remote_resource|
                    remote_resource.id =~ /^http/ ? remote_resource.id.split('/').last : remote_resource.id
                  end

                end
                "#{resource.class.graph_name.gsub(/\/$/,'')}/#{remote_resources.first.name.tableize}?filter[id]=#{resource_ids.join(',')}" unless remote_resources.nil? || resource_ids.empty?
              end
            end
          end

          resource.filter :"#{key}_id", :string, single: true, only: [:eq, :not_eq] do
            eq do |scope, filter_value|
              scope[:filters][key.to_sym] = filter_value
              scope
            end

            not_eq do |scope, filter_value|
              scope[:filters][key.to_sym] = {value: [filter_value], operator: '=', is_not: true}
              scope
            end
          end

        end
      end
      resource.sparql_endpoint = @sparql_endpoint
      resource.endpoint_namespace = "#{resource.model.graph_name.gsub(/\/$/,'')}#{Solis::Options.instance.get[:base_path]}"
      resource
    end

    def flush_all(graph_name=nil, force = false)
      raise Solis::Error::NotFoundError, "Supplied graph_name '#{graph_name}' does not equal graph name defined in config file '#{@graph_name}', set force to true" unless graph_name.eql?(@graph_name) && !force

      @sparql_client = SPARQL::Client.new(@sparql_endpoint)
      result = @sparql_client.query("with <#{graph_name}> delete {?s ?p ?o} where{?s ?p ?o}")
      LOGGER.info(result)
      true
    end

  end
end