require_relative 'generic'

require 'rdf'
require 'rdf/vocab'

class PlantUMLWriter < Solis::Model::Writer::Generic
  INDENT = "  "

  # Main method to convert a RDF::Repository with SHACL definitions to a PlantUML class diagram
  def self.write(repository, options = {})
    return "No repository provided" if repository.nil?

    # Extract all node shapes from the repository
    shapes = extract_shapes(repository)
    return "No SHACL shapes found in repository" if shapes.empty?

    # Start building the PlantUML diagram
    plantuml = ["@startuml", ""]

    # Add skinparam settings for better styling
    plantuml << "skinparam classAttributeIconSize 0"
    plantuml << "skinparam classFontStyle bold"
    plantuml << "skinparam classFontName Arial"
    plantuml << ""

    # Process each shape
    shapes.each do |shape_uri, shape_data|
      # Add class definition
      class_name = get_class_name(shape_data[:name] || extract_name_from_uri(shape_uri))

      # Start class definition with its description if available
      if shape_data[:description] && !shape_data[:description].empty?
        plantuml << "class #{class_name} << (S,#ADD1B2) SHACL >> {"
      else
        plantuml << "class #{class_name} << (S,#ADD1B2) >> {"
      end

      # Add properties with their datatypes
      if shape_data[:properties] && !shape_data[:properties].empty?
        shape_data[:properties].each do |property|
          property_name = property[:name] || extract_name_from_uri(property[:path])

          # Determine the type - either datatype or class reference
          if property[:datatype]
            property_type = get_data_type(property[:datatype])
          elsif property[:class]
            property_type = get_class_name(extract_name_from_uri(property[:class]))
          else
            property_type = "any"
          end

          # Format cardinality constraints
          cardinality = format_cardinality(property[:min_count], property[:max_count])

          # Add property description as a comment if available
          if property[:description] && !property[:description].empty?
            plantuml << "#{INDENT}' #{property[:description]}"
          end

          plantuml << "#{INDENT}#{property_name} : #{property_type}#{cardinality}"
        end
      end

      plantuml << "}"

      # Add class description as a note if available
      if shape_data[:description] && !shape_data[:description].empty?
        plantuml << "note bottom of #{class_name}"
        plantuml << "#{INDENT}#{shape_data[:description]}"
        plantuml << "end note"
      end

      plantuml << ""
    end

    # Add relationships between classes
    add_relationships(plantuml, shapes)

    # Add legend
    plantuml << "legend right"
    plantuml << "#{INDENT}Created from SHACL definitions"
    plantuml << "#{INDENT}[Required] = minCount >= 1"
    plantuml << "#{INDENT}[Optional] = minCount = 0 or not specified"
    plantuml << "#{INDENT}[*] = maxCount not specified or > 1"
    plantuml << "end legend"

    # End the PlantUML diagram
    plantuml << ""
    plantuml << "@enduml"

    # Return the complete PlantUML diagram
    plantuml.join("\n")
  end

  private

  # Extract all node shapes from the repository
  def self.extract_shapes(repository)
    shapes = {}

    # Find all resources that are defined as NodeShapes
    repository.query([nil, RDF.type, RDF::Vocab::SHACL.NodeShape]) do |statement|
      shape_uri = statement.subject.to_s
      shape_data = { uri: shape_uri, properties: [] }

      # Get shape name
      repository.query([statement.subject, RDF::Vocab::SHACL.name, nil]) do |name_stmt|
        shape_data[:name] = name_stmt.object.to_s
      end

      # Get shape description
      repository.query([statement.subject, RDF::Vocab::SHACL.description, nil]) do |desc_stmt|
        shape_data[:description] = desc_stmt.object.to_s
      end

      # Get target class
      repository.query([statement.subject, RDF::Vocab::SHACL.targetClass, nil]) do |target_stmt|
        shape_data[:target_class] = target_stmt.object.to_s
      end

      # Get superclass
      repository.query([statement.subject, RDF::Vocab::SHACL.node, nil]) do |node_stmt|
        shape_data[:node] = node_stmt.object.to_s
      end

      # Get all property shapes
      repository.query([statement.subject, RDF::Vocab::SHACL.property, nil]) do |prop_stmt|
        property_shape = prop_stmt.object
        property_data = {}

        # Get property path (predicate)
        repository.query([property_shape, RDF::Vocab::SHACL.path, nil]) do |path_stmt|
          property_data[:path] = path_stmt.object.to_s
        end

        # Get property name
        repository.query([property_shape, RDF::Vocab::SHACL.name, nil]) do |name_stmt|
          property_data[:name] = name_stmt.object.to_s
        end

        # Get property description
        repository.query([property_shape, RDF::Vocab::SHACL.description, nil]) do |desc_stmt|
          property_data[:description] = desc_stmt.object.to_s
        end

        # Get datatype
        repository.query([property_shape, RDF::Vocab::SHACL.datatype, nil]) do |type_stmt|
          property_data[:datatype] = type_stmt.object.to_s
        end

        # Get class for object properties
        repository.query([property_shape, RDF::Vocab::SHACL.class, nil]) do |class_stmt|
          property_data[:class] = class_stmt.object.to_s
        end

        # Get nodeKind
        repository.query([property_shape, RDF::Vocab::SHACL.nodeKind, nil]) do |kind_stmt|
          property_data[:node_kind] = kind_stmt.object.to_s
        end

        # Get min cardinality
        repository.query([property_shape, RDF::Vocab::SHACL.minCount, nil]) do |min_stmt|
          property_data[:min_count] = min_stmt.object.to_i
        end

        # Get max cardinality
        repository.query([property_shape, RDF::Vocab::SHACL.maxCount, nil]) do |max_stmt|
          property_data[:max_count] = max_stmt.object.to_i
        end

        shape_data[:properties] << property_data
      end

      shapes[shape_uri] = shape_data
    end

    shapes
  end

  # Add relationships between classes to the diagram
  def self.add_relationships(plantuml, shapes)
    # Add inheritance relationships
    shapes.each do |shape_uri, shape_data|
      if shape_data[:node] && shape_data[:node] != shape_uri
        parent_class = get_class_name(shapes[shape_data[:node]]&.dig(:name) || extract_name_from_uri(shape_data[:node]))
        child_class = get_class_name(shape_data[:name] || extract_name_from_uri(shape_uri))
        plantuml << "#{parent_class} <|-- #{child_class} : inherits"
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

          plantuml << "#{class_name} #{cardinality} #{target_class_name} : #{property_name}"
        end
      end
    end

    # Add a blank line after all relationships
    plantuml << ""
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

  # Clean and format class names for PlantUML
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
    when "http://www.w3.org/1999/02/22-rdf-syntax-ns#JSON"
      "JSON"
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

  # Determine relationship notation for PlantUML
  def self.determine_relationship_cardinality(min_count, max_count)
    if max_count.nil? || max_count > 1
      "\"1\" --* \"*\""  # One-to-many
    elsif min_count == 0
      "\"1\" --o \"0..1\""  # One-to-zero-or-one
    else
      "\"1\" --* \"1\""  # One-to-one
    end
  end
end