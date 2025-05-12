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
              sh:property     [ sh:path        example:driving_license;
                                sh:name        "driving_license" ;
                                sh:description "Driving license of the person" ;
                                sh:nodeKind    sh:IRI ;
                                sh:class       example:DrivingLicense ;
                                sh:minCount    1 ;
                                sh:maxCount    1 ; ];
      .

      example:DrivingLicenseShape
              a sh:NodeShape;
              sh:description  "Abstract shape that describes a driving license" ;
              sh:targetClass  example:DrivingLicense;
              sh:node         example:DrivingLicense;
              sh:name         "DrivingLicense";
              sh:property     [ sh:path        example:address;
                                sh:name        "address" ;
                                sh:description "Address on the license" ;
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
              sh:property     [ sh:path        example:number;
                                sh:name        "number" ;
                                sh:description "Street number of the address" ;
                                sh:datatype    xsd:integer ;
                                sh:minCount    1 ;
                                sh:maxCount    5 ; ];
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

  def test_entity_load

    data = JSON.parse %(
      {
        "@id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota",
        "owners": [
          {
            "@id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
            "name": "jon doe",
            "driving_license": {
              "@id": "https://example.com/f23dd664-adf0-4b86-a309-bd5e9e18ed5a",
              "address": {
                "@id": "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea",
                "street": "fake street",
                "number": [1, 15]
              }
            }
          }
        ]
      }
    )

    repository = RDF::Repository.new
    store = Solis::Store::RDFProxy.new(repository, @name_graph)

    car = Solis::Model::Entity.new(data, @model, 'Car', store)

    car.save

    data = JSON.parse %(
      {
        "@id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9"
      }
    )

    person = Solis::Model::Entity.new(data, @model, 'Person', store)

    person.load(deep=true)
    assert_equal(person.driving_license['address']['street'], 'fake street')

    person.save

    str_ttl_truth = %(
      <https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> "https://example.com/Address" .
      <https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea> <https://example.com/street> "fake street" .
      <https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea> <https://example.com/number> "1"^^<http://www.w3.org/2001/XMLSchema#integer> .
      <https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea> <https://example.com/number> "15"^^<http://www.w3.org/2001/XMLSchema#integer> .
      <https://example.com/f23dd664-adf0-4b86-a309-bd5e9e18ed5a> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> "https://example.com/DrivingLicense" .
      <https://example.com/f23dd664-adf0-4b86-a309-bd5e9e18ed5a> <https://example.com/address> <https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea> .
      <https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> "https://example.com/Person" .
      <https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9> <https://example.com/name> "jon doe" .
      <https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9> <https://example.com/driving_license> <https://example.com/f23dd664-adf0-4b86-a309-bd5e9e18ed5a> .
      <https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> "https://example.com/Car" .
      <https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be> <https://example.com/color> "green" .
      <https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be> <https://example.com/color> "yellow" .
      <https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be> <https://example.com/brand> "toyota" .
      <https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be> <https://example.com/owners> <https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9> .
    )
    graph_truth = RDF::Graph.new
    graph_truth.from_ttl(str_ttl_truth)

    graph_to_check = RDF::Graph.new(data: repository)

    assert_equal(graph_truth == graph_to_check, true)

  end

end