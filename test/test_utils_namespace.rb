require 'test_helper'

class TestUtilsNamespace < Minitest::Test
  def setup
    super
    Solis.config.path = 'test/resources/config'
    Solis.config.name = 'bibo_config.yml'

    @solis = Solis.new({
                         store: Solis::Store::RDFProxy.new(Solis.config[:sparql], Solis.config[:model][:namespace]),
                         model: Solis.config[:model]
                       })
    @graph = @solis.model.graph
    @namespace = @solis.model.namespace
    @prefix = @solis.model.prefix
    File.open('./test/resources/bibo_shapes.ttl', 'wb') do |f|
      f.puts @solis.model.writer
    end
  end

  def test_extract_unique_namespaces
    unique_namespaces = Solis::Utils::Namespace.extract_unique_namespaces(@graph)

    refute unique_namespaces.empty?
    assert_includes unique_namespaces, "http://purl.org/ontology/bibo/"
  end

  def test_extract_unique_namespaces_with_metadata
    unique_namespaces = Solis::Utils::Namespace.extract_unique_namespaces_with_metadata(@graph, @namespace)
    primary_namespace = unique_namespaces.select { |namespace| namespace[:is_primary] }.first

    assert_equal primary_namespace[:namespace], @namespace
    pp primary_namespace
  end

  def test_extract_shape_defining_namespaces
    namespaces = Solis::Utils::Namespace.extract_shape_defining_namespaces(@graph)

    assert_includes namespaces, "http://purl.org/ontology/bibo/"
  end

  def test_detect_primary_namespace
    primary = Solis::Utils::Namespace.detect_primary_namespace(@graph)

    assert_equal primary, @namespace

    primary_prefix = Solis::Utils::PrefixResolver.resolve_prefix(primary)
    assert_equal primary_prefix, @prefix
  end


  def test_extract_entities_for_namespace
    entities = Solis::Utils::Namespace.extract_entities_for_namespace(@graph, @namespace)

    assert_includes entities, "Article"
    assert_includes entities, "Book"
    refute_includes entities, "Agent"
  end
end