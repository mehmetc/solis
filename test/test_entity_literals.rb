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

    @model_literals = Solis::Model.new(model: {
      uri: "file://test/resources/literals.ttl",
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
    pp car.validate

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
    pp car.validate

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

    puts car.to_pretty_pre_validate_jsonld

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

    puts car.to_pretty_pre_validate_jsonld

    assert_equal(car.valid?, true)
  end

  def test_integer
    data = {
      integer: 1
    }
    literal = Solis::Model::Entity.new(data, @model_literals, 'test_literal', nil)

    puts literal.to_pretty_pre_validate_jsonld
    assert_equal(literal.valid?, true)
  end

  def test_float
    data = {
      float: 1.0
    }
    literal = Solis::Model::Entity.new(data, @model_literals, 'test_literal', nil)

    puts literal.to_pretty_pre_validate_jsonld
    assert_equal(literal.valid?, true)
  end

  def test_double
    data = {
      double: 1.0
    }
    literal = Solis::Model::Entity.new(data, @model_literals, 'test_literal', nil)

    puts literal.to_pretty_pre_validate_jsonld
    assert_equal(literal.valid?, true)
  end

  def test_uri
    data = {
      uri: "https://example.com"
    }
    literal = Solis::Model::Entity.new(data, @model_literals, 'test_literal', nil)

    puts literal.to_pretty_pre_validate_jsonld
    assert_equal(literal.valid?, true)
  end

end