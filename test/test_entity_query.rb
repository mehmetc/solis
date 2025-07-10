require "test_helper"

class TestEntityQuery < Minitest::Test

  def setup
    super
    dir_tmp = File.join(__dir__, './data')
    @name_graph = 'https://example.com/'
    @model = Solis::Model.new(model: {
      uri: "file://test/resources/car/car_test_entity_query.ttl",
      prefix: 'ex',
      namespace: @name_graph,
      tmp_dir: dir_tmp
    })

  end

  def test_entity_query

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

    puts "\n\nREPO CONTENT:\n\n"
    puts repository.dump(:ntriples)

    query_runner = Solis::Query::QueryRunner.new(@model, store)

    attributes = {
      "brand" => "toyota"
    }

    query_builder_car = Solis::Query::QueryBuilder.new(@model.namespace, 'Car', query_runner)
    entity = query_builder_car.find_by(attributes)
    assert_equal(entity.class, Solis::Model::Entity)

    cont = query_builder_car.where(attributes).count
    assert_equal(cont, 1)

  end

end