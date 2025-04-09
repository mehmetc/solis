require_relative 'model/reader'
require_relative 'model/writer'

module Solis
  class Model
    attr_reader :graph, :namespace, :prefix, :uri, :content_type, :logger
    def initialize(params = {})
      raise Solis::Error::BadParameter, "Please provide a {model: {prefix: 'ex', namespace: 'http://example.com/', uri: 'file://cars.ttl', content_type: 'text/turtle'}}" unless params[:model]
      model = params[:model]
      raise Solis::Error::BadParameter, "One of :prefix, :namespace, :uri is missing" unless (model.keys & [:prefix, :namespace, :uri]).size == 3
      @logger = params[:logger] || Solis.logger([STDOUT])
      @namespace = model[:namespace]
      @prefix = model[:prefix]
      @uri = model[:uri]
      @content_type = model[:content_type]

      @graph = Solis::Model::Reader.from_uri(model)
    end

    def list
      #TODO: what about multiple namespaces?
      data = @graph.query([nil, RDF::Vocab::SHACL.targetClass, nil]).map do |klass|
        klass.object.to_s
        #klass.object.to_s.gsub(@namespace,'')
      end

      data
    end

    def entity(name)

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
      else
        shacl = StringIO.new
        Solis::Model::Writer.to_uri(uri: shacl, namespace: @namespace, prefix: @prefix, model: @graph, content_type: content_type)
        shacl.rewind
        shacl.read
      end
    end
  end
end