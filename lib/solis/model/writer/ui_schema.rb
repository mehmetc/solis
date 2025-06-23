# In lib/solis/model/writer/ui_schema.rb
# Fixed version that works with the actual JSONSchemaWriter structure

class UISchemaWriter
  # Takes a JSON Schema string or Hash and extends/customizes the UI Schema portion
  #
  # Options can include:
  #   theme: String - specifies a theme ('default', 'bootstrap', 'material', etc.)
  #   layout: String - specifies a layout ('vertical', 'horizontal', 'grid')
  #   field_options: Hash - per-field UI customizations
  #   global_options: Hash - global UI customizations
  def self.enhance(json_schema, options = {})
    # Parse if string was provided
    schema = json_schema.is_a?(String) ? JSON.parse(json_schema) : json_schema.dup

    # Create or get uiSchema
    ui_schema = schema["uiSchema"] || {}

    # Global customization settings
    theme = options[:theme] || 'default'
    layout = options[:layout] || 'vertical'

    # Apply global settings
    ui_schema["ui:globalOptions"] = {
      "theme" => theme,
      "layout" => layout
    }

    # Apply any additional global options
    if options[:global_options] && options[:global_options].is_a?(Hash)
      ui_schema["ui:globalOptions"].merge!(options[:global_options])
    end

    # FIXED: Process each property in the schema (root level properties are $refs)
    if schema["properties"]
      schema["properties"].each do |property_name, property_def|
        # If this is a reference to a definition
        if property_def["$ref"]
          # Extract the definition name from $ref (e.g., "#/definitions/CarShape" -> "CarShape")
          definition_name = property_def["$ref"].split('/').last

          # Process this definition if it exists
          if schema["definitions"] && schema["definitions"][definition_name]
            process_definition(ui_schema, property_name, schema["definitions"][definition_name], options)
          end
        else
          # Direct property definition (handle direct properties too)
          process_direct_property(ui_schema, property_name, property_def, options)
        end
      end
    end

    # FIXED: Also process definitions directly (for cases where there are no root properties)
    if schema["definitions"]
      schema["definitions"].each do |definition_name, definition|
        # Only process if not already processed via root properties
        unless ui_schema[definition_name] || ui_schema[underscore(definition_name)]
          process_definition_standalone(ui_schema, definition_name, definition, options)
        end
      end
    end

    # Update the schema with our enhanced uiSchema
    schema["uiSchema"] = ui_schema

    # Return as JSON string or hash based on input type
    json_schema.is_a?(String) ? JSON.pretty_generate(schema) : schema
  end

  private

  # Process a definition to enhance its UI schema
  def self.process_definition(ui_schema, property_name, definition, options)
    # Ensure the property exists in uiSchema
    ui_schema[property_name] ||= {}

    # If this is an allOf definition (inheritance), we may need to merge properties
    if definition["allOf"]
      merged_properties = {}

      # Extract properties from all parent schemas
      definition["allOf"].each do |schema_part|
        if schema_part["properties"]
          merged_properties.merge!(schema_part["properties"])
        end
      end

      # Process the merged properties
      process_properties(ui_schema[property_name], merged_properties, options)

      # Standard definition with properties
    elsif definition["properties"]
      process_properties(ui_schema[property_name], definition["properties"], options)
    end
  end

  # Process a definition standalone (when not referenced by root properties)
  def self.process_definition_standalone(ui_schema, definition_name, definition, options)
    # Use underscored name for UI schema key
    ui_key = underscore(definition_name)
    ui_schema[ui_key] ||= {}

    if definition["properties"]
      process_properties(ui_schema[ui_key], definition["properties"], options)
    end
  end

  # Process a direct property (not a $ref)
  def self.process_direct_property(ui_schema, property_name, property_def, options)
    ui_schema[property_name] ||= {}

    # Apply field options if available
    if options[:field_options] && options[:field_options][property_name]
      ui_schema[property_name].merge!(options[:field_options][property_name])
    end

    # Add smart defaults
    add_smart_defaults_for_property(ui_schema, property_name, property_def)
  end

  # Process individual properties to enhance their UI schema
  def self.process_properties(parent_ui_schema, properties, options)
    # Default order if not already set
    parent_ui_schema["ui:order"] ||= properties.keys

    # Process each property for UI enhancements
    properties.each do |prop_name, prop_def|
      # Apply custom field options if available
      if options[:field_options] && options[:field_options][prop_name]
        field_options = options[:field_options][prop_name]

        # Create property UI schema if not exists
        parent_ui_schema[prop_name] ||= {}

        # Apply field-specific options
        field_options.each do |option_key, option_value|
          parent_ui_schema[prop_name][option_key] = option_value
        end
      end

      # Add smart defaults based on property type
      add_smart_defaults(parent_ui_schema, prop_name, prop_def)
    end
  end

  # Add smart UI schema defaults based on property characteristics
  def self.add_smart_defaults(parent_ui_schema, prop_name, prop_def)
    parent_ui_schema[prop_name] ||= {}

    # Property type-based settings
    case prop_def["type"]
    when "string"
      if prop_def["format"] == "date-time"
        parent_ui_schema[prop_name]["ui:widget"] ||= "datetime"
      elsif prop_def["format"] == "date"
        parent_ui_schema[prop_name]["ui:widget"] ||= "date"
      elsif prop_def["format"] == "email"
        parent_ui_schema[prop_name]["ui:widget"] ||= "email"
      elsif prop_def["format"] == "uri"
        parent_ui_schema[prop_name]["ui:widget"] ||= "uri"
      elsif prop_def["maxLength"] && prop_def["maxLength"] > 100
        parent_ui_schema[prop_name]["ui:widget"] ||= "textarea"
      end

    when "integer", "number"
      parent_ui_schema[prop_name]["ui:widget"] ||= "updown"

    when "boolean"
      parent_ui_schema[prop_name]["ui:widget"] ||= "checkbox"

    when "array"
      parent_ui_schema[prop_name]["ui:widget"] ||= "array"
      parent_ui_schema[prop_name]["ui:options"] ||= {}
      parent_ui_schema[prop_name]["ui:options"]["addable"] = true
      parent_ui_schema[prop_name]["ui:options"]["removable"] = true
      parent_ui_schema[prop_name]["ui:options"]["orderable"] = true

    when "object"
      parent_ui_schema[prop_name]["ui:widget"] ||= "fieldset"
    end

    # Add help text if description exists
    if prop_def["description"] && !prop_def["description"].empty?
      parent_ui_schema[prop_name]["ui:help"] ||= prop_def["description"]
    end

    # Add placeholder from title if none exists
    if prop_def["title"] && !parent_ui_schema[prop_name]["ui:placeholder"]
      parent_ui_schema[prop_name]["ui:placeholder"] ||= "Enter #{prop_def["title"].downcase}"
    end
  end

  # Add smart defaults for direct properties
  def self.add_smart_defaults_for_property(parent_ui_schema, prop_name, prop_def)
    add_smart_defaults(parent_ui_schema, prop_name, prop_def)
  end

  # Convert CamelCase to snake_case
  def self.underscore(string)
    string.gsub(/::/, '/').
      gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
      gsub(/([a-z\d])([A-Z])/,'\1_\2').
      tr("-", "_").
      downcase
  end
end