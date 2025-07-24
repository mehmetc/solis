require_relative 'generic'
require_relative 'ui_schema'
require_relative "../../utils/string"
require 'rdf'
require 'rdf/vocab'
require 'json'

class JSONSchemaWriter < Solis::Model::Writer::Generic
  def self.write(repository, options = {})
    return "No repository provided" if repository.nil?
    return "options[:entities] missing" unless options.key?(:entities)

    # Copy in case some deep refs are updated
    entities = Marshal.load(Marshal.dump(options[:entities]))

    if entities.empty?
      return "No entities found in repository"
    end

    return '{"error": "No entities found in repository"}' if entities.empty?

    language_code = nil # TODO: get from properties

    # Create the base JSON Schema document
    schema = {
      "$schema" => "https://json-schema.org/draft/2019-09/schema",
      "title" => options[:title] || "Generated from entities definitions",
      "description" => options[:description] || "JSON Schema generated from entities",
      "type" => "object",
      "definitions" => {},
      "properties" => {},
      "additionalProperties" => false,
      "uiSchema" => {} # Add UI Schema for JSON Schema Form libraries
    }

    # Process each entity to create schema definitions
    entities.each do |entity_uri, entity_data|

      # Generate a definition for this entity
      definition = convert_entity_to_json_schema(entity_data, entities)

      # Add it to the definitions section
      definition_name = Solis::Utils::String.extract_name_from_uri(entity_uri)
      schema["definitions"][definition_name] = definition

      property_name = Solis::Utils::String.camel_to_snake(definition_name)

      schema["properties"][property_name] = {
        "$ref" => "#/definitions/#{definition_name}"
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

    # FIXED: Use UISchemaWriter properly
    schema = UISchemaWriter.enhance(schema, options)

    # Return the JSON Schema as a formatted string
    JSON.pretty_generate(schema)
  end

  private

  # Helper method to convert a single entity to JSON Schema format
  def self.convert_entity_to_json_schema(entity_data, all_entities)
    definition = {
      "type" => "object",
      "properties" => {},
      "required" => []
    }

    # Add entity description if available
    if entity_data[:description] && !entity_data[:description].empty?
      definition["description"] = entity_data[:description]
    end

    # Add entity title if available
    if entity_data[:name] && !entity_data[:name].empty?
      definition["title"] = entity_data[:name]
    end

    # Add UI schema hints (will be moved to uiSchema later)
    definition["ui:order"] = []

    # Process properties
    if entity_data[:properties] && !entity_data[:properties].empty?
      entity_data[:properties].each do |property_uri, property_data|
        property_name = Solis::Utils::String.extract_name_from_uri(property_uri)

        # Convert property to JSON Schema property
        json_property = convert_property_to_json_schema_detailed(property_uri, property_data, all_entities)
        definition["properties"][property_name] = json_property

        # Add to UI order
        definition["ui:order"] << property_name

        # Add to required array if minCount >= 1
        if property_data[:constraints][0][:data][:min_count] && property_data[:constraints][0][:data][:min_count] >= 1
          definition["required"] << property_name
        end
      end
    end
    definition["properties"]['@id'] = convert_id_property_to_json_schema(entity_data[:snake_case_name])

    # Add additionalProperties control
    definition["additionalProperties"] = false

    # Remove required array if empty
    if definition["required"].empty?
      definition.delete("required")
    end

    definition
  end

  # Enhanced property conversion with full support
  def self.convert_property_to_json_schema_detailed(property_uri, property_data, all_entities)

    # NOTE: this is basic but ok for now, will need to be evolved.
    property = property_data[:constraints][0][:data]
    property[:description] = property_data[:constraints][0][:description]

    json_property = {}

    # Get the title with language support
    title = get_label_for_language(property[:labels], nil) ||
      property[:name] ||
      Solis::Utils::String.extract_name_from_uri(property_uri)

    # Get description with language support
    description = get_label_for_language(property[:descriptions], nil) ||
      property[:description]

    # Always add title and description
    json_property["title"] = title if title
    json_property["description"] = description if description

    # Handle datatype vs class reference
    if property[:datatype] && !property[:datatype].empty?
      # Map RDF datatype to JSON Schema type
      type_info = map_rdf_datatype_to_json_schema(property[:datatype])
      json_property.merge!(type_info)

      # Add default value
      json_property["default"] = default_value_for_type(type_info["type"])

    elsif property[:class] && !property[:class].empty?
      referenced_entity_uri = property[:class]
      referenced_entity = all_entities[referenced_entity_uri]
      if referenced_entity
        json_property["$ref"] = "#/definitions/#{Solis::Utils::String.extract_name_from_uri(referenced_entity_uri)}"
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

  def self.convert_id_property_to_json_schema(name)
    {
      'type' => 'string',
      'title' => "ID of the #{name}",
      'description' => "ID of the #{name}",
      'readOnly' => true
    }
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

  # Helper method to map RDF datatypes to JSON Schema types
  def self.map_rdf_datatype_to_json_schema(datatype)
    # NOTE: "format" not supported by every client.
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

end
