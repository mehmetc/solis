# frozen_string_literal: true

require "test_helper"

class TestUtilsJSON < Minitest::Test

  def test_deep_replace_prefix_in_name_attr

    hash_data_json = JSON.parse %(
      {
        "_id": "http://schema.org/my_car",
        "_type": "Car",
        "brand": "toyota",
        "color": "blue",
        "attr_obj": {
            "x": 1,
            "y": 2
        },
        "door": {
            "_id": "http://schema.org/my_door",
            "_type": "Door",
            "window": {
                "_id": "http://schema.org/my_window",
                "_type": "Window",
                "glass": {
                    "_id": "http://schema.org/my_glass",
                    "_type": "Glass"
                }
            }
        },
        "others": [
            {
                "_id": "http://schema.org/my_obj_1",
                "_type": "Object",
                "attribute": "value"
            },
            {
                "_id": "http://schema.org/my_obj_2",
                "_type": "Object",
                "attribute": "value"
            }
        ]
      }
    )

    hash_data_jsonld = Solis::Utils::JSONUtils.deep_replace_prefix_in_name_attr(hash_data_json, '_', '@')

    assert_equal(hash_data_jsonld['@id'], "http://schema.org/my_car")
    assert_equal(hash_data_jsonld['door']['window']['glass']['@id'], "http://schema.org/my_glass")

  end

  def test_delete_empty_attributes

    data = JSON.parse %(
      {
        "color": [],
        "brand": "",
        "owners": [
          {
            "name": "jon doe",
            "address": {}
          },
          {},
          {
            "name": "jon doe 2",
            "address": {}
          },
          3,
          "",
          null
        ]
      }
    )

    data2 = Marshal.load(Marshal.dump(data))

    Solis::Utils::JSONUtils.recursive_compact!(data2)

    # puts JSON.pretty_generate(data2)

    assert_equal(data2["color"].nil?, true)
    assert_equal(data2["brand"].nil?, true)
    assert_equal(data2["owners"].length, 3)
    assert_equal(data2["owners"][0]['name'], 'jon doe')
    assert_equal(data2["owners"][1]['name'], 'jon doe 2')
    assert_equal(data2["owners"][2], 3)

    data2 = Marshal.load(Marshal.dump(data))

    Solis::Utils::JSONUtils.recursive_compact!(data2, exclude_types=[Array])

  end

end
