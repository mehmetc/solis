require 'json'
require 'linkeddata'

module Solis
  class Model
    class Reader
      class JSONEntities

        def self.read(data_in)
          if data_in.is_a?(String)
            data = JSON.parse(data_in)
          else
            data = data_in
          end

          shacl_graph = RDF::Repository.new

          # Add metadata

          graph_namespace = data['namespace']
          graph_title = data['title']
          graph_version = data['version']
          graph_version_counter = data['version_counter']
          graph_description = data['description']

          metadata_node = RDF::URI(graph_namespace)

          shacl_graph << [metadata_node, RDF::Vocab::DC.title, graph_title]
          shacl_graph << [metadata_node, RDF::Vocab::OWL.versionInfo, graph_version]
          shacl_graph << [metadata_node, RDF::URI(Solis::Model::Entity::URI_DB_OPTIMISTIC_LOCK_VERSION), graph_version_counter]
          shacl_graph << [metadata_node, RDF::Vocab::DC.title, graph_description]

          # Add entities

          entities = data['entities']

          entities.each do |name_entity, data_entity|

            # Add node shape

            class_uri = name_entity

            name = Solis::Utils::String.extract_name_from_uri(class_uri)
            description = data_entity['description']
            plural = data_entity['plural']
            direct_parents = data_entity['direct_parents']

            shape = RDF::URI.new("#{class_uri}Shape")

            shacl_graph << [shape, RDF.type, RDF::Vocab::SHACL.NodeShape]
            shacl_graph << [shape, RDF::Vocab::SHACL.name, name]
            shacl_graph << [shape, RDF::Vocab::SHACL.targetClass, RDF::URI.new(class_uri)]
            shacl_graph << [shape, RDF::Vocab::SHACL.description, description] if description
            shacl_graph << [shape, RDF::Vocab::SKOS.altLabel, plural] if plural
            direct_parents.each do |parent|
              shape_subclass_of = RDF::URI.new("#{parent}Shape")
              shacl_graph << [shape, RDF::Vocab::SHACL.node, shape_subclass_of]
            end

            # Add property shapes to the node shape

            data_entity['own_properties'].each do |property_uri|

              data_property = data_entity['properties'][property_uri]

              data_property['constraints'].each do |constraint|

                property_shape = RDF::Node.new
                shacl_graph << [shape, RDF::Vocab::SHACL.property, property_shape]

                shacl_graph << [property_shape, RDF::Vocab::SHACL.path, RDF::URI.new(property_uri)]

                property_name = constraint['data']['name'] ||
                  Solis::Utils::String.extract_name_from_uri(property_uri)

                shacl_graph << [property_shape, RDF::Vocab::SHACL.name, property_name]

                add_constraint(shacl_graph, property_shape, constraint)

                constraint_data = constraint['data']
                options = constraint_data['or']
                if options
                  list = RDF::List.new
                  options.each do |option|
                    node = RDF::Node.new
                    or_constraint = option['constraints'][0]
                    add_constraint(shacl_graph, node, or_constraint)
                    list << node
                  end
                  shacl_graph << list
                  shacl_graph << [property_shape, RDF::Vocab::SHACL.or, list.subject]
                end

              end


            end

          end

          shacl_graph
        rescue Solis::Error::General => e
          raise e
        end

        private

        def self.add_constraint(shacl_graph, node, constraint)

          description = constraint['description']
          constraint_data = constraint['data']
          min_count = constraint_data['min_count']
          max_count = constraint_data['max_count']
          datatype = constraint_data['datatype']
          klass = constraint_data['class']
          pattern = constraint_data['pattern']

          shacl_graph << [node, RDF::Vocab::SHACL.description, description] if description
          shacl_graph << [node, RDF::Vocab::SHACL.minCount, min_count] if min_count
          shacl_graph << [node, RDF::Vocab::SHACL.maxCount, max_count] if max_count
          shacl_graph << [node, RDF::Vocab::SHACL.datatype, RDF::URI.new(datatype)] if datatype
          shacl_graph << [node, RDF::Vocab::SHACL.class, RDF::URI.new(klass)] if klass
          shacl_graph << [node, RDF::Vocab::SHACL.nodeKind, RDF::Vocab::SHACL.IRI] if klass
          shacl_graph << [node, RDF::Vocab::SHACL.pattern, pattern] if pattern

        end

      end
    end
  end
end