require 'graphiti'
require 'moneta'
require 'active_support/all'

require_relative 'shape'
require_relative 'model'
require_relative 'resource'

module Solis
  class Graph
    def initialize(graph, options = {})
      @global_resource_stack = []
      @graph = graph
      @graph_name = options.delete(:graph_name) || '/'
      @graph_prefix = options.delete(:graph_prefix) || 'pf0'
      @sparql_endpoint = options.delete(:sparql_endpoint) || nil
      @inflections = options.delete(:inflections) || nil
      @shapes = Solis::Shape.from_graph(graph)
      @language = options.delete(:language) || 'nl'

      unless @inflections.nil?
        raise "Inflection file not found #{File.absolute_path(@inflections)}" unless File.exist?(@inflections)
        JSON.parse(File.read(@inflections)).each do |s, p|
          ActiveSupport::Inflector.inflections.irregular(s, p)
        end
      end

      @shape_tree = {}
      shape_keys = @shapes.map do |shape_name, _|
        if shape_name.empty?
          LOGGER.warn("Dangling entity found #{_[:target_class].to_s} removing")
          next
        end
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

      Graphiti.config.context_for_endpoint = ->(path, action) {
        Solis::NoopEndpoint.new(path, action)
      }

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

      # attributes << :id unless attributes.include?(:id)
      # attributes << :updated_at unless attributes.include?(:id)
      # attributes << :created_at unless attributes.include?(:id)

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
      model.language = @language
      unless parent_model.nil?
        parent_model.metadata[:attributes].each do |k, v|
          unless model.metadata[:attributes].key?(k)
            model.metadata[:attributes][k] = v
          end
        end
      end
      model.sparql_endpoint = @sparql_endpoint
      model.graph = self

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
              attribute key.to_sym, metadata[:datatype], description: metadata[:comment]
            end
          end
        end)

        relations.each do |key, value|
          next if value[:datatype].to_s.classify.eql?(shape_name)
          #if (value[:mincount] && value[:mincount] > 1) || (value[:maxcount] && value[:maxcount] > 1)
          if (value[:mincount] && value[:mincount] > 1 || value[:mincount].nil?) || (value[:maxcount] && value[:maxcount] > 1 || value[:maxcount].nil?)
            has_many_resource_name = value[:datatype].nil? ? value[:class].gsub(self.model.graph_name, '') : value[:datatype].to_s.classify
            LOGGER.info "\t a #{resource_name} has_many #{has_many_resource_name}"
            resource.has_many(key.to_sym, foreign_key: :id, primary_key: :id, resource: graph.shape_as_resource("#{has_many_resource_name}", stack_level << has_many_resource_name)) do

              belongs_to_resource = graph.shape_as_resource("#{has_many_resource_name}")
              belongs_to_resource.belongs_to(resource.model.name.tableize.singularize, foreign_key: :id, primary_key: :id, resource: graph.shape_as_resource(resource.model.name)) do
                link do |resource|
                  remote_resources = resource.instance_variable_get("@#{shape_name.tableize.singularize}")
                  if remote_resources
                    remote_resources = [remote_resources] unless remote_resources.is_a?(Array)
                    remote_resources = remote_resources.map do |remote_resource|
                      resource_id = remote_resource.id =~ /^http/ ? remote_resource.id.split('/').last : remote_resource.id
                      #"/#{key.tableize}/#{resource_id}"
                      "/#{belongs_to_resource_name.tableize}/#{resource_id}"
                    end

                    # return remote_resources.length == 1 ? remote_resources.first : remote_resources
                  end
                  remote_resources if remote_resources #has_many_belongs_to
                end
              end
              #
              link do |resource|
                remote_resources = resource.instance_variable_get("@#{key}")
                if remote_resources
                  remote_resources = [remote_resources] unless remote_resources.is_a?(Array)
                  remote_resources = remote_resources.map do |remote_resource|
                    resource_id = remote_resource.id =~ /^http/ ? remote_resource.id.split('/').last : remote_resource.id
                    #"/#{key.tableize}/#{resource_id}"
                    "/#{has_many_resource_name.tableize}/#{resource_id}"
                  end

                  #return remote_resources.length == 1 ? remote_resources.first : remote_resources
                end
                remote_resources.first if remote_resources
              end

            end
          else
            belongs_to_resource_name = value[:datatype].nil? ? value[:class].value.gsub(self.model.graph_name, '') : value[:datatype].to_s.tableize.classify
            LOGGER.info "\t A #{resource_name} belongs_to #{belongs_to_resource_name}"
            resource.belongs_to(key.to_sym, foreign_key: :id, resource: graph.shape_as_resource("#{belongs_to_resource_name}", stack_level << belongs_to_resource_name)) do

              link do |resource|
                remote_resources = resource.instance_variable_get("@#{key}")
                if remote_resources
                  remote_resources = [remote_resources] unless remote_resources.is_a?(Array)
                  remote_resources = remote_resources.map do |remote_resource|
                    resource_id = remote_resource.id =~ /^http/ ? remote_resource.id.split('/').last : remote_resource.id
                    #"/#{key.tableize}/#{resource_id}"
                    "/#{belongs_to_resource_name.tableize}/#{resource_id}"
                  end

                  #    return remote_resources.length == 1 ? remote_resources.first : remote_resources
                end

                remote_resources.first if remote_resources #belongs_to
              end
            end
          end
        end
      end
      resource.sparql_endpoint = @sparql_endpoint
      resource
    end
  end
end