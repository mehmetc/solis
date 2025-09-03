require "test_helper"

class TestWriter < Minitest::Test
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

  def test_write_shacl_file_to_stringio
    shacl = StringIO.new
    Solis::Model::Writer.to_uri(uri: shacl,
                                content_type: 'text/turtle',
                                prefix: @solis.model.prefix,
                                namespace: @solis.model.namespace,
                                graph: @solis.model.graph)

    shacl.rewind
    assert_match('CarShape', shacl.read)
  end

  def test_write_shacl_file_from_model
    assert_match('CarShape', @solis.model.writer)
  end

  def test_write_shacl_file_from_model_as_json_ld
    data = JSON.parse(@solis.model.writer("application/ld+json"))

    descriptions = DataCollector::Core.filter(data, '$..shacl:description')
    context = DataCollector::Core.filter(data, '$..@context').first
    assert_includes(descriptions, "Abstract shape that describes a car entity")
    assert_includes(context.keys, "e")

  end

  def test_write_to_mermaid
    expect = File.read('test/resources/car/car.mermaid')

    mermaid  = @solis.model.writer('text/vnd.mermaid')

    assert_equal(expect, mermaid)
  end


  def test_write_to_mermaid_link
    mermaid  = @solis.model.writer('text/vnd.mermaid', link: true)

    puts mermaid
  end

  def test_write_to_plantuml
    expect=File.read('test/resources/car/car.puml')
    plantuml = @solis.model.writer('text/vnd.plantuml')

    assert_equal(expect, plantuml)
  end

  def test_write_json_schema
    expect=File.read('test/resources/car/car_schema.json')
    json_schema = @solis.model.writer("application/schema+json")

    assert_equal(expect, json_schema)
  end

  def test_write_form
    expect=File.read('test/resources/car/car.html')
    options = {
      theme: 'bootstrap',
      layout: 'horizontal',
      field_options: {
        # Custom options for specific fields
        'color': {
          'ui:widget': 'color',
          'ui:placeholder': 'Choose a color'
        }
      },
      global_options: {
        'ui:readonly': false,
        'ui:disabled': false
      }
    }

    form = @solis.model.writer('application/form', options)

    assert_equal(expect, form)
  end

  def test_write_open_api
    expect=File.read('test/resources/car/car_openapi.json')
    open_api = @solis.model.writer('application/openapi.json')
    assert_equal(expect, open_api)
  end

  def test_write_shacl_for_sioc
    s = Solis.new({store: Solis::Store::Memory.new(),model: {
      prefix: 'sioc',
      namespace: 'http://rdfs.org/sioc/ns#',
      uri: 'http://rdfs.org/sioc/ns#',
      content_type: 'application/rdf+xml'
    }})

    shacl = s.model.writer
    mermaid  = s.model.writer('text/vnd.mermaid', link: true)
    #expected_mermaid='https://mermaid.live/view#pako:eNqNWNtu4zYQ_RWDj4UTxA5kp0JfFrtosUAvi6Z9KQwYtETLbCVSIKlk3TT_3iElSiRFav1kaeZoZjg3HvgNFbwkKEdFjaX8RHElcHNgq5V5X_3GasrIh6LgHVOrN614n7QfKhKRfuJF18QUH3nTdIyqa0TDFAZHoteA2AqO_LzKV5hde_kFy-OFSxXKWiy0x0Aqu5MsBD2BXUcDHtWRKtIcS6wIaPRPr2JdYzQSpIyzX0mFFX0hn5kiFRE9pnflxeWc5EcuusaeQsfQQHoFVtwLQftRF0FwmfbkGP0MIVmb-MQ776C4LAWRkpRHxT25Uri4NEFadGJ70bMSlFW9tCQ1OBdgA3togkVNoQigk5QzT9WcSCmP_zD-WpOyIq4O2mJ-Zp2MsayhoqSy6GToQ2sEaeurXz4Vj0groLIRjU4CiKRXAvJVHU9X2wO-PGKjFeSF8k7Gvhl1ke90kYOsmiMFjQ0lbDkLaygvWBfl5CVA0hMMZRVtvy96NoZOUVTVJFL7I2F65ktPBWGqWflLosenVWE6eUnPlMyPdYYWYoXnE0bwb1KoaLC_c4hvCPbcsUL7icy7LHhLogaeW1wQd9g6SUQleNd6IWhUal6fYdxdC7hsKKNSzdsXMpsy8ocZ5dlW-xOi8VYnDGX_GpzScxrqXrDCYlarGY40mNYzwRE6aBMM-5nXNX-V_oDANIcWx801l-vyh2L-Ol_X0wIOFGcqIJ0MN2S2mX1hkM6-uO56NZG7RsYemFfLv81--O_uLhDlK8ouRFAlNby_3gysf_TV4z1nEOObD5ruPIOaXkOYXYwDbNqTC7D-svEh5q4wWvOUUn7pL1FXacbRKM2Tr-xHzWj7x7SaKrIc9jAuPiZSG3d-fPDUCiPQjn3c790dXx3Qdwdks-ISjBR0OInlHCmYW6yJi6TQ_qF8lnKLh5F-aHDfAEvGxyEeyz9LhWEUC2qHXyygRrYRwfwMiRRYbyeXaESAPwncXgAWkou035FqRCBhYcaap835XGQZZ67xNMSnIxGcXyzLUdIGXcbyDVTa6YAK2cwNyLTNqbwD2Ulbs9RnCWGJ0DdTNrIjjTQLbUIO-23kJOOCmyDDlnOYRxo08pBp2flR2fXjsZAY2G5Py0oMRi-apSn2CELkC6_Te6Ji16Q1NIHtXTZxkTR2WIEhQUl_4Mfek5db0ROxufULw3FuBQ-8Zxlu6zgyojTc3r4uT7o1FodD3fqJ5VdpvNsFHvPyr8zF68IcO4W3vetSLLRGDRFQhxLlyBCzA1IX0pADyuGxJGfc1eqADuwdoLhT_PnKCpQr0ZE1AiPVBeVnXEt461q9i4Y_ISykxQzlb-gryrPs_unpYbd92m--zzb7x222RleU77P77SZ7fNpm--0ue9xl72v0L-dg4OF-v9mA6CF73O8esu3Tbo1ISaFUvwx_eugf4-Iv80HvsRL6MEOAhEF1P-oUQQDv_wOqiKYt'
    #assert_equal(expected_mermaid, mermaid)

    assert_includes(s.model.entity.all, 'Post')
    assert_includes(s.model.entity.all, 'Item')
  end

  def test_write_shacl_for_bibo
    s = Solis.new({store: Solis::Store::Memory.new(),model: {
      prefix: 'bibo',
      namespace: 'http://purl.org/ontology/bibo/',
      uri: 'file://test/resources/bibo_owl.xml',
      content_type: 'application/rdf+xml'
    }})
    puts JSON.pretty_generate(s.model.dependencies)
    puts JSON.pretty_generate(s.model.context)
    File.open('./test/resources/bibo_shapes.ttl', 'wb') do |f|
      f.puts s.model.writer
    end
    File.open('./test/resources/bibo.puml', 'wb') do |f|
      f.puts s.model.writer('text/vnd.plantuml')
    end
    File.open('./test/resources/bibo_entities.json', 'wb') do |f|
      f.puts JSON.pretty_generate JSON.parse(s.model.writer('application/entities+json'))
    end
  end

end