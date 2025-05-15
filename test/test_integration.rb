require 'test_helper'

class TestIntegration < Minitest::Test
  def test_intregration_sioc_rdf
    @opts = {
      path_dir: File.join(__dir__, './data')
    }

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

    # mock = Solis::ModelMock.new(graph: @solis.model.graph,
    #                                     prefix: 'sioc',
    #                                     namespace: 'http://rdfs.org/sioc/ns#',
    #                                     uri: "file://test/resources/sioc_rdf.xml",
    #                                     content_type: 'application/rdf+xml')

    # create a ttl string object
    sioc_shacl = @solis.model.writer

    # check if the generated SHACL is valid
    shacl_shacl = Solis::Model::Reader.from_uri(uri: 'file://test/resources/shacl-shacl.ttl', content_type: 'text/turtle')
    validator = Solis::SHACLValidatorV2.new(shacl_shacl.dump(:ttl), :ttl, @opts)
    conform, messages = validator.execute(RDF::Graph.new.from_ttl(sioc_shacl), :graph)
    assert_equal(true, conform)

    logger.info(messages.join("\n"))
    # TODO: How to add multiple namespaces to the graph.
    # for example: SIOC references DC and FOAF the SHACL is generated correctly but the prefix does not contain a reference to these


    assert_includes(@solis.model.entity.list, "Post")
    assert_includes(@solis.model.entity.properties('Post'), 'title')

    data = {
      "title" => "Hello World",
      "created_at" => Time.now,
      "description" => "This is a post",
      "subject" => "Testing subject"
    }

    post = @solis.model.entity.new('Post', data)

    post.valid?


    # #
    # community = Solis::Model::Entity.new({ "abc": 1 }, @solis, 'Community', nil)
    # community.xxxx = "yyyy"
    #
    # @solis.store = Solis::Store::Memory.new(persist: { delay: true, read: false },
    #                                         hooks: { create: { before: {}, after: {} },
    #                                                  update: { before: {}, after: {} },
    #                                                  delete: { before: {}, after: {} },
    #                                                  read: { before: {}, after: {} } })
    #
    # @solis.model = Solis::ModelMock.new(prefix: 'sioc',
    #                                     namespace: 'http://rdfs.org/sioc/ns#',
    #                                     uri: "file://test/resources/sioc_rdf.xml",
    #                                     content_type: 'application/rdf+xml')
    #
    # community = @solis.entity('Community', { id: 1, xxx: 'yyyy' })
    # community.valid?
    # community.validate
    # community.save
    # hooks on Store for create/update/delete/read

  end
end