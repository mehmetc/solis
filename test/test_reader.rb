require "test_helper"

class TestReader < Minitest::Test
  def setup
    super
    Solis.config.path = 'test/resources/config'

    @shacl = File.read('test/resources/car/car_shacl.ttl')

    config = {
      cache_dir: '/tmp/cache',
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
    assert_includes(@solis.model.entity.all, 'Car')
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
    assert_includes(solis.model.entity.all, 'Title')
    #TODO: test more
    File.open('./test/resources/bibframe_shapes.ttl', 'wb') do |f|
      f.puts solis.model.writer
    end
  end

  def test_read_from_uri_wine_ontology
    # Used to test:
    # - sh:minCount
    # - sh:maxCount
    config = {
      store: Solis::Store::Memory.new(),
      model: {
        prefix: 'wn',
        namespace: 'http://example.org/',
        uri: 'file://test/resources/wine_ontology.xml',
        content_type: 'application/rdf+xml'}
    }
    solis = Solis.new(config)
    File.open('./test/resources/wine_shapes.ttl', 'wb') do |f|
      f.puts solis.model.writer
    end
  end

  def test_read_from_uri_family_ontology
    # Used to test:
    # - sh:minExclusive
    # - sh:maxInclusive
    # See "Teenager" shape.
    config = {
      store: Solis::Store::Memory.new(),
      model: {
        prefix: 'fm',
        namespace: 'http://example.org/',
        uri: 'https://raw.githubusercontent.com/phillord/owl-api/refs/heads/master/contract/src/test/resources/primer.rdfxml.xml',
        content_type: 'application/rdf+xml'}
    }
    solis = Solis.new(config)
    File.open('./test/resources/family_shapes.ttl', 'wb') do |f|
      f.puts solis.model.writer
    end
  end

  def test_read_from_uri_pizza_ontology
    # No specific test, but to see ir errors are thrown
    config = {
      store: Solis::Store::Memory.new(),
      model: {
        prefix: 'pz',
        namespace: 'http://example.org/',
        uri: 'https://protege.stanford.edu/ontologies/pizza/pizza.owl',
        content_type: 'application/rdf+xml'}
    }
    solis = Solis.new(config)
    File.open('./test/resources/pizza_shapes.ttl', 'wb') do |f|
      f.puts solis.model.writer
    end
  end

  #TODO: make it do something
  def test_load_from_google_sheet
    Solis.config.name = 'google_config.yml'

    config = Solis.config.to_h
    config[:store] = Solis::Store::Memory.new()

    solis = Solis.new(config)
    all_entities = solis.model.entity.all
    assert_includes(all_entities, 'Tenant')

    puts JSON.pretty_generate(all_entities)
    # File.open('./test/resources/solis_shacl2.ttl', 'wb') do |f|
    #   f.puts solis.model.writer
    # end
  end

  def test_load_from_google_sheet_my_library
    Solis.config.name = 'my_library.yml'

    config = Solis.config.to_h
    config[:store] = Solis::Store::Memory.new()

    solis = Solis.new(config)
    all_entities = solis.model.entity.all

    puts JSON.pretty_generate(all_entities)
    File.open('./test/resources/my_library.ttl', 'wb') do |f|
       f.puts solis.model.writer
    end
  end


  def test_convert_bibo_json_entities_to_shacl
    graph = Solis::Model::Reader.from_uri({
                                    uri: 'file://test/resources/bibo_entities.json',
                                    content_type: 'application/json'
                                   })
    File.open('./test/resources/bibo_shapes_from_json.ttl', 'wb') do |f|
      f.puts graph.dump(:ttl, prefixes: graph.extract_prefixes)
    end
  end

  def test_read_from_bibo_json_entities
    config = {
      store: Solis::Store::Memory.new(),
      model: {
        prefix: 'ex',
        namespace: 'http://example.org/',
        uri: 'file://test/resources/bibo_entities.json',
        content_type: 'application/json'}
    }
    solis = Solis.new(config)
    puts solis.model.version
    puts solis.model.version_counter
    puts solis.model.description
  end

end