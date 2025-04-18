# frozen_string_literal: true

require "test_helper"

class TestUtilsJSONLD < Minitest::Test

  def test_flatten_depsort

    hash_data_jsonld = JSON.parse %(
      {
          "@context": {
              "@vocab": "https://example.com/"
          },
          "@graph": [
              {
                  "@id": "http://schema.org/my_car",
                  "@type": "Car",
                  "brand": "toyota",
                  "color": "blue",
                  "attr_obj": {
                      "x": 1,
                      "y": 2
                  },
                  "door": {
                      "@id": "http://schema.org/my_door",
                      "@type": "Door",
                      "window": {
                          "@id": "http://schema.org/my_window",
                          "@type": "Window",
                          "glass": {
                              "@id": "http://schema.org/my_glass",
                              "@type": "Glass"
                          }
                      }
                  },
                  "others": [
                      {
                          "@id": "http://schema.org/my_obj_1",
                          "@type": "Object",
                          "attribute": "value"
                      },
                      {
                          "@id": "http://schema.org/my_obj_2",
                          "@type": "Object",
                          "attribute": "value"
                      }
                  ]
              }
          ]
      }
    )

    flattened = Solis::Utils::JSONLD.flatten_jsonld(hash_data_jsonld)

    assert_equal(flattened['@graph'].size, 7)

    flattened_ordered = Solis::Utils::JSONLD.sort_flat_jsonld_by_deps(flattened)
    assert_equal(flattened_ordered['@graph'].size, 7)

    g = flattened_ordered['@graph']
    assert_equal(g.index { |e| e['@type'] == "Glass" } < g.index { |e| e['@type'] == "Window" }, true)
    assert_equal(g.index { |e| e['@type'] == "Window" } < g.index { |e| e['@type'] == "Door" }, true)
    assert_equal(g.index { |e| e['@type'] == "Door" } < g.index { |e| e['@type'] == "Car" }, true)
    assert_equal(g.index { |e| e['@type'] == "Object" } < g.index { |e| e['@type'] == "Car" }, true)
    assert_equal(g.index { |e| e['x'] == 1 } < g.index { |e| e['@type'] == "Car" }, true)
    assert_equal(g.index { |e| e['@type'] == "Car" }, g.size-1)

  end


  def test_infer_jsonld_types_from_shapes

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
              sh:property     [ sh:path        example:address;
                                sh:name        "address" ;
                                sh:description "Address of the person" ;
                                sh:nodeKind    sh:IRI ;
                                sh:class       example:Address ;
                                sh:minCount    1 ;
                                sh:maxCount    1 ; ];
      .

      example:AddressShape
              a sh:NodeShape;
              sh:description  "Abstract shape that describes an address" ;
              sh:targetClass  example:Address;
              sh:node         example:Address;
              sh:name         "Address";
              sh:property     [ sh:path        example:street;
                                sh:name        "street" ;
                                sh:description "Street of the address" ;
                                sh:datatype    xsd:string ;
                                sh:minCount    1 ;
                                sh:maxCount    1 ; ];
      .

    )

    graph_shacl = RDF::Graph.new
    graph_shacl.from_ttl(str_shacl_ttl)

    parser = SHACLParser.new(graph_shacl)
    shapes = parser.parse_shapes

    hash_data_json = JSON.parse %(
      {
          "color": "blue",
          "brand": "toyota",
          "owners": [
            {
              "name": "jon doe",
              "address": {
                "street": "fake street"
              }
            }
          ]
      }
    )

    Solis::Utils::JSONLD.infer_jsonld_types_from_shapes!(hash_data_json, shapes, 'Car')

    assert_equal(hash_data_json['@type'], 'Car')
    assert_equal(hash_data_json['owners'][0]['@type'], 'Person')
    assert_equal(hash_data_json['owners'][0]['address']['@type'], 'Address')

  end

  def test_make_jsonld_datatypes_context_from_shape

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

    graph_shacl = RDF::Graph.new
    graph_shacl.from_ttl(str_shacl_ttl)

    parser = SHACLParser.new(graph_shacl)
    shapes = parser.parse_shapes

    obj = JSON.parse %(
      {
          "@type": "Car",
          "color": "blue",
          "brand": "toyota"
      }
    )

    shape = shapes[obj['@type']]
    context_datatypes = Solis::Utils::JSONLD.make_jsonld_datatypes_context_from_shape(shape)

    context = {
      "@vocab" => "https://example.com/"
    }
    context.merge!(context_datatypes)

    hash_jsonld_compacted = Solis::Utils::JSONLD.json_object_to_jsonld(obj, context)

    hash_jsonld_expanded = JSON::LD::API.expand(hash_jsonld_compacted)[0]

    assert_equal(hash_jsonld_expanded['@context'], nil)
    assert_equal(hash_jsonld_expanded['https://example.com/color'].is_a?(Array), true)
    assert_equal(hash_jsonld_expanded['https://example.com/color'][0]['@value'], 'blue')
    assert_equal(hash_jsonld_expanded['https://example.com/brand'][0]['@value'], 'toyota')

  end


end
