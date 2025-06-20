require 'data_collector/config_file'
require 'linkeddata'

=begin
|Property Type        |Links|Example|
|owl:ObjectProperty   |Individual → Individual|ex:hasAuthor (Book → Person)|
|owl:DatatypeProperty |Individual → Literal   |ex:publicationYear (Book → xsd:integer)|
|owl:SymmetricProperty|A ↔ B (Both Directions)|ex:isMarriedTo (Person ↔ Person)|
=end

module Solis
  class Model
    class Reader
      class Rdf
        # Reserved Ruby keywords to avoid conflicts
        RESERVED_WORDS = %w[Object Class Module End Begin If Else Def]

        def self.read(ontology)
          if ontology.is_a?(String)
            graph = RDF::Repository.load(ontology)
          else
            graph = ontology
          end

          # shacl_graph = RDF::Graph.new
          shacl_graph = RDF::Repository.new
          shacl_graph.graph_name = graph.graph_name if graph.named?

          # First pass: collect all properties that should be added to all classes
          universal_properties = collect_universal_properties(graph)

          # Create a base shape with all universal properties
          base_shape = create_universal_base_shape(graph, universal_properties, shacl_graph)

          graph.query([nil, RDF.type, RDF::OWL.Class]).each do |stmt|
            class_uri = stmt.subject

            # Skip blank node classes - they're usually complex constructs like unionOf
            # that shouldn't become direct SHACL node shapes
            next if class_uri.is_a?(RDF::Node)

            class_name = safe_class_name(class_uri.to_s)
            shape = RDF::URI.new("#{class_uri}Shape")

            shape_definition = graph.first_object([class_uri, RDF::Vocab::SKOS.definition, nil])
            shape_subclass_of = graph.first_object([class_uri, RDF::RDFS.subClassOf, nil])
            shape_subclass_of = nil unless graph.first_subject([shape_subclass_of, RDF.type, RDF::OWL.Restriction]).nil?
            shape_subclass_of = shape_subclass_of.nil? ? class_uri : RDF::URI.new("#{shape_subclass_of}Shape")

            shacl_graph << [shape, RDF.type, RDF::Vocab::SHACL.NodeShape]
            shacl_graph << [shape, RDF::Vocab::SHACL.name, class_name] # class_uri.path.split('/').last]
            shacl_graph << [shape, RDF::Vocab::SHACL.targetClass, class_uri]
            shacl_graph << [shape, RDF::Vocab::SHACL.node, shape_subclass_of] if shape_subclass_of
            shacl_graph << [shape, RDF::Vocab::SHACL.description, shape_definition] if shape_definition

            # Reference the universal base shape for common properties
            shacl_graph << [shape, RDF::Vocab::SHACL.node, base_shape] if base_shape

            # Extract properties with explicit domain for this class
            graph.query([nil, RDF::RDFS.domain, class_uri]).each do |property_stmt|
              add_property_to_shape(graph, property_stmt.subject, class_uri, shape, shacl_graph)
            end

            # Handle properties with unionOf domains that include this class
            handle_union_domain_properties(graph, class_uri, shape, shacl_graph)

            # add:
            # - Cardinality Constraint Components
            # - sh:hasValue
            # - Value Range Constraint Components
            # - String-based Constraint Components
            graph.query([class_uri, RDF::RDFS.subClassOf, nil]).each do |restriction_stmt|
              next if graph.first_subject([restriction_stmt.object, RDF.type, RDF::OWL.Restriction]).nil?
              # get restriction property target
              restriction = restriction_stmt.object
              property = graph.first_object([restriction, RDF::OWL.onProperty])
              next if property.nil?
              property_name = safe_class_name(property.to_s)
              # search for "property_shape" whose "sh:name" is "property_name", and associated to "shape",
              # i.e. find property shape that matches pattern:
              # shape - sh:property - property_shape - sh:name - property_name
              property_shape = nil
              shacl_graph.query([shape, RDF::Vocab::SHACL.property, nil]) do |property_shape_stmt|
                next unless property_shape.nil?
                candidate_shape = property_shape_stmt.object
                shape_name = shacl_graph.first_object([candidate_shape, RDF::Vocab::SHACL.name])
                if shape_name && shape_name.value == property_name
                  property_shape = candidate_shape
                end
              end
              # if empty, make it;
              # reason for not existing is not being created earlier
              # (not coming from either owl:ObjectProperty or owl:DatatypeProperty)
              if property_shape.nil?
                property_shape = RDF::Node.new
                shacl_graph << [shape, RDF::Vocab::SHACL.property, property_shape]
                shacl_graph << [property_shape, RDF::Vocab::SHACL.name, property_name] # property.path.split('/').last]
                shacl_graph << [property_shape, RDF::Vocab::SHACL.path, property]
              end
              # add cardinality
              unless property_shape.nil? # this can be removed
                graph.query([restriction, nil, nil]).each do |restriction_info_stmt|
                  predicate = restriction_info_stmt.predicate
                  object = restriction_info_stmt.object
                  case predicate
                  when RDF::OWL.cardinality
                    cardinality = RDF::Literal(object.value, datatype: 'http://www.w3.org/2001/XMLSchema#integer')
                    shacl_graph << [property_shape, RDF::Vocab::SHACL.minCount, cardinality]
                    shacl_graph << [property_shape, RDF::Vocab::SHACL.maxCount, cardinality]
                  when RDF::OWL.minCardinality
                    min_cardinality = RDF::Literal(object.value, datatype: 'http://www.w3.org/2001/XMLSchema#integer')
                    # add to property shape
                    shacl_graph << [property_shape, RDF::Vocab::SHACL.minCount, min_cardinality]
                  when RDF::OWL.maxCardinality
                    max_cardinality = RDF::Literal(object.value, datatype: 'http://www.w3.org/2001/XMLSchema#integer')
                    # add to property shape
                    shacl_graph << [property_shape, RDF::Vocab::SHACL.maxCount, max_cardinality]
                  when RDF::OWL.hasValue
                    has_value = object
                    # add to property shape
                    shacl_graph << [property_shape, RDF::Vocab::SHACL.hasValue, has_value]
                  when RDF::OWL.someValuesFrom
                    # Check if someValuesFrom refers to a unionOf
                    if graph.first_object([object, RDF::OWL.unionOf])
                      add_union_constraint_to_property_shape(graph, object, shacl_graph, property_shape)
                    else
                      owl_datatype = object # TODO: must check if it is a Datatype ...
                      add_owl_datatype_with_restrictions_to_property_shape(graph, owl_datatype, shacl_graph, property_shape)
                    end
                  when RDF::OWL.allValuesFrom
                    # Check if allValuesFrom refers to a unionOf
                    if graph.first_object([object, RDF::OWL.unionOf])
                      add_union_constraint_to_property_shape(graph, object, shacl_graph, property_shape)
                    else
                      # Handle regular allValuesFrom constraint
                      if object.to_s.start_with?("http://www.w3.org/2001/XMLSchema#")
                        shacl_graph << [property_shape, RDF::Vocab::SHACL.datatype, object]
                      else
                        shacl_graph << [property_shape, RDF::Vocab::SHACL.class, object]
                      end
                    end
                  end
                end
              end
            end
          end

          extract_metadata(graph).each_statement do |statement|
            shacl_graph << statement
          end

          shacl_graph
        rescue Solis::Error::General => e
          raise e
        end

        def self.is_rdf?(graph)
          graph.query([nil, RDF.type, RDF::OWL.Class]).size > 0
        end

        private

        def self.safe_class_name(name)
          name = name.split("#").last =~ /^http/ ? name.split("/").last : name.split("#").last
          RESERVED_WORDS.include?(name) ? "#{name}Class" : name
        end

        # Create a base shape containing all universal properties
        def self.create_universal_base_shape(graph, universal_properties, shacl_graph)
          return nil if universal_properties.empty?

          # Create base shape URI - use graph namespace if available, otherwise generic
          base_namespace = graph.graph_name || "http://solis.libis.be/shapes/"
          base_shape = RDF::URI.new("#{base_namespace}UniversalPropertiesShape")

          # Define the base shape
          shacl_graph << [base_shape, RDF.type, RDF::Vocab::SHACL.NodeShape]
          shacl_graph << [base_shape, RDF::Vocab::SHACL.name, "UniversalProperties"]
          shacl_graph << [base_shape, RDF::Vocab::SHACL.description, "Base shape containing properties that can be applied to any resource"]

          # Add all universal properties to the base shape
          universal_properties.each do |property|
            add_property_to_shape(graph, property, RDF::RDFS.Resource, base_shape, shacl_graph)
          end

          base_shape
        end

        # Collect properties that should be available to all classes
        def self.collect_universal_properties(graph)
          universal_properties = []

          # Find all ObjectProperties and DatatypeProperties
          all_properties = []
          graph.query([nil, RDF.type, RDF::OWL.ObjectProperty]).each { |stmt| all_properties << stmt.subject }
          graph.query([nil, RDF.type, RDF::OWL.DatatypeProperty]).each { |stmt| all_properties << stmt.subject }

          all_properties.each do |property|
            domain = graph.first_object([property, RDF::RDFS.domain])

            # Include properties with no domain or domain rdfs:Resource
            if domain.nil? || domain == RDF::RDFS.Resource
              universal_properties << property
            elsif domain.is_a?(RDF::Node)
              # Check if it's a unionOf that contains very general classes
              union_list = graph.first_object([domain, RDF::OWL.unionOf])
              if union_list
                union_members = []
                parse_owl_list(union_members, graph, union_list)

                # If the union contains very broad classes like rdfs:Resource, consider it universal
                if union_members.include?(RDF::RDFS.Resource) ||
                  union_members.length > 3 # Heuristic: if many classes, likely meant to be broad
                  universal_properties << property
                end
              end
            end
          end

          universal_properties
        end

        # New method to handle owl:unionOf constructs
        def self.add_union_constraint_to_property_shape(graph, union_class, shacl_graph, property_shape)
          union_list = graph.first_object([union_class, RDF::OWL.unionOf])
          return unless union_list

          # Parse the union list to get all possible types/classes
          union_members = []
          parse_owl_list(union_members, graph, union_list)

          return if union_members.empty?

          # Create sh:or constraint with multiple alternatives
          or_constraint_list = create_shacl_or_constraint(union_members, shacl_graph)
          shacl_graph << [property_shape, RDF::Vocab::SHACL.or, or_constraint_list]
        end

        # Helper method to create SHACL sh:or constraint from union members
        def self.create_shacl_or_constraint(union_members, shacl_graph)
          # Create a list of shape constraints for each union member
          constraint_nodes = union_members.map do |member|
            constraint_node = RDF::Node.new

            if member.to_s.start_with?("http://www.w3.org/2001/XMLSchema#")
              # It's a datatype
              shacl_graph << [constraint_node, RDF::Vocab::SHACL.datatype, member]
            else
              # It's a class
              shacl_graph << [constraint_node, RDF::Vocab::SHACL.class, member]
              shacl_graph << [constraint_node, RDF::Vocab::SHACL.nodeKind, RDF::Vocab::SHACL.IRI]
            end

            constraint_node
          end

          # Create RDF list from constraint nodes
          create_rdf_list(constraint_nodes, shacl_graph)
        end

        # Helper method to create RDF list structure
        def self.create_rdf_list(items, shacl_graph)
          return RDF.nil if items.empty?

          list_head = RDF::Node.new
          current_node = list_head

          items.each_with_index do |item, index|
            shacl_graph << [current_node, RDF.first, item]

            if index == items.length - 1
              # Last item points to rdf:nil
              shacl_graph << [current_node, RDF.rest, RDF.nil]
            else
              # Create next node in the list
              next_node = RDF::Node.new
              shacl_graph << [current_node, RDF.rest, next_node]
              current_node = next_node
            end
          end

          list_head
        end

        def self.add_owl_datatype_with_restrictions_to_property_shape(graph, owl_datatype, shacl_graph, property_shape)
          with_restrictions = graph.first_object([owl_datatype, RDF::OWL.withRestrictions, nil])
          list = []
          parse_owl_list(list, graph, with_restrictions)
          list.each do |el|
            graph.query([el, nil, nil]) do |stmt|
              case stmt.predicate
              when RDF::Vocab::XSD.minExclusive
                shacl_graph << [property_shape, RDF::Vocab::SHACL.minExclusive, stmt.object]
              when RDF::Vocab::XSD.minInclusive
                shacl_graph << [property_shape, RDF::Vocab::SHACL.minInclusive, stmt.object]
              when RDF::Vocab::XSD.maxExclusive
                shacl_graph << [property_shape, RDF::Vocab::SHACL.maxExclusive, stmt.object]
              when RDF::Vocab::XSD.maxInclusive
                shacl_graph << [property_shape, RDF::Vocab::SHACL.maxInclusive, stmt.object]
              when RDF::Vocab::XSD.minLength
                shacl_graph << [property_shape, RDF::Vocab::SHACL.minLength, stmt.object]
              when RDF::Vocab::XSD.maxLength
                shacl_graph << [property_shape, RDF::Vocab::SHACL.maxLength, stmt.object]
              when RDF::Vocab::XSD.length
                shacl_graph << [property_shape, RDF::Vocab::SHACL.minLength, stmt.object]
                shacl_graph << [property_shape, RDF::Vocab::SHACL.maxLength, stmt.object]
              when RDF::Vocab::XSD.pattern
                shacl_graph << [property_shape, RDF::Vocab::SHACL.pattern, stmt.object]
              else
                if stmt.predicate.to_s.eql?('http://www.w3.org/1999/02/22-rdf-syntax-ns#langRange')
                  # https://www.w3.org/TR/2012/REC-owl2-syntax-20121211/#Strings
                  shacl_graph << [property_shape, RDF::Vocab::SHACL.languageIn, stmt.object]
                end
              end
            end
          end
        end

        # Extract method for adding a property to a shape
        def self.add_property_to_shape(graph, property, domain_class, shape, shacl_graph)
          range = graph.first_object([property, RDF::RDFS.range])
          domain = graph.first_object([property, RDF::RDFS.domain])
          property_definition = graph.first_object([property, RDF::Vocab::SKOS.definition, nil])
          property_type = graph.first_object([property, RDF.type])
          property_name = safe_class_name(property.to_s)
          sub_property_of = graph.first_object([property, RDF::RDFS.subPropertyOf])

          property_shape = RDF::Node.new
          shacl_graph << [shape, RDF::Vocab::SHACL.property, property_shape]
          shacl_graph << [property_shape, RDF::Vocab::SHACL.name, property_name]
          shacl_graph << [property_shape, RDF::Vocab::SHACL.path, property]
          shacl_graph << [property_shape, RDF::Vocab::SHACL.description, property_definition] if property_definition

          # Check if range is a unionOf construct
          if range && graph.first_object([range, RDF::OWL.unionOf])
            add_union_constraint_to_property_shape(graph, range, shacl_graph, property_shape)
          elsif property_type == RDF::OWL.ObjectProperty
            shacl_graph << [property_shape, RDF::Vocab::SHACL.nodeKind, RDF::Vocab::SHACL.IRI]
            shacl_graph << [property_shape, RDF::Vocab::SHACL.class, range] if range
          elsif property_type == RDF::OWL.DatatypeProperty
            if sub_property_of
              # Look up the range of the parent property instead of using the property URI as datatype
              parent_range = graph.first_object([sub_property_of, RDF::RDFS.range])
              if parent_range
                if parent_range == RDF::RDFS.Literal
                  shacl_graph << [property_shape, RDF::Vocab::SHACL.datatype, RDF::XSD.string]
                elsif parent_range.to_s.start_with?("http://www.w3.org/2001/XMLSchema#")
                  shacl_graph << [property_shape, RDF::Vocab::SHACL.datatype, parent_range]
                else
                  # Custom datatype or class - use as is
                  shacl_graph << [property_shape, RDF::Vocab::SHACL.datatype, parent_range]
                end
              else
                # Fallback to string if no range found on parent
                shacl_graph << [property_shape, RDF::Vocab::SHACL.datatype, RDF::XSD.string]
              end
            else
              if range
                if range == RDF::RDFS.Literal
                  shacl_graph << [property_shape, RDF::Vocab::SHACL.datatype, RDF::XSD.string]
                elsif range.to_s.start_with?("http://www.w3.org/2001/XMLSchema#")
                  shacl_graph << [property_shape, RDF::Vocab::SHACL.datatype, range]
                  shacl_graph << [property_shape, RDF::Vocab::SHACL.pattern, "^.+$"] if range == RDF::XSD.string
                else
                  # TODO, when ontologies are found, add:
                  # - https://www.w3.org/TR/owl-ref/#EnumeratedDatatype
                  # - https://stackoverflow.com/questions/14172610/how-to-define-my-own-ranges-for-owl-dataproperties/14173705#14173705
                end
              else
                shacl_graph << [property_shape, RDF::Vocab::SHACL.datatype, RDF::XSD.string]
              end
            end
          end

          if domain && range.nil?
            shacl_graph << [property_shape, RDF::Vocab::SHACL.class, domain]
            shacl_graph << [property_shape, RDF::Vocab::SHACL.nodeKind, RDF::Vocab::SHACL.IRI]
          end
        end

        # Handle properties that have unionOf domains
        def self.handle_union_domain_properties(graph, class_uri, shape, shacl_graph)
          # Find all properties and check their domains
          graph.query([nil, RDF.type, RDF::OWL.ObjectProperty]).each do |property_stmt|
            check_and_add_union_property(graph, property_stmt.subject, class_uri, shape, shacl_graph)
          end

          graph.query([nil, RDF.type, RDF::OWL.DatatypeProperty]).each do |property_stmt|
            check_and_add_union_property(graph, property_stmt.subject, class_uri, shape, shacl_graph)
          end
        end

        # Helper method to check if a property has a unionOf domain that includes our class
        def self.check_and_add_union_property(graph, property, class_uri, shape, shacl_graph)
          domain = graph.first_object([property, RDF::RDFS.domain])
          return unless domain

          # Skip if domain is directly our class (already handled by main loop)
          return if domain == class_uri

          # Check if domain is a blank node with owl:unionOf
          union_list = graph.first_object([domain, RDF::OWL.unionOf])
          return unless union_list

          # Parse the union list to see if our class is included
          union_members = []
          parse_owl_list(union_members, graph, union_list)

          # If this class is in the union, add the property to this shape
          if union_members.include?(class_uri)
            # Check if we've already added this property to avoid duplicates
            existing_property = shacl_graph.query([shape, RDF::Vocab::SHACL.property, nil]).find do |stmt|
              prop_shape = stmt.object
              path = shacl_graph.first_object([prop_shape, RDF::Vocab::SHACL.path])
              path == property
            end

            # Only add if not already present
            unless existing_property
              add_property_to_shape(graph, property, class_uri, shape, shacl_graph)
            end
          end
        end

        def self.parse_owl_list(list, graph, owl_list)
          # parses this: https://www.w3.org/TR/owl-ref/#EnumeratedDatatype
          # maybe there is a utility in RDF to do so ...
          return if owl_list == RDF.nil

          first = graph.first_object([owl_list, RDF.first])
          list << first if first
          rest = graph.first_object([owl_list, RDF.rest])
          parse_owl_list(list, graph, rest) if rest && rest != RDF.nil
        end

        def self.extract_metadata(graph)
          metadata_graph = RDF::Graph.new
          graph.query([nil, RDF.type, RDF::Vocab::OWL.Ontology]) do |statement|
            metadata_graph << [statement.subject, RDF.type, RDF::Vocab::OWL.Ontology]
            graph.query([statement.subject, nil, nil]) do |metadata_statement|
              case metadata_statement.predicate
              when RDF::Vocab::DC.title
                metadata_graph << [statement.subject, metadata_statement.predicate, metadata_statement.object]

              when RDF::Vocab::DC.description
                metadata_graph << [statement.subject, metadata_statement.predicate, metadata_statement.object]
              when RDF::Vocab::DC.creator
                metadata_graph << [statement.subject, metadata_statement.predicate, metadata_statement.object]
              when RDF::Vocab::OWL.versionInfo
                metadata_graph << [statement.subject, metadata_statement.predicate, metadata_statement.object]
              end
            end

            metadata_graph
          end
          metadata_graph
        end
      end
    end
  end
end