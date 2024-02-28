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

end