module Solis
  module Utils
    class Namespace

      # Extract unique namespaces from an RDF graph
      # Returns array of namespace URIs found in the graph
      def self.extract_unique_namespaces(graph)
        namespaces = Set.new

        # Iterate through all statements in the graph
        graph.each_statement do |statement|
          # Check subject, predicate, and object for namespace URIs
          [statement.subject, statement.predicate, statement.object].each do |term|
            if term.is_a?(RDF::URI)
              namespace = extract_namespace_from_uri(term)
              namespaces.add(namespace) if namespace
            end
          end
        end

        # Convert Set to Array and sort for consistent ordering
        namespaces.to_a.sort
      end

      # Extract unique namespaces with additional metadata
      # Returns array of hashes with namespace info
      def self.extract_unique_namespaces_with_metadata(graph, primary_namespace = nil)
        namespace_stats = Hash.new { |h, k| h[k] = { count: 0, types: Set.new, properties: Set.new } }

        # Collect statistics about namespace usage
        graph.each_statement do |statement|
          [statement.subject, statement.predicate, statement.object].each do |term|
            if term.is_a?(RDF::URI)
              namespace = extract_namespace_from_uri(term)
              next unless namespace

              namespace_stats[namespace][:count] += 1

              # Track if this is a class/type definition
              if statement.predicate == RDF.type ||
                statement.predicate == RDF::RDFS.subClassOf ||
                statement.predicate == RDF::OWL.Class
                namespace_stats[namespace][:types].add(term.to_s)
              end

              # Track if this is a property
              if statement.predicate == RDF::RDFS.domain ||
                statement.predicate == RDF::RDFS.range ||
                term.to_s.include?('property') ||
                statement.object == RDF::OWL.ObjectProperty ||
                statement.object == RDF::OWL.DatatypeProperty
                namespace_stats[namespace][:properties].add(term.to_s)
              end
            end
          end
        end

        # Convert to array of hashes with metadata
        namespaces = namespace_stats.map do |namespace, stats|
          {
            namespace: namespace,
            usage_count: stats[:count],
            types_count: stats[:types].size,
            properties_count: stats[:properties].size,
            is_primary: namespace == primary_namespace,
            estimated_importance: calculate_importance_score(stats)
          }
        end

        # Sort by importance (primary first, then by usage)
        namespaces.sort_by { |ns| [ns[:is_primary] ? 0 : 1, -ns[:estimated_importance]] }
      end

      # Extract namespaces that define SHACL shapes (likely primary ontologies)
      def self.extract_shape_defining_namespaces(graph)
        shape_namespaces = Set.new

        # Look for SHACL NodeShape definitions
        graph.query([nil, RDF.type, RDF::Vocab::SHACL.NodeShape]) do |statement|
          namespace = extract_namespace_from_uri(statement.subject)
          shape_namespaces.add(namespace) if namespace
        end

        # Look for SHACL targetClass definitions
        graph.query([nil, RDF::Vocab::SHACL.targetClass, nil]) do |statement|
          if statement.object.is_a?(RDF::URI)
            namespace = extract_namespace_from_uri(statement.object)
            shape_namespaces.add(namespace) if namespace
          end
        end

        shape_namespaces.to_a.sort
      end

      # Determine the most likely primary namespace
      def self.detect_primary_namespace(graph, config_namespace = nil)
        # If explicitly configured, use that
        return config_namespace if config_namespace

        # Get namespaces with metadata
        namespaces = extract_unique_namespaces_with_metadata(graph)

        # Primary namespace is likely the one with:
        # 1. Most SHACL shape definitions
        # 2. Highest usage count
        # 3. Most types defined

        shape_namespaces = extract_shape_defining_namespaces(graph)

        # Prefer namespaces that define shapes
        primary_candidates = namespaces.select { |ns| shape_namespaces.include?(ns[:namespace]) }

        if primary_candidates.any?
          # Return the shape-defining namespace with highest importance
          primary_candidates.max_by { |ns| ns[:estimated_importance] }[:namespace]
        else
          # Fallback to most used namespace
          namespaces.max_by { |ns| ns[:estimated_importance] }&.dig(:namespace)
        end
      end

      # Extract entities (classes) for a specific namespace
      def self.extract_entities_for_namespace(graph, target_namespace)
        entities = Set.new

        # Look for SHACL shapes targeting classes in this namespace
        graph.query([nil, RDF::Vocab::SHACL.targetClass, nil]) do |statement|
          if statement.object.is_a?(RDF::URI)
            namespace = extract_namespace_from_uri(statement.object)
            if namespace == target_namespace
              entity_name = extract_local_name_from_uri(statement.object)
              entities.add(entity_name) if entity_name
            end
          end
        end

        # Also look for direct class definitions
        graph.query([nil, RDF.type, RDF::RDFS.Class]) do |statement|
          namespace = extract_namespace_from_uri(statement.subject)
          if namespace == target_namespace
            entity_name = extract_local_name_from_uri(statement.subject)
            entities.add(entity_name) if entity_name
          end
        end

        # Look for OWL classes
        graph.query([nil, RDF.type, RDF::OWL.Class]) do |statement|
          namespace = extract_namespace_from_uri(statement.subject)
          if namespace == target_namespace
            entity_name = extract_local_name_from_uri(statement.subject)
            entities.add(entity_name) if entity_name
          end
        end

        entities.to_a.sort
      end

      private

      # Extract namespace from a URI (everything before the last # or /)
      def self.extract_namespace_from_uri(uri)
        return nil unless uri.is_a?(RDF::URI)

        uri_str = uri.to_s

        # Match everything up to and including the last # or /
        if uri_str =~ /(.*[#\/])/
          $1
        else
          nil
        end
      end

      # Extract local name from URI (everything after the last # or /)
      def self.extract_local_name_from_uri(uri)
        return nil unless uri.is_a?(RDF::URI)

        uri_str = uri.to_s

        # Match everything after the last # or /
        if uri_str =~ /[#\/]([^#\/]+)$/
          $1
        else
          uri_str # If no separator found, return the whole string
        end
      end

      # Calculate importance score based on usage statistics
      def self.calculate_importance_score(stats)
        # Weighted scoring: types and properties are more important than general usage
        (stats[:count] * 1) +
          (stats[:types].size * 10) +
          (stats[:properties].size * 5)
      end
    end
  end
end
