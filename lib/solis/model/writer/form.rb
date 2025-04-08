require 'json'
require 'cgi'

class FormWriter
  # Default options for form generation
  DEFAULT_OPTIONS = {
    form_id: 'shacl-form',
    submit_button_text: 'Submit',
    cancel_button_text: 'Cancel',
    form_class: 'shacl-form',
    field_wrapper_class: 'form-group',
    label_class: 'form-label',
    input_class: 'form-control',
    submit_button_class: 'btn btn-primary',
    cancel_button_class: 'btn btn-secondary',
    include_validation: true,
    include_styles: true,
    include_scripts: true,
    layout: 'bootstrap'  # bootstrap, basic, or custom
  }

  # Main method to generate HTML form from JSON Schema and UI Schema
  def self.write(repository, options = {})
    # Merge options with defaults
    opts = DEFAULT_OPTIONS.merge(options)

    json_schema = JSONSchemaWriter.write(repository, opts)

    # Parse schema if it's a string
    schema = json_schema.is_a?(String) ? JSON.parse(json_schema) : json_schema
    # Start building HTML
    html = []

    # Include CSS if requested
    html << generate_css(opts) if opts[:include_styles]

    # Form opening tag
    html << %(<form id="#{opts[:form_id]}" class="#{opts[:form_class]}" action="#{opts[:form_action] || '#'}" method="#{opts[:form_method] || 'post'}" novalidate="#{opts[:include_validation]}">)

    # Process each root property in the schema
    schema["properties"].each do |property_name, property_def|
      # If this is a reference to a definition
      if property_def["$ref"]
        # Extract the definition name from $ref (e.g., "#/definitions/CarShape" -> "CarShape")
        definition_name = property_def["$ref"].split('/').last

        # Get the definition
        definition = schema["definitions"][definition_name]

        if definition
          # Process the definition's properties
          html << generate_fieldset(property_name, property_def, definition, schema["uiSchema"], opts)
        end
      else
        # Direct property definition (less common case)
        html << generate_field(property_name, property_def, schema["uiSchema"], opts)
      end
    end

    # Form buttons
    html << generate_form_buttons(opts)

    # Form closing tag
    html << "</form>"

    # Include JavaScript if requested
    html << generate_javascript(schema, opts) if opts[:include_scripts]

    # Return the complete HTML
    html.join("\n")
  end

  private

  # Generate a fieldset for a complex object
  def self.generate_fieldset(name, property, definition, ui_schema, opts)
    title = property["title"] || definition["title"] || humanize(name)
    description = property["description"] || definition["description"] || ""

    # Use legend for the title in fieldsets
    html = []
    html << %(<fieldset class="#{opts[:fieldset_class] || 'fieldset'}">)
    html << %(<legend>#{title}</legend>)

    # Add description if available
    html << %(<div class="description">#{description}</div>) unless description.empty?

    # Process properties within definition
    properties = get_merged_properties(definition)

    # Get UI order from uiSchema if available
    ui_property = ui_schema && ui_schema[name] ? ui_schema[name] : {}
    property_order = ui_property["ui:order"] || properties.keys

    # Generate fields in order
    property_order.each do |prop_name|
      next unless properties[prop_name]
      html << generate_field(prop_name, properties[prop_name], ui_property, opts)
    end

    html << "</fieldset>"
    html.join("\n")
  end

  # Get merged properties from definition (handles allOf inheritance)
  def self.get_merged_properties(definition)
    if definition["allOf"]
      # Merge properties from all parent schemas
      merged_properties = {}
      definition["allOf"].each do |schema_part|
        if schema_part["properties"]
          merged_properties.merge!(schema_part["properties"])
        end
      end
      merged_properties
    else
      # Direct properties
      definition["properties"] || {}
    end
  end

  # Generate an individual form field
  def self.generate_field(name, property, ui_schema, opts)
    # Get UI options for this field
    ui_field = ui_schema && ui_schema[name] ? ui_schema[name] : {}

    # Determine field type and widget
    field_type = property["type"] || "string"
    widget = ui_field["ui:widget"] || default_widget_for_type(field_type, property)

    # Get field properties
    title = property["title"] || humanize(name)
    description = property["description"] || ""
    required = ui_field["ui:required"] || false
    placeholder = ui_field["ui:placeholder"] || ""
    help_text = ui_field["ui:help"] || description

    # Create field wrapper
    html = []
    html << %(<div class="#{opts[:field_wrapper_class]}" data-field-name="#{name}">)

    # Add label (except for checkboxes which have special handling)
    unless widget == "checkbox"
      required_marker = required ? %( <span class="required">*</span>) : ""
      html << %(<label class="#{opts[:label_class]}" for="#{name}">#{title}#{required_marker}</label>)
    end

    # Generate the appropriate input based on widget type
    case widget
    when "text", "email", "uri", "password"
      html << generate_text_input(name, property, widget, placeholder, required, opts)
    when "textarea"
      html << generate_textarea(name, property, placeholder, required, opts)
    when "select"
      html << generate_select(name, property, required, opts)
    when "radio"
      html << generate_radio_group(name, property, required, opts)
    when "checkbox"
      html << generate_checkbox(name, title, property, required, opts)
    when "date", "datetime"
      html << generate_date_input(name, property, widget, required, opts)
    when "updown", "range"
      html << generate_number_input(name, property, widget, required, opts)
    when "array"
      html << generate_array_input(name, property, ui_field, opts)
    else
      # Default to text input for unknown widgets
      html << generate_text_input(name, property, "text", placeholder, required, opts)
    end

    # Add help text
    html << %(<small class="form-text text-muted">#{help_text}</small>) unless help_text.empty?

    html << "</div>"
    html.join("\n")
  end

  # Generate text input (text, email, url, etc.)
  def self.generate_text_input(name, property, type, placeholder, required, opts)
    default_value = property["default"] || ""
    pattern = property["pattern"] ? %( pattern="#{property["pattern"]}") : ""
    maxlength = property["maxLength"] ? %( maxlength="#{property["maxLength"]}") : ""
    minlength = property["minLength"] ? %( minlength="#{property["minLength"]}") : ""

    %(<input type="#{type}" id="#{name}" name="#{name}" class="#{opts[:input_class]}" value="#{CGI.escapeHTML(default_value.to_s)}"#{pattern}#{maxlength}#{minlength} placeholder="#{placeholder}"#{required ? ' required' : ''}>)
  end

  # Generate textarea
  def self.generate_textarea(name, property, placeholder, required, opts)
    default_value = property["default"] || ""
    maxlength = property["maxLength"] ? %( maxlength="#{property["maxLength"]}") : ""

    %(<textarea id="#{name}" name="#{name}" class="#{opts[:input_class]}"#{maxlength} placeholder="#{placeholder}"#{required ? ' required' : ''}>#{CGI.escapeHTML(default_value.to_s)}</textarea>)
  end

  # Generate select dropdown
  def self.generate_select(name, property, required, opts)
    default_value = property["default"] || ""

    html = []
    html << %(<select id="#{name}" name="#{name}" class="#{opts[:input_class]}"#{required ? ' required' : ''}>)

    if !required
      html << %(<option value="">-- Select --</option>)
    end

    if property["enum"]
      property["enum"].each do |option|
        selected = option.to_s == default_value.to_s ? ' selected' : ''
        label = property["enumNames"] && property["enumNames"][property["enum"].index(option)] || option
        html << %(<option value="#{option}"#{selected}>#{label}</option>)
      end
    end

    html << "</select>"
    html.join("\n")
  end

  # Generate radio button group
  def self.generate_radio_group(name, property, required, opts)
    default_value = property["default"] || ""

    html = []
    html << %(<div class="#{opts[:radio_group_class] || 'radio-group'}">)

    if property["enum"]
      property["enum"].each do |option|
        checked = option.to_s == default_value.to_s ? ' checked' : ''
        label = property["enumNames"] && property["enumNames"][property["enum"].index(option)] || option
        radio_id = "#{name}_#{option.to_s.gsub(/\s+/, '_')}"

        html << %(<div class="#{opts[:radio_item_class] || 'form-check'}">)
        html << %(<input type="radio" id="#{radio_id}" name="#{name}" value="#{option}"#{checked}#{required ? ' required' : ''} class="#{opts[:radio_input_class] || 'form-check-input'}">)
        html << %(<label for="#{radio_id}" class="#{opts[:radio_label_class] || 'form-check-label'}">#{label}</label>)
        html << "</div>"
      end
    end

    html << "</div>"
    html.join("\n")
  end

  # Generate checkbox
  def self.generate_checkbox(name, title, property, required, opts)
    default_value = property["default"] || false
    checked = default_value ? ' checked' : ''

    html = []
    html << %(<div class="#{opts[:checkbox_class] || 'form-check'}">)
    html << %(<input type="checkbox" id="#{name}" name="#{name}" class="#{opts[:checkbox_input_class] || 'form-check-input'}"#{checked}#{required ? ' required' : ''}>)
    html << %(<label class="#{opts[:checkbox_label_class] || 'form-check-label'}" for="#{name}">#{title}</label>)
    html << "</div>"
    html.join("\n")
  end

  # Generate date or datetime input
  def self.generate_date_input(name, property, widget, required, opts)
    default_value = property["default"] || ""
    type = widget == "datetime" ? "datetime-local" : "date"

    %(<input type="#{type}" id="#{name}" name="#{name}" class="#{opts[:input_class]}" value="#{default_value}"#{required ? ' required' : ''}>)
  end

  # Generate number input (spinner or range)
  def self.generate_number_input(name, property, widget, required, opts)
    default_value = property["default"] || 0
    min = property["minimum"] ? %( min="#{property["minimum"]}") : ""
    max = property["maximum"] ? %( max="#{property["maximum"]}") : ""
    step = property["multipleOf"] ? %( step="#{property["multipleOf"]}") : ""

    type = widget == "range" ? "range" : "number"
    %(<input type="#{type}" id="#{name}" name="#{name}" class="#{opts[:input_class]}" value="#{default_value}"#{min}#{max}#{step}#{required ? ' required' : ''}>)
  end

  # Generate array input
  def self.generate_array_input(name, property, ui_field, opts)
    html = []

    # Get UI options
    ui_options = ui_field["ui:options"] || {}
    addable = ui_options["addable"] != false
    removable = ui_options["removable"] != false

    html << %(<div class="array-field" data-field-name="#{name}">)

    # Template container for item
    html << %(<div class="array-items">)

    # If we have a default value, show those items
    default_items = property["default"] || []
    if default_items.any?
      default_items.each_with_index do |item, index|
        html << generate_array_item(name, index, property, item, removable, opts)
      end
    else
      # Always have at least one empty item
      html << generate_array_item(name, 0, property, nil, removable, opts)
    end

    html << "</div>" # End array-items

    # Add button
    if addable
      html << %(<button type="button" class="#{opts[:array_add_class] || 'btn btn-sm btn-outline-secondary'} add-array-item" data-array-field="#{name}">
                  Add Item
                </button>)
    end

    html << "</div>" # End array-field
    html.join("\n")
  end

  # Generate a single array item
  def self.generate_array_item(name, index, property, value, removable, opts)
    html = []
    html << %(<div class="array-item" data-item-index="#{index}">)

    # Handle different item types
    if property["items"] && property["items"]["type"]
      # Simple scalar items
      case property["items"]["type"]
      when "string"
        str_value = value.is_a?(String) ? value : ""
        html << %(<input type="text" name="#{name}[#{index}]" class="#{opts[:input_class]}" value="#{CGI.escapeHTML(str_value)}">)
      when "number", "integer"
        num_value = value.is_a?(Numeric) ? value : 0
        html << %(<input type="number" name="#{name}[#{index}]" class="#{opts[:input_class]}" value="#{num_value}">)
      else
        # Default to text for unknown types
        html << %(<input type="text" name="#{name}[#{index}]" class="#{opts[:input_class]}" value="">)
      end
    elsif property["items"] && property["items"]["$ref"]
      # Complex object items - placeholder for now
      # Would need to resolve the reference and generate a nested form
      html << %(<div class="complex-object-placeholder">[Complex object - see JSONSchema reference]</div>)
    else
      # Default fallback
      html << %(<input type="text" name="#{name}[#{index}]" class="#{opts[:input_class]}" value="">)
    end

    # Remove button
    if removable
      html << %(<button type="button" class="#{opts[:array_remove_class] || 'btn btn-sm btn-outline-danger'} remove-array-item">
                  Remove
                </button>)
    end

    html << "</div>" # End array-item
    html.join("\n")
  end

  # Generate form buttons
  def self.generate_form_buttons(opts)
    html = []
    html << %(<div class="#{opts[:button_group_class] || 'form-buttons'}">)

    # Submit button
    html << %(<button type="submit" class="#{opts[:submit_button_class]}">#{opts[:submit_button_text]}</button>)

    # Cancel button
    if opts[:show_cancel]
      html << %(<button type="button" class="#{opts[:cancel_button_class]}" onclick="window.history.back()">#{opts[:cancel_button_text]}</button>)
    end

    html << "</div>"
    html.join("\n")
  end

  # Determine the default widget for a field type
  def self.default_widget_for_type(type, property)
    case type
    when "string"
      if property["format"] == "date-time"
        "datetime"
      elsif property["format"] == "date"
        "date"
      elsif property["format"] == "email"
        "email"
      elsif property["format"] == "uri"
        "uri"
      elsif property["enum"]
        property["enum"].length > 3 ? "select" : "radio"
      elsif property["maxLength"] && property["maxLength"] > 100
        "textarea"
      else
        "text"
      end
    when "integer", "number"
      "number"
    when "boolean"
      "checkbox"
    when "array"
      "array"
    when "object"
      "fieldset"
    else
      "text"
    end
  end

  # Generate CSS for form
  def self.generate_css(opts)
    case opts[:layout]
    when 'bootstrap'
      # Just include Bootstrap classes, assume Bootstrap is loaded externally
      ""
    when 'basic'
      basic_css
    when 'custom'
      opts[:custom_css] || ""
    else
      basic_css
    end
  end

  # Basic CSS for forms without a framework
  def self.basic_css
    <<-CSS
    <style>
      .shacl-form {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
        max-width: 800px;
        margin: 0 auto;
        padding: 20px;
      }
      
      .form-group {
        margin-bottom: 1rem;
      }
      
      .form-label {
        display: block;
        margin-bottom: 0.5rem;
        font-weight: 500;
      }
      
      .required {
        color: red;
      }
      
      .form-control {
        display: block;
        width: 100%;
        padding: 0.375rem 0.75rem;
        font-size: 1rem;
        line-height: 1.5;
        color: #495057;
        background-color: #fff;
        background-clip: padding-box;
        border: 1px solid #ced4da;
        border-radius: 0.25rem;
        transition: border-color 0.15s ease-in-out, box-shadow 0.15s ease-in-out;
      }
      
      textarea.form-control {
        min-height: 100px;
      }
      
      .btn {
        display: inline-block;
        font-weight: 400;
        text-align: center;
        white-space: nowrap;
        vertical-align: middle;
        user-select: none;
        border: 1px solid transparent;
        padding: 0.375rem 0.75rem;
        font-size: 1rem;
        line-height: 1.5;
        border-radius: 0.25rem;
        cursor: pointer;
      }
      
      .btn-primary {
        color: #fff;
        background-color: #007bff;
        border-color: #007bff;
      }
      
      .btn-secondary {
        color: #fff;
        background-color: #6c757d;
        border-color: #6c757d;
      }
      
      .btn-sm {
        padding: 0.25rem 0.5rem;
        font-size: 0.875rem;
        border-radius: 0.2rem;
      }
      
      .btn-outline-secondary {
        color: #6c757d;
        border-color: #6c757d;
        background-color: transparent;
      }
      
      .btn-outline-danger {
        color: #dc3545;
        border-color: #dc3545;
        background-color: transparent;
      }
      
      .form-buttons {
        margin-top: 1.5rem;
      }
      
      .text-muted {
        color: #6c757d;
      }
      
      .form-text {
        display: block;
        margin-top: 0.25rem;
        font-size: 0.875rem;
      }
      
      .array-field {
        border: 1px solid #e9ecef;
        padding: 1rem;
        border-radius: 0.25rem;
        margin-bottom: 1rem;
      }
      
      .array-item {
        display: flex;
        margin-bottom: 0.5rem;
      }
      
      .array-item input {
        flex: 1;
        margin-right: 0.5rem;
      }
      
      .array-item .remove-array-item {
        flex-shrink: 0;
      }
      
      fieldset {
        padding: 1rem;
        margin-bottom: 1rem;
        border: 1px solid #e9ecef;
        border-radius: 0.25rem;
      }
      
      legend {
        width: auto;
        padding: 0 0.5rem;
        font-size: 1.25rem;
        font-weight: 500;
      }
      
      .form-check {
        position: relative;
        display: block;
        padding-left: 1.25rem;
      }
      
      .form-check-input {
        position: absolute;
        margin-top: 0.3rem;
        margin-left: -1.25rem;
      }
      
      .form-check-label {
        margin-bottom: 0;
      }
      
      .radio-group {
        margin-bottom: 0.5rem;
      }
    </style>
    CSS
  end

  # Generate JavaScript for form interactions
  def self.generate_javascript(schema, opts)
    <<-JAVASCRIPT
    <script>
      document.addEventListener('DOMContentLoaded', function() {
        // Handle form validation
        const form = document.getElementById('#{opts[:form_id]}');
        if (form) {
          form.addEventListener('submit', function(event) {
            if (!form.checkValidity()) {
              event.preventDefault();
              event.stopPropagation();
              // Mark all invalid fields
              Array.from(form.elements).forEach(input => {
                if (!input.validity.valid) {
                  input.classList.add('is-invalid');
                }
              });
            }
            form.classList.add('was-validated');
          });
          
          // Add array item handling
          const addButtons = document.querySelectorAll('.add-array-item');
          addButtons.forEach(button => {
            button.addEventListener('click', function() {
              const fieldName = this.getAttribute('data-array-field');
              const container = document.querySelector(`.array-field[data-field-name="${fieldName}"] .array-items`);
              
              if (container) {
                // Clone the last item
                const lastItem = container.querySelector('.array-item:last-child');
                if (lastItem) {
                  const newItem = lastItem.cloneNode(true);
                  const newIndex = parseInt(lastItem.getAttribute('data-item-index')) + 1;
                  
                  // Update the index
                  newItem.setAttribute('data-item-index', newIndex);
                  
                  // Update input names
                  newItem.querySelectorAll('input, select, textarea').forEach(input => {
                    const name = input.getAttribute('name');
                    if (name) {
                      input.setAttribute('name', name.replace(/\\[(\\d+)\\]/, `[${newIndex}]`));
                      input.value = '';
                    }
                  });
                  
                  // Re-attach remove event
                  const removeButton = newItem.querySelector('.remove-array-item');
                  if (removeButton) {
                    removeButton.addEventListener('click', handleRemoveClick);
                  }
                  
                  // Add the new item to the container
                  container.appendChild(newItem);
                }
              }
            });
          });
          
          // Remove array item handling
          const handleRemoveClick = function() {
            const item = this.closest('.array-item');
            const container = item.parentNode;
            
            // Only remove if there's more than one item
            if (container.querySelectorAll('.array-item').length > 1) {
              container.removeChild(item);
              
              // Renumber remaining items
              Array.from(container.querySelectorAll('.array-item')).forEach((item, index) => {
                item.setAttribute('data-item-index', index);
                
                // Update input names
                item.querySelectorAll('input, select, textarea').forEach(input => {
                  const name = input.getAttribute('name');
                  if (name) {
                    input.setAttribute('name', name.replace(/\\[(\\d+)\\]/, `[${index}]`));
                  }
                });
              });
            }
          };
          
          // Attach remove handlers
          document.querySelectorAll('.remove-array-item').forEach(button => {
            button.addEventListener('click', handleRemoveClick);
          });
        }
      });
    </script>
    JAVASCRIPT
  end

  # Helper to convert snake_case or camelCase to Human Readable
  def self.humanize(string)
    string.to_s
          .gsub(/([A-Z])/, ' \1') # Add space before capital letters
          .gsub(/_/, ' ')         # Replace underscores with spaces
          .gsub(/\s+/, ' ')       # Remove duplicate spaces
          .gsub(/^\s|\s$/, '')    # Remove leading/trailing spaces
          .capitalize             # Capitalize first letter
  end
end