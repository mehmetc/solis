require 'test_helper'

class TestIntegration < Minitest::Test
  def setup
    super

    @opts = {
      path_dir: File.join(__dir__, './data')
    }
  end
  def test_intregration_sioc_rdf
    # Configuration object it holds a store and model description
    config = {
      store: Solis::Store::Memory.new(),
      model: {
        prefix: 'sioc',
        namespace: 'http://rdfs.org/sioc/ns#',
        uri: "file://test/resources/sioc_rdf.xml",
        content_type: 'application/rdf+xml'
      }
    }
    # instantiate a logger
    logger = Solis.logger([STDOUT])
    # instantiate Solis with the configuration
    @solis = Solis.new(config)

    # create a ttl string object
    sioc_shacl = @solis.model.writer

    # File.open('./test/resources/sioc_shapes.ttl', 'wb') do |f|
    #   f.puts sioc_shacl
    # end

    # check if the generated SHACL is valid
    shacl_shacl = Solis::Model::Reader.from_uri(uri: 'file://test/resources/shacl-shacl.ttl', content_type: 'text/turtle')
    validator = Solis::SHACLValidatorV2.new(shacl_shacl.dump(:ttl), :ttl, @opts)
    conform, messages = validator.execute(RDF::Graph.new.from_ttl(sioc_shacl), :graph)
    assert_equal(true, conform)

    logger.info(messages.join("\n"))
    # TODO: How to add multiple namespaces to the graph.
    # for example: SIOC references DC and FOAF the SHACL is generated correctly but the prefix does not contain a reference to these

    post = @solis.model.entity.new('Post')
    properties = post.get_properties_info.keys

    assert_includes(@solis.model.entity.all, "Post")
    assert_includes(properties, 'title')

    data = {
      "title" => "Hello World",
      "created_at" => Time.now,
      "description" => "This is a post",
      "subject" => "Testing subject"
    }

    post = @solis.model.entity.new('Post', data)

    post.valid?
  end

  def test_integration_bibo_rdf

    graph_name = "http://purl.org/ontology/bibo/"
    config = {
      store: Solis::Store::Memory.new(graph: graph_name),
      model: {
        prefix: 'bibo',
        namespace: 'http://purl.org/ontology/bibo/',
        uri: "file://test/resources/bibo_owl.xml",
        content_type: 'application/rdf+xml'
      }
    }

    # instantiate Solis with the configuration
    @solis = Solis.new(config)

    # @solis.model.logger.level = Logger::DEBUG
    @solis.model.logger.level = Logger::INFO

    # create a ttl string object
    bibo_shacl = @solis.model.writer

    File.open('./test/resources/bibo_shapes.ttl', 'wb') do |f|
      f.puts bibo_shacl
    end

    # check if the generated SHACL is valid
    shacl_shacl = Solis::Model::Reader.from_uri(uri: 'file://test/resources/shacl-shacl.ttl', content_type: 'text/turtle')
    validator = Solis::SHACLValidatorV2.new(shacl_shacl.dump(:ttl), :ttl, @opts)
    conform, messages = validator.execute(RDF::Graph.new.from_ttl(bibo_shacl), :graph)
    assert_equal(0, messages.size)
    assert_equal(true, conform)

    #data = JSON.parse(URI.open('https://open-na.hosted.exlibrisgxroup.com/alma/32KUL_LIBIS_NETWORK/bibs/99122040101471').read)
    data = JSON.parse(File.read('test/resources/bibo/book_99122040101471.jsonld'))
    #data = JSON.parse(File.read('test/resources/bibo/alice_in_wonderland.jsonld'))
    bibo_record = @solis.model.entity.new('Book', data)

    # puts bibo_record.to_pretty_pre_validate_jsonld

    pp bibo_record.validate

    # TOFIX: SHACL generation from ontology
    assert_equal(true, bibo_record.valid?)
    result = bibo_record.save

    pp result

  end
end