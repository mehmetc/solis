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


  # def test_infer_jsonld_types_from_shapes
  #
  #   str_shacl_ttl = %(
  #     @prefix example: <https://example.com/> .
  #     @prefix xsd:    <http://www.w3.org/2001/XMLSchema#> .
  #     @prefix sh:     <http://www.w3.org/ns/shacl#> .
  #
  #     example:CarShape
  #             a sh:NodeShape;
  #             sh:description  "Abstract shape that describes a car entity" ;
  #             sh:targetClass  example:Car;
  #             sh:node         example:Car;
  #             sh:name         "Car";
  #             sh:property     [ sh:path        example:color;
  #                               sh:name        "color" ;
  #                               sh:description "Color of the car" ;
  #                               sh:datatype    xsd:string ;
  #                               sh:minCount    1 ;
  #                               sh:maxCount    1 ; ];
  #             sh:property     [ sh:path        example:brand;
  #                               sh:name        "brand" ;
  #                               sh:description "Brand of the car" ;
  #                               sh:datatype    xsd:string ;
  #                               sh:minCount    1 ;
  #                               sh:maxCount    1 ; ];
  #             sh:property     [ sh:path        example:owners;
  #                               sh:name        "owners" ;
  #                               sh:description "Owners of the car" ;
  #                               sh:nodeKind    sh:IRI ;
  #                               sh:class       example:Person ;
  #                               sh:minCount    1 ; ];
  #     .
  #
  #     example:PersonShape
  #             a sh:NodeShape;
  #             sh:description  "Abstract shape that describes a person entity" ;
  #             sh:targetClass  example:Person;
  #             sh:node         example:Person;
  #             sh:name         "Person";
  #             sh:property     [ sh:path        example:name;
  #                               sh:name        "name" ;
  #                               sh:description "Name of the person" ;
  #                               sh:datatype    xsd:string ;
  #                               sh:minCount    1 ;
  #                               sh:maxCount    1 ; ];
  #             sh:property     [ sh:path        example:address;
  #                               sh:name        "address" ;
  #                               sh:description "Address of the person" ;
  #                               sh:nodeKind    sh:IRI ;
  #                               sh:class       example:Address ;
  #                               sh:minCount    1 ;
  #                               sh:maxCount    1 ; ];
  #     .
  #
  #     example:AddressShape
  #             a sh:NodeShape;
  #             sh:description  "Abstract shape that describes an address" ;
  #             sh:targetClass  example:Address;
  #             sh:node         example:Address;
  #             sh:name         "Address";
  #             sh:property     [ sh:path        example:street;
  #                               sh:name        "street" ;
  #                               sh:description "Street of the address" ;
  #                               sh:datatype    xsd:string ;
  #                               sh:minCount    1 ;
  #                               sh:maxCount    1 ; ];
  #     .
  #
  #   )
  #
  #   graph_shacl = RDF::Graph.new
  #   graph_shacl.from_ttl(str_shacl_ttl)
  #
  #   parser = SHACLParser.new(graph_shacl)
  #   shapes = parser.parse_shapes
  #
  #   hash_data_json = JSON.parse %(
  #     {
  #         "color": "blue",
  #         "brand": "toyota",
  #         "owners": [
  #           {
  #             "name": "jon doe",
  #             "address": {
  #               "street": "fake street"
  #             }
  #           }
  #         ]
  #     }
  #   )
  #
  #   Solis::Utils::JSONLD.infer_jsonld_types_from_shapes!(hash_data_json, shapes, 'Car')
  #
  #   assert_equal(hash_data_json['@type'], 'Car')
  #   assert_equal(hash_data_json['owners'][0]['@type'], 'Person')
  #   assert_equal(hash_data_json['owners'][0]['address']['@type'], 'Address')
  #
  # end
  #
  # def test_make_jsonld_datatypes_context_from_shape
  #
  #   str_shacl_ttl = %(
  #     @prefix example: <https://example.com/> .
  #     @prefix xsd:    <http://www.w3.org/2001/XMLSchema#> .
  #     @prefix sh:     <http://www.w3.org/ns/shacl#> .
  #
  #     example:CarShape
  #             a sh:NodeShape;
  #             sh:description  "Abstract shape that describes a car entity" ;
  #             sh:targetClass  example:Car;
  #             sh:node         example:Car;
  #             sh:name         "Car";
  #             sh:property     [ sh:path        example:color;
  #                               sh:name        "color" ;
  #                               sh:description "Color of the car" ;
  #                               sh:datatype    xsd:string ;
  #                               sh:minCount    1 ;
  #                               sh:maxCount    1 ; ];
  #             sh:property     [ sh:path        example:brand;
  #                               sh:name        "brand" ;
  #                               sh:description "Brand of the car" ;
  #                               sh:datatype    xsd:string ;
  #                               sh:minCount    1 ;
  #                               sh:maxCount    1 ; ];
  #     .
  #   )
  #
  #   graph_shacl = RDF::Graph.new
  #   graph_shacl.from_ttl(str_shacl_ttl)
  #
  #   parser = SHACLParser.new(graph_shacl)
  #   shapes = parser.parse_shapes
  #
  #   obj = JSON.parse %(
  #     {
  #         "@type": "Car",
  #         "color": "blue",
  #         "brand": "toyota"
  #     }
  #   )
  #
  #   shape = shapes[obj['@type']]
  #   context_datatypes = Solis::Utils::JSONLD.make_jsonld_datatypes_context_from_shape(shape)
  #
  #   context = {
  #     "@vocab" => "https://example.com/"
  #   }
  #   context.merge!(context_datatypes)
  #
  #   hash_jsonld_compacted = Solis::Utils::JSONLD.json_object_to_jsonld(obj, context)
  #
  #   hash_jsonld_expanded = JSON::LD::API.expand(hash_jsonld_compacted)[0]
  #
  #   assert_equal(hash_jsonld_expanded['@context'], nil)
  #   assert_equal(hash_jsonld_expanded['https://example.com/color'].is_a?(Array), true)
  #   assert_equal(hash_jsonld_expanded['https://example.com/color'][0]['@value'], 'blue')
  #   assert_equal(hash_jsonld_expanded['https://example.com/brand'][0]['@value'], 'toyota')
  #
  # end

  def test_remember_to_remove_other_than_top_context

    # Original data (with native context)
    hash_jsonld_1 = JSON.parse %(
      {
        "identifier": [
          {
            "label": "085-139-212-1"
          },
          {
            "label": "LOC-77364452"
          },
          {
            "label": "(BeLVLBS)000012204LBS01-Aleph"
          },
          {
            "label": "26931"
          }
        ],
        "contributor": [
          {
            "viafLink": "http://viaf.org/viaf/305003200",
            "@id": "http://id.loc.gov/authorities/names/n88622561",
            "label": "Brown, Peter."
          },
          {
            "viafLink": "http://viaf.org/viaf/93286981",
            "@id": "http://id.loc.gov/authorities/names/n77001068",
            "label": "Whittaker, Chris"
          },
          {
            "viafLink": "http://viaf.org/viaf/62792360",
            "@id": "http://id.loc.gov/authorities/names/n77001069",
            "label": "Monahan, Jane"
          }
        ],
        "@type": "Book",
        "subject": [
          {
            "label": "614.7 Pollutie van lucht, water, grond--(openbare gezondheidszorg)"
          },
          {
            "label": "#TCON:CCHTB"
          },
          {
            "@id": "http://id.loc.gov/authorities/subjects/sh2008103248",
            "label": "Environmental law Great Britain"
          }
        ],
        "publisher": "Architectural press",
        "place_of_publication": "London",
        "language": {
          "@id": "http://id.loc.gov/vocabulary/iso639-2/eng",
          "label": "eng"
        },
        "@id": "https://open-na.hosted.exlibrisgroup.com/alma/32KUL_LIBIS_NETWORK/bibs/99122040101471",
        "title": "The handbook of environmental powers",
        "@context": "https://open-na.hosted.exlibrisgroup.com/alma/contexts/bib"
      }
    )

    # Original data (with native context) + top custom context.
    # This is a malformed JSON-LD.
    # The flattening function will mess up data content.
    hash_jsonld_2 = JSON.parse %(
      {
        "@context": {
          "@vocab": "http://purl.org/ontology/bibo/"
        },
        "@graph": [
          {
            "identifier": [
              {
                "label": "085-139-212-1",
                "@id": "http://purl.org/ontology/bibo/e6f544d5-b88b-4f16-996b-28460cd03a2b"
              },
              {
                "label": "LOC-77364452",
                "@id": "http://purl.org/ontology/bibo/89d3a46b-9117-46e2-a78a-0263242fc3e3"
              },
              {
                "label": "(BeLVLBS)000012204LBS01-Aleph",
                "@id": "http://purl.org/ontology/bibo/d0c3fe26-01e5-49f5-99fb-254763a834aa"
              },
              {
                "label": "26931",
                "@id": "http://purl.org/ontology/bibo/d0bf61ab-de3d-451f-861b-7224a99c11a3"
              }
            ],
            "contributor": [
              {
                "viafLink": "http://viaf.org/viaf/305003200",
                "@id": "http://id.loc.gov/authorities/names/n88622561",
                "label": "Brown, Peter."
              },
              {
                "viafLink": "http://viaf.org/viaf/93286981",
                "@id": "http://id.loc.gov/authorities/names/n77001068",
                "label": "Whittaker, Chris"
              },
              {
                "viafLink": "http://viaf.org/viaf/62792360",
                "@id": "http://id.loc.gov/authorities/names/n77001069",
                "label": "Monahan, Jane"
              }
            ],
            "@type": "Book",
            "subject": [
              {
                "label": "614.7 Pollutie van lucht, water, grond--(openbare gezondheidszorg)",
                "@id": "http://purl.org/ontology/bibo/24ab5f5b-17c1-4427-b0eb-a5215493a689"
              },
              {
                "label": "#TCON:CCHTB",
                "@id": "http://purl.org/ontology/bibo/4a05f967-a43d-492c-9c6e-84d3a89fc97d"
              },
              {
                "@id": "http://id.loc.gov/authorities/subjects/sh2008103248",
                "label": "Environmental law Great Britain"
              }
            ],
            "publisher": "Architectural press",
            "place_of_publication": "London",
            "language": {
              "@id": "http://id.loc.gov/vocabulary/iso639-2/eng",
              "label": "eng"
            },
            "@id": "https://open-na.hosted.exlibrisgroup.com/alma/32KUL_LIBIS_NETWORK/bibs/99122040101471",
            "title": "The handbook of environmental powers",
            "@context": "https://open-na.hosted.exlibrisgroup.com/alma/contexts/bib"
          }
        ]
      }
    )

    # Original data (without native context) + top custom context.
    # This is a well-formed JSON-LD.
    hash_jsonld_3 = JSON.parse %(
      {
        "@context": {
          "@vocab": "http://purl.org/ontology/bibo/"
        },
        "@graph": [
          {
            "identifier": [
              {
                "label": "085-139-212-1",
                "@id": "http://purl.org/ontology/bibo/e6f544d5-b88b-4f16-996b-28460cd03a2b"
              },
              {
                "label": "LOC-77364452",
                "@id": "http://purl.org/ontology/bibo/89d3a46b-9117-46e2-a78a-0263242fc3e3"
              },
              {
                "label": "(BeLVLBS)000012204LBS01-Aleph",
                "@id": "http://purl.org/ontology/bibo/d0c3fe26-01e5-49f5-99fb-254763a834aa"
              },
              {
                "label": "26931",
                "@id": "http://purl.org/ontology/bibo/d0bf61ab-de3d-451f-861b-7224a99c11a3"
              }
            ],
            "contributor": [
              {
                "viafLink": "http://viaf.org/viaf/305003200",
                "@id": "http://id.loc.gov/authorities/names/n88622561",
                "label": "Brown, Peter."
              },
              {
                "viafLink": "http://viaf.org/viaf/93286981",
                "@id": "http://id.loc.gov/authorities/names/n77001068",
                "label": "Whittaker, Chris"
              },
              {
                "viafLink": "http://viaf.org/viaf/62792360",
                "@id": "http://id.loc.gov/authorities/names/n77001069",
                "label": "Monahan, Jane"
              }
            ],
            "@type": "Book",
            "subject": [
              {
                "label": "614.7 Pollutie van lucht, water, grond--(openbare gezondheidszorg)",
                "@id": "http://purl.org/ontology/bibo/24ab5f5b-17c1-4427-b0eb-a5215493a689"
              },
              {
                "label": "#TCON:CCHTB",
                "@id": "http://purl.org/ontology/bibo/4a05f967-a43d-492c-9c6e-84d3a89fc97d"
              },
              {
                "@id": "http://id.loc.gov/authorities/subjects/sh2008103248",
                "label": "Environmental law Great Britain"
              }
            ],
            "publisher": "Architectural press",
            "place_of_publication": "London",
            "language": {
              "@id": "http://id.loc.gov/vocabulary/iso639-2/eng",
              "label": "eng"
            },
            "@id": "https://open-na.hosted.exlibrisgroup.com/alma/32KUL_LIBIS_NETWORK/bibs/99122040101471",
            "title": "The handbook of environmental powers"
          }
        ]
      }
    )

    flattened = JSON::LD::API.flatten(hash_jsonld_2, hash_jsonld_2['@context'])
    assert_equal(flattened['@graph'][0]['http://purl.org/dc/elements/1.1/identifier'].nil?, false)

    flattened = JSON::LD::API.flatten(hash_jsonld_3, hash_jsonld_3['@context'])
    assert_equal(flattened['@graph'][0]['identifier'].nil?, false)

  end

  def test_expand_term_from_vocab

    term = 'my_attr'
    context = {
      "@vocab" => "https://example.org/"
    }
    term_expanded = Solis::Utils::JSONLD.expand_term(term, context)
    assert_equal(term_expanded, "https://example.org/my_attr")

  end

  def test_expand_valid_term_from_resolvable_url

    term = 'issn'
    context = "https://open-na.hosted.exlibrisgroup.com/alma/contexts/bib"
    term_expanded = Solis::Utils::JSONLD.expand_term(term, context)
    assert_equal(term_expanded, "http://purl.org/ontology/bibo/issn")

  end

  def test_expand_invalid_term_from_resolvable_url

    term = 'issnnnnnn'
    context = "https://open-na.hosted.exlibrisgroup.com/alma/contexts/bib"
    term_expanded = Solis::Utils::JSONLD.expand_term(term, context)
    assert_equal(term_expanded, nil)

  end

  def test_expand_already_expanded_term_from_vocab

    term = 'https://example.org/my_attr'
    context = {
      "@vocab" => "https://example.org/"
    }
    term_expanded = Solis::Utils::JSONLD.expand_term(term, context)
    assert_equal(term_expanded, "https://example.org/my_attr")

  end

  def test_expand_term_with_empty_context_1

    term = 'https://example.org/my_attr'
    context = {}
    term_expanded = Solis::Utils::JSONLD.expand_term(term, context)
    assert_equal(term_expanded, "https://example.org/my_attr")

  end

  def test_expand_term_with_empty_context_2

    term = 'my_attr'
    context = {}
    term_expanded = Solis::Utils::JSONLD.expand_term(term, context)
    assert_equal(term_expanded, "my_attr")

  end

  def test_is_empty_object_an_embedded_entity
    assert Solis::Utils::JSONLD.is_object_an_embedded_entity({})
  end

  def test_expand_type

    data = JSON.parse %(
      {
        "@id": "http://purl.org/ontology/bibo/collections/f81a158f-3dac-463d-baed-1a09d50db5ae",
        "@type": "Collection",
        "https://libis.be/solis/metadata/db/locks/optimistic/_version": 1,
        "hasPart": {
          "@id": "http://purl.org/ontology/bibo/collections/a13e075a-3b7d-422d-a99c-a4bbf451166c",
          "@type": "Collection",
          "https://libis.be/solis/metadata/db/locks/optimistic/_version": 1,
          "upc": "upc"
        },
        "@context": {
          "@vocab": "http://purl.org/ontology/bibo/"
        }
      }
    )
    Solis::Utils::JSONLD.expand_type!(data, data['@context'])

  end

end
