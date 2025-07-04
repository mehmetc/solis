require "test_helper"

class TestEntityOptLocks < Minitest::Test

  def setup
    super
    dir_tmp = File.join(__dir__, './data')
    @name_graph = 'https://example.com/'
    @model = Solis::Model.new(model: {
      uri: "file://test/resources/car/car_test_entity_opt_locks.ttl",
      prefix: 'ex',
      namespace: @name_graph,
      tmp_dir: dir_tmp
    })

    @uri_version = Solis::Model::Entity::URI_DB_OPTIMISTIC_LOCK_VERSION

  end

  def test_correct_increment_version

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

    assert_equal(car.version, 0)

    car.save

    assert_equal(car.version, 1)

    puts "\n\nREPO CONTENT:\n\n"
    puts repository.dump(:ntriples)

    str_ttl_truth = %(
      <https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> "https://example.com/Address" .
      <https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea> <https://example.com/street> "fake street" .
      <https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea> <https://example.com/number> "1"^^<http://www.w3.org/2001/XMLSchema#integer> .
      <https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea> <https://example.com/number> "15"^^<http://www.w3.org/2001/XMLSchema#integer> .
      <https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea> <#{@uri_version}> "1"^^<http://www.w3.org/2001/XMLSchema#integer> .
      <https://example.com/f23dd664-adf0-4b86-a309-bd5e9e18ed5a> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> "https://example.com/DrivingLicense" .
      <https://example.com/f23dd664-adf0-4b86-a309-bd5e9e18ed5a> <https://example.com/address> <https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea> .
      <https://example.com/f23dd664-adf0-4b86-a309-bd5e9e18ed5a> <#{@uri_version}> "1"^^<http://www.w3.org/2001/XMLSchema#integer> .
      <https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> "https://example.com/Person" .
      <https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9> <https://example.com/name> "jon doe" .
      <https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9> <https://example.com/driving_license> <https://example.com/f23dd664-adf0-4b86-a309-bd5e9e18ed5a> .
      <https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9> <#{@uri_version}> "1"^^<http://www.w3.org/2001/XMLSchema#integer> .
      <https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> "https://example.com/Car" .
      <https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be> <https://example.com/color> "green" .
      <https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be> <https://example.com/color> "yellow" .
      <https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be> <https://example.com/brand> "toyota" .
      <https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be> <https://example.com/owners> <https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9> .
      <https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be> <#{@uri_version}> "1"^^<http://www.w3.org/2001/XMLSchema#integer> .
    )
    graph_truth = RDF::Graph.new
    graph_truth.from_ttl(str_ttl_truth)

    graph_to_check = RDF::Graph.new(data: repository)

    assert_equal(graph_truth == graph_to_check, true)

    car.save

    assert_equal(car.version, 2)

    puts "\n\nREPO CONTENT:\n\n"
    puts repository.dump(:ntriples)

    puts "\n\nREPO CONTENT:\n\n"
    puts repository.dump(:ntriples)

    str_ttl_truth = %(
      <https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> "https://example.com/Address" .
      <https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea> <https://example.com/street> "fake street" .
      <https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea> <https://example.com/number> "1"^^<http://www.w3.org/2001/XMLSchema#integer> .
      <https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea> <https://example.com/number> "15"^^<http://www.w3.org/2001/XMLSchema#integer> .
      <https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea> <#{@uri_version}> "2"^^<http://www.w3.org/2001/XMLSchema#integer> .
      <https://example.com/f23dd664-adf0-4b86-a309-bd5e9e18ed5a> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> "https://example.com/DrivingLicense" .
      <https://example.com/f23dd664-adf0-4b86-a309-bd5e9e18ed5a> <https://example.com/address> <https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea> .
      <https://example.com/f23dd664-adf0-4b86-a309-bd5e9e18ed5a> <#{@uri_version}> "2"^^<http://www.w3.org/2001/XMLSchema#integer> .
      <https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> "https://example.com/Person" .
      <https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9> <https://example.com/name> "jon doe" .
      <https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9> <https://example.com/driving_license> <https://example.com/f23dd664-adf0-4b86-a309-bd5e9e18ed5a> .
      <https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9> <#{@uri_version}> "2"^^<http://www.w3.org/2001/XMLSchema#integer> .
      <https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> "https://example.com/Car" .
      <https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be> <https://example.com/color> "green" .
      <https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be> <https://example.com/color> "yellow" .
      <https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be> <https://example.com/brand> "toyota" .
      <https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be> <https://example.com/owners> <https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9> .
      <https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be> <#{@uri_version}> "2"^^<http://www.w3.org/2001/XMLSchema#integer> .
    )
    graph_truth = RDF::Graph.new
    graph_truth.from_ttl(str_ttl_truth)

    graph_to_check = RDF::Graph.new(data: repository)

    assert_equal(graph_truth == graph_to_check, true)

  end

  def test_first_saved_wins

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

    car_1 = Solis::Model::Entity.new(data, @model, 'Car', store)
    car_2 = Solis::Model::Entity.new(data, @model, 'Car', store)

    car_1.save

    assert_raises(Solis::Model::Entity::SaveError) do
      car_2.save
    end

    car_2.load(deep = true)
    car_2.save

  end

  def test_first_saved_wins_2

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

    person.load(deep = true)
    person.save

    assert_raises(Solis::Model::Entity::SaveError) do
      car.save
    end

    car.load(deep = true)
    car.save

  end


end