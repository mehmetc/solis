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

  def test_write_shacl_file_to_stringio
    shacl = StringIO.new
    Solis::Model::Writer.to_uri(uri: shacl,
                                content_type: 'text/turtle',
                                prefix: @solis.model.prefix,
                                namespace: @solis.model.namespace,
                                model: @solis.model.graph)

    shacl.rewind
    assert_match('CarShape', shacl.read)
  end

  def test_write_shacl_file_from_model
    assert_match('CarShape', @solis.model.writer)
  end

  def test_write_shacl_file_from_model_as_json_ld
    data = JSON.parse(@solis.model.writer("application/ld+json"))

    descriptions = DataCollector::Core.filter(data, '$..sh:description')
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

    puts form
  end

  def test_write_open_api
    open_api = @solis.model.writer('application/openapi.json')

    puts open_api
  end

  def test_write_shacl_for_sioc
    s = Solis.new({store: Solis::Store::Memory.new(),model: {
      prefix: 'sioc',
      namespace: 'http://rdfs.org/sioc/ns#',
      uri: 'http://rdfs.org/sioc/ns#',
      content_type: 'application/rdf+xml'
    }})

    expected_mermaid='http://mermaid.live/view#pako:eNqVWEtv3DYQ/isLHYsYaK5GLkGCtgGCNqibmwGCK4122UqkQFJ2DNf/vXyIFIciterJ2pmPM8N58YNfm1Z00Nw37UCV+szoRdLxkZ9O7vfpN60nQsiPceCKtGIkvaA9+Zm8J3/wgXH42LZi5vr0ao+8HTn38QL/C/9ZtPNYOvJJjOPMmX4paLimJjjpNUYcBET0p/sT5S9efqWKXIXSuWyi0nrMpGo+q1ays7GbaIxHTZiGkXRUg9HYP17F59FplJFywX+HC9XsCb5wDReQHuNdobiSm/wi5DyGW9gYRlMsSbVAIVg/+iqBdnVPidEvJqRgk57FjC5Ku06CUtARLZBca9pexywtNrFe9KAl4xcv7WAwzqWxQREaqByYKYLRKSY4Uo1n6BT5h4vnAboLpDrTMNs722TEsuaKjql2VrkPq5EwDS+4fLockVWYyhY0NglGpFAJ4Icm55fQA1hesDFJeGJiVqUzUVc4Z4ucZdVdKWtsU8JJ8LyG6kptUc4oAYqdzSBfiu33zc7G0ima6QEKtSfA7QbpkMqEqTfl78COz6TzdIqO9Qy21+pNC/EW+TQj+De0uhjsn8LEtwTbz7y1fgrzrloxQdHAw0RbSIdtViAvUswTCsGiavP6YMY9tUC7kXGm9LZ9TWZrRv5yo7zZat9NNGjdmqH0P7NbIqe57olqKje12uBgpGzYCIjpoPfZsPdiGMSzwgNipjm3GDfXVm7Ln4vF83Zdrws4U/RMmnRyOsJmM2Nhlk5f3HS9ushTI7EHttXCL+CHf+/uDj+X9yfGryCZVtaQfxJvGPAgfDC+jTfORhw+vr6g7vz6M4eFNbvA1q27A/NPF4a4l8dp3VdN+c0/yanSDbdTui+s9IPrtP6zrmYa9sNehg9jjpbVWUjnFJtZWy4Cw3opR3R3J06PzU+PTchXSmRq0OWOgdvUYGkZV85TQ+NLYTZ0xEOkORbsW2PPeFwWsTE2qXDMZUed8JgdVGQ1BcxXk0hJ7RZMCU0B+Kuk09XAchJT9xspTQGSFybWvG4Oc559nKMLdQimPQUcLlbgQnWDKTO6gao7XVA5azqArNtcy7uQqrq1QLH2EIFw3UxZZGEW6Vbdilw2X+Q+cfWtkGX/JQynDop8Z12DOKqwfhDbKYHDXg3sx2HsotmbYkRECidQp3tCFNZkMLSCb7+MKxuqW1mWY06R6gfwrTx9OopeqdXRE45lHQUvzGsfHiocOVkdHl7slKkdjSVhcUePBIZXx6f9gbgffkx3HxJ37Ro+dHVK8pp3zQjS1KFr7l8bfYXR/nekg57Og27e3v4DI8G48A=='
    shacl = s.model.writer
    mermaid  = s.model.writer('text/vnd.mermaid', link: true)
    assert_equal(expected_mermaid, mermaid)

    assert_includes(s.model.entity.list(namespace: true), 'http://rdfs.org/sioc/ns#Post')
    assert_includes(s.model.entity.list, 'http://xmlns.com/foaf/0.1/Agent')
  end

end