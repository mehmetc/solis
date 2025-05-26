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

    assert_equal(solis.model.shapes['Car'][:plural], nil)

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

    assert_equal(solis.model.shapes['Car'][:plural], 'cars')

  end

end