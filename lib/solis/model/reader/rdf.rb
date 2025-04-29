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
            shape_subclass_of = shape_subclass_of.nil? ? class_uri : RDF::URI.new("#{shape_subclass_of}Shape")

            shacl_graph << [shape, RDF.type, RDF::Vocab::SHACL.NodeShape]
            shacl_graph << [shape, RDF::Vocab::SHACL.name, class_name] #class_uri.path.split('/').last]
            shacl_graph << [shape, RDF::Vocab::SHACL.targetClass, class_uri]
            shacl_graph << [shape, RDF::Vocab::SHACL.node, shape_subclass_of] if shape_subclass_of
            shacl_graph << [shape, RDF::Vocab::SHACL.description, shape_definition]

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
              shacl_graph << [property_shape, RDF::Vocab::SHACL.description, property_definition]

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
          end

          shacl_graph
        end
        
        def self.is_rdf?(graph)
          graph.query([nil, RDF.type, RDF::OWL.Class]).size > 0
        end
        private

        def self.safe_class_name(name)
          name = name.split("#").last || name.split("/").last
          RESERVED_WORDS.include?(name) ? "#{name}Class" : name
        end
      end
    end
  end
end

