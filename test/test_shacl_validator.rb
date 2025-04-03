# frozen_string_literal: true

require "test_helper"

class TestSHACLValidator < Minitest::Test

  def test_required_property

    str_shacl_ttl = %(
      @prefix example: <https://example.com/> .
      @prefix xsd:    <http://www.w3.org/2001/XMLSchema#> .
      @prefix sh:     <http://www.w3.org/ns/shacl#> .

      example:CarShape
              a sh:NodeShape;
              sh:description  "Abstract shape that describes a car entity" ;
              sh:targetClass  example:Car;
              sh:node         example:Car;
              sh:name         "Car";
              sh:property     [ sh:path        example:color;
                                sh:name        "color" ;
                                sh:description "Color of the car" ;
                                sh:datatype    xsd:string ;
                                sh:minCount    1 ;
                                sh:maxCount    1 ; ];
              sh:property     [ sh:path        example:brand;
                                sh:name        "brand" ;
                                sh:description "Brand of the car" ;
                                sh:datatype    xsd:string ;
                                sh:minCount    1 ;
                                sh:maxCount    1 ; ];
      .
    )

    hash_data_jsonld = JSON.parse %(
      {
        "@context": {
          "@vocab": "https://example.com/"
        },
        "@graph": [
          {
            "@id": "http://schema.org/my_car_1",
            "@type": "Car",
            "color": "blue",
            "brand": "toyota"
          },
          {
            "@id": "http://schema.org/my_car_2",
            "@type": "Car",
            "color": "green",
            "brand": "toyota"
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    assert_equal(conform, true)
    assert_equal(messages.size, 0)

    hash_data_jsonld = JSON.parse %(
      {
        "@context": {
          "@vocab": "https://example.com/"
        },
        "@graph": [
          {
            "@id": "http://schema.org/my_car_1",
            "@type": "Car",
            "color": "blue",
            "brand": "toyota"
          },
          {
            "@id": "http://schema.org/my_car_2",
            "@type": "Car",
            "color": "green"
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    assert_equal(conform, false)
    assert_equal(messages.size, 1)

  end

  def test_valid_property_xsd_datatype

    str_shacl_ttl = %(
      @prefix example: <https://example.com/> .
      @prefix xsd:    <http://www.w3.org/2001/XMLSchema#> .
      @prefix sh:     <http://www.w3.org/ns/shacl#> .

      example:CarShape
              a sh:NodeShape;
              sh:description  "Abstract shape that describes a car entity" ;
              sh:targetClass  example:Car;
              sh:node         example:Car;
              sh:name         "Car";
              sh:property     [ sh:path        example:color;
                                sh:name        "color" ;
                                sh:description "Color of the car" ;
                                sh:datatype    xsd:string ;
                                sh:minCount    1 ;
                                sh:maxCount    1 ; ];
              sh:property     [ sh:path        example:brand;
                                sh:name        "brand" ;
                                sh:description "Brand of the car" ;
                                sh:datatype    xsd:string ;
                                sh:minCount    1 ;
                                sh:maxCount    1 ; ];
      .
    )

    hash_data_jsonld = JSON.parse %(
      {
        "@context": {
          "@vocab": "https://example.com/"
        },
        "@graph": [
          {
            "@id": "http://schema.org/my_car_1",
            "@type": "Car",
            "color": "blue",
            "brand": "toyota"
          },
          {
            "@id": "http://schema.org/my_car_2",
            "@type": "Car",
            "color": "green",
            "brand": "toyota"
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    assert_equal(conform, true)
    assert_equal(messages.size, 0)

    hash_data_jsonld = JSON.parse %(
      {
        "@context": {
          "@vocab": "https://example.com/"
        },
        "@graph": [
          {
            "@id": "http://schema.org/my_car_1",
            "@type": "Car",
            "color": "blue",
            "brand": "toyota"
          },
          {
            "@id": "http://schema.org/my_car_2",
            "@type": "Car",
            "color": 1,
            "brand": "toyota"
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    assert_equal(conform, false)
    assert_equal(messages.size, 1)

  end

  def test_valid_property_class_datatype

    str_shacl_ttl = %(
      @prefix example: <https://example.com/> .
      @prefix xsd:    <http://www.w3.org/2001/XMLSchema#> .
      @prefix sh:     <http://www.w3.org/ns/shacl#> .

      example:CarShape
              a sh:NodeShape;
              sh:description  "Abstract shape that describes a car entity" ;
              sh:targetClass  example:Car;
              sh:node         example:Car;
              sh:name         "Car";
              sh:property     [ sh:path        example:color;
                                sh:name        "color" ;
                                sh:description "Color of the car" ;
                                sh:datatype    xsd:string ;
                                sh:minCount    1 ;
                                sh:maxCount    1 ; ];
              sh:property     [ sh:path        example:brand;
                                sh:name        "brand" ;
                                sh:description "Brand of the car" ;
                                sh:datatype    xsd:string ;
                                sh:minCount    1 ;
                                sh:maxCount    1 ; ];
              sh:property     [ sh:path        example:owners;
                                sh:name        "owners" ;
                                sh:description "Owners of the car" ;
                                sh:nodeKind    sh:IRI ;
                                sh:class       example:Person ;
                                sh:minCount    1 ; ];
      .
   )

    hash_data_jsonld = JSON.parse %(
      {
        "@context": {
          "@vocab": "https://example.com/"
        },
        "@graph": [
          {
            "@id": "http://schema.org/my_car_1",
            "@type": "Car",
            "color": "blue",
            "brand": "toyota",
            "owners": [
              {
                "@id":"http://schema.org/john_doe"
              }
            ]
          },
          {
            "@id": "http://schema.org/john_doe",
            "@type": "Person"
          },
          {
            "@id": "http://schema.org/my_cat",
            "@type": "Animal"
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    assert_equal(conform, true)
    assert_equal(messages.size, 0)

    hash_data_jsonld = JSON.parse %(
      {
        "@context": {
          "@vocab": "https://example.com/"
        },
        "@graph": [
          {
            "@id": "http://schema.org/my_car_1",
            "@type": "Car",
            "color": "blue",
            "brand": "toyota",
            "owners": [
              {
                "@id":"http://schema.org/john_doe"
              },
              {
                "@id":"http://schema.org/my_cat"
              }
            ]
          },
          {
            "@id": "http://schema.org/john_doe",
            "@type": "Person"
          },
          {
            "@id": "http://schema.org/my_cat",
            "@type": "Animal"
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    assert_equal(conform, false)
    assert_equal(messages.size, 1)

  end

  def test_valid_property_enums_datatype

    str_shacl_ttl = %(
      @prefix example: <https://example.com/> .
      @prefix xsd:    <http://www.w3.org/2001/XMLSchema#> .
      @prefix sh:     <http://www.w3.org/ns/shacl#> .

      example:CarShape
              a sh:NodeShape;
              sh:description  "Abstract shape that describes a car entity" ;
              sh:targetClass  example:Car;
              sh:node         example:Car;
              sh:name         "Car";
              sh:property     [ sh:path        example:color;
                                sh:name        "color" ;
                                sh:description "Color of the car" ;
                                sh:datatype    xsd:string ;
                                sh:minCount    1 ;
                                sh:maxCount    1 ; ];
              sh:property     [ sh:path        example:brand;
                                sh:name        "brand" ;
                                sh:description "Brand of the car" ;
                                sh:datatype    xsd:string ;
                                sh:in          ("toyota" "mercedes" "fiat") ;
                                sh:minCount    1 ;
                                sh:maxCount    1 ; ];
      .
   )

    hash_data_jsonld = JSON.parse %(
      {
        "@context": {
          "@vocab": "https://example.com/"
        },
        "@graph": [
          {
            "@id": "http://schema.org/my_car_1",
            "@type": "Car",
            "color": "blue",
            "brand": "toyota"
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    assert_equal(conform, true)
    assert_equal(messages.size, 0)

    hash_data_jsonld = JSON.parse %(
      {
        "@context": {
          "@vocab": "https://example.com/"
        },
        "@graph": [
          {
            "@id": "http://schema.org/my_car_1",
            "@type": "Car",
            "color": "blue",
            "brand": "citroen"
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    assert_equal(conform, false)
    assert_equal(messages.size, 1)

  end

  def test_deny_unshaped_property

    str_shacl_ttl = %(
      @prefix example: <https://example.com/> .
      @prefix xsd:    <http://www.w3.org/2001/XMLSchema#> .
      @prefix sh:     <http://www.w3.org/ns/shacl#> .
      @prefix rdf:    <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .

      example:CarShape
              a sh:NodeShape;
              sh:description  "Abstract shape that describes a car entity" ;
              sh:targetClass  example:Car;
              sh:node         example:Car;
              sh:name         "Car";
              sh:closed       true ;
              sh:ignoredProperties (rdf:type) ;
              sh:property     [ sh:path        example:color;
                                sh:name        "color" ;
                                sh:description "Color of the car" ;
                                sh:datatype    xsd:string ;
                                sh:minCount    1 ;
                                sh:maxCount    1 ; ];
              sh:property     [ sh:path        example:brand;
                                sh:name        "brand" ;
                                sh:description "Brand of the car" ;
                                sh:datatype    xsd:string ;
                                sh:in          ("toyota" "mercedes" "fiat") ;
                                sh:minCount    1 ;
                                sh:maxCount    1 ; ];
      .
   )

    hash_data_jsonld = JSON.parse %(
      {
        "@context": {
          "@vocab": "https://example.com/"
        },
        "@graph": [
          {
            "@id": "http://schema.org/my_car_1",
            "@type": "Car",
            "color": "blue",
            "brand": "toyota"
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    assert_equal(conform, true)
    assert_equal(messages.size, 0)

    hash_data_jsonld = JSON.parse %(
      {
        "@context": {
          "@vocab": "https://example.com/"
        },
        "@graph": [
          {
            "@id": "http://schema.org/my_car_1",
            "@type": "Car",
            "color": "blue",
            "brand": "toyota",
            "plate": "12345ab"
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    assert_equal(conform, false)
    assert_equal(messages.size, 1)

  end

  def test_valid_property_integer_datatype_in_range

    str_shacl_ttl = %(
      @prefix example: <https://example.com/> .
      @prefix xsd:    <http://www.w3.org/2001/XMLSchema#> .
      @prefix sh:     <http://www.w3.org/ns/shacl#> .

      example:CarShape
              a sh:NodeShape;
              sh:description  "Abstract shape that describes a car entity" ;
              sh:targetClass  example:Car;
              sh:node         example:Car;
              sh:name         "Car";
              sh:property     [ sh:path        example:color;
                                sh:name        "color" ;
                                sh:description "Color of the car" ;
                                sh:datatype    xsd:string ;
                                sh:minCount    1 ;
                                sh:maxCount    1 ; ];
              sh:property     [ sh:path        example:brand;
                                sh:name        "brand" ;
                                sh:description "Brand of the car" ;
                                sh:datatype    xsd:string ;
                                sh:in          ("toyota" "mercedes" "fiat") ;
                                sh:minCount    1 ;
                                sh:maxCount    1 ; ];
              sh:property     [ sh:path        example:n_doors;
                                sh:name        "n_doors" ;
                                sh:description "Number of doors" ;
                                sh:datatype    xsd:integer ;
                                sh:minInclusive   3 ;
                                sh:maxInclusive   5 ;
                                sh:minCount    1 ;
                                sh:maxCount    1 ; ];
      .
   )

    hash_data_jsonld = JSON.parse %(
      {
        "@context": {
          "@vocab": "https://example.com/"
        },
        "@graph": [
          {
            "@id": "http://schema.org/my_car_1",
            "@type": "Car",
            "color": "blue",
            "brand": "toyota",
            "n_doors": 5
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    assert_equal(conform, true)
    assert_equal(messages.size, 0)

    hash_data_jsonld = JSON.parse %(
      {
        "@context": {
          "@vocab": "https://example.com/"
        },
        "@graph": [
          {
            "@id": "http://schema.org/my_car_1",
            "@type": "Car",
            "color": "blue",
            "brand": "toyota",
            "n_doors": 6
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    assert_equal(conform, false)
    assert_equal(messages.size, 1)

  end

  def test_valid_property_email_pattern

    # NOTE: see here; here using HTML regex.
    str_shacl_ttl = %(
      @prefix example: <https://example.com/> .
      @prefix xsd:    <http://www.w3.org/2001/XMLSchema#> .
      @prefix sh:     <http://www.w3.org/ns/shacl#> .

      example:CarShape
              a sh:NodeShape;
              sh:description  "Abstract shape that describes a car entity" ;
              sh:targetClass  example:Car;
              sh:node         example:Car;
              sh:name         "Car";
              sh:property     [ sh:path        example:color;
                                sh:name        "color" ;
                                sh:description "Color of the car" ;
                                sh:datatype    xsd:string ;
                                sh:minCount    1 ;
                                sh:maxCount    1 ; ];
              sh:property     [ sh:path        example:brand;
                                sh:name        "brand" ;
                                sh:description "Brand of the car" ;
                                sh:datatype    xsd:string ;
                                sh:in          ("toyota" "mercedes" "fiat") ;
                                sh:minCount    1 ;
                                sh:maxCount    1 ; ];
              sh:property     [ sh:path        example:email_warehouse;
                                sh:name        "email_warehouse" ;
                                sh:description "Warehouse e-mail" ;
                                sh:datatype    xsd:string ;
                                sh:pattern     "^[a-zA-Z0-9.!#$%&’*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)*$" ;
                                sh:flags       "g" ;
                                sh:minCount    1 ;
                                sh:maxCount    1 ; ];
      .
   )

    hash_data_jsonld = JSON.parse %(
      {
        "@context": {
          "@vocab": "https://example.com/"
        },
        "@graph": [
          {
            "@id": "http://schema.org/my_car_1",
            "@type": "Car",
            "color": "blue",
            "brand": "toyota",
            "email_warehouse": "john.doe@fake.com"
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    assert_equal(conform, true)
    assert_equal(messages.size, 0)

    hash_data_jsonld = JSON.parse %(
      {
        "@context": {
          "@vocab": "https://example.com/"
        },
        "@graph": [
          {
            "@id": "http://schema.org/my_car_1",
            "@type": "Car",
            "color": "blue",
            "brand": "toyota",
            "email_warehouse": "john.doe@fakecom"
          },
          {
            "@id": "http://schema.org/my_car_1",
            "@type": "Car",
            "color": "blue",
            "brand": "toyota",
            "email_warehouse": "john.doefake.com"
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    assert_equal(conform, false)
    assert_equal(messages.size, 2)

  end

end
