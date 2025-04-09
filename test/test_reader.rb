require "test_helper"

class TestSolis < Minitest::Test
  def setup
    super
    @shacl = %(
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
)

    config = {
      store: Solis::Store::Memory.new(),
      model: {
        prefix: 'e',
        namespace: 'https://example.com/',
        uri: StringIO.new(@shacl),
        content_type: 'text/turtle'
      }
    }
    @solis = Solis.new(config)

  end

  def test_read_from_stringio
    assert_includes(@solis.list, 'https://example.com/Car')
  end

  def test_read_from_uri
    config = {
      store: Solis::Store::Memory.new(),
      model: {
        prefix: 'bf',
        namespace: 'http://id.loc.gov/ontologies/bibframe/',
        uri: 'https://id.loc.gov/ontologies/bibframe.rdf',
        content_type: 'application/rdf+xml'}
    }
    solis = Solis.new(config)
    assert_includes(solis.list, 'http://id.loc.gov/ontologies/bibframe/Title')
    #TODO: test more
    # File.open('bibframe.ttl', 'wb') do |f|
    #   f.puts solis.to_shacl
    # end
  end

  def test_load_from_google_sheet
    graph = {
      uri: 'https://127.0.0.1:8890/sparql',
      namespace: 'https://data.odis.be/',
      prefix: 'odis'
    }
    config = {
      store: Solis::Store::Memory.new(),
      model: {
        namespace: 'https://data.odis.be/',
        prefix: 'odis',
        uri: 'google+sheet://18JDgCfr2CLl_jATuvFTcpu-a5T6CWAgJwTwEqtSe8YE',
        config_path: 'test/resources/correct'
      }
    }

    solis = Solis.new(config)

    #models = Solis::Model::Reader.from_uri('google+sheet://18JDgCfr2CLl_jATuvFTcpu-a5T6CWAgJwTwEqtSe8YE')


    # Solis::Model::Writer.to_shacl
    # Solis::Model::Writer.to_rdf
    # Solis::Model::Writer.to_puml
    # Solis::Model::Writer.to_sql
  end
end