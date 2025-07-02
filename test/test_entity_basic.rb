require "test_helper"

class TestEntityBasic < Minitest::Test

  def setup
    super

    dir_tmp = File.join(__dir__, './data')
    @name_graph = 'https://example.com/'
    @model = Solis::Model.new(model:{
                                   uri: "file://test/resources/car/car_test_entity_basic.ttl",
                                   prefix: 'ex',
                                   namespace: @name_graph,
                                   tmp_dir: dir_tmp
                                 })

  end

  def test_entity_creation

    data = JSON.parse %(
      {
        "_id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota",
        "owners": [
          {
            "_id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
            "name": "jon doe",
            "address": {
              "_id": "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea",
              "street": "fake street"
            }
          }
        ]
      }
    )

    car = Solis::Model::Entity.new(data, @model, 'Car', nil)

    assert_equal(car['_id'], "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be")
    assert_equal(car.owners[0]['address']['_id'], "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea")

  end

  def test_entity_creation_without_ids

    data = JSON.parse %(
      {
        "color": ["green", "yellow"],
        "brand": "toyota",
        "owners": [
          {
            "name": "jon doe",
            "address": {
              "street": "fake street"
            }
          }
        ]
      }
    )

    car = Solis::Model::Entity.new(data, @model, 'Car', nil)

    assert_equal(car['_id'].nil?, false)
    assert_equal(car.owners[0]['_id'].nil?, false)
    assert_equal(car.owners[0]['address']['_id'].nil?, false)

  end

  def test_entity_get_shape

    data = JSON.parse %(
      {
        "color": ["green", "yellow"],
        "brand": "toyota",
        "owners": [
          {
            "name": "jon doe",
            "address": {
              "street": "fake street"
            }
          }
        ]
      }
    )

    car = Solis::Model::Entity.new(data, @model, 'Car', nil)

    shape = car.get_shape

    assert_equal(shape[:uri], 'https://example.com/CarShape')
    assert_equal(shape[:closed], false)

  end

  def test_entity_get_properties_info

    data = JSON.parse %(
      {
        "color": ["green", "yellow"],
        "brand": "toyota",
        "owners": [
          {
            "name": "jon doe",
            "address": {
              "street": "fake street"
            }
          }
        ]
      }
    )

    car = Solis::Model::Entity.new(data, @model, 'Car', nil)

    info = car.get_properties_info

    assert_equal(info['https://example.com/color'].nil?, false)
    assert_equal(info['https://example.com/color'][:constraints][0][:description], 'Color of the car')

  end

  def test_entity_data_replacement

    data = JSON.parse %(
      {
        "_id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota",
        "owners": [
          {
            "_id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
            "name": "jon doe",
            "address": {
              "_id": "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea",
              "street": "fake street"
            }
          }
        ]
      }
    )

    car = Solis::Model::Entity.new(data, @model, 'Car', nil)

    data_2 = JSON.parse %(
      {
        "_id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": "black",
        "brand": "toyota",
        "owners": [
          {
            "_id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
            "name": "jon doe",
            "address": {
              "_id": "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea",
              "street": "other fake street"
            }
          }
        ]
      }
    )

    car.replace(data_2)

    assert_equal(car.color, 'black')
    assert_equal(car.owners[0]['address']['street'], 'other fake street')

  end

  def test_entity_patch

    data = JSON.parse %(
      {
        "_id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota",
        "owners": [
          {
            "_id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
            "name": "jon doe",
            "address": {
              "_id": "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea",
              "street": "fake street"
            }
          }
        ]
      }
    )

    car = Solis::Model::Entity.new(data, @model, 'Car', nil)

    obj_patch = JSON.parse %(
      {
        "color": "black",
        "brand": "nissan",
        "owners": [
          {
            "_id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
            "name": "john smith"
          }
        ]
      }
    )

    car.patch(obj_patch)

    assert_equal(car.color, 'black')
    assert_equal(car.owners[0]['name'], 'john smith')

  end

  def test_entity_no_partial_patch_on_error

    data = JSON.parse %(
      {
        "_id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota",
        "owners": [
          {
            "_id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
            "name": "jon doe",
            "address": {
              "_id": "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea",
              "street": "fake street"
            }
          }
        ]
      }
    )

    car = Solis::Model::Entity.new(data, @model, 'Car', nil)

    obj_patch = JSON.parse %(
      {
        "color": "black",
        "brand": {
          "_id": "bla-bla-bla",
          "attr": "value"
        }
      }
    )

    assert_raises(Solis::Model::Entity::PatchTypeMismatchError) do
      car.patch(obj_patch)
    end

    assert_equal(car.color, ["green", "yellow"])
    assert_equal(car.brand, "toyota")

  end

  def test_entity_patch_add_missing_refs

    data = JSON.parse %(
      {
        "_id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota",
        "owners": [
          {
            "_id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
            "name": "jon doe",
            "address": {
              "_id": "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea",
              "street": "fake street"
            }
          }
        ]
      }
    )

    car = Solis::Model::Entity.new(data, @model, 'Car', nil)

    obj_patch = JSON.parse %(
      {
        "color": "black",
        "brand": "nissan",
        "owners": [
          {
            "_id": "https://example.com/12345-non-existing",
            "name": "john smith"
          }
        ]
      }
    )

    assert_raises(Solis::Model::Entity::MissingRefError) do
      car.patch(obj_patch)
    end

    assert_equal((car.color-["green", "yellow"]).size, 0)

    car.patch(obj_patch, opts={
      add_missing_refs: true,
      autoload_missing_refs: false
    })

    assert_equal(car.color, 'black')
    assert_equal(car.owners[1]['name'], 'john smith')

  end

  def test_entity_patch_overwrite_refs_lists

    repository = RDF::Repository.new
    store = Solis::Store::RDFProxy.new(repository, @name_graph)

    # prepare car along with an owner

    data = JSON.parse %(
      {
        "_id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota",
        "owners": [
          {
            "_id": "https://example.com/c4cba0e3-f7a0-43e3-bbde-134337f74323",
            "name": "super mario",
            "address": {
              "_id": "https://example.com/e958232b-e35a-4658-bbd7-5f56d7b50da9",
              "street": "fake street"
            }
          }
        ]
      }
    )

    car = Solis::Model::Entity.new(data, @model, 'Car', store)

    car.save

    # prepare one person and save

    data = JSON.parse %(
      {
        "_id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
        "name": "jon doe",
        "address": {
          "_id": "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea",
          "street": "fake street"
        }
      }
    )

    person_1 = Solis::Model::Entity.new(data, @model, 'Person', store)

    person_1.save

    # prepare another person and save

    data = JSON.parse %(
      {
        "_id": "https://example.com/caf57ff7-b568-43b3-81bb-f31b7371d8db",
        "name": "mary jane",
        "address": {
          "_id": "https://example.com/15120d60-9272-4c8d-ba1b-b1ee040ad396",
          "street": "fake street"
        }
      }
    )

    person_2 = Solis::Model::Entity.new(data, @model, 'Person', store)

    person_2.save

    # patch car by linking to existing persons

    obj_patch = JSON.parse %(
      {
        "color": "black",
        "brand": "nissan",
        "owners": [
          {
            "_id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9"
          },
          {
            "_id": "https://example.com/caf57ff7-b568-43b3-81bb-f31b7371d8db"
          }
        ]
      }
    )

    car.patch(obj_patch, opts={
      overwrite_refs_lists: true,
      add_missing_refs: true,
      autoload_missing_refs: true
    })

    assert_equal(car.valid?, true)

    assert_equal(car.owners.size, 2)

  end

  def test_entity_patch_add_missing_refs_with_autoload_no_store

    repository = RDF::Repository.new
    store = Solis::Store::RDFProxy.new(repository, @name_graph)

    # prepare car (without ref to any person)

    data = JSON.parse %(
      {
        "_id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota",
        "owners": []
      }
    )

    car = Solis::Model::Entity.new(data, @model, 'Car', nil)

    # prepare person and save

    data = JSON.parse %(
      {
        "_id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
        "name": "jon doe",
        "address": {
          "_id": "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea",
          "street": "fake street"
        }
      }
    )

    person = Solis::Model::Entity.new(data, @model, 'Person', store)

    person.save

    obj_patch = JSON.parse %(
      {
        "color": "black",
        "brand": "nissan",
        "owners": [
          {
            "_id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
            "name": "john smith"
          }
        ]
      }
    )

    assert_raises(Solis::Model::Entity::MissingStoreError) do
      car.patch(obj_patch, opts={
        add_missing_refs: true,
        autoload_missing_refs: true
      })
    end

  end

  def test_entity_patch_append_attributes

    data = JSON.parse %(
      {
        "_id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota",
        "owners": [
          {
            "_id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
            "name": "jon doe",
            "address": {
              "_id": "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea",
              "street": "fake street"
            }
          }
        ]
      }
    )

    car = Solis::Model::Entity.new(data, @model, 'Car', nil)

    obj_patch = JSON.parse %(
      {
        "color": "black"
      }
    )

    car.patch(obj_patch, opts={
      append_attributes: true
    })

    assert_equal((car.color-["green", "yellow", "black"]).size, 0)

  end

  def test_entity_patch_add_missing_refs_with_autoload

    repository = RDF::Repository.new
    store = Solis::Store::RDFProxy.new(repository, @name_graph)

    # prepare car (without ref to any person) and save

    data = JSON.parse %(
      {
        "_id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota",
        "owners": []
      }
    )

    car = Solis::Model::Entity.new(data, @model, 'Car', store)

    car.save

    # prepare person and save

    data = JSON.parse %(
      {
        "_id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
        "name": "jon doe",
        "address": {
          "_id": "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea",
          "street": "fake street"
        }
      }
    )

    person = Solis::Model::Entity.new(data, @model, 'Person', store)

    person.save

    # wrongly patch car by linking to non-existing person

    obj_patch = JSON.parse %(
      {
        "color": "black",
        "brand": "nissan",
        "owners": [
          {
            "_id": "https://example.com/non-existing-id",
            "name": "john smith"
          }
        ]
      }
    )

    assert_raises(Solis::Model::Entity::LoadError) do
      car.patch(obj_patch, opts={
        add_missing_refs: true,
        autoload_missing_refs: true
      })
    end

    # correctly patch car by linking to existing person

    obj_patch = JSON.parse %(
      {
        "color": "black",
        "brand": "nissan",
        "owners": [
          {
            "_id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
            "name": "john smith"
          }
        ]
      }
    )

    car.patch(obj_patch, opts={
      add_missing_refs: true,
      autoload_missing_refs: true
    })

    assert_equal(car.valid?, true)

    assert_equal(car.color, 'black')
    assert_equal(car.brand, 'nissan')
    assert_equal(car.owners[0]['name'], 'john smith')

  end
  def test_entity_patch_depth0_1

    data = JSON.parse %(
      {
        "_id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota",
        "owners": [
          {
            "_id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
            "name": "jon doe",
            "address": {
              "_id": "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea",
              "street": "fake street"
            }
          }
        ]
      }
    )

    car = Solis::Model::Entity.new(data, @model, 'Car', nil)

    obj_patch = JSON.parse %(
      {
        "color": "black",
        "brand": "@unset",
        "owners": [
          {
            "_id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
            "name": "john smith"
          }
        ]
      }
    )

    car.patch(obj_patch)

    assert_equal(car.brand, "@unset")

  end

  def test_entity_patch_depth0_2

    data = JSON.parse %(
      {
        "_id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota",
        "owners": [
          {
            "_id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
            "name": "jon doe",
            "address": {
              "_id": "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea",
              "street": "fake street"
            }
          }
        ]
      }
    )

    car = Solis::Model::Entity.new(data, @model, 'Car', nil)

    obj_patch = JSON.parse %(
      {
        "color": "black",
        "brand": "@unset",
        "owners": "@unset"
      }
    )

    car.patch(obj_patch)

    assert_equal(car.owners, "@unset")

  end

  def test_entity_patch_depth1

    data = JSON.parse %(
      {
        "_id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota",
        "owners": [
          {
            "_id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
            "name": "jon doe",
            "address": {
              "_id": "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea",
              "street": "fake street"
            }
          }
        ]
      }
    )

    car = Solis::Model::Entity.new(data, @model, 'Car', nil)

    obj_patch = JSON.parse %(
      {
        "color": "black",
        "brand": "@unset",
        "owners": [
          {
            "_id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
            "name": "john smith",
            "address": "@unset"
          }
        ]
      }
    )

    car.patch(obj_patch)

    assert_equal(car.owners[0]["address"], "@unset")

  end

  def test_entity_show_pre_validate_jssonld

    data = JSON.parse %(
      {
        "_id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota",
        "owners": [
          {
            "_id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
            "name": "jon doe",
            "address": {
              "_id": "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea",
              "street": "fake street"
            }
          }
        ]
      }
    )

    car = Solis::Model::Entity.new(data, @model, 'Car', nil)

    # TODO: write asserts on .to_pretty_pre_validate_jsonld
    # puts car.to_pretty_pre_validate_jsonld

  end

  def test_entity_deep_dup

    data = JSON.parse %(
      {
        "_id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota",
        "owners": [
          {
            "_id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
            "name": "jon doe",
            "address": {
              "_id": "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea",
              "street": "fake street"
            }
          }
        ]
      }
    )

    car = Solis::Model::Entity.new(data, @model, 'Car', nil)

    car_copy = car.deep_dup(true)

    assert_raises(NoMethodError) do
      car_copy.save
    end

  end

end