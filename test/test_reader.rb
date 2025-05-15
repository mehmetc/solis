require "test_helper"

class TestSolis < Minitest::Test
  def setup
    super
    @shacl = File.read('test/resources/car/car_shacl.ttl')

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
    assert_includes(@solis.model.entity.list(namespace: true), 'https://example.com/Car')
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
    assert_includes(solis.model.entity.list, 'Title')
    #TODO: test more
    File.open('bibframe.ttl', 'wb') do |f|
      f.puts solis.model.writer
    end
  end

  #TODO: make it do something
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
        config_path: 'test/resources/correct',
        config_name: 'test_config.yml'
      }
    }

    solis = Solis.new(config)

    pp solis.model.entity.list

    #models = Solis::Model::Reader.from_uri('google+sheet://18JDgCfr2CLl_jATuvFTcpu-a5T6CWAgJwTwEqtSe8YE')


    # Solis::Model::Writer.to_shacl
    # Solis::Model::Writer.to_rdf
    # Solis::Model::Writer.to_puml
    # Solis::Model::Writer.to_sql
  end
end