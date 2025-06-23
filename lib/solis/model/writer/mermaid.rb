require_relative 'generic'

require 'rdf'
require 'rdf/vocab'

class MermaidWriter < Solis::Model::Writer::Generic
  INDENT = "  "

  # Main method to convert a RDF::Repository with SHACL definitions to a Mermaid class diagram
  def self.write(repository, options = {})
    return "No repository provided" if repository.nil?
    return "options[:shapes] missing" unless options.key?(:shapes)

    shapes = adapt_parse_shapes_to_extract_shapes_format(options[:shapes])

    if shapes.empty?
      return "No SHACL shapes found in repository"
    end

    # Rest of the method remains the same...
    # Start building the Mermaid diagram
    mermaid = ["classDiagram"]

    # Process each shape
    shapes.each do |shape_uri, shape_data|
      # Add class definition
      class_name = get_class_name(shape_data[:name] || extract_name_from_uri(shape_uri))
      mermaid << "#{INDENT}class #{class_name} {"

      # Add properties with their datatypes
      if shape_data[:properties] && !shape_data[:properties].empty?
        shape_data[:properties].each do |property|
          property_name = property[:name] || extract_name_from_uri(property[:path])
          property_type = get_data_type(property[:datatype])

          # Format cardinality constraints
          cardinality = format_cardinality(property[:min_count], property[:max_count])
          mermaid << "#{INDENT}#{INDENT}#{property_name} : #{property_type}#{cardinality}"
        end
      end

      mermaid << "#{INDENT}}"

      # Add class description as a note if available
      if shape_data[:description] && !shape_data[:description].empty?
        mermaid << "#{INDENT}note for #{class_name} \"#{shape_data[:description].gsub('"', '\\"')}\""
      end
    end

    # Add relationships between classes
    add_relationships(mermaid, shapes)

    # Return the complete Mermaid diagram
    mermaid = mermaid.join("\n")
    mermaid = get_link(mermaid) if options.key?(:link) && options[:link]
    mermaid
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
          class: property_info.dig(:constraints, :class)
        }

        adapted_shapes[shape_uri][:properties] << adapted_property
      end
    end

    adapted_shapes
  end

  # Add relationships between classes to the diagram
  def self.add_relationships(mermaid, shapes)
    # Add inheritance relationships
    shapes.each do |shape_uri, shape_data|
      if shape_data[:node] && shape_data[:node] != shape_uri
        parent_class = get_class_name(shapes[shape_data[:node]]&.dig(:name) || extract_name_from_uri(shape_data[:node]))
        child_class = get_class_name(shape_data[:name] || extract_name_from_uri(shape_uri))
        mermaid << "#{INDENT}#{parent_class} <|-- #{child_class} : inherits"
      end
    end

    # Add object property relationships
    shapes.each do |shape_uri, shape_data|
      class_name = get_class_name(shape_data[:name] || extract_name_from_uri(shape_uri))

      shape_data[:properties].each do |property|
        # Check if this is an object property (has a class reference)
        if property[:class]
          target_class_name = nil

          # Find the shape that has this class as its target class
          shapes.each do |_, other_shape|
            if other_shape[:target_class] == property[:class]
              target_class_name = get_class_name(other_shape[:name] || extract_name_from_uri(other_shape[:uri]))
              break
            end
          end

          # If no matching shape found, use the URI's local name
          target_class_name ||= get_class_name(extract_name_from_uri(property[:class]))
          property_name = property[:name] || extract_name_from_uri(property[:path])

          # Determine cardinality for relationship
          cardinality = determine_relationship_cardinality(property[:min_count], property[:max_count])

          mermaid << "#{INDENT}#{class_name} #{cardinality} #{target_class_name} : #{property_name}"
        end
      end
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

  # Clean and format class names for Mermaid
  def self.get_class_name(name)
    return "UnnamedClass" if name.nil? || name.empty?

    # Remove spaces and special characters, capitalize first letter
    name.gsub(/[^a-zA-Z0-9_]/, '_').gsub(/^([a-z])/) { $1.upcase }
  end

  # Convert RDF datatype URIs to simple type names
  def self.get_data_type(datatype)
    return "any" unless datatype

    case datatype
    when RDF::XSD.string.to_s, "http://www.w3.org/2001/XMLSchema#string"
      "String"
    when RDF::XSD.integer.to_s, "http://www.w3.org/2001/XMLSchema#integer"
      "Integer"
    when RDF::XSD.decimal.to_s, "http://www.w3.org/2001/XMLSchema#decimal"
      "Decimal"
    when RDF::XSD.boolean.to_s, "http://www.w3.org/2001/XMLSchema#boolean"
      "Boolean"
    when RDF::XSD.date.to_s, "http://www.w3.org/2001/XMLSchema#date"
      "Date"
    when RDF::XSD.time.to_s, "http://www.w3.org/2001/XMLSchema#time"
      "Time"
    when RDF::XSD.dateTime.to_s, "http://www.w3.org/2001/XMLSchema#dateTime"
      "DateTime"
    when RDF::XSD.anyURI.to_s, "http://www.w3.org/2001/XMLSchema#anyURI"
      "URI"
    else
      # For other datatypes, extract the local name
      extract_name_from_uri(datatype)
    end
  end

  # Format cardinality constraints for properties
  def self.format_cardinality(min_count, max_count)
    if min_count && max_count
      if min_count == 0 && max_count == 1
        " [Optional]"
      elsif min_count >= 1 && max_count == 1
        " [Required]"
      elsif max_count.nil? || max_count > 1
        " [*]"
      else
        " [#{min_count}..#{max_count}]"
      end
    elsif min_count && min_count >= 1
      " [Required]"
    elsif max_count && max_count == 1
      " [Optional]"
    else
      ""
    end
  end

  # Determine cardinality notation for Mermaid relationships
  def self.determine_relationship_cardinality(min_count, max_count)
    if max_count.nil? || max_count > 1
      "--o \"*\"" # Many
    elsif min_count == 0
      "--o \"0..1\"" # Optional
    else
      "--o \"1\"" # One
    end
  end

  def self.get_link(diagram)
    json_graph = {
      "code": diagram,
      "mermaid": { "theme": "default" }
    }

    encoded = Base64.strict_encode64(pako_deflate(JSON.generate(json_graph).b)).force_encoding('ASCII-8BIT').encode('ASCII-8BIT')
    "http://mermaid.live/view#pako:#{encoded}"
  end

  def self.pako_deflate(data)
    z = Zlib::Deflate.new(9, Zlib::MAX_WBITS, 8, Zlib::DEFAULT_STRATEGY)
    compressed_data = z.deflate(data, Zlib::FINISH)
    z.close
    compressed_data
  end
end