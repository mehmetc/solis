require "test_helper"

class TestEntityHooks < Minitest::Test

  def setup
    super
    @name_graph = 'https://example.com/'

    dir_tmp = File.join(__dir__, './data')

    @model = Solis::Model.new(model: {
      uri: "file://test/resources/car/car_test_entity_hooks.ttl",
      prefix: 'ex',
      namespace: @name_graph,
      tmp_dir: dir_tmp
    })

  end

  def test_entity_create_hooks

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

    repository = RDF::Repository.new
    store = Solis::Store::RDFProxy.new(repository, @name_graph)

    count_create = 0

    hooks = {
      before_create: lambda do |obj|
        obj
      end,
      after_create: lambda do |obj, success|
        assert_equal(success, true)
        count_create += 1
      end,
    }

    car = Solis::Model::Entity.new(data, @model, 'Car', store, hooks)

    car.save
    car.save
    car.save

    assert_equal(count_create, 1)

  end

  def test_entity_save_hooks

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

    repository = RDF::Repository.new
    store = Solis::Store::RDFProxy.new(repository, @name_graph)

    hooks = {
      before_save: lambda do |obj|
        obj
      end,
      after_save: lambda do |obj, success|
        assert_equal(success, true)
        assert_equal(obj['brand'], 'toyota')
      end,
    }

    car = Solis::Model::Entity.new(data, @model, 'Car', store, hooks)

    car.save

  end

  def test_entity_save_hooks_make_attribute_invalid

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

    repository = RDF::Repository.new
    store = Solis::Store::RDFProxy.new(repository, @name_graph)

    done_after_save = false

    hooks = {
      before_save: lambda do |obj|
        obj['brand'] = 1
        obj
      end,
      after_save: lambda do |obj, success|
        done_after_save = true
      end,
    }

    car = Solis::Model::Entity.new(data, @model, 'Car', store, hooks)

    assert_raises(Solis::Model::Entity::ValidationError) do
      car.save
    end
    assert_equal(done_after_save, false)

  end

  def test_entity_save_hooks_pre_hook_modified_attribute

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

    repository = RDF::Repository.new
    store = Solis::Store::RDFProxy.new(repository, @name_graph)

    hooks = {
      before_save: lambda do |obj|
        obj['brand'] = 'byd'
        obj
      end,
      after_save: lambda do |obj, success|
        assert_equal(obj['brand'], 'byd')
      end,
    }

    car = Solis::Model::Entity.new(data, @model, 'Car', store, hooks)

    car.save

  end

  def test_entity_save_hooks_saving_fails

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

    repository = RDF::Repository.new
    store = Solis::Store::RDFProxy.new(repository, @name_graph)

    # mock store instance to fail on save
    def store.run_save_operations(ops_generic)
      res = ops_generic.map do |op|
        [op['id'], {
          "success" => false,
          "message" => ""
        }]
      end.to_h
      res
    end

    side_effect_status = nil

    hooks = {
      before_save: lambda do |obj|
        side_effect_status = 'committed'
        obj
      end,
      after_save: lambda do |obj, success|
        assert_equal(success, false)
        side_effect_status = 'rolled_back'
      end,
    }

    car = Solis::Model::Entity.new(data, @model, 'Car', store, hooks)

    assert_raises(Solis::Model::Entity::SaveError) do
      car.save
    end
    assert_equal(side_effect_status, 'rolled_back')

  end

  def test_entity_destroy_hooks

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

    repository = RDF::Repository.new
    store = Solis::Store::RDFProxy.new(repository, @name_graph)

    count_destroy = 0

    hooks = {
      before_destroy: lambda do |obj|
        nil
      end,
      after_destroy: lambda do |obj, success|
        assert_equal(success, true)
        count_destroy += 1
      end,
    }

    car = Solis::Model::Entity.new(data, @model, 'Car', store, hooks)

    car.save

    car.destroy

    assert_equal(count_destroy, 1)

  end

end