require "test_helper"

class TestPlurals < Minitest::Test
  def setup
    super
    Solis.config.path = 'test/resources/config'
  end

  def test_no_plurals

    config = {
      store: Solis::Store::Memory.new(),
      model: {
        prefix: 'ex',
        namespace: 'https://example.com/',
        uri: 'file://test/resources/car/car_shacl.ttl',
        content_type: 'text/turtle'}
    }
    solis = Solis.new(config)

    shape_uri = Shapes.find_uri_by_name(solis.model.shapes, 'Car')
    assert_nil(solis.model.shapes[shape_uri][:plural])

  end

  def test_with_plurals

    config = {
      store: Solis::Store::Memory.new(),
      model: {
        prefix: 'ex',
        namespace: 'https://example.com/',
        uri: 'file://test/resources/car/car_shacl.ttl',
        content_type: 'text/turtle',
        plurals: {
          'Car' => 'cars'
        }
      }
    }
    solis = Solis.new(config)


    shape_uri = Shapes.find_uri_by_name(solis.model.shapes, 'Car')
    assert_equal(solis.model.shapes[shape_uri][:plural], 'cars')
  end

end