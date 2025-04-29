require 'test_helper'

class TestShacl < Minitest::Test
  def setup
    config = {
      store: Solis::Store::Memory.new(),
      model: {
        prefix: 'lbs',
        namespace: 'https://lib.is/test/',
        uri: "file://test/resources/multiple_inheritance_shacl.ttl",
        content_type: 'text/turtle'
      }
    }
    @solis = Solis.new(config)
  end

  def test_is_shacl_loaded
    assert_kind_of(RDF::Repository, @solis.graph)
    assert_equal('lbs', @solis.prefix)
    assert_equal('https://lib.is/test/', @solis.namespace)
  end

  def test_validate_shacl
    shacl = SHACL.open('test/resources/shacl-shacl.ttl')
    results = shacl.execute(@solis.graph)

    pp results
  end
end
