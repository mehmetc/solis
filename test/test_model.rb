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
    all_entities = @solis.model.entity.all

    assert_includes(all_entities, 'Car')
  end

  def test_model_should_have_property
    assert @solis.model.entity.exists?('Car')
    assert @solis.model.entity.exists?('Cars')
    assert @solis.model.entity.exists?('cars')
    refute @solis.model.entity.exists?('Auto')
  end

  def test_model_instantiate_car_entity
    car_entity = @solis.model.entity.new('Car')

    assert_equal('Car', car_entity.attributes['_type'])
    #TODO: the id cannot start with an @ in Ruby
    assert_match(@solis.model.namespace, car_entity.attributes["_id"])
  end

  def test_model_instance_namepace
    assert_equal(@namespace, @solis.model.namespace)
  end

  def test_model_instance_prefix
    assert_equal(@prefix, @solis.model.prefix)
  end

  # def test_model_car_instance_should_return_an_error_when_requesting_non_existing_property
  #   car_entity = @solis.model.entity.new('Car')
  #   assert_raises Solis::Error::PropertyNotFound do
  #     car_entity.blabla
  #   end
  # end

  def test_model_check_core_functions

    @name_graph = 'https://example.com/'

    dir_tmp = File.join(__dir__, './data')

    hierarchies = [
      {
        'ElectricCar' => ['Car']
      },
      {
        'ex:ElectricCar' => ['Car']
      },
      {
        'ElectricCar' => ['ex:Car']
      },
      {
        'ex:ElectricCar' => ['ex:Car']
      }
    ]

    hierarchies.each do |hierarchy|

      model = Solis::Model.new(model: {
        uri: "file://test/resources/car/car_test_entity_save.ttl",
        prefix: 'ex',
        namespace: @name_graph,
        tmp_dir: dir_tmp,
        hierarchy: hierarchy,
        plurals: {
          'Car' => 'cars',
          'ElectricCar' => 'electric_cars',
          'Person' => 'persons',
          'Address' => 'addresses'
        }
      })

      r = model.get_parent_entities_for_entity('https://example.com/ElectricCar')
      assert_equal(r == ['https://example.com/Car'], true)

      r = model.get_all_parent_entities_for_entity('https://example.com/ElectricCar')
      assert_equal(r == ['https://example.com/Car'], true)

      r = model.get_parent_entities_for_entity('https://example.com/Car')
      assert_equal(r.empty?, true)

      r = model.get_property_entity_for_entity('https://example.com/Car', 'https://example.com/owners')
      assert_equal(r == 'https://example.com/Person', true)

      r = model.get_property_entity_for_entity('https://example.com/ElectricCar', 'https://example.com/owners')
      assert_equal(r == 'https://example.com/Person', true)

      r = model.get_property_entity_for_entity('https://example.com/ElectricCar', 'owners')
      assert_equal(r.nil?, true)

      r = model.get_property_entity_for_entity('https://example.com/ElectricCar', nil)
      assert_equal(r.nil?, true)

      r = model.get_property_datatype_for_entity('https://example.com/ElectricCar', 'https://example.com/color')
      assert_equal(r == 'http://www.w3.org/2001/XMLSchema#string', true)

      r = model.get_properties_info_for_entity('https://example.com/ElectricCar')
      assert_equal(r.key?('https://example.com/color'), true)

      r = model.writer('application/entities+json', raw: true)
      assert_equal(r.key?('https://example.com/ElectricCar'), true)
      assert_equal(r['https://example.com/ElectricCar'][:properties].key?('https://example.com/color'), true)

      r = model.get_shape_for_entity('https://example.com/ElectricCar')
      assert_equal(r[:uri] == 'https://example.com/ElectricCarShape', true)
      assert_equal(r[:target_class] == 'https://example.com/ElectricCar', true)

      assert_equal(model.find_entity_by_plural('electric_cars'), 'https://example.com/ElectricCar')
      assert_equal(model.find_entity_by_plural('electric_carsss'), nil)

      assert_equal(model.hierarchy['https://example.com/Car'], [])
      assert_equal(model.hierarchy['https://example.com/ElectricCar'], ['https://example.com/Car'])

    end

  end

end
