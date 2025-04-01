# frozen_string_literal: true

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
  def test_does_it_have_a_version
    refute_nil ::Solis::VERSION
  end

  def test_mandatory_parameters
    assert_raises Solis::Error::MissingParameter do
      solis = Solis.new(not_mandatory: '1234')
    end
    # missing Google key
    assert_raises Solis::Error::MissingParameter do
      solis = Solis.new(uri: 'google+sheet://18JDgCfr2CLl_jATuvFTcpu-a5T6CWAgJwTwEqtSe8YE', config_path: 'test/resources/incorrect')
    end
  end

  def test_setup_logger
    #define logers
    s = StringIO.new
    logger = Solis.logger([STDOUT, s])
    assert_kind_of(Logger, logger)

    logger.info('test')

    s.rewind
    data = s.read.split(']').last
    assert_equal("  INFO -- : test\n", data)
  end


  def test_setup_load_schema_from_stringio
    assert_includes(@solis.list, 'https://example.com/Car')
  end

  def test_setup_load_schema_from_uri
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

    File.open('bibframe.ttl', 'wb') do |f|
      f.puts solis.to_shacl
    end
  end

  def test_write_shacl_file_to_stringio
    shacl = StringIO.new
    Solis::Model::Writer.to_uri(uri: shacl,
                                content_type: 'text/turtle',
                                prefix: @solis.prefix,
                                namespace: @solis.namespace,
                                model: @solis.graph)

    shacl.rewind
    assert_match('CarShape', shacl.read)
  end

  def test_write_shacl_file_from_model
    assert_match('CarShape', @solis.to_shacl)
  end

  def test_load_from_file
    graph = {
      uri: 'https://127.0.0.1:8890/sparql',
      namespace: 'https://data.odis.be/',
      prefix: 'odis'
    }
    config = {
      store: Solis::Store::Triple.new(graph),
      model: {
        namespace: 'https://data.odis.be/',
        prefix: 'odis',
        uri: 'google+sheet://18JDgCfr2CLl_jATuvFTcpu-a5T6CWAgJwTwEqtSe8YE'
      }
    }

    Solis.new(config)

    models = Solis::Model::Reader.from_uri('google+sheet://18JDgCfr2CLl_jATuvFTcpu-a5T6CWAgJwTwEqtSe8YE')


    Solis::Model::Writer.to_shacl
    Solis::Model::Writer.to_rdf
    Solis::Model::Writer.to_puml
    Solis::Model::Writer.to_sql
  end

end
