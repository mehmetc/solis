module Solis
  class Model
    class Reader
      class Shacl
        def self.read(ontology)
          if ontology.is_a?(String)
            graph = RDF::Repository.load(ontology)
          else
            graph = ontology
          end

          graph
        end
        def self.is_shacl?(graph)
          graph.query([nil, RDF.type, RDF::Vocab::SHACL.NodeShape]).size > 0
        end
      end
    end
  end
end
