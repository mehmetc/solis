require_relative 'model/reader'

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

    def to_shacl
      shacl = StringIO.new
      Solis::Model::Writer.to_uri(uri: shacl, namespace: @namespace, prefix: @prefix, model: @graph)
      shacl.rewind
      shacl.read
    end

    def list
      @graph.query([nil, RDF::Vocab::SHACL.targetClass, nil]).map do |klass|
        klass.object.to_s
      end
    end
  end
end