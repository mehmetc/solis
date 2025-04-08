require_relative 'generic'
require_relative 'ui_schema'
require 'rdf'
require 'rdf/vocab'
require 'json'

class JSONSchemaWriter
  # Main method to convert a RDF::Repository with SHACL definitions to a JSON Schema
  # language_code can be 'en', 'fr', 'de', etc. or nil for default language
  def self.write(repository, options = {})
    return '{"error": "No repository provided"}' if repository.nil?

    # Extract all node shapes from the repository
    shapes = extract_shapes(repository)
    return '{"error": "No SHACL shapes found in repository"}' if shapes.empty?

    language_code = nil #TODO: get from properties

    # Create the base JSON Schema document
    schema = {
      "$schema" => "http://json-schema.org/draft-07/schema#",
      "title" => "Generated from SHACL definitions",
      "description" => "JSON Schema generated from SHACL shapes",
      "type" => "object",
      "definitions" => {},
      "properties" => {},
      "additionalProperties" => false,
      "uiSchema" => {}  # Add UI Schema for JSON Schema Form libraries
    }

    # Process each shape to create schema definitions
    shapes.each do |shape_uri, shape_data|
      # Generate a definition for this shape
      definition = process_shape_to_definition(shape_data, shapes, language_code)

      # Add it to the definitions section
      definition_name = get_class_name(shape_data[:name] || extract_name_from_uri(shape_uri))
      schema["definitions"][definition_name] = definition

      # For root-level shapes, also add them to the properties section
      # (Unless they inherit from another shape)
      unless shape_data[:node] && shape_data[:node] != shape_uri
        property_name = definition_name.gsub(/Shape$/, '')
        property_name = underscore(property_name)

        # Get the title in the specified language if available
        title = get_label_for_language(shape_data[:labels], language_code) ||
          shape_data[:name] ||
          property_name.capitalize

        # Get description in the specified language if available
        description = get_label_for_language(shape_data[:descriptions], language_code) ||
          shape_data[:description] ||
          "#{property_name.capitalize} object"

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
          definition["properties"].each do |prop_name, prop_schema|
            if prop_schema["ui:widget"]
              schema["uiSchema"][property_name][prop_name] = {
                "ui:widget" => prop_schema["ui:widget"]
              }
              # Remove from actual schema to avoid validation errors
              definition["properties"][prop_name].delete("ui:widget")
            end
          end

          # Remove ui:order from actual schema to avoid validation errors
          definition.delete("ui:order")
        end
      end
    end


    schema['uiSchema'] = UISchemaWriter.enhance(schema, options)
    # Return the JSON Schema as a formatted string
    JSON.pretty_generate(schema)
  end

  private

  # Extract all node shapes from the repository
  def self.extract_shapes(repository)
    shapes = {}

    # Find all resources that are defined as NodeShapes
    repository.query([nil, RDF.type, RDF::Vocab::SHACL.NodeShape]) do |statement|
      shape_uri = statement.subject.to_s
      shape_data = {
        uri: shape_uri,
        properties: [],
        labels: {},
        descriptions: {}
      }

      # Get shape name
      name_results = repository.query([statement.subject, RDF::Vocab::SHACL.name, nil]).to_a
      shape_data[:name] = name_results.first.object.to_s if name_results.any?

      # Get shape description
      desc_results = repository.query([statement.subject, RDF::Vocab::SHACL.description, nil]).to_a
      shape_data[:description] = desc_results.first.object.to_s if desc_results.any?

      # Get multilingual labels
      label_results = repository.query([statement.subject, RDF::RDFS.label, nil]).to_a
      label_results.each do |label_stmt|
        if label_stmt.object.is_a?(RDF::Literal) && label_stmt.object.language?
          shape_data[:labels][label_stmt.object.language.to_s] = label_stmt.object.value
        else
          shape_data[:labels]['default'] = label_stmt.object.to_s
        end
      end

      # Get multilingual descriptions
      comment_results = repository.query([statement.subject, RDF::RDFS.comment, nil]).to_a
      comment_results.each do |comment_stmt|
        if comment_stmt.object.is_a?(RDF::Literal) && comment_stmt.object.language?
          shape_data[:descriptions][comment_stmt.object.language.to_s] = comment_stmt.object.value
        else
          shape_data[:descriptions]['default'] = comment_stmt.object.to_s
        end
      end

      # Get target class
      target_results = repository.query([statement.subject, RDF::Vocab::SHACL.targetClass, nil]).to_a
      shape_data[:target_class] = target_results.first.object.to_s if target_results.any?

      # Get superclass
      node_results = repository.query([statement.subject, RDF::Vocab::SHACL.node, nil]).to_a
      shape_data[:node] = node_results.first.object.to_s if node_results.any?

      # Get all property shapes
      prop_results = repository.query([statement.subject, RDF::Vocab::SHACL.property, nil]).to_a

      prop_results.each do |prop_stmt|
        property_shape = prop_stmt.object
        property_data = { labels: {}, descriptions: {} }

        # Get property path (predicate)
        path_results = repository.query([property_shape, RDF::Vocab::SHACL.path, nil]).to_a
        if path_results.any?
          property_data[:path] = path_results.first.object.to_s
        end

        # Get property name
        name_results = repository.query([property_shape, RDF::Vocab::SHACL.name, nil]).to_a
        if name_results.any?
          property_data[:name] = name_results.first.object.to_s
        end

        # Get property description
        desc_results = repository.query([property_shape, RDF::Vocab::SHACL.description, nil]).to_a
        if desc_results.any?
          property_data[:description] = desc_results.first.object.to_s
        end

        # Get multilingual labels
        label_results = repository.query([property_shape, RDF::RDFS.label, nil]).to_a
        label_results.each do |label_stmt|
          if label_stmt.object.is_a?(RDF::Literal) && label_stmt.object.language?
            property_data[:labels][label_stmt.object.language.to_s] = label_stmt.object.value
          else
            property_data[:labels]['default'] = label_stmt.object.to_s
          end
        end

        # Get multilingual descriptions
        comment_results = repository.query([property_shape, RDF::RDFS.comment, nil]).to_a
        comment_results.each do |comment_stmt|
          if comment_stmt.object.is_a?(RDF::Literal) && comment_stmt.object.language?
            property_data[:descriptions][comment_stmt.object.language.to_s] = comment_stmt.object.value
          else
            property_data[:descriptions]['default'] = comment_stmt.object.to_s
          end
        end

        # Get datatype
        type_results = repository.query([property_shape, RDF::Vocab::SHACL.datatype, nil]).to_a
        if type_results.any?
          property_data[:datatype] = type_results.first.object.to_s
        end

        # Get class for object properties
        class_results = repository.query([property_shape, RDF::Vocab::SHACL.class, nil]).to_a
        if class_results.any?
          property_data[:class] = class_results.first.object.to_s
        end

        # Get nodeKind
        kind_results = repository.query([property_shape, RDF::Vocab::SHACL.nodeKind, nil]).to_a
        if kind_results.any?
          property_data[:node_kind] = kind_results.first.object.to_s
        end

        # Get min cardinality
        min_results = repository.query([property_shape, RDF::Vocab::SHACL.minCount, nil]).to_a
        if min_results.any?
          property_data[:min_count] = min_results.first.object.to_i
        end

        # Get max cardinality
        max_results = repository.query([property_shape, RDF::Vocab::SHACL.maxCount, nil]).to_a
        if max_results.any?
          property_data[:max_count] = max_results.first.object.to_i
        end

        # Get pattern constraint
        pattern_results = repository.query([property_shape, RDF::Vocab::SHACL.pattern, nil]).to_a
        if pattern_results.any?
          property_data[:pattern] = pattern_results.first.object.to_s
        end

        # Get min value constraint
        min_val_results = repository.query([property_shape, RDF::Vocab::SHACL.minInclusive, nil]).to_a
        if min_val_results.any?
          property_data[:min_inclusive] = min_val_results.first.object.to_s
        end

        # Get max value constraint
        max_val_results = repository.query([property_shape, RDF::Vocab::SHACL.maxInclusive, nil]).to_a
        if max_val_results.any?
          property_data[:max_inclusive] = max_val_results.first.object.to_s
        end

        # Only add properties that have at least a path
        if property_data[:path]
          shape_data[:properties] << property_data
        end
      end

      shapes[shape_uri] = shape_data
    end

    shapes
  end

  # Convert a SHACL shape to a JSON Schema definition
  def self.process_shape_to_definition(shape_data, all_shapes, language_code = nil)
    # Get the title in the specified language if available
    title = get_label_for_language(shape_data[:labels], language_code) ||
      shape_data[:name]

    # Get description in the specified language if available
    description = get_label_for_language(shape_data[:descriptions], language_code) ||
      shape_data[:description]

    definition = {
      "type" => "object",
      "title" => title,
      "additionalProperties" => false
    }

    # Add description if available
    definition["description"] = description if description

    # Add UI schema hints
    definition["ui:order"] = []

    # Add required properties array if needed
    required_properties = []

    # Properties container
    definition["properties"] = {}

    # Process shape properties
    shape_data[:properties].each do |property|
      property_name = property[:name] || extract_name_from_uri(property[:path])
      property_name = underscore(property_name)

      # Create property schema
      property_schema = create_property_schema(property, all_shapes, language_code)

      # Check if this property is required
      if property[:min_count] && property[:min_count] > 0
        required_properties << property_name
      end

      # Add the property to the definition
      definition["properties"][property_name] = property_schema

      # Add to UI order
      definition["ui:order"] << property_name
    end

    # If no properties were added (unlikely but possible), add a dummy property
    # to ensure the schema is valid and renderable
    if definition["properties"].empty?
      definition["properties"]["id"] = {
        "type" => "string",
        "title" => "ID",
        "description" => "Identifier",
        "default" => ""
      }
      definition["ui:order"] = ["id"]
    end

    # Add required properties if any
    if required_properties.any?
      definition["required"] = required_properties
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

  # Create a JSON Schema representation of a SHACL property
  def self.create_property_schema(property, all_shapes, language_code = nil)
    property_schema = {}

    # Get the title in the specified language if available
    title = get_label_for_language(property[:labels], language_code) ||
      property[:name] ||
      extract_name_from_uri(property[:path])

    # Get description in the specified language if available
    description = get_label_for_language(property[:descriptions], language_code) ||
      property[:description]

    # Always add title from the name - this is important for UI rendering
    property_schema["title"] = title if title

    # Always add description if available (UI libraries use this)
    property_schema["description"] = description if description

    # Handle different property types
    if property[:datatype]
      # Literal property with datatype
      json_type = get_json_type(property[:datatype])
      property_schema["type"] = json_type

      # Add format for certain types
      format = get_json_format(property[:datatype])
      property_schema["format"] = format if format

      # Add pattern constraint if present
      if property[:pattern]
        property_schema["pattern"] = property[:pattern]
      end

      # Add numeric constraints if present
      if property[:min_inclusive] && json_type == "number"
        property_schema["minimum"] = property[:min_inclusive].to_i
      end

      if property[:max_inclusive] && json_type == "number"
        property_schema["maximum"] = property[:max_inclusive].to_i
      end

      # Add default value for better UI rendering
      property_schema["default"] = default_value_for_type(json_type)

    elsif property[:class]
      # Reference to another entity
      target_class_name = nil

      # Find the shape that has this class as its target class
      all_shapes.each do |_, other_shape|
        if other_shape[:target_class] == property[:class]
          target_class_name = get_class_name(other_shape[:name] || extract_name_from_uri(other_shape[:uri]))
          break
        end
      end

      # If no matching shape found, use the URI's local name
      target_class_name ||= get_class_name(extract_name_from_uri(property[:class]))

      # Check cardinality for arrays
      if property[:max_count].nil? || property[:max_count] > 1
        property_schema["type"] = "array"
        property_schema["items"] = { "$ref" => "#/definitions/#{target_class_name}" }
        property_schema["default"] = []  # Empty array as default
      else
        property_schema["$ref"] = "#/definitions/#{target_class_name}"
      end
    else
      # Default to string if no specific type is found
      property_schema["type"] = "string"
      property_schema["default"] = ""
    end

    # Add a widget hint for UI frameworks (optional, but helpful)
    property_schema["ui:widget"] = suggest_widget(property) if property[:datatype]

    property_schema
  end

  # Suggest appropriate widget types for UI rendering
  def self.suggest_widget(property)
    return nil unless property[:datatype]

    case property[:datatype]
    when RDF::XSD.string.to_s
      if property[:pattern] && property[:pattern].include?("@")
        "email"
      elsif property[:max_count] && property[:max_count] > 1
        "textarea"
      else
        "text"
      end
    when RDF::XSD.boolean.to_s
      "checkbox"
    when RDF::XSD.date.to_s
      "date"
    when RDF::XSD.dateTime.to_s
      "datetime"
    when RDF::XSD.time.to_s
      "time"
    when RDF::XSD.anyURI.to_s
      "uri"
    when "http://www.w3.org/1999/02/22-rdf-syntax-ns#JSON"
      "textarea"
    else
      nil
    end
  end

  # Provide sensible default values based on type
  def self.default_value_for_type(json_type)
    case json_type
    when "string"
      ""
    when "integer", "number"
      0
    when "boolean"
      false
    when "object"
      {}
    when "array"
      []
    else
      nil
    end
  end

  # Extract a readable name from a URI
  def self.extract_name_from_uri(uri)
    return "" unless uri
    # Extract the last part of the URI (after the last # or /)
    if uri.include?('#')
      uri.split('#').last
    else
      uri.split('/').last
    end
  end

  # Clean and format class names
  def self.get_class_name(name)
    return "UnnamedClass" if name.nil? || name.empty?

    # Remove spaces and special characters, capitalize first letter
    name.gsub(/[^a-zA-Z0-9_]/, '_').gsub(/^([a-z])/) { $1.upcase }
  end

  # Convert camelCase to snake_case
  def self.underscore(name)
    name.gsub(/::/, '/')
        .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
        .gsub(/([a-z\d])([A-Z])/, '\1_\2')
        .tr("-", "_")
        .downcase
  end

  # Map RDF datatypes to JSON Schema types
  def self.get_json_type(datatype)
    return "string" unless datatype

    case datatype
    when RDF::XSD.string.to_s, "http://www.w3.org/2001/XMLSchema#string"
      "string"
    when RDF::XSD.integer.to_s, "http://www.w3.org/2001/XMLSchema#integer"
      "integer"
    when RDF::XSD.decimal.to_s, "http://www.w3.org/2001/XMLSchema#decimal",
      RDF::XSD.float.to_s, "http://www.w3.org/2001/XMLSchema#float",
      RDF::XSD.double.to_s, "http://www.w3.org/2001/XMLSchema#double"
      "number"
    when RDF::XSD.boolean.to_s, "http://www.w3.org/2001/XMLSchema#boolean"
      "boolean"
    when RDF::XSD.date.to_s, "http://www.w3.org/2001/XMLSchema#date",
      RDF::XSD.dateTime.to_s, "http://www.w3.org/2001/XMLSchema#dateTime"
      "string"
    when RDF::XSD.anyURI.to_s, "http://www.w3.org/2001/XMLSchema#anyURI"
      "string"
    when "http://www.w3.org/1999/02/22-rdf-syntax-ns#JSON"
      "object"
    else
      "string"
    end
  end

  # Map RDF datatypes to JSON Schema formats
  def self.get_json_format(datatype)
    return nil unless datatype

    case datatype
    when RDF::XSD.date.to_s, "http://www.w3.org/2001/XMLSchema#date"
      "date"
    when RDF::XSD.dateTime.to_s, "http://www.w3.org/2001/XMLSchema#dateTime"
      "date-time"
    when RDF::XSD.time.to_s, "http://www.w3.org/2001/XMLSchema#time"
      "time"
    when RDF::XSD.anyURI.to_s, "http://www.w3.org/2001/XMLSchema#anyURI"
      "uri"
    when RDF::XSD.email.to_s, "http://www.w3.org/2001/XMLSchema#email"
      "email"
    else
      nil
    end
  end
end