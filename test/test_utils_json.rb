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

    hash_data_jsonld = Solis::Utils::JSON.deep_replace_prefix_in_name_attr(hash_data_json, '_', '@')

    assert_equal(hash_data_jsonld['@id'], "http://schema.org/my_car")
    assert_equal(hash_data_jsonld['door']['window']['glass']['@id'], "http://schema.org/my_glass")

  end

end
