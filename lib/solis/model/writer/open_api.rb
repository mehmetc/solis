require 'json'
require 'rdf'
require 'rdf/turtle'

class OpenApiWriter < Solis::Model::Writer::Generic
  def self.write(repository, options = {})
    shapes = options[:shapes]
    # Initialize OpenAPI structure
    openapi = {
      "openapi" => "3.0.0",
      "info" => {
        "title" => options[:title].value,
        "version" => options[:version].value,
        "description" => options[:description].value
      },
      "paths" => {},
      "components" => {
        "schemas" => {}
      }
    }

     entities = Solis::Utils::Namespace.extract_entities_for_namespace(repository, options[:namespace])
     entities.each do |entity|
       shape_uri = Solis::Utils::Namespace.target_class_for_entity_name(repository, options[:namespace], entity)
       schema_name = entity
       properties = extract_properties(repository, shape_uri)
       schema = convert_shape_to_schema(properties)
       entity_plural = shapes[schema_name][:plural] || schema_name.pluralize
       openapi["components"]["schemas"][schema_name] = schema

       # Create a basic path for this resource
       path = "/#{entity_plural.underscore}"
       openapi["paths"][path] = generate_basic_path_operations(schema_name)
     end

    openapi.to_json
  end

  private

  def self.extract_shapes(repository)
    shapes = {}

    # Find all NodeShapes
    shape_subjects = repository.query([nil, RDF.type, RDF::Vocab::SHACL.NodeShape]).map(&:subject)

    shape_subjects.each do |shape_uri|
      shapes[shape_uri.to_s] = extract_properties(repository, shape_uri)
    end

    shapes
  end

  def self.extract_properties(repository, shape_uri)
    properties = {}

    # Find all property constraints for this shape
    property_paths = repository.query([shape_uri, RDF::Vocab::SHACL.property, nil]).map(&:object)

    property_paths.each do |prop_path|
      # Get the property path
      path = repository.query([prop_path, RDF::Vocab::SHACL.path, nil]).first&.object

      next unless path

      property_name = extract_name_from_uri(path.to_s)
      properties[property_name] = {
        "datatype" => extract_datatype(repository, prop_path),
        "required" => is_required(repository, prop_path),
        "min_count" => extract_min_count(repository, prop_path),
        "max_count" => extract_max_count(repository, prop_path),
        "pattern" => extract_pattern(repository, prop_path),
        "min_length" => extract_min_length(repository, prop_path),
        "max_length" => extract_max_length(repository, prop_path)
      }
    end

    properties
  end

  def self.extract_datatype(repository, prop_path)
    datatype = repository.query([prop_path, RDF::Vocab::SHACL.datatype, nil]).first&.object
    datatype ? datatype.to_s : nil
  end

  def self.is_required(repository, prop_path)
    min_count = extract_min_count(repository, prop_path)
    min_count && min_count > 0
  end

  def self.extract_min_count(repository, prop_path)
    min_count = repository.query([prop_path, RDF::Vocab::SHACL.minCount, nil]).first&.object
    min_count ? min_count.to_i : nil
  end

  def self.extract_max_count(repository, prop_path)
    max_count = repository.query([prop_path, RDF::Vocab::SHACL.maxCount, nil]).first&.object
    max_count ? max_count.to_i : nil
  end

  def self.extract_pattern(repository, prop_path)
    pattern = repository.query([prop_path, RDF::Vocab::SHACL.pattern, nil]).first&.object
    pattern ? pattern.to_s : nil
  end

  def self.extract_min_length(repository, prop_path)
    min_length = repository.query([prop_path, RDF::Vocab::SHACL.minLength, nil]).first&.object
    min_length ? min_length.to_i : nil
  end

  def self.extract_max_length(repository, prop_path)
    max_length = repository.query([prop_path, RDF::Vocab::SHACL.maxLength, nil]).first&.object
    max_length ? max_length.to_i : nil
  end

  def self.extract_name_from_uri(uri)
    # Extract the last part of the URI after # or /
    uri.match(/[#\/]([^#\/]+)$/)[1]
  end

  def self.convert_shape_to_schema(properties)
    schema = {
      "type" => "object",
      "properties" => {},
      "required" => []
    }

    properties.each do |prop_name, constraints|
      schema["properties"][prop_name] = property_to_openapi(constraints)

      if constraints["required"]
        schema["required"] << prop_name
      end
    end

    # Remove required array if empty
    if schema["required"].empty?
      schema.delete("required")
    end

    schema
  end

  def self.property_to_openapi(constraints)
    openapi_property = {}

    # Map SHACL datatype to OpenAPI type and format
    if constraints["datatype"]
      type_format = shacl_datatype_to_openapi(constraints["datatype"])
      openapi_property["type"] = type_format["type"]

      if type_format["format"]
        openapi_property["format"] = type_format["format"]
      end
    else
      # Default to string if no datatype specified
      openapi_property["type"] = "string"
    end

    # Add other constraints
    if constraints["pattern"]
      openapi_property["pattern"] = constraints["pattern"]
    end

    if constraints["min_length"]
      openapi_property["minLength"] = constraints["min_length"]
    end

    if constraints["max_length"]
      openapi_property["maxLength"] = constraints["max_length"]
    end

    openapi_property
  end

  def self.shacl_datatype_to_openapi(datatype)
    # Mapping from SHACL datatypes to OpenAPI types and formats
    case datatype
    when "http://www.w3.org/2001/XMLSchema#string"
      { "type" => "string" }
    when "http://www.w3.org/2001/XMLSchema#integer"
      { "type" => "integer" }
    when "http://www.w3.org/2001/XMLSchema#decimal"
      { "type" => "number" }
    when "http://www.w3.org/2001/XMLSchema#boolean"
      { "type" => "boolean" }
    when "http://www.w3.org/2001/XMLSchema#date"
      { "type" => "string", "format" => "date" }
    when "http://www.w3.org/2001/XMLSchema#dateTime"
      { "type" => "string", "format" => "date-time" }
    when "http://www.w3.org/2001/XMLSchema#time"
      { "type" => "string", "format" => "time" }
    when "http://www.w3.org/2001/XMLSchema#email"
      { "type" => "string", "format" => "email" }
    when "http://www.w3.org/2001/XMLSchema#uri"
      { "type" => "string", "format" => "uri" }
    else
      # Default to string for unknown datatypes
      { "type" => "string" }
    end
  end

  def self.generate_basic_path_operations(schema_name)
    {
      "get" => {
        "summary" => "List all #{schema_name}s",
        "responses" => {
          "200" => {
            "description" => "A list of #{schema_name}s",
            "content" => {
              "application/json" => {
                "schema" => {
                  "type" => "array",
                  "items" => {
                    "$ref" => "#/components/schemas/#{schema_name}"
                  }
                }
              }
            }
          }
        }
      },
      "post" => {
        "summary" => "Create a new #{schema_name}",
        "requestBody" => {
          "required" => true,
          "content" => {
            "application/json" => {
              "schema" => {
                "$ref" => "#/components/schemas/#{schema_name}"
              }
            }
          }
        },
        "responses" => {
          "201" => {
            "description" => "#{schema_name} created successfully",
            "content" => {
              "application/json" => {
                "schema" => {
                  "$ref" => "#/components/schemas/#{schema_name}"
                }
              }
            }
          }
        }
      }
    }
  end
end