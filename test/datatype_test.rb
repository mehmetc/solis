require "test_helper"

class DatatypeTest < Minitest::Test
  def setup
    @solis = Solis::Graph.new(Solis::Shape::Reader::File.read(Solis::ConfigFile[:solis][:shacl]), Solis::ConfigFile[:solis])
  end

  def test_lang_string
    @solis.flush_all('http://solis.template/')
    e = EveryDataType.new({id: '1', lang_string_dt: 'Hello world'})
    e.save

    r = EveryDataTypeResource.all({filter:{id: '1'}})

    a = r.data.first.lang_string_dt

    assert_equal("Hello world", a)

  end

  def test_lang_string_fr
    @solis.flush_all('http://solis.template/')
    context = OpenStruct.new(query_user: 'unknown', language: 'fr')
    Graphiti::with_context(context) do
      e = EveryDataType.new({id: '2', lang_string_dt: 'Bonjour monde'})
      e.save

      r = EveryDataTypeResource.all({filter: {id: '2'}})
      a = r.data.first.lang_string_dt

      assert_equal('Bonjour monde', a)
    end

    r = EveryDataTypeResource.all({filter: {id: '2'}})
    a = r.data.first

    assert_nil(a.lang_string_dt)
  end

  def test_lang_string_with_same_value_in_different_languages
    @solis.flush_all('http://solis.template/')
    context = OpenStruct.new(query_user: 'unknown', language: 'en')
    Graphiti::with_context(context) do
      e = EveryDataType.new({id: '1', lang_string_dt: 'illustrator'})
      e.save

      r = EveryDataTypeResource.all({filter: {id: '1'}})
      a = r.data.first.lang_string_dt
      assert_equal('illustrator', a)
    end

    context = OpenStruct.new(query_user: 'unknown', language: 'nl')
    Graphiti::with_context(context) do
      e = EveryDataType.new({id: '1', lang_string_dt: 'illustrator'})
      e.save

      r = EveryDataTypeResource.all({filter: {id: '1'}})
      a = r.data.first.lang_string_dt
      assert_equal('illustrator', a)
    end
    graph_name = Solis::Options.instance.get.key?(:graphs) ? Solis::Options.instance.get[:graphs].select{|s| s['type'].eql?(:main)}&.first['name'] : ''
    sparql_endpoint = Solis::Options.instance.get[:sparql_endpoint]
    result = Solis::Store::Sparql::Client.new(sparql_endpoint, graph_name: graph_name).query("select ?o WHERE {?s <http://solis.template/lang_string_dt> ?o}")

    data = []
    result.each do |s|
      data << {value: s.o.value, language: s.o.language}
    end
    assert_equal(2, data.size)
    assert_equal(data[0][:value], 'illustrator')
    assert_includes(data.map{|s| s[:language].to_s}, 'en')
    assert_includes(data.map{|s| s[:language].to_s}, 'nl')

  end

  def test_lang_string_array_dt
    @solis.flush_all('http://solis.template/')
    e = EveryDataType.new({id: '1', lang_string_array_dt: ['one', 'two', 'three']})
    e.save

    r = EveryDataTypeResource.all({filter: {id: '1'}})
    a = r.data.first.lang_string_array_dt

    assert_kind_of(Array, a)
    assert_equal(["one", "three", "two"], a.sort)
    pp a
  end

  def test_lang_string_array_dt_fr
    @solis.flush_all('http://solis.template/')
    e = EveryDataType.new({id: '1', lang_string_array_dt: ['one', 'two', 'three'], string_dt: "text"})
    e.save

    context = OpenStruct.new(query_user: 'unknown', language: 'fr')
    Graphiti::with_context(context) do
      e = EveryDataType.new.update({ id:'1', lang_string_array_dt: ['un', 'due', 'trois'] }.with_indifferent_access)
      r = EveryDataTypeResource.all({filter: {id: '1'}})
      a = r.data.first

      assert_equal("fr", a.class.language)
      assert_kind_of(Array, a.lang_string_array_dt)
      assert_equal(["un", "due", "trois"].sort, a.lang_string_array_dt.sort)
      pp a.lang_string_array_dt
    end

    r = EveryDataTypeResource.all({filter: {id: '1'}})
    a = r.data.first.lang_string_array_dt

    pp a

    assert_kind_of(Array, a)
    assert_equal(["one", "three", "two"].sort, a.sort)
    pp a
  end

  def test_datering_systematisch_array
    dt = ["1956-12-31T23:00:00.000Z/1977-12-31T23:00:00.000Z", "1956/1958"]
    @solis.flush_all('http://solis.template/')

    e = EveryDataType.new({id: '1', datetimeinterval_array_dt: dt})
    e.save

    r = EveryDataTypeResource.all({filter: {id: '1'}})
    data = r.data.first

    assert_equal(2, data.datetimeinterval_array_dt.size)
  end

  def test_delete_from_datering_systematisch_array
    dt = ["0999-12-31T23:43:00.000Z/2999-12-31T23:00:00.000Z", "1999-12-31T23:43:00.000Z/2999-12-31T23:00:00.000Z"]
    @solis.flush_all('http://solis.template/')

    # c=Solis::Store::Sparql::Client.new(Solis::ConfigFile[:solis][:sparql_endpoint], Solis::ConfigFile[:solis][:graph_name])
    # c.query()

    e = EveryDataType.new({id: '2', datetimeinterval_array_dt: dt})
    e.save

    r = EveryDataTypeResource.all({filter: {id: '2'}})
    data = r.data.first
    pp data.datetimeinterval_array_dt
    assert_equal(2, data.datetimeinterval_array_dt.size)
    assert_equal(data.datetimeinterval_array_dt, dt)


    data.datetimeinterval_array_dt.delete_at(1)

    e = EveryDataType.new.update({id: data.id, datetimeinterval_array_dt: data.datetimeinterval_array_dt}.with_indifferent_access)
    r = EveryDataTypeResource.all({filter: {id: '2'}})
    data = r.data.first

    puts data.to_ttl
    assert_equal(1, data.datetimeinterval_array_dt.size)
    assert_includes(dt, data.datetimeinterval_array_dt.first)
  end

  def test_anyuri_with_string
    @solis.flush_all('http://solis.template/')
    uri = 'https://example.com/resource/123'

    e = EveryDataType.new({id: '1', uri_dt: uri})
    e.save

    r = EveryDataTypeResource.all({filter: {id: '1'}})
    data = r.data.first

    assert_equal(uri, data.uri_dt)
  end

  def test_anyuri_with_rdf_uri
    @solis.flush_all('http://solis.template/')
    uri_string = 'https://example.com/resource/456'

    e = EveryDataType.new({id: '2', uri_dt: RDF::URI(uri_string)})
    e.save

    r = EveryDataTypeResource.all({filter: {id: '2'}})
    data = r.data.first

    assert_equal(uri_string, data.uri_dt)
  end

  def test_anyuri_with_various_uri_formats
    @solis.flush_all('http://solis.template/')

    test_cases = [
      {id: '3', uri: 'http://www.example.org/test'},
      {id: '4', uri: 'https://example.com/path/to/resource'},
      {id: '5', uri: 'ftp://ftp.example.com/file.txt'},
      {id: '6', uri: 'urn:isbn:0-486-27557-4'}
    ]

    test_cases.each do |test_case|
      e = EveryDataType.new({id: test_case[:id], uri_dt: test_case[:uri]})
      e.save

      r = EveryDataTypeResource.all({filter: {id: test_case[:id]}})
      data = r.data.first

      assert_equal(test_case[:uri], data.uri_dt, "Failed for URI: #{test_case[:uri]}")
    end
  end

  def test_anyuri_update
    @solis.flush_all('http://solis.template/')
    original_uri = 'https://example.com/original'
    updated_uri = 'https://example.com/updated'

    e = EveryDataType.new({id: '7', uri_dt: original_uri})
    e.save

    r = EveryDataTypeResource.all({filter: {id: '7'}})
    data = r.data.first
    assert_equal(original_uri, data.uri_dt)

    e = EveryDataType.new.update({id: '7', uri_dt: updated_uri}.with_indifferent_access)

    r = EveryDataTypeResource.all({filter: {id: '7'}})
    data = r.data.first
    assert_equal(updated_uri, data.uri_dt)
  end

  def test_anyuri_stored_as_rdf_uri
    @solis.flush_all('http://solis.template/')
    uri = 'https://example.com/resource/789'

    e = EveryDataType.new({id: '8', uri_dt: uri})
    e.save

    # Query the triple store directly to verify it's stored as RDF::URI
    graph_name = Solis::Options.instance.get.key?(:graphs) ? Solis::Options.instance.get[:graphs].select{|s| s['type'].eql?(:main)}&.first['name'] : ''
    sparql_endpoint = Solis::Options.instance.get[:sparql_endpoint]
    result = Solis::Store::Sparql::Client.new(sparql_endpoint, graph_name: graph_name).query("select ?o WHERE {?s <http://solis.template/uri_dt> ?o}")

    assert_equal(1, result.count)
    result.each do |s|
      assert_kind_of(RDF::URI, s.o)
      assert_equal(uri, s.o.to_s)
    end
  end

end