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
        "@id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
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
        "@id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
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

end