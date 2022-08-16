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
    assert_equal(["one", "three", "two"], a)
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

end