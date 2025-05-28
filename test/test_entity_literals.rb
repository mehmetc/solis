require "test_helper"

class TestEntityLiterals < Minitest::Test

  def setup
    super

    dir_tmp = File.join(__dir__, './data')
    @name_graph = 'https://example.com/'
    @model = Solis::Model.new(model: {
      uri: "file://test/resources/car/car_test_entity_literals.ttl",
      prefix: 'ex',
      namespace: @name_graph,
      tmp_dir: dir_tmp
    })

  end

  def test_entity_valid_literals

    data = JSON.parse %(
      {
        "_id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota",
        "demolishing_year_forecast": "2030-06~",
        "check_interval": "P1Y"
      }
    )

    car = Solis::Model::Entity.new(data, @model, 'Car', nil)

    assert_equal(car.valid?, true)

  end

  def test_entity_invalid_literals

    data = JSON.parse %(
      {
        "_id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota",
        "demolishing_year_forecast": "bla-bla",
        "check_interval": "bla-bla"
      }
    )

    car = Solis::Model::Entity.new(data, @model, 'Car', nil)

    assert_equal(car.valid?, false)

  end

  def test_entity_express_literal_by_obj_1

    data = JSON.parse %(
      {
        "_id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota",
        "demolishing_year_forecast": {
          "_value": "2030-06~"
        },
        "check_interval": "P1Y"
      }
    )

    car = Solis::Model::Entity.new(data, @model, 'Car', nil)

    assert_equal(car.valid?, true)

  end

  def test_entity_express_literal_by_obj_2

    data = JSON.parse %(
      {
        "_id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota",
        "demolishing_year_forecast": {
          "_value": "2030-06~",
          "_type": "http://www.w3.org/2001/XMLSchema#integer"
        },
        "check_interval": "P1Y"
      }
    )

    car = Solis::Model::Entity.new(data, @model, 'Car', nil)

    assert_equal(car.valid?, false)

  end

  def test_entity_literal_with_alternatives_1

    data = JSON.parse %(
      {
        "_id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota",
        "demolishing_year_forecast": "2030-06~",
        "check_interval": "P1Y",
        "tag": {
          "_value": 123456
        }
      }
    )

    car = Solis::Model::Entity.new(data, @model, 'Car', nil)

    assert_equal(car.valid?, true)

  end

  def test_entity_literal_with_alternatives_2

    data = JSON.parse %(
      {
        "_id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota",
        "demolishing_year_forecast": "2030-06~",
        "check_interval": "P1Y",
        "tag": {
          "_value": "123456",
          "_type": "https://example.com/id"
        }
      }
    )

    car = Solis::Model::Entity.new(data, @model, 'Car', nil)

    assert_equal(car.valid?, true)

  end

  def test_entity_literal_with_alternatives_3

    data = JSON.parse %(
      {
        "_id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota",
        "demolishing_year_forecast": "2030-06~",
        "check_interval": "P1Y",
        "tag": {
          "_value": "123456"
        }
      }
    )

    car = Solis::Model::Entity.new(data, @model, 'Car', nil)

    # NOTE: it fails because the datatype, for a property that has alternative datatypes,
    # cannot be inferred by the data model. Hence, the datatype must be provided explicitly.
    # If not, then it is guessed internally. But in this case it is a string, that does not match
    # with a <https://example.com/id>.
    assert_equal(car.valid?, false)

  end

end
