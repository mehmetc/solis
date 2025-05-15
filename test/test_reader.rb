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

    expected_mermaid_url = 'https://mermaid.live/view#pako:eNqdVk1z2zgM_SscHndsT5S4jqvZS7rpoZ3ZpNOkl1YdDyzBMluJ1JJUN2qa_16Q-rD8ISW7F0sUngG8BwLkI49VgjzkcQbGXAtINeSRZMyv2Rsw-FZaYSv26L4yJhIWsjurhUzZl4_4Tyk0Jl9rG5SJsGQGWR3YntyPVBbZRum-14i__YG6YlgvhdyiFtawjVY5s1thZuwqy1is8lxJVmhVoLYCDTNbVWYJWyMrMogxqf-KEd8lf48SpG0Tt361kpDjMIMETaxFYQUFa3jc-hVkDSLHfI3a1Nb6k_pXon4B7SafiN_qFKT4CT6M3YJlsUawxIoIfsOY-INM2BZMG65P65OhaA2pkt6foYQ5iGzIvJ-g9xzxO5UJ4133w36oU2sjN5n-Jz1b0IGkEFvxwzl5o1SGII-8lNoR-PTx3ZGl0LgRD8PxrfqOcsRcV-T50rXkI34lmZJWZSqtWg329hyY77VEB7V33yMOzFTGYs5SpD1DJU-YJUvfww0Jagra0q3Ssv3wjNbPafGiWjSUXiDJLs99Ubp0-6T2Z4ihyGUGeoRLVmrIhu2mXHvHK7U5mSohKI0VmIF90yU58O8M1ujC1899kfZl6ObYdU9eyoq2cTPTEiqLFO777KCf3Cyreg3l1_-row5AuXDGd9JiSh19NMLgYcSagAVbFdgqd2Ae0_WoZ2qCfn80YrQs-0pc-WOjkSERG1fS93e3N6d2OE16IryKtyBTHBjR9TBNVuC28TW93gtS9NBZi1pXwzoSxIzrbOIu2ZFNUjMkHfzTaprItQC9k_DPX9Npfx12h-Ep4H07ucZAfp6PQz50_T4azU2vcchNr6PGcC9i122dcdhVc98YwEynijT_I-Id0F9QHKqRr0YEPUSvvY5wzlMjaXssn3LVQPytwAFaiXeIrnj1-eNAO_l2sF1t2oOGgHvcHKoTtDcTTwL7FdoNaULW3I-1OGw3PuE5arpOJHRf9O0acbvFnCZ9SK8056DM_Gn4RFAorbqrZMxDq0uccK3KdMvDDWSGVmVBcwab-2YLKUDy8JE_8HB-Prs4XwTzi-WrV0GwOL-c8IqH03mwnL2eB4vLs-VyebaYn82fJvynUuQhmNHyLLiczxf0uzgPJpxyt0r_3dxv3cOH-OzxdcRUOzJNgigT1H-pUlpy9_ri6TdFUr0q'
    mermaid_url = solis.model.writer('text/vnd.mermaid', link: true)
    assert_equal(expected_mermaid_url, mermaid_url )

    File.open('test/resources/solis_shacl.ttl', 'wb') do |f|
      f.puts solis.model.writer
    end

    assert_equal(File.read('test/resources/solis_shacl.ttl'), solis.model.writer)
  end
end