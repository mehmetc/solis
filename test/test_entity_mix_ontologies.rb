require "test_helper"

class TestEntityMixOntologies < Minitest::Test

  def setup
    super
    @name_graph = 'https://example.com/'

    dir_tmp = File.join(__dir__, './data')

    @model = Solis::Model.new(model: {
      uri: "file://test/resources/car/car_test_entity_mix_ontologies.ttl",
      prefix: 'ex',
      namespace: @name_graph,
      tmp_dir: dir_tmp
    })

  end

  def test_entity_mix_ontologies

    data = JSON.parse %(
      {
        "@context": {
          "@vocab": "https://example.com/",
           "dct": "http://purl.org/dc/terms/"
        },
        "@id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "dct:identifier": "dummy_identifier",
        "color": ["green", "yellow"],
        "brand": "toyota",
        "owners": [
          {
            "@id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
            "name": "jon doe",
            "address": {
              "@id": "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea",
              "street": "fake street"
            }
          }
        ]
      }
    )

    repository = RDF::Repository.new
    store = Solis::Store::RDFProxy.new(repository, @name_graph)

    car = Solis::Model::Entity.new(data, @model, 'Car', store)

    puts car.to_pretty_pre_validate_jsonld

    assert_equal(car.valid?, true)

    car.save

    puts "\n\nREPO CONTENT:\n\n"
    puts repository.dump(:ntriples)

  end

end

