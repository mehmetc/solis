require 'test_helper'

Solis::SHACLValidator = Solis::SHACLValidatorV2
class TestShacl < Minitest::Test
  def setup
    super
    config = {
      store: Solis::Store::Memory.new(),
      model: {
        prefix: 'lbs',
        namespace: 'https://lib.is/test/',
        uri: "file://test/resources/multiple_inheritance_shacl.ttl",
        content_type: 'text/turtle'
      }
    }
    @solis = Solis.new(config)

    @opts = {
      path_dir: File.join(__dir__, './data')
    }
  end

  def test_is_shacl_loaded
    assert_kind_of(RDF::Repository, @solis.model.graph)
    assert_equal('lbs', @solis.model.prefix)
    assert_equal('https://lib.is/test/', @solis.model.namespace)
  end

  def test_validate_shacl
    shacl_shacl = Solis::Model::Reader.from_uri(uri: 'file://test/resources/shacl-shacl.ttl', content_type: 'text/turtle')
    validator = Solis::SHACLValidatorV2.new(shacl_shacl.dump(:ttl), :ttl, @opts)
    conform, messages = validator.execute(RDF::Graph.new.from_ttl(@solis.model.writer), :graph)
    pp conform
    pp messages
    assert_equal(true, conform)
    assert_equal(0, messages.size)
  end

  def test_validate_shacl_with_data_graph
    # foaf = Solis::Model::Reader.from_uri(uri: 'file://test/resources/foaf.rdf', content_type: 'application/rdf+xml')
    #
    # File.open('test/resources/foaf.ttl', 'w') do |f|
    #   f.puts foaf.dump(:ttl)
    # end

    mis = Solis::Model::Reader.from_uri(uri: 'file://test/resources/multiple_inheritance_shacl.ttl', content_type: 'text/turtle')
    person = RDF::Graph.new.from_ttl(File.read('test/resources/person_with_multiple_inheritance.ttl'))

    validator1 = Solis::SHACLValidatorV1.new(mis.dump(:ttl), :ttl)
    validator2 = Solis::SHACLValidatorV2.new(mis.dump(:ttl), :ttl, @opts)
    conform, messages = validator1.execute(JSON.parse(person.dump(:jsonld)), :jsonld)

    pp conform
    pp messages
    conform, messages = validator2.execute(JSON.parse(person.dump(:jsonld)), :jsonld)

    pp conform
    pp messages

  end
end
