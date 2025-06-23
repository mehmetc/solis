require_relative 'generic'
require_relative 'ui_schema'
require 'rdf'
require 'rdf/vocab'
require 'json'

class JSONSchemaWriter < Solis::Model::Writer::Generic
  def self.write(repository, options = {})
    return '{"error": "No repository provided"}' if repository.nil?

    # STEP 5: Use parse_shapes if available in options, otherwise fall back to extract_shapes
    if options[:shapes]
      shapes = adapt_parse_shapes_to_extract_shapes_format(options[:shapes])
    else
      shapes = extract_shapes(repository)
    end

    return '{"error": "No SHACL shapes found in repository"}' if shapes.empty?

    language_code = nil # TODO: get from properties

    # Create the base JSON Schema document
    schema = {
      "$schema" => "https://json-schema.org/draft/2019-09/schema",
      "title" => options[:title] || "Generated from SHACL definitions",
      "description" => options[:description] || "JSON Schema generated from SHACL shapes",
      "type" => "object",
      "definitions" => {},
      "properties" => {},
      "additionalProperties" => false,
      "uiSchema" => {} # Add UI Schema for JSON Schema Form libraries
    }

    # Process each shape to create schema definitions
    shapes.each do |shape_uri, shape_data|
      # Generate a definition for this shape
      definition = convert_shape_to_json_schema(shape_data, shapes)

      # Add it to the definitions section
      definition_name = get_class_name(shape_data[:name] || extract_name_from_uri(shape_uri))
      schema["definitions"][definition_name] = definition

      # FIXED: Always add root properties for each shape (unless it inherits from another shape)
      unless shape_data[:node] && shape_data[:node] != shape_uri
        property_name = definition_name.gsub(/Shape$/, '')
        property_name = underscore(property_name)

        # Get the title and description for the root property
        title = shape_data[:name] || property_name.capitalize
        description = shape_data[:description] || "#{property_name.capitalize} object"

        schema["properties"][property_name] = {
          "$ref" => "#/definitions/#{definition_name}",
          "title" => title,
          "description" => description
        }

        # Extract UI Schema information from definition if it exists
        if definition["ui:order"]
          schema["uiSchema"][property_name] = {
            "ui:order" => definition["ui:order"]
          }

          # Add any property-specific UI schema elements
          if definition["properties"]
            definition["properties"].each do |prop_name, prop_schema|
              if prop_schema["ui:widget"]
                schema["uiSchema"][property_name] ||= {}
                schema["uiSchema"][property_name][prop_name] = {
                  "ui:widget" => prop_schema["ui:widget"]
                }
                # Remove from actual schema to avoid validation errors
                definition["properties"][prop_name].delete("ui:widget")
              end
            end
          end

          # Remove ui:order from actual schema to avoid validation errors
          definition.delete("ui:order")
        end
      end
    end

    # FIXED: Use UISchemaWriter properly
    schema = UISchemaWriter.enhance(schema, options)

    # Return the JSON Schema as a formatted string
    JSON.pretty_generate(schema)
  end

  private

  # STEP 5: Adapter method to convert parse_shapes format to extract_shapes format
  def self.adapt_parse_shapes_to_extract_shapes_format(parse_shapes_output)
    adapted_shapes = {}

    parse_shapes_output.each do |shape_uri, shape_data|
      adapted_shapes[shape_uri] = {
        uri: shape_data[:uri],
        name: shape_data[:name],
        description: shape_data[:description],
        target_class: shape_data[:target_class],
        node: shape_data[:nodes].first, # Take first node for inheritance relationship
        properties: [],
        labels: {},
        descriptions: {}
      }

      # Add labels and descriptions for internationalization support
      if shape_data[:description] && !shape_data[:description].empty?
        adapted_shapes[shape_uri][:descriptions]['default'] = shape_data[:description]
      end

      if shape_data[:name] && !shape_data[:name].empty?
        adapted_shapes[shape_uri][:labels]['default'] = shape_data[:name]
      end

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
          # Add additional JSON Schema specific properties if available
          pattern: property_info.dig(:constraints, :pattern),
          min_length: property_info.dig(:constraints, :min_length),
          max_length: property_info.dig(:constraints, :max_length),
          min_value: property_info.dig(:constraints, :min_value),
          max_value: property_info.dig(:constraints, :max_value),
          # Add support for multilingual labels and descriptions
          labels: {},
          descriptions: {}
        }

        # Add default labels/descriptions
        if property_info[:name]
          adapted_property[:labels]['default'] = property_info[:name]
        end
        if property_info[:description]
          adapted_property[:descriptions]['default'] = property_info[:description]
        end

        adapted_shapes[shape_uri][:properties] << adapted_property
      end
    end

    adapted_shapes
  end

  # Helper method to convert a single shape to JSON Schema format
  def self.convert_shape_to_json_schema(shape_data, all_shapes)
    definition = {
      "type" => "object",
      "properties" => {},
      "required" => []
    }

    # Add shape description if available
    if shape_data[:description] && !shape_data[:description].empty?
      definition["description"] = shape_data[:description]
    end

    # Add shape title if available
    if shape_data[:name] && !shape_data[:name].empty?
      definition["title"] = shape_data[:name]
    end

    # Add UI schema hints (will be moved to uiSchema later)
    definition["ui:order"] = []

    # Process properties
    if shape_data[:properties] && !shape_data[:properties].empty?
      shape_data[:properties].each do |property|
        property_name = property[:name] || extract_name_from_uri(property[:path])
        property_name = underscore(property_name)

        # Convert property to JSON Schema property
        json_property = convert_property_to_json_schema_detailed(property, all_shapes)
        definition["properties"][property_name] = json_property

        # Add to UI order
        definition["ui:order"] << property_name

        # Add to required array if minCount >= 1
        if property[:min_count] && property[:min_count] >= 1
          definition["required"] << property_name
        end
      end
    end

    # Add additionalProperties control
    definition["additionalProperties"] = false

    # Remove required array if empty
    if definition["required"].empty?
      definition.delete("required")
    end

    # Handle inheritance - allOf with parent definition
    if shape_data[:node] && shape_data[:node] != shape_data[:uri]
      parent_shape = all_shapes[shape_data[:node]]
      if parent_shape
        parent_name = get_class_name(parent_shape[:name] || extract_name_from_uri(shape_data[:node]))

        # Use allOf to combine with the parent schema
        definition = {
          "allOf" => [
            { "$ref" => "#/definitions/#{parent_name}" },
            definition
          ]
        }
      end
    end

    definition
  end

  # Enhanced property conversion with full support
  def self.convert_property_to_json_schema_detailed(property, all_shapes)
    json_property = {}

    # Get the title with language support
    title = get_label_for_language(property[:labels], nil) ||
      property[:name] ||
      extract_name_from_uri(property[:path])

    # Get description with language support
    description = get_label_for_language(property[:descriptions], nil) ||
      property[:description]

    # Always add title and description
    json_property["title"] = title if title
    json_property["description"] = description if description

    # Handle datatype vs class reference
    if property[:datatype] && !property[:datatype].empty?
      # Map SHACL datatype to JSON Schema type
      type_info = map_shacl_datatype_to_json_schema(property[:datatype])
      json_property.merge!(type_info)

      # Add default value
      json_property["default"] = default_value_for_type(type_info["type"])

    elsif property[:class] && !property[:class].empty?
      # Reference to another shape/object
      referenced_shape = all_shapes.values.find { |s| s[:target_class] == property[:class] }
      if referenced_shape && referenced_shape[:name]
        json_property["$ref"] = "#/definitions/#{referenced_shape[:name]}"
      else
        json_property["type"] = "object"
      end
    else
      # Default to string if no type specified
      json_property["type"] = "string"
      json_property["default"] = ""
    end

    # Add cardinality constraints
    if property[:max_count] && property[:max_count] > 1
      # Array property
      array_property = {
        "type" => "array",
        "items" => json_property.dup
      }

      if property[:min_count] && property[:min_count] > 0
        array_property["minItems"] = property[:min_count]
      end

      if property[:max_count] != Float::INFINITY
        array_property["maxItems"] = property[:max_count]
      end

      json_property = array_property
    end

    # Add string constraints
    if property[:pattern] && !property[:pattern].empty?
      json_property["pattern"] = property[:pattern]
    end

    if property[:min_length]
      json_property["minLength"] = property[:min_length]
    end

    if property[:max_length]
      json_property["maxLength"] = property[:max_length]
    end

    # Add numeric constraints
    if property[:min_value]
      json_property["minimum"] = property[:min_value]
    end

    if property[:max_value]
      json_property["maximum"] = property[:max_value]
    end

    # Add smart UI widget suggestions (will be moved to uiSchema)
    if json_property["type"] == "string"
      if property[:max_length] && property[:max_length] > 100
        json_property["ui:widget"] = "textarea"
      else
        json_property["ui:widget"] = "text"
      end
    end

    json_property
  end

  # Helper method to get a label in the specified language
  def self.get_label_for_language(labels, language_code)
    return nil if labels.nil? || labels.empty?

    if language_code && labels.key?(language_code)
      labels[language_code]
    elsif labels.key?('default')
      labels['default']
    else
      # Just take the first available label if specific language not found
      labels.values.first
    end
  end

  # Helper method to map SHACL datatypes to JSON Schema types
  def self.map_shacl_datatype_to_json_schema(datatype)
    case datatype
    when /string$/
      { "type" => "string" }
    when /integer$/
      { "type" => "integer" }
    when /decimal$/, /double$/, /float$/
      { "type" => "number" }
    when /boolean$/
      { "type" => "boolean" }
    when /date$/, /dateTime$/
      { "type" => "string", "format" => "date-time" }
    when /anyURI$/
      { "type" => "string", "format" => "uri" }
    else
      { "type" => "string" }
    end
  end

  # Helper method to provide default values based on type
  def self.default_value_for_type(type)
    case type
    when "string"
      ""
    when "integer", "number"
      0
    when "boolean"
      false
    when "array"
      []
    when "object"
      {}
    else
      ""
    end
  end

  # Convert CamelCase to snake_case
  def self.underscore(string)
    string.gsub(/::/, '/').
      gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').
      gsub(/([a-z\d])([A-Z])/, '\1_\2').
      tr("-", "_").
      downcase
  end

  # Extract name from URI
  def self.extract_name_from_uri(uri)
    return "" unless uri
    if uri.include?('#')
      uri.split('#').last
    else
      uri.split('/').last
    end
  end

  # Clean and format class names
  def self.get_class_name(name)
    return "UnnamedClass" if name.nil? || name.empty?
    name.strip.gsub(/[^a-zA-Z0-9]/, '')
  end

end
