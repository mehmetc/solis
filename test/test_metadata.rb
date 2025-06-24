require 'test_helper'

class TestModel < Minitest::Test
  def setup
    @namespace = 'http://purl.org/ontology/bibo/'
    @prefix = 'bibo'

    config_bibo = {
      store: Solis::Store::Memory.new(),
      model: {
        prefix: @prefix,
        namespace: @namespace,
        uri: "file://test/resources/bibo_owl.xml",
        content_type: 'application/rdf+xml'
      }
    }

    @bibo_solis = Solis.new(config_bibo)
  end
  def test_model_metadata
    assert_equal 'The Bibliographic Ontology', @bibo_solis.model.title
    assert_instance_of Array, @bibo_solis.model.creator
    assert_includes @bibo_solis.model.creator, "http://purl.org/ontology/bibo/fgiasson"
  end

  def test_model_set_metadata
    assert_equal @bibo_solis.model.creator.size,2
    @bibo_solis.model.creator = @bibo_solis.model.creator << "https://solis.example.com/"
    assert_equal @bibo_solis.model.creator.size,3
  end

  def test_model_metadata_write
    openapi = JSON.parse(@bibo_solis.model.writer('application/openapi.json'))

    assert_equal 'The Bibliographic Ontology', openapi['info']['title']
  end
end
