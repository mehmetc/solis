# frozen_string_literal: true

require "test_helper"

Solis::SHACLValidator = Solis::SHACLValidatorV2

class TestSHACLValidator < Minitest::Test
  def setup
    super
    @opts = {
      path_dir: File.join(__dir__, './data')
    }
  end

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

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
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

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
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

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
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

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
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

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
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

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    assert_equal(conform, false)
    assert_equal(messages.size, 1)

  end

  def test_no_type_in_referenced_entity_instance

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

    # "owners" missing "@type"
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
                "@id": "http://schema.org/john_doe",
                "address": "fake street"
              }
            ]
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    assert_equal(conform, false)
    assert_equal(messages.size, 1)

  end

  def test_allow_blank_node_as_referenced_entity_instance

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

    # referenced instance has no "@id" (i.e. blank node), not allowed
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
                "@type": "Person",
                "address": "fake street"
              }
            ]
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    assert_equal(conform, false)
    assert_equal(messages.size, 1)

    # blank not allowed by the model
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
                                sh:nodeKind    sh:BlankNodeOrIRI ;
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
                "@type": "Person",
                "address": "fake street"
              }
            ]
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    assert_equal(conform, true)
    assert_equal(messages.size, 0)

  end

  def test_validation_on_wrongly_shaped_id

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
                                sh:nodeKind    sh:BlankNodeOrIRI ;
                                sh:class       example:Person ;
                                sh:minCount    1 ; ];
      .
    )

    # "@id" in referenced entity instance is malformed (neither IRI or blank node).
    # In this case, when JSON-LD is translated into a graph where the whole referenced "owner" is not there.
    # Hence the error here is about missing "owner" (required by definition),
    # and not about a malformed "@id" of the owner.
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
                "@id": "something",
                "@type": "Person",
                "address": "fake street"
              }
            ]
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
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

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
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

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
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

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
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

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
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

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
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

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    assert_equal(conform, false)
    assert_equal(messages.size, 1)

  end

  def test_valid_property_email_pattern

    # NOTE: see here:
    # https://piotr.gg/regexp/email-address-regular-expression-that-99-99-works.html
    # The used regex is: HTML5.
    # SHACLValidatorV2 does not support "sh:flags"
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

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    assert_equal(conform, true)
    assert_equal(messages.size, 0)

    # can check here: https://www.activityinfo.org/support/docs/regex/test.html
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
            "@id": "http://schema.org/my_car_2",
            "@type": "Car",
            "color": "blue",
            "brand": "toyota",
            "email_warehouse": "john.doefake.com"
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    assert_equal(conform, false)
    assert_equal(messages.size, 1)

  end

  def test_property_amount_in_range

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
                                sh:maxCount    3 ; ];
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

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
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
            "color": ["blue"],
            "brand": "toyota"
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
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
            "color": ["blue", "red"],
            "brand": "toyota"
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    assert_equal(conform, true)
    assert_equal(messages.size, 0)

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
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
            "color": ["blue", "red", "yellow", "green"],
            "brand": "toyota"
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    assert_equal(conform, false)
    assert_equal(messages.size, 1)

  end

  def test_missing_data_type_when_ref_class_exists

    str_shacl_ttl = %(
      @prefix example: <https://example.com/> .
      @prefix xsd:    <http://www.w3.org/2001/XMLSchema#> .
      @prefix sh:     <http://www.w3.org/ns/shacl#> .

      example:PersonShape
              a sh:NodeShape;
              sh:description  "Abstract shape that describes a person entity" ;
              sh:targetClass  example:Person;
              sh:node         example:Person;
              sh:name         "Person";
              sh:property     [ sh:path        example:name;
                                sh:name        "name" ;
                                sh:description "Name of the person" ;
                                sh:datatype    xsd:string ;
                                sh:minCount    1 ;
                                sh:maxCount    1 ; ];
      .

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

    # "owners" object misses "@type".
    # But this is allowed, to express that the "Car" object just wants to
    # reference an existing "Person" object.
    # However, since the "owners" property in the SHACL file contains a "sh:class" predicate,
    # "@type" must exist in order for the validation to succeed.
    # Having a type in a nested object triggers both the following validations:
    # 1) the shape constraint on that data type instance
    # 2) if referenced, also reference class check is triggered in the referent
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
                "@id": "http://schema.org/john_doe"
              }
            ]
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    assert_equal(conform, false)
    assert_equal(messages.size, 1)

  end

end
