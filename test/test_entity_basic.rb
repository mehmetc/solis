require "test_helper"

class TestEntity < Minitest::Test

  def setup
    super

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
                                sh:minCount    0 ;
                                sh:maxCount    1 ; ];
              sh:property     [ sh:path        example:owners;
                                sh:name        "owners" ;
                                sh:description "Owners of the car" ;
                                sh:nodeKind    sh:IRI ;
                                sh:class       example:Person ;
                                sh:minCount    0 ; ];
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
                                sh:minCount    0 ;
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

    @name_graph = 'https://example.com/'

    dir_tmp = File.join(__dir__, './data')

    @model = Solis::ModelMock.new({
                                   graph: graph_shacl,
                                   prefix: 'ex',
                                   namespace: @name_graph,
                                   tmp_dir: dir_tmp
                                 })

  end

  def test_entity_creation

    data = JSON.parse %(
      {
        "@id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota",
        "owners": [
          {
            "@id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
            "name": "jon doe",
            "address": {
              "@id": "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea",
              "street": "fake street"
            }
          }
        ]
      }
    )

    car = Solis::Model::Entity.new(data, @model, 'Car', nil)

    assert_equal(car['@id'], "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be")
    assert_equal(car.owners[0]['address']['@id'], "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea")

  end

  def test_entity_creation_without_ids

    data = JSON.parse %(
      {
        "color": ["green", "yellow"],
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

    car = Solis::Model::Entity.new(data, @model, 'Car', nil)

    assert_equal(car['@id'].nil?, false)
    assert_equal(car.owners[0]['@id'].nil?, false)
    assert_equal(car.owners[0]['address']['@id'].nil?, false)

  end

  def test_entity_data_replacement

    data = JSON.parse %(
      {
        "@id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota",
        "owners": [
          {
            "@id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
            "name": "jon doe",
            "address": {
              "@id": "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea",
              "street": "fake street"
            }
          }
        ]
      }
    )

    car = Solis::Model::Entity.new(data, @model, 'Car', nil)

    data_2 = JSON.parse %(
      {
        "@id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": "black",
        "brand": "toyota",
        "owners": [
          {
            "@id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
            "name": "jon doe",
            "address": {
              "@id": "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea",
              "street": "other fake street"
            }
          }
        ]
      }
    )

    car.replace(data_2)

    assert_equal(car.color, 'black')
    assert_equal(car.owners[0]['address']['street'], 'other fake street')

  end

  def test_entity_patch

    data = JSON.parse %(
      {
        "@id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota",
        "owners": [
          {
            "@id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
            "name": "jon doe",
            "address": {
              "@id": "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea",
              "street": "fake street"
            }
          }
        ]
      }
    )

    car = Solis::Model::Entity.new(data, @model, 'Car', nil)

    obj_patch = JSON.parse %(
      {
        "color": "black",
        "brand": "nissan",
        "owners": [
          {
            "@id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
            "name": "john smith"
          }
        ]
      }
    )

    car.patch(obj_patch)

    assert_equal(car.color, 'black')
    assert_equal(car.owners[0]['name'], 'john smith')

  end

  def test_entity_patch_add_missing_refs

    data = JSON.parse %(
      {
        "@id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota",
        "owners": [
          {
            "@id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
            "name": "jon doe",
            "address": {
              "@id": "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea",
              "street": "fake street"
            }
          }
        ]
      }
    )

    car = Solis::Model::Entity.new(data, @model, 'Car', nil)

    obj_patch = JSON.parse %(
      {
        "color": "black",
        "brand": "nissan",
        "owners": [
          {
            "@id": "https://example.com/12345-non-existing",
            "name": "john smith"
          }
        ]
      }
    )

    assert_raises(Solis::Model::Entity::MissingRefError) do
      car.patch(obj_patch)
    end

    assert_equal((car.color-["green", "yellow"]).size, 0)

    car.patch(obj_patch, opts={
      add_missing_refs: true
    })

    assert_equal(car.color, 'black')
    assert_equal(car.owners[1]['name'], 'john smith')

  end

  def test_entity_patch_append_attributes

    data = JSON.parse %(
      {
        "@id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota",
        "owners": [
          {
            "@id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
            "name": "jon doe",
            "address": {
              "@id": "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea",
              "street": "fake street"
            }
          }
        ]
      }
    )

    car = Solis::Model::Entity.new(data, @model, 'Car', nil)

    obj_patch = JSON.parse %(
      {
        "color": "black"
      }
    )

    car.patch(obj_patch, opts={
      append_attributes: true
    })

    assert_equal((car.color-["green", "yellow", "black"]).size, 0)

  end

  def test_entity_patch_depth0_1

    data = JSON.parse %(
      {
        "@id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota",
        "owners": [
          {
            "@id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
            "name": "jon doe",
            "address": {
              "@id": "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea",
              "street": "fake street"
            }
          }
        ]
      }
    )

    car = Solis::Model::Entity.new(data, @model, 'Car', nil)

    obj_patch = JSON.parse %(
      {
        "color": "black",
        "brand": "@unset",
        "owners": [
          {
            "@id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
            "name": "john smith"
          }
        ]
      }
    )

    car.patch(obj_patch)

    assert_equal(car.brand, "@unset")

  end

  def test_entity_patch_depth0_2

    data = JSON.parse %(
      {
        "@id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota",
        "owners": [
          {
            "@id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
            "name": "jon doe",
            "address": {
              "@id": "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea",
              "street": "fake street"
            }
          }
        ]
      }
    )

    car = Solis::Model::Entity.new(data, @model, 'Car', nil)

    obj_patch = JSON.parse %(
      {
        "color": "black",
        "brand": "@unset",
        "owners": "@unset"
      }
    )

    car.patch(obj_patch)

    assert_equal(car.owners, "@unset")

  end

  def test_entity_patch_depth1

    data = JSON.parse %(
      {
        "@id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota",
        "owners": [
          {
            "@id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
            "name": "jon doe",
            "address": {
              "@id": "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea",
              "street": "fake street"
            }
          }
        ]
      }
    )

    car = Solis::Model::Entity.new(data, @model, 'Car', nil)

    obj_patch = JSON.parse %(
      {
        "color": "black",
        "brand": "@unset",
        "owners": [
          {
            "@id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
            "name": "john smith",
            "address": "@unset"
          }
        ]
      }
    )

    car.patch(obj_patch)

    assert_equal(car.owners[0]["address"], "@unset")

  end

end