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

  def test_read_from_uri_more_complex_ontology
    config = {
      store: Solis::Store::Memory.new(),
      model: {
        prefix: 'wn',
        namespace: 'http://example.org/',
        uri: 'file://test/resources/wine_ontology.xml',
        content_type: 'application/rdf+xml'}
    }
    solis = Solis.new(config)
    File.open('wine_shapes.ttl', 'wb') do |f|
      f.puts solis.model.writer
    end
  end

  #TODO: make it do something
  def test_load_from_google_sheet
    config = {
      store: Solis::Store::Memory.new(),
      model: {
        namespace: 'https://solis.libis.be/',
        prefix: 'solis',
        uri: 'google+sheet://11APPpKYfNfUdAN5_hj_x-B_Ck2zdZlnZZcgSyUvR8As',
        config_path: 'test/resources/correct',
        config_name: 'test_config.yml'
      }
    }

    solis = Solis.new(config)
    all_entities = solis.model.entity.list
    assert_includes(all_entities, 'Tenant')

    assert_equal(File.read('test/resources/solis_shacl.ttl'), solis.model.writer)
  end
end