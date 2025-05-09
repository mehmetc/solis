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

  def test_entity_bulk_ops

    data_1 = JSON.parse %(
      {
        "@id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
        "color": ["green", "yellow"],
        "brand": "toyota"
      }
    )

    data_2 = JSON.parse %(
      {
        "@id": "https://example.com/77f77a12-d05a-4872-b789-e25219302e8a",
        "color": "pink",
        "brand": "subaru"
      }
    )

    repository = RDF::Repository.new
    store = Solis::Store::RDFProxy.new(repository, @name_graph)

    car_1 = Solis::Model::Entity.new(data_1, @model, 'Car', store)
    car_2 = Solis::Model::Entity.new(data_2, @model, 'Car', store)

    car_1.save(delayed=true)
    car_2.save(delayed=true)

    str_ttl_truth = %(
    )
    graph_truth = RDF::Graph.new
    graph_truth.from_ttl(str_ttl_truth)

    graph_to_check = RDF::Graph.new(data: repository)

    assert_equal(graph_truth == graph_to_check, true)

    store.run_operations

    str_ttl_truth = %(
      <https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> "https://example.com/Car" .
      <https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be> <https://example.com/color> "green" .
      <https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be> <https://example.com/color> "yellow" .
      <https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be> <https://example.com/brand> "toyota" .
      <https://example.com/77f77a12-d05a-4872-b789-e25219302e8a> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> "https://example.com/Car" .
      <https://example.com/77f77a12-d05a-4872-b789-e25219302e8a> <https://example.com/color> "pink" .
      <https://example.com/77f77a12-d05a-4872-b789-e25219302e8a> <https://example.com/brand> "subaru" .
    )
    graph_truth = RDF::Graph.new
    graph_truth.from_ttl(str_ttl_truth)

    graph_to_check = RDF::Graph.new(data: repository)

    assert_equal(graph_truth == graph_to_check, true)

    car_1.destroy(delayed=true)
    car_2.destroy(delayed=true)

    str_ttl_truth = %(
      <https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> "https://example.com/Car" .
      <https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be> <https://example.com/color> "green" .
      <https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be> <https://example.com/color> "yellow" .
      <https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be> <https://example.com/brand> "toyota" .
      <https://example.com/77f77a12-d05a-4872-b789-e25219302e8a> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> "https://example.com/Car" .
      <https://example.com/77f77a12-d05a-4872-b789-e25219302e8a> <https://example.com/color> "pink" .
      <https://example.com/77f77a12-d05a-4872-b789-e25219302e8a> <https://example.com/brand> "subaru" .
    )
    graph_truth = RDF::Graph.new
    graph_truth.from_ttl(str_ttl_truth)

    graph_to_check = RDF::Graph.new(data: repository)

    assert_equal(graph_truth == graph_to_check, true)

    store.run_operations
    
    str_ttl_truth = %(
    )
    graph_truth = RDF::Graph.new
    graph_truth.from_ttl(str_ttl_truth)

    graph_to_check = RDF::Graph.new(data: repository)

    assert_equal(graph_truth == graph_to_check, true)

  end

end