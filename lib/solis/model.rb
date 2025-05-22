require_relative 'model/reader'
require_relative 'model/writer'
require_relative 'model/extension'

module Solis
  class Model
    include Solis::Model::Extension
    attr_accessor :title, :version, :description
    attr_reader :graph, :namespace, :prefix, :uri, :content_type, :logger
    attr_reader :shapes, :validator, :hash_validator_literals, :namespace, :hierarchy

    def initialize(params = {})
      raise Solis::Error::BadParameter, "Please provide a {model: {prefix: 'ex', namespace: 'http://example.com/', uri: 'file://cars.ttl', content_type: 'text/turtle'}}" unless params[:model]
      model = params[:model]
      raise Solis::Error::BadParameter, "One of :prefix, :namespace, :uri is missing" unless (model.keys & [:prefix, :namespace, :uri]).size == 3
      @logger = params[:logger] || Solis.logger([STDOUT])
      @namespace = model[:namespace]
      @prefix = model[:prefix]
      @uri = model[:uri]
      @content_type = model[:content_type]
      @store = params[:store] || nil

      @graph = Solis::Model::Reader.from_uri(model)

      @parser = SHACLParser.new(@graph)
      @shapes = @parser.parse_shapes
      @validator = Solis::SHACLValidatorV2.new(@graph, :graph, {
        path_dir: params[:tmp_dir]
      })
      hash_validator_literals_custom = model[:hash_validator_literals_custom] || {}
      @hash_validator_literals = Solis::Model::Literals.get_default_hash_validator
      @hash_validator_literals.merge!(hash_validator_literals_custom)
      @hierarchy = model[:hierarchy] || {}
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

        def properties(name)
          result = []
          @graph.query([nil, RDF::Vocab::SHACL.targetClass, RDF::URI("#{@namespace}#{name}")]) do |klass|
            shape = klass.subject
            @graph.query([shape, RDF::Vocab::SHACL.property, nil]) do |property|
              property_shape =  property.object
              path = @graph.query([property_shape, RDF::Vocab::SHACL.path, nil]).first&.object
              next unless path
              name = @graph.query([property_shape, RDF::Vocab::SHACL.name, nil]).first&.object
              result << name.to_s if name
            end
          end
          result
        end
      end

      self
    end

    ## Export model as a shacl, mermaid, plantuml diagram
    def writer(content_type = 'text/turtle', options = {})
      options[:namespace] ||= @namespace
      options[:prefix] ||= @prefix
      options[:model] ||= @graph

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
  end
end