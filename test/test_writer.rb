require "test_helper"

class TestSolis < Minitest::Test
  def setup
    super
    @shacl = %(
@prefix example: <https://example.com/> .
@prefix xsd:    <http://www.w3.org/2001/XMLSchema#> .
@prefix sh:     <http://www.w3.org/ns/shacl#> .
@prefix rdfs:   <http://www.w3.org/2000/01/rdf-schema#> .

example:CarShape
        a sh:NodeShape;
        sh:description  "Abstract shape that describes a car entity" ;
        sh:targetClass  example:Car;
        sh:name         "Car";
        sh:property     [ sh:path        example:color;
                          rdfs:label     "Kleur"@nl ;
                          rdfs:label     "Color"@en ;
                          sh:name        "color" ;
                          sh:description "Color of the car" ;
                          sh:datatype    xsd:string ;
                          sh:minCount    1 ;
                          sh:maxCount    1 ; ];
        sh:property     [ sh:path        example:brand;
                          sh:name        "brand" ;
                          rdfs:label     "Brand"@en ;
                          rdfs:label     "Marque"@fr ;
                          rdfs:label     "Marke"@de ;
                          rdfs:label     "Merk"@nl ;
                          sh:description "Brand of the car" ;
                          rdfs:comment   "The manufacturer brand"@en ;
                          rdfs:comment   "La marque du fabricant"@fr ;
                          sh:datatype    xsd:string ;
                          sh:minCount    1 ;
                          sh:maxCount    1 ; ];
.
)

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
                                prefix: @solis.prefix,
                                namespace: @solis.namespace,
                                model: @solis.graph)

    shacl.rewind
    assert_match('CarShape', shacl.read)
  end

  def test_write_shacl_file_from_model
    assert_match('CarShape', @solis.writer)
  end

  def test_write_shacl_file_from_model_as_json_ld
    data = JSON.parse(@solis.writer("application/ld+json"))

    descriptions = DataCollector::Core.filter(data, '$..sh:description')
    context = DataCollector::Core.filter(data, '$..@context').first
    assert_includes(descriptions, "Abstract shape that describes a car entity")
    assert_includes(context.keys, "e")

  end

  def test_write_to_mermaid
    expect=%(classDiagram
  class Car {
    color : String [Required]
    brand : String [Required]
  }
  note for Car "Abstract shape that describes a car entity")

    mermaid  = @solis.writer('text/vnd.mermaid')

    assert_equal(expect, mermaid)
  end

  def test_write_to_plantuml
    expect=%(@startuml

skinparam classAttributeIconSize 0
skinparam classFontStyle bold
skinparam classFontName Arial

class Car << (S,#ADD1B2) SHACL >> {
  ' Color of the car
  color : String [Required]
  ' Brand of the car
  brand : String [Required]
}
note bottom of Car
  Abstract shape that describes a car entity
end note


legend right
  Created from SHACL definitions
  [Required] = minCount >= 1
  [Optional] = minCount = 0 or not specified
  [*] = maxCount not specified or > 1
end legend

@enduml)

    plantuml = @solis.writer('text/vnd.plantuml')

    assert_equal(expect, plantuml)
  end

  def test_write_json_schema
    expect=%({
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Generated from SHACL definitions",
  "description": "JSON Schema generated from SHACL shapes",
  "type": "object",
  "definitions": {
    "Car": {
      "type": "object",
      "title": "Car",
      "additionalProperties": false,
      "description": "Abstract shape that describes a car entity",
      "properties": {
        "color": {
          "title": "Kleur",
          "description": "Color of the car",
          "type": "string",
          "default": ""
        },
        "brand": {
          "title": "Brand",
          "description": "The manufacturer brand",
          "type": "string",
          "default": ""
        }
      },
      "required": [
        "color",
        "brand"
      ]
    }
  },
  "properties": {
    "car": {
      "$ref": "#/definitions/Car",
      "title": "Car",
      "description": "Abstract shape that describes a car entity"
    }
  },
  "additionalProperties": false,
  "uiSchema": {
    "$schema": "http://json-schema.org/draft-07/schema#",
    "title": "Generated from SHACL definitions",
    "description": "JSON Schema generated from SHACL shapes",
    "type": "object",
    "definitions": {
      "Car": {
        "type": "object",
        "title": "Car",
        "additionalProperties": false,
        "description": "Abstract shape that describes a car entity",
        "properties": {
          "color": {
            "title": "Kleur",
            "description": "Color of the car",
            "type": "string",
            "default": ""
          },
          "brand": {
            "title": "Brand",
            "description": "The manufacturer brand",
            "type": "string",
            "default": ""
          }
        },
        "required": [
          "color",
          "brand"
        ]
      }
    },
    "properties": {
      "car": {
        "$ref": "#/definitions/Car",
        "title": "Car",
        "description": "Abstract shape that describes a car entity"
      }
    },
    "additionalProperties": false,
    "uiSchema": {
      "car": {
        "ui:order": [
          "color",
          "brand"
        ],
        "color": {
          "ui:widget": "text",
          "ui:help": "Color of the car"
        },
        "brand": {
          "ui:widget": "text",
          "ui:help": "The manufacturer brand"
        }
      },
      "ui:globalOptions": {
        "theme": "default",
        "layout": "vertical"
      }
    }
  }
})
    json_schema = @solis.writer("application/schema+json")

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

    form = @solis.writer('application/form', options)

    puts form
  end
end