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

    assert_equal(["@language", "@value"], a.keys.sort)

    e = EveryDataType.new({id: '2', lang_string_array_dt: ['Hello world', 'Bonjour monde']})
    e.save

    r = EveryDataTypeResource.all({filter: {id: '2'}})

    a = r.data.first.lang_string_array_dt

    assert_equal(["@language", "@value"], a.keys.sort)
    assert_kind_of(Array, a["@value"])

    puts r.to_jsonapi
  end

end