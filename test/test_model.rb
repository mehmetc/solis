require 'test_helper'

class TestModel < Minitest::Test
  def setup
    @namespace = 'https://example.com/'
    @prefix = 'example'

    config = {
      store: Solis::Store::Memory.new(),
      model: {
        prefix: @prefix,
        namespace: @namespace,
        uri: "file://test/resources/car/car_shacl.ttl",
        content_type: 'text/turtle'
      }
    }

    @solis = Solis.new(config)
  end

  def test_model_should_contain_car_entity
    all_entities = @solis.model.entity.list

    assert_includes(all_entities, 'Car')
  end

  def test_model_instantiate_car_entity
    car_entity = @solis.model.entity.new('Car')

    assert_equal('Car', car_entity.instance_variable_get('@type'))
    #TODO: the id cannot start with an @ in Ruby
    assert_match(@solis.model.namespace, car_entity["@id"])
  end

  def test_model_instance_namepace
    assert_equal(@namespace, @solis.model.namespace)
  end

  def test_model_instance_prefix
    assert_equal(@prefix, @solis.model.prefix)
  end

  def test_model_car_instance_should_return_an_error_when_requesting_non_existing_property
    car_entity = @solis.model.entity.new('Car')
    assert_raises Solis::Error::PropertyNotFound do
      car_entity.blabla
    end
  end
end