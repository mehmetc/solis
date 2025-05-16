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
            #graph = RDF::Graph.load(ontology)
            graph = RDF::Repository.load(ontology)
          else
            graph = ontology
          end

          #shacl_graph = RDF::Graph.new
          shacl_graph = RDF::Repository.new
          shacl_graph.graph_name = graph.graph_name if graph.named?
          graph.query([nil, RDF.type, RDF::OWL.Class]).each do |stmt|
            class_uri = stmt.subject
            class_name = safe_class_name(class_uri.to_s)
            shape = RDF::URI.new("#{class_uri}Shape")

            shape_definition = graph.first_object([class_uri, RDF::Vocab::SKOS.definition, nil])
            shape_subclass_of = graph.first_object([class_uri, RDF::RDFS.subClassOf, nil])
            shape_subclass_of = nil unless graph.first_subject([shape_subclass_of, RDF.type, RDF::OWL.Restriction]).nil?
            shape_subclass_of = shape_subclass_of.nil? ? class_uri : RDF::URI.new("#{shape_subclass_of}Shape")

            shacl_graph << [shape, RDF.type, RDF::Vocab::SHACL.NodeShape]
            shacl_graph << [shape, RDF::Vocab::SHACL.name, class_name] #class_uri.path.split('/').last]
            shacl_graph << [shape, RDF::Vocab::SHACL.targetClass, class_uri]
            shacl_graph << [shape, RDF::Vocab::SHACL.node, shape_subclass_of] if shape_subclass_of
            shacl_graph << [shape, RDF::Vocab::SHACL.description, shape_definition] if shape_definition

            # Extract properties associated with this class
            graph.query([nil, RDF::RDFS.domain, class_uri]).each do |property_stmt|
              property = property_stmt.subject
              range = graph.first_object([property, RDF::RDFS.range])
              domain = graph.first_object([property, RDF::RDFS.domain])
              property_definition = graph.first_object([property, RDF::Vocab::SKOS.definition, nil])
              property_type = graph.first_object([property, RDF.type])
              property_name = safe_class_name(property.to_s)
              sub_property_of = graph.first_object([property, RDF::RDFS.subPropertyOf])

              property_shape = RDF::Node.new
              shacl_graph << [shape, RDF::Vocab::SHACL.property, property_shape]
              shacl_graph << [property_shape, RDF::Vocab::SHACL.name, property_name]# property.path.split('/').last]
              shacl_graph << [property_shape, RDF::Vocab::SHACL.path, property]
              shacl_graph << [property_shape, RDF::Vocab::SHACL.description, property_definition] if property_definition

              # Add range constraints if available
              # if range
              #   if range.to_s.start_with?("http://www.w3.org/2001/XMLSchema#")
              #     shacl_graph << [property_shape, RDF::Vocab::SHACL.datatype, range]
              #     # Add sh:pattern for string literals as an example
              #     if range == RDF::XSD.string
              #       shacl_graph << [property_shape, RDF::Vocab::SHACL.pattern, "^.+$"]
              #     end
              #   else
              #     if range == RDF::RDFS.Literal
              #       shacl_graph << [property_shape, RDF::Vocab::SHACL.datatype, RDF::XSD.string]
              #     else
              #       shacl_graph << [property_shape, RDF::Vocab::SHACL.class, range]
              #       shacl_graph << [property_shape, RDF::Vocab::SHACL.nodeKind, RDF::Vocab::SHACL.IRI]
              #     end
              #   end
              # end

              # Determine property type
              if property_type == RDF::OWL.ObjectProperty
                shacl_graph << [property_shape, RDF::Vocab::SHACL.nodeKind, RDF::Vocab::SHACL.IRI]
                shacl_graph << [property_shape, RDF::Vocab::SHACL.class, range] if range
              elsif property_type == RDF::OWL.DatatypeProperty
                if sub_property_of
                  #shacl_graph << [property_shape, RDF::Vocab::SHACL.nodeKind, RDF::Vocab::SHACL.IRI]
                  shacl_graph << [property_shape, RDF::Vocab::SHACL.datatype, sub_property_of]
                else
                  if range
                    if range == RDF::RDFS.Literal
                      #shacl_graph << [property_shape, RDF::Vocab::SHACL.nodeKind, RDF::Vocab::SHACL.Literal]
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
                    #shacl_graph << [property_shape, RDF::Vocab::SHACL.nodeKind, RDF::Vocab::SHACL.Literal]
                    shacl_graph << [property_shape, RDF::Vocab::SHACL.datatype, RDF::XSD.string]
                  end
                end
              end

              if domain && range.nil?
                shacl_graph << [property_shape, RDF::Vocab::SHACL.class, domain]
                shacl_graph << [property_shape, RDF::Vocab::SHACL.nodeKind, RDF::Vocab::SHACL.IRI]
              end

              # Default constraints (adjust as needed)
              # shacl_graph << [property_shape, RDF::Vocab::SHACL.minCount, 0]
              # shacl_graph << [property_shape, RDF::Vocab::SHACL.maxCount, 1]
            end

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
                property_shape = property_shape_stmt.object
                property_shape = shacl_graph.first_subject([property_shape, RDF::Vocab::SHACL.name, property_name])
              end
              # if empty, make it;
              # reason for not existing is not being created earlier
              # (not coming from either owl:ObjectProperty or owl:DatatypeProperty)
              if property_shape.nil?
                property_shape = RDF::Node.new
                shacl_graph << [shape, RDF::Vocab::SHACL.property, property_shape]
                shacl_graph << [property_shape, RDF::Vocab::SHACL.name, property_name]# property.path.split('/').last]
                shacl_graph << [property_shape, RDF::Vocab::SHACL.path, property]
              end
              # add cardinality
              unless property_shape.nil?  # this can be removed
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
                    owl_datatype = object   # TODO: must check if it is a Datatype ...
                    add_owl_datatype_with_restrictions_to_property_shape(graph, owl_datatype, shacl_graph, property_shape)
                  end
                end
              end
            end

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
          name = name.split("#").last || name.split("/").last
          RESERVED_WORDS.include?(name) ? "#{name}Class" : name
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

        def self.parse_owl_list(list, graph, owl_list)
          # parses this: https://www.w3.org/TR/owl-ref/#EnumeratedDatatype
          # maybe there is a utility in RDF to do so ...
          first = graph.first_object([owl_list, RDF.first])
          list << first if first
          rest = graph.first_object([owl_list, RDF.rest])
          parse_owl_list(list, graph, rest) if rest
        end

      end
    end
  end
end

