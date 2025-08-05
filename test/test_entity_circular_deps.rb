require "test_helper"

class TestEntityCircularDeps < Minitest::Test

  def setup
    super

    dir_tmp = File.join(__dir__, './data')
    @name_graph = 'https://example.com/'
    @model = Solis::Model.new(model:{
                                   uri: "file://test/resources/car/car_test_entity_circular_deps.ttl",
                                   prefix: 'ex',
                                   namespace: @name_graph,
                                   tmp_dir: dir_tmp
                                 })

  end


  def test_entity_load_with_circular_deps

    repository = RDF::Repository.new
    store = Solis::Store::RDFProxy.new(repository, @name_graph)

    # add 1st car

    data = JSON.parse %(
      {
        "_id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota"
      }
    )

    car_1 = Solis::Model::Entity.new(data, @model, 'Car', store)

    car_1.save

    # add 2nd car

    data = JSON.parse %(
      {
        "_id": "https://example.com/12b03797-c6d0-4fe5-a25d-da92d716bd34",
        "color": "blue",
        "brand": "toyota"
      }
    )

    car_2 = Solis::Model::Entity.new(data, @model, 'Car', store)

    car_2.save

    # create circular dependency

    obj_patch = JSON.parse %(
      {
        "_id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "replacement": {
          "_id": "https://example.com/12b03797-c6d0-4fe5-a25d-da92d716bd34"
        }
      }
    )

    car_1.patch(obj_patch, opts={
      autoload_missing_refs: true
    })

    car_1.save

    obj_patch = JSON.parse %(
      {
        "_id": "https://example.com/12b03797-c6d0-4fe5-a25d-da92d716bd34",
        "replacement": {
          "_id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be"
        }
      }
    )

    car_2.load(deep = true) # necessary because the previous car_1.save also saved (hence made dirty) car_2 alongside

    car_2.patch(obj_patch, opts={
      autoload_missing_refs: true
    })

    car_2.save

    puts "\n\nREPO CONTENT:\n\n"
    puts repository.dump(:ntriples)

    # load data with circular dependencies

    car_1.load(deep = true)

    assert_equal(car_1.valid?, true)

  end

end