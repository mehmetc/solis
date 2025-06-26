require "test_helper"

class TestEntityLoad < Minitest::Test

  def setup
    super
    dir_tmp = File.join(__dir__, './data')
    @name_graph = 'https://example.com/'
    @model = Solis::Model.new(model: {
      uri: "file://test/resources/car/car_test_entity_load.ttl",
      prefix: 'ex',
      namespace: @name_graph,
      tmp_dir: dir_tmp
    })

  end

  def test_entity_load

    data = JSON.parse %(
      {
        "_id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota",
        "owners": [
          {
            "_id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
            "name": "jon doe",
            "driving_license": {
              "_id": "https://example.com/f23dd664-adf0-4b86-a309-bd5e9e18ed5a",
              "address": {
                "_id": "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea",
                "street": "fake street",
                "number": [1, 15]
              }
            }
          }
        ]
      }
    )

    repository = RDF::Repository.new
    store = Solis::Store::RDFProxy.new(repository, @name_graph)

    car = Solis::Model::Entity.new(data, @model, 'Car', store)

    car.save
    
    data = JSON.parse %(
      {
        "_id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9"
      }
    )

    person = Solis::Model::Entity.new(data, @model, 'Person', store)

    assert_equal(person.exists?, true)

    person.load(deep = true)
    assert_equal(person.driving_license['address']['street'], 'fake street')

    person.save

    str_ttl_truth = %(
      <https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> "https://example.com/Address" .
      <https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea> <https://example.com/street> "fake street" .
      <https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea> <https://example.com/number> "1"^^<http://www.w3.org/2001/XMLSchema#integer> .
      <https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea> <https://example.com/number> "15"^^<http://www.w3.org/2001/XMLSchema#integer> .
      <https://example.com/f23dd664-adf0-4b86-a309-bd5e9e18ed5a> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> "https://example.com/DrivingLicense" .
      <https://example.com/f23dd664-adf0-4b86-a309-bd5e9e18ed5a> <https://example.com/address> <https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea> .
      <https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> "https://example.com/Person" .
      <https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9> <https://example.com/name> "jon doe" .
      <https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9> <https://example.com/driving_license> <https://example.com/f23dd664-adf0-4b86-a309-bd5e9e18ed5a> .
      <https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> "https://example.com/Car" .
      <https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be> <https://example.com/color> "green" .
      <https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be> <https://example.com/color> "yellow" .
      <https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be> <https://example.com/brand> "toyota" .
      <https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be> <https://example.com/owners> <https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9> .
    )
    graph_truth = RDF::Graph.new
    graph_truth.from_ttl(str_ttl_truth)

    graph_to_check = RDF::Graph.new(data: repository)
    delete_metadata_from_graph(graph_to_check)

    assert_equal(graph_truth == graph_to_check, true)

  end

  def test_entity_load_no_existing_id

    data = JSON.parse %(
      {
        "_id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota",
        "owners": [
          {
            "_id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
            "name": "jon doe",
            "driving_license": {
              "_id": "https://example.com/f23dd664-adf0-4b86-a309-bd5e9e18ed5a",
              "address": {
                "_id": "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea",
                "street": "fake street",
                "number": [1, 15]
              }
            }
          }
        ]
      }
    )

    repository = RDF::Repository.new
    store = Solis::Store::RDFProxy.new(repository, @name_graph)

    car = Solis::Model::Entity.new(data, @model, 'Car', store)

    car.save

    data = JSON.parse %(
      {
        "_id": "https://example.com/non-existing-id"
      }
    )

    person = Solis::Model::Entity.new(data, @model, 'Person', store)

    assert_equal(person.exists?, false)

    assert_raises(Solis::Model::Entity::LoadError) do
      person.load
    end

    data = JSON.parse %(
      {}
    )

    person = Solis::Model::Entity.new(data, @model, 'Person', store)
    assert_equal(person['_id'].nil?, false)

    assert_raises(Solis::Model::Entity::LoadError) do
      person.load
    end

  end

  def test_entity_load_mismatch_type

    data = JSON.parse %(
      {
        "_id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota",
        "owners": [
          {
            "_id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
            "name": "jon doe",
            "driving_license": {
              "_id": "https://example.com/f23dd664-adf0-4b86-a309-bd5e9e18ed5a",
              "address": {
                "_id": "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea",
                "street": "fake street",
                "number": [1, 15]
              }
            }
          }
        ]
      }
    )

    repository = RDF::Repository.new
    store = Solis::Store::RDFProxy.new(repository, @name_graph)

    car = Solis::Model::Entity.new(data, @model, 'Car', store)

    car.save

    data = JSON.parse %(
      {
        "_id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9"
      }
    )

    driving_license = Solis::Model::Entity.new(data, @model, 'DrivingLicense', store)

    assert_raises(Solis::Model::Entity::TypeMismatchError) do
      driving_license.load(deep = true)
    end

    person = Solis::Model::Entity.new(data, @model, 'Person', store)

    person.load(deep = true)


  end

end