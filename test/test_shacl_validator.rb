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


  def test_invalid_property_xsd_datatype

    str_shacl_ttl = %(
      @prefix example: <https://example.com/> .
      @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
      @prefix sh: <http://www.w3.org/ns/shacl#> .
      @prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .

      example:AgentShape
          a sh:NodeShape ;
          sh:description "Abstract shape that describes an agent entity" ;
          sh:targetClass example:Agent ;
          sh:name "Agent" ;
      .

      example:PersonShape
          a sh:NodeShape ;
          sh:node example:AgentShape ;
          sh:description "Person entity" ;
          sh:targetClass example:Person ;
          sh:name "Person" ;
          sh:property
              [
                  sh:path example:name ;
                  sh:name "name" ;
                  sh:description "name of the person" ;
                  sh:datatype xsd:string ;
                  sh:minCount 1 ;
                  sh:maxCount 1 ;
              ] .

    )

    hash_data_jsonld = JSON.parse %(
      {
        "@context": {
          "@vocab": "https://example.com/"
        },
        "@graph": [
          {
            "@type": "Person",
            "name": {
              "@id": "http://schema.org/my_wrong_obj",
              "label": "ciao"
            }
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    # pp messages
    assert_equal(conform, false)

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

  def test_missing_data_type_when_ref_class_does_not_exist

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
                "@id": "http://schema.org/john_doe"
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

  def test_single_inheritance

    str_shacl_ttl = %(
      @prefix example: <https://example.com/> .
      @prefix xsd:    <http://www.w3.org/2001/XMLSchema#> .
      @prefix sh:     <http://www.w3.org/ns/shacl#> .

      example:CarShape
              a sh:NodeShape;
              sh:description  "Abstract shape that describes a car entity" ;
              sh:targetClass  example:Car;
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

      example:ElectricCarShape
              a sh:NodeShape;
              sh:description  "Abstract shape that describes a electric car entity" ;
              sh:targetClass  example:ElectricCar;
              sh:name         "ElectricCar";
              sh:property     [ sh:path        example:battery;
                                sh:name        "battery" ;
                                sh:description "Battery of the car" ;
                                sh:datatype    xsd:string ;
                                sh:minCount    1 ;
                                sh:maxCount    3 ; ];
      .

    )

    hash_data_jsonld = JSON.parse %(
      {
          "@context": {
            "@vocab": "https://example.com/",
            "rdfs": "http://www.w3.org/2000/01/rdf-schema#",
            "rdfs:subClassOf": {
              "@type": "@id"
            }
          },
        "@graph": [
          {
            "@id": "https://example.com/ElectricCar",
            "rdfs:subClassOf": "https://example.com/Car"
          },
          {
            "@id": "http://schema.org/my_car_1",
            "@type": "Car",
            "color": "blue",
            "brand": "toyota"
          },
          {
            "@id": "http://schema.org/my_car_2",
            "@type": "ElectricCar",
            "brand": "BYD"
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    assert_equal(conform, false)
    # non conform for "my_car_2":
    # - misses one prop of type "ElectricCar": "battery"
    # - misses one prop of parent type "Car: "color"
    assert_equal(messages.size, 2)

  end

  def test_multiple_inheritance

    str_shacl_ttl = %(
      @prefix example: <https://example.com/> .
      @prefix xsd:    <http://www.w3.org/2001/XMLSchema#> .
      @prefix sh:     <http://www.w3.org/ns/shacl#> .

      example:CarShape
          a sh:NodeShape;
          sh:description  "Abstract shape that describes a car entity" ;
          sh:targetClass  example:Car;
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

      example:ElectricVehicleShape
          a sh:NodeShape;
          sh:description  "Abstract shape that describes a electric vehicle entity" ;
          sh:targetClass  example:ElectricVehicle;
          sh:name         "ElectricVehicle";
          sh:property     [ sh:path        example:efficiency;
                            sh:name        "efficiency" ;
                            sh:description "Efficiency of the vehicle" ;
                            sh:datatype    xsd:float ;
                            sh:minCount    1 ;
                            sh:maxCount    1 ; ];
      .

      example:ElectricCarShape
          a sh:NodeShape;
          sh:description  "Abstract shape that describes a electric car entity" ;
          sh:targetClass  example:ElectricCar;
          sh:name         "ElectricCar";
          sh:property     [ sh:path        example:battery;
                            sh:name        "battery" ;
                            sh:description "Battery of the car" ;
                            sh:datatype    xsd:string ;
                            sh:minCount    1 ;
                            sh:maxCount    3 ; ];
      .

    )

    hash_data_jsonld = JSON.parse %(
      {
          "@context": {
            "@vocab": "https://example.com/",
            "rdfs": "http://www.w3.org/2000/01/rdf-schema#",
            "rdfs:subClassOf": {
              "@type": "@id"
            }
          },
        "@graph": [
          {
            "@id": "https://example.com/ElectricCar",
            "rdfs:subClassOf": "https://example.com/Car"
          },
          {
            "@id": "https://example.com/ElectricCar",
            "rdfs:subClassOf": "https://example.com/ElectricVehicle"
          },
          {
            "@id": "http://schema.org/my_car_1",
            "@type": "Car",
            "color": "blue",
            "brand": "toyota"
          },
          {
            "@id": "http://schema.org/my_car_2",
            "@type": "ElectricCar",
            "brand": "toyota",
            "battery": "something"
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    assert_equal(conform, false)
    # non conform for "my_car_2":
    # - misses one prop of parent 1 type "Car": "color"
    # - misses one prop of parent 2 type "ElectricVehicle": "efficiency"
    assert_equal(messages.size, 2)

  end

  def test_shacl_datatype_vs_jsonld_type

    str_shacl_ttl = %(
      @prefix example: <https://example.com/> .
      @prefix xsd:    <http://www.w3.org/2001/XMLSchema#> .
      @prefix sh:     <http://www.w3.org/ns/shacl#> .
      @prefix time:   <http://www.w3.org/2006/time#> .
      @prefix time2:  <https://example.com/time#> .

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
              sh:property     [ sh:path        example:interval_check;
                                sh:name        "interval_check" ;
                                sh:description "Interval to check the car" ;
                                sh:datatype    time2:MyInterval ;
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
            "@id": "http://schema.org/my_car_2",
            "@type": "Car",
            "color": "black",
            "interval_check": {
              "@type": "https://example.com/time#MyInterval",
              "@value": "can-be-anything"
            }
          }
        ]
      }
    )

    # If JSON-LD @type is declared to be matching the sh:datatype,
    # and no other constrains are indicated, this is valid.

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
            "@id": "http://schema.org/my_car_2",
            "@type": "Car",
            "color": "black",
            "interval_check": {
              "@type": "http://www.w3.org/2006/time#DateTimeInterval",
              "@value": "can-be-anything"
            }
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    assert_equal(conform, false)
    assert_equal(messages.size, 1)

  end

  def test_invalid_literal

    str_shacl_ttl = %(
      @prefix example: <https://example.com/> .
      @prefix xsd:    <http://www.w3.org/2001/XMLSchema#> .
      @prefix sh:     <http://www.w3.org/ns/shacl#> .
      @prefix time:   <http://www.w3.org/2006/time#> .

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
              sh:property     [ sh:path        example:interval_check;
                                sh:name        "interval_check" ;
                                sh:description "Interval to check the car" ;
                                sh:datatype    xsd:integer ;
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
            "@id": "http://schema.org/my_car_2",
            "@type": "Car",
            "color": "black",
            "interval_check": {
              "@type": "http://www.w3.org/2001/XMLSchema#integer",
              "@value": "1b"
            }
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    assert_equal(conform, false)
    assert_equal(messages.size, 1)

  end

  def test_inherited_change_property
    Solis.config.path = 'test/resources/config'

    @shacl = File.read('test/resources/person_shacl.ttl')

    config = {
      cache_dir: '/tmp/cache',
      store: Solis::Store::Memory.new(),
      model: {
        prefix: 'example',
        namespace: 'https://example.com/',
        uri: StringIO.new(@shacl),
        content_type: 'text/turtle'
      }
    }
    solis = Solis.new(config)

    person_shacl = solis.model.writer

    # check if the generated SHACL is valid
    shacl_shacl = Solis::Model::Reader.from_uri(uri: 'file://test/resources/shacl-shacl.ttl', content_type: 'text/turtle')
    validator = Solis::SHACLValidatorV2.new(shacl_shacl.dump(:ttl), :ttl, @opts)
    conform, messages = validator.execute(RDF::Graph.new.from_ttl(person_shacl), :graph)

    assert_equal(conform, true)

    #www = RDF::Literal.new("http://example.org", datatype: RDF::XSD.anyURI)
    # www = RDF::Literal::AnyURI.new("http://example.org")
    #assert_kind_of(RDF::Literal::AnyURI, www)
    www = "http://example.org/abc"
    person_string = {
      name: { firstName: "John", lastName: "Doe"},
      website: www
    }

    person_integer = {
      name: 1,
      website: www
    }

    good_person_entity = solis.model.entity.new('Person', person_string)
    #    puts good_person_entity.to_pretty_pre_validate_jsonld

    bad_person_entity = solis.model.entity.new('Person', person_integer)
    #puts bad_person_entity.to_pretty_pre_validate_jsonld

    validator = Solis::SHACLValidatorV2.new(person_shacl, :ttl, @opts)
    conform, messages = validator.execute(JSON.parse(good_person_entity.to_pretty_jsonld), :jsonld)
    puts good_person_entity.to_pretty_jsonld
    puts JSON.pretty_generate(messages)
    assert_equal(0, messages.size)
    assert_equal(conform, true)

    conform, messages = validator.execute(JSON.parse(bad_person_entity.to_pretty_jsonld), :jsonld)
    assert_equal(conform, false)
    assert_equal(messages.size, 1)
    assert_match("Value must be an instance of <https://example.com/PersonName>", messages[0])


    organization = {
      name: "LIBIS",
      website: "http://example.org"
    }

    organization_entity = solis.model.entity.new('Organization', organization)

    conform_literals, messages_literals, conform_shacl, messages_shacl = organization_entity.validate
    pp messages_shacl
    assert_equal(conform_literals & conform_shacl, true)



  end

  def test_inherited_change_property_2

    # NOTE:
    # the only difference with previous test is that before:
    #     sh:node example:Agent
    # while now:
    #     sh:node example:AgentShape
    # As defined in https://www.w3.org/TR/shacl/#NodeConstraintComponent,
    # sh:node predicate always wants a SHAPE object.
    # However, in the tests sometimes it uses a CLASS, which seems out of specifications.
    # When this happens, my understanding is that sh:node is simply ignored by the validator,
    # and the information about sub-classing is lost, that is why assertions in test_inherited_change_property
    # where passing .... to be discussed

    str_shacl_ttl = %(
      @prefix example: <https://example.com/> .
      @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
      @prefix sh: <http://www.w3.org/ns/shacl#> .
      @prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .

      example:AgentShape
          a sh:NodeShape ;
          sh:description "Abstract shape that describes an agent entity" ;
          sh:targetClass example:Agent ;
          sh:name "Agent" ;
          sh:property
              [
                  sh:path example:name ;
                  sh:name "name" ;
                  sh:description "name of the agent" ;
                  sh:datatype xsd:string ;
                  sh:minCount 1 ;
                  sh:maxCount 1 ;
              ] .

      example:PersonShape
          a sh:NodeShape ;
          sh:node example:AgentShape ;
          sh:description "Person entity" ;
          sh:targetClass example:Person ;
          sh:name "Person" ;
          sh:property
              [
                  sh:path example:name ;
                  sh:name "name" ;
                  sh:description "name of the person" ;
                  sh:datatype xsd:integer ;
                  sh:minCount 1 ;
                  sh:maxCount 1 ;
              ] .

    )

    hash_data_jsonld = JSON.parse %(
      {
        "@context": {
          "@vocab": "https://example.com/"
        },
        "@graph": [
          {
            "@type": "Person",
            "name": 1
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    # pp messages
    assert_equal(conform, false)

  end
  def test_overwrite_datatype_when_inheriting_1

    # SHACL shapes for "color" are both enabled:
    # there is no data that is, at the same time, both string and integer ...
    str_shacl_ttl = %(
      @prefix example: <https://example.com/> .
      @prefix xsd:    <http://www.w3.org/2001/XMLSchema#> .
      @prefix sh:     <http://www.w3.org/ns/shacl#> .

      example:CarShape
              a sh:NodeShape;
              sh:description  "Abstract shape that describes a car entity" ;
              sh:targetClass  example:Car;
              sh:name         "Car";
              sh:property     [ sh:path        example:color;
                                sh:name        "color" ;
                                sh:description "Color of the car" ;
                                sh:datatype    xsd:string ;
                                sh:minCount    1 ;
                                sh:maxCount    1 ; ];
      .

      example:ElectricCarShape
              a sh:NodeShape;
              sh:description  "Abstract shape that describes a electric car entity" ;
              sh:targetClass  example:ElectricCar;
              sh:name         "ElectricCar";
              sh:property     [ sh:path        example:color;
                                sh:name        "color" ;
                                sh:description "Color of the car" ;
                                sh:datatype    xsd:integer ;
                                sh:minCount    1 ;
                                sh:maxCount    1 ; ];
      .

    )

    hash_data_jsonld = JSON.parse %(
      {
        "@context": {
          "@vocab": "https://example.com/",
          "rdfs": "http://www.w3.org/2000/01/rdf-schema#",
          "rdfs:subClassOf": {
            "@type": "@id"
          }
        },
        "@graph": [
          {
            "@id": "https://example.com/ElectricCar",
            "rdfs:subClassOf": "https://example.com/Car"
          },
          {
            "@id": "http://schema.org/my_car",
            "@type": "ElectricCar",
            "color": "abc"
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    # pp messages
    assert_equal(conform, false)

    hash_data_jsonld = JSON.parse %(
      {
        "@context": {
          "@vocab": "https://example.com/",
          "rdfs": "http://www.w3.org/2000/01/rdf-schema#",
          "rdfs:subClassOf": {
            "@type": "@id"
          }
        },
        "@graph": [
          {
            "@id": "https://example.com/ElectricCar",
            "rdfs:subClassOf": "https://example.com/Car"
          },
          {
            "@id": "http://schema.org/my_car",
            "@type": "ElectricCar",
            "color": 123
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    # pp messages
    assert_equal(conform, false)

  end

  def test_overwrite_datatype_when_inheriting_2

    str_shacl_ttl = %(
      @prefix example: <https://example.com/> .
      @prefix xsd:    <http://www.w3.org/2001/XMLSchema#> .
      @prefix sh:     <http://www.w3.org/ns/shacl#> .

      example:CarShape
              a sh:NodeShape;
              sh:description  "Abstract shape that describes a car entity" ;
              sh:targetClass  example:Car;
              sh:name         "Car";
              sh:property     [ sh:path        example:color;
                                sh:name        "color" ;
                                sh:description "Color of the car" ;
                                sh:datatype    xsd:string ;
                                sh:minCount    1 ;
                                sh:maxCount    1 ; ];
      .

      example:ElectricCarShape
              a sh:NodeShape;
              sh:node         example:CarShape ;
              sh:description  "Abstract shape that describes a electric car entity" ;
              sh:targetClass  example:ElectricCar;
              sh:name         "ElectricCar";
              sh:property     [ sh:path        example:color;
                                sh:name        "color" ;
                                sh:description "Color of the car" ;
                                sh:datatype    xsd:integer ;
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
            "@id": "http://schema.org/my_car",
            "@type": "ElectricCar",
            "color": "abc"
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    # pp messages
    assert_equal(conform, false)

    hash_data_jsonld = JSON.parse %(
      {
        "@context": {
          "@vocab": "https://example.com/"
        },
        "@graph": [
          {
            "@id": "http://schema.org/my_car",
            "@type": "ElectricCar",
            "color": 123
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    # pp messages
    assert_equal(conform, false)

  end

  def test_split_attribute_info_in_different_property_nodes

    str_shacl_ttl = %(
      @prefix rdf:    <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
      @prefix example: <https://example.com/> .
      @prefix xsd:    <http://www.w3.org/2001/XMLSchema#> .
      @prefix sh:     <http://www.w3.org/ns/shacl#> .
      @prefix time:   <http://www.w3.org/2006/time#> .

      example:CarShape
              a sh:NodeShape;
              sh:description  "Abstract shape that describes a car entity" ;
              sh:targetClass  example:Car;
              sh:node         example:Car;
              sh:name         "Car";
              sh:closed       true ;
              sh:ignoredProperties (rdf:type) ;
              sh:property     [ sh:path        example:color;
                                sh:name        "color_datatype" ;
                                sh:description "Color datatype" ;
                                sh:datatype    xsd:string ; ];
              sh:property     [ sh:path        example:color;
                                sh:name        "color_cardinality" ;
                                sh:description "Color cardinality" ;
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
            "@id": "http://schema.org/my_car_2",
            "@type": "Car",
            "color": "black"
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    assert_equal(conform, true)

  end

  def test_validator_ignores_owl_equivalent_class

    str_shacl_ttl = %(
      @prefix example: <https://example.com/> .
      @prefix xsd:    <http://www.w3.org/2001/XMLSchema#> .
      @prefix sh:     <http://www.w3.org/ns/shacl#> .

      example:CarShape
              a sh:NodeShape;
              sh:description  "Abstract shape that describes a car entity" ;
              sh:targetClass  example:Car;
              sh:name         "Car";
              sh:property     [ sh:path        example:color;
                                sh:name        "color" ;
                                sh:description "Color of the car" ;
                                sh:datatype    xsd:string ;
                                sh:minCount    1 ;
                                sh:maxCount    1 ; ];
      .

    )

    hash_data_jsonld = JSON.parse %(
      {
        "@context": {
          "@vocab": "https://example.com/",
          "owl": "http://www.w3.org/2002/07/owl#",
          "owl:equivalentClass": {
            "@type": "@id"
          }
        },
        "@graph": [
          {
            "@id": "https://example.com/Car",
            "@type": "owl:Class"
          },
          {
            "@id": "https://example.com/AnotherCar",
            "@type": "owl:Class"
          },
          {
            "@id": "https://example.com/AnotherCar",
            "owl:equivalentClass": "https://example.com/Car"
          },
          {
            "@id": "http://schema.org/my_car",
            "@type": "AnotherCar",
            "color": 123
          }
        ]
      }
    )

    # graph_data = RDF::Graph.new << JSON::LD::API.toRdf(hash_data_jsonld)
    # puts graph_data.dump(:ttl)

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    assert_equal(conform, true)

    str_shacl_ttl = %(
      @prefix example: <https://example.com/> .
      @prefix xsd:    <http://www.w3.org/2001/XMLSchema#> .
      @prefix sh:     <http://www.w3.org/ns/shacl#> .
      @prefix owl:    <http://www.w3.org/2002/07/owl#> .

      example:Car a owl:Class .
      example:AnotherCar a owl:Class .
      example:Car owl:equivalentClass example:AnotherCar .

      example:CarShape
              a sh:NodeShape;
              sh:description  "Abstract shape that describes a car entity" ;
              sh:targetClass  example:Car;
              sh:name         "Car";
              sh:property     [ sh:path        example:color;
                                sh:name        "color" ;
                                sh:description "Color of the car" ;
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
            "@id": "http://schema.org/my_car",
            "@type": "AnotherCar",
            "color": 123
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    assert_equal(conform, true)

  end

  def test_multiple_target_classes

    str_shacl_ttl = %(
      @prefix example: <https://example.com/> .
      @prefix xsd:    <http://www.w3.org/2001/XMLSchema#> .
      @prefix sh:     <http://www.w3.org/ns/shacl#> .

      example:CarShape
              a sh:NodeShape;
              sh:description  "Abstract shape that describes a car entity" ;
              sh:targetClass  example:Car;
              sh:targetClass  example:AnotherCar;
              sh:name         "Car";
              sh:property     [ sh:path        example:color;
                                sh:name        "color" ;
                                sh:description "Color of the car" ;
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
            "@id": "http://schema.org/my_car",
            "@type": "Car",
            "color": 123
          },
          {
            "@id": "http://schema.org/my_car_2",
            "@type": "AnotherCar",
            "color": 123
          }
        ]
      }
    )

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    assert_equal(conform, false)

  end

  def test_rdf_lists_and_containers_with_target_class

    # NOTE:
    # the validator seems to ignore rdf:List and containers (rdf:Seq).
    # Check this: https://github.com/TopQuadrant/shacl/issues/196

    str_shacl_ttl = %(
      @prefix example: <https://example.com/> .
      @prefix xsd:    <http://www.w3.org/2001/XMLSchema#> .
      @prefix sh:     <http://www.w3.org/ns/shacl#> .
      @prefix rdf:    <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .

      example:CarShape
              a sh:NodeShape;
              sh:description  "Abstract shape that describes a car entity" ;
              sh:targetClass  example:Car;
              sh:name         "Car";
              sh:property     [ sh:path        example:color;
                                sh:name        "color" ;
                                sh:description "Color of the car" ;
                                sh:class       rdf:List;
                              ];
      .

    )

    hash_data_jsonld = JSON.parse %(
      {
        "@context": {
          "@vocab": "https://example.com/",
          "color": {
            "@id": "https://example.com/color",
            "@container": "@list"
          }
        },
        "@graph": [
          {
            "@id": "http://schema.org/my_car",
            "@type": "Car",
            "color": [1, "green"]
          }
        ]
      }
    )

    g = RDF::Graph.new << JSON::LD::API.toRdf(hash_data_jsonld)
    puts g.dump(:ttl)

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    pp messages

    hash_data_jsonld = JSON.parse %(
      {
        "@context": {
          "@vocab": "https://example.com/"
        },
        "@graph": [
          {
            "@id": "http://schema.org/my_car",
            "@type": "Car",
            "color": {
              "@list": [1, "green"]
            }
          }
        ]
      }
    )

    g = RDF::Graph.new << JSON::LD::API.toRdf(hash_data_jsonld)
    puts g.dump(:ttl)

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    pp messages

  end

  def test_rdf_lists_and_containers_with_dash

    str_shacl_ttl = %(
      @prefix example: <https://example.com/> .
      @prefix xsd:    <http://www.w3.org/2001/XMLSchema#> .
      @prefix sh:     <http://www.w3.org/ns/shacl#> .
      @prefix dash:   <http://datashapes.org/dash#> .
      @prefix rdf:    <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .

      example:CarShape
              a sh:NodeShape;
              sh:description  "Abstract shape that describes a car entity" ;
              sh:targetClass  example:Car;
              sh:name         "Car";
              sh:property     [ sh:path        example:color;
                                sh:name        "color" ;
                                sh:description "Color of the car" ;
                                sh:node        dash:ListShape;
                              ];
      .

    )

    hash_data_jsonld = JSON.parse %(
      {
        "@context": {
          "@vocab": "https://example.com/"
        },
        "@graph": [
          {
            "@id": "http://schema.org/my_car",
            "@type": "Car",
            "color": {
              "@list": [1, "green"]
            }
          }
        ]
      }
    )

    g = RDF::Graph.new << JSON::LD::API.toRdf(hash_data_jsonld)
    puts g.dump(:ttl)

    validator = Solis::SHACLValidator.new(str_shacl_ttl, :ttl, @opts)
    conform, messages = validator.execute(hash_data_jsonld, :jsonld)
    pp messages

  end

end
