require "test_helper"

class TestEntityDestroy < Minitest::Test

  def setup
    super

    dir_tmp = File.join(__dir__, './data')
    @name_graph = 'https://example.com/'
    @model = Solis::Model.new(model: {
      uri: "file://test/resources/car/car_test_entity_destroy.ttl",
      prefix: 'ex',
      namespace: @name_graph,
      tmp_dir: dir_tmp
    })

  end

  def test_entity_destroy

    data = JSON.parse %(
      {
        "@id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota",
        "owners": [
          {
            "@id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
            "name": "jon doe",
            "driving_license": {
              "@id": "https://example.com/f23dd664-adf0-4b86-a309-bd5e9e18ed5a",
              "address": {
                "@id": "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea",
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
        "@id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9"
      }
    )

    person = Solis::Model::Entity.new(data, @model, 'Person', store)

    person.load(deep = true)

    assert_equal(car.referenced?, false)
    assert_equal(person.referenced?, true)

    assert_raises(Solis::Model::Entity::DestroyError) do
      person.destroy
    end

    car.destroy
    person.destroy

    puts "\n\nREPO CONTENT:\n\n"
    puts repository.dump(:ntriples)

    str_ttl_truth = %(
      <https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> "https://example.com/Address" .
      <https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea> <https://example.com/street> "fake street" .
      <https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea> <https://example.com/number> "1"^^<http://www.w3.org/2001/XMLSchema#integer> .
      <https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea> <https://example.com/number> "15"^^<http://www.w3.org/2001/XMLSchema#integer> .
      <https://example.com/f23dd664-adf0-4b86-a309-bd5e9e18ed5a> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> "https://example.com/DrivingLicense" .
      <https://example.com/f23dd664-adf0-4b86-a309-bd5e9e18ed5a> <https://example.com/address> <https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea> .
    )
    graph_truth = RDF::Graph.new
    graph_truth.from_ttl(str_ttl_truth)

    graph_to_check = RDF::Graph.new(data: repository)

    assert_equal(graph_truth == graph_to_check, true)

  end

end