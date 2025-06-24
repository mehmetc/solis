require 'json'
require 'rdf'
require 'rdf/turtle'

class OpenApiWriter < Solis::Model::Writer::Generic
  def self.write(repository, options = {})
    return "No repository provided" if repository.nil?
    return "options[:shapes] missing" unless options.key?(:shapes)

    shapes = adapt_parse_shapes_to_extract_shapes_format(options[:shapes])

    if shapes.empty?
      return "No SHACL shapes found in repository"
    end

    # Initialize OpenAPI structure
    openapi = {
      "openapi" => "3.0.0",
      "info" => {
        "title" => options[:title] || '',
        "version" => options[:version] || '',
        "description" => options[:description] || ''
      },
      "paths" => {},
      "components" => {
        "schemas" => {}
      }
    }

    # If we're using the new format, process shapes directly
    if options[:shapes]
      shapes.each do |shape_uri, shape_data|
        schema_name = shape_data[:name] || extract_name_from_uri(shape_uri)
        schema = convert_shape_to_openapi_schema(shape_data, shapes)

        # Get plural form for entity
        entity_plural = options[:shapes][shape_uri][:plural] || schema_name.pluralize
        openapi["components"]["schemas"][schema_name] = schema

        # Create a basic path for this resource
        entity_plural_path = entity_plural.underscore
        collection_path = "/#{entity_plural_path}"
        individual_path = "/#{entity_plural_path}/{id}"

        openapi["paths"][collection_path] = generate_collection_operations(schema_name)
        openapi["paths"][individual_path] = generate_individual_operations(schema_name)
      end
    else
      # Fallback to old namespace-based approach
      entities = Solis::Utils::Namespace.extract_entities_for_namespace(repository, options[:namespace])
      entities.each do |entity|
        shape_uri = Solis::Utils::Namespace.target_class_for_entity_name(repository, options[:namespace], entity)
        schema_name = entity
        properties = extract_properties(repository, shape_uri)
        schema = convert_shape_to_schema(properties)
        entity_plural = shapes[shape_uri.value][:plural] || schema_name.pluralize
        openapi["components"]["schemas"][schema_name] = schema

        # Create a basic path for this resource
        path = "/#{entity_plural.underscore}"
        openapi["paths"][path] = generate_basic_path_operations(schema_name)
      end
    end

    openapi.to_json
  end

  private

  def self.adapt_parse_shapes_to_extract_shapes_format(parse_shapes_output)
    adapted_shapes = {}

    parse_shapes_output.each do |shape_uri, shape_data|
      adapted_shapes[shape_uri] = {
        uri: shape_data[:uri],
        name: shape_data[:name],
        description: shape_data[:description],
        target_class: shape_data[:target_class],
        node: shape_data[:nodes].first, # Take first node for inheritance relationship
        properties: []
      }

      # Convert properties from hash to array format
      shape_data[:properties].each do |property_path, property_info|
        adapted_property = {
          name: property_info[:name],
          path: property_info[:path],
          description: property_info[:description],
          datatype: property_info.dig(:constraints, :datatype),
          min_count: property_info.dig(:constraints, :min_count),
          max_count: property_info.dig(:constraints, :max_count),
          class: property_info.dig(:constraints, :class),
          # Add OpenAPI specific constraints
          pattern: property_info.dig(:constraints, :pattern),
          min_length: property_info.dig(:constraints, :min_length),
          max_length: property_info.dig(:constraints, :max_length),
          min_value: property_info.dig(:constraints, :min_value),
          max_value: property_info.dig(:constraints, :max_value)
        }

        adapted_shapes[shape_uri][:properties] << adapted_property
      end
    end

    adapted_shapes
  end

  # Helper method to convert a shape to OpenAPI schema format
  def self.convert_shape_to_openapi_schema(shape_data, all_shapes)
    schema = {
      "type" => "object",
      "properties" => {},
      "required" => []
    }

    # Add shape description if available
    if shape_data[:description] && !shape_data[:description].empty?
      schema["description"] = shape_data[:description]
    end

    # Add shape title if available
    if shape_data[:name] && !shape_data[:name].empty?
      schema["title"] = shape_data[:name]
    end

    # Process properties
    if shape_data[:properties] && !shape_data[:properties].empty?
      shape_data[:properties].each do |property|
        property_name = property[:name] || extract_name_from_uri(property[:path])

        # Convert property to OpenAPI property
        openapi_property = convert_property_to_openapi(property, all_shapes)
        schema["properties"][property_name] = openapi_property

        # Add to required array if minCount >= 1
        if property[:min_count] && property[:min_count] >= 1
          schema["required"] << property_name
        end
      end
    end

    # Remove required array if empty
    if schema["required"].empty?
      schema.delete("required")
    end

    schema
  end

  # Helper method to convert a property to OpenAPI format
  def self.convert_property_to_openapi(property, all_shapes)
    openapi_property = {}

    # Add property description
    if property[:description] && !property[:description].empty?
      openapi_property["description"] = property[:description]
    end

    # Handle datatype vs class reference
    if property[:datatype] && !property[:datatype].empty?
      # Map SHACL datatype to OpenAPI type and format
      type_format = map_shacl_datatype_to_openapi(property[:datatype])
      openapi_property["type"] = type_format["type"]

      if type_format["format"]
        openapi_property["format"] = type_format["format"]
      end
    elsif property[:class] && !property[:class].empty?
      # Reference to another schema
      referenced_shape = all_shapes.values.find { |s| s[:target_class] == property[:class] }
      if referenced_shape && referenced_shape[:name]
        openapi_property["$ref"] = "#/components/schemas/#{referenced_shape[:name]}"
      else
        openapi_property["type"] = "object"
      end
    else
      # Default to string if no type specified
      openapi_property["type"] = "string"
    end

    # Handle array properties (maxCount > 1)
    if property[:max_count] && property[:max_count] > 1
      array_property = {
        "type" => "array",
        "items" => openapi_property.dup
      }

      if property[:min_count] && property[:min_count] > 0
        array_property["minItems"] = property[:min_count]
      end

      if property[:max_count] != Float::INFINITY
        array_property["maxItems"] = property[:max_count]
      end

      openapi_property = array_property
    end

    # Add string constraints
    if property[:pattern] && !property[:pattern].empty?
      openapi_property["pattern"] = property[:pattern]
    end

    if property[:min_length]
      openapi_property["minLength"] = property[:min_length]
    end

    if property[:max_length]
      openapi_property["maxLength"] = property[:max_length]
    end

    # Add numeric constraints
    if property[:min_value]
      openapi_property["minimum"] = property[:min_value]
    end

    if property[:max_value]
      openapi_property["maximum"] = property[:max_value]
    end

    openapi_property
  end

  # Helper method to map SHACL datatypes to OpenAPI types and formats
  def self.map_shacl_datatype_to_openapi(datatype)
    case datatype
    when /string$/
      { "type" => "string" }
    when /integer$/
      { "type" => "integer" }
    when /decimal$/
      { "type" => "number", "format" => "decimal" }
    when /double$/, /float$/
      { "type" => "number", "format" => "double" }
    when /boolean$/
      { "type" => "boolean" }
    when /date$/
      { "type" => "string", "format" => "date" }
    when /dateTime$/
      { "type" => "string", "format" => "date-time" }
    when /anyURI$/
      { "type" => "string", "format" => "uri" }
    when /base64Binary$/
      { "type" => "string", "format" => "byte" }
    else
      { "type" => "string" }
    end
  end

  # Generate basic CRUD operations for a resource
  def self.generate_collection_operations(schema_name)
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
                  "items" => { "$ref" => "#/components/schemas/#{schema_name}" }
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
              "schema" => { "$ref" => "#/components/schemas/#{schema_name}" }
            }
          }
        },
        "responses" => {
          "201" => {
            "description" => "#{schema_name} created successfully",
            "content" => {
              "application/json" => {
                "schema" => { "$ref" => "#/components/schemas/#{schema_name}" }
              }
            }
          }
        }
      }
    }
  end

  def self.generate_individual_operations(schema_name)
    {
      "get" => {
        "summary" => "Get a #{schema_name} by ID",
        "parameters" => [
          {
            "name" => "id",
            "in" => "path",
            "required" => true,
            "schema" => { "type" => "string" },
            "description" => "ID of the #{schema_name}"
          }
        ],
        "responses" => {
          "200" => {
            "description" => "#{schema_name} details",
            "content" => {
              "application/json" => {
                "schema" => { "$ref" => "#/components/schemas/#{schema_name}" }
              }
            }
          },
          "404" => {
            "description" => "#{schema_name} not found"
          }
        }
      },
      "put" => {
        "summary" => "Update a #{schema_name}",
        "parameters" => [
          {
            "name" => "id",
            "in" => "path",
            "required" => true,
            "schema" => { "type" => "string" },
            "description" => "ID of the #{schema_name}"
          }
        ],
        "requestBody" => {
          "required" => true,
          "content" => {
            "application/json" => {
              "schema" => { "$ref" => "#/components/schemas/#{schema_name}" }
            }
          }
        },
        "responses" => {
          "200" => {
            "description" => "#{schema_name} updated successfully",
            "content" => {
              "application/json" => {
                "schema" => { "$ref" => "#/components/schemas/#{schema_name}" }
              }
            }
          }
        }
      },
      "delete" => {
        "summary" => "Delete a #{schema_name}",
        "parameters" => [
          {
            "name" => "id",
            "in" => "path",
            "required" => true,
            "schema" => { "type" => "string" },
            "description" => "ID of the #{schema_name}"
          }
        ],
        "responses" => {
          "200" => {
            "description" => "#{schema_name} deleted successfully"
          }
        }
      }
    }
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