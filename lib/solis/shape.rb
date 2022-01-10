require_relative 'shape/reader/file'
require_relative 'shape/reader/sheet'

Graphiti::Types[:year] = {
  canonical_name: :year,
  params: Dry::Types["coercible.integer"],
  read: Dry::Types["coercible.integer"],
  write: Dry::Types["coercible.integer"],
  kind: "scalar",
  description: "contains only the year of a date"
}

module Solis
  module Shape
    def self.from_graph(graph)
      class << self
        def parse_graph(graph)
          shapes = {}
          #puts query.execute(graph).to_csv

          query.execute(graph) do |solution|
            parse_solution(shapes, solution)
          end

          # shapes = add_missing_attributes(shapes)
          shapes
        rescue Solis::Error::GeneralError => e
          raise "Unable to parse shapes: #{e.message}"
        end

        def lookup_datatype(datatype, node)
          if datatype =~ /^http:\/\/www.w3.org\/2001\/XMLSchema#/
            case datatype
            when /^http:\/\/www.w3.org\/2001\/XMLSchema#anyURI/
              :string
            when /http:\/\/www.w3.org\/2001\/XMLSchema#duration/
              :string
            when /http:\/\/www.w3.org\/2001\/XMLSchema#integer/
              :integer
            when /http:\/\/www.w3.org\/2001\/XMLSchema#int/
              :integer
            when /http:\/\/www.w3.org\/2001\/XMLSchema#dateTime/
              :datetime
            when /http:\/\/www.w3.org\/2001\/XMLSchema#gYear/
              :year
            else
              datatype.split('#').last.to_sym
            end
          elsif datatype.nil? && node.is_a?(RDF::URI)
            node.value.split('/').last.gsub(/Shape$/, '').to_sym
          elsif datatype =~ /^http:\/\/www.w3.org\/1999\/02\/22-rdf-syntax-ns/
            case datatype
            when /http:\/\/www.w3.org\/1999\/02\/22-rdf-syntax-ns#langString/
              :string
            else
              :string
            end
          else
            :string
          end
        end

        def parse_solution(shapes, solution)
          shape_rdf = solution.targetClass
          shape_node = solution.targetNode if solution.bound?(:targetNode)
          shape_name = solution.className.value
          attribute_name = solution.attributeName.value if solution.bound?(:attributeName)
          comment = solution.comment.value if solution.bound?(:comment)
          attribute_rdf = solution.attributePath.value if solution.bound?(:attributePath)
          attribute_datatype_rdf = solution.attributeDatatype.value if solution.bound?(:attributeDatatype)
          attribute_min_count = solution.bound?(:attributeMinCount) ? solution.attributeMinCount.value.to_i : 0
          attribute_max_count = solution.bound?(:attributeMaxCount) ? solution.attributeMaxCount.value.to_i : nil
          attribute_node_kind = solution.attributeNodeKind if solution.bound?(:attributeNodeKind)
          attribute_node = solution.attributeNode if solution.bound?(:attributeNode)
          attribute_class = solution.attributeClass if solution.bound?(:attributeClass)
          attribute_comment = solution.attributeComment if solution.bound?(:attributeComment)
          # if solution.bound?(:attributeOr)
          #   pp solution
          # end

          attribute_node = attribute_class if attribute_name && attribute_datatype_rdf.nil? && attribute_node.nil?

          shape = shapes.key?(shape_name) ? shapes[shape_name] : { target_class: nil, target_node: nil, attributes: {} }
          shape[:target_class] = shape_rdf
          shape[:target_node] = shape_node
          shape[:comment] = comment
          shape[:attributes][attribute_name] = {
            path: attribute_rdf,
            datatype_rdf: attribute_datatype_rdf,
            datatype: lookup_datatype(attribute_datatype_rdf, attribute_node),
            mincount: attribute_min_count,
            maxcount: attribute_max_count,
            node: attribute_node,
            node_kind: attribute_node_kind,
            class: attribute_class,
            comment: attribute_comment
          }

          shape[:attributes].delete_if { |k, _| k.nil? }
          shapes[shape_name] = shape
        end

        def query
          SPARQL.parse %(
PREFIX sh: <http://www.w3.org/ns/shacl#>
PREFIX rdfv: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>

SELECT ?targetClass ?targetNode ?comment ?className ?attributePath ?attributeName ?attributeDatatype
       ?attributeMinCount ?attributeMaxCount ?attributeOr ?attributeClass
       ?attributeNode ?attributeNodeKind ?attributeComment ?o
WHERE {

  ?s a sh:NodeShape;
     sh:targetClass ?targetClass ;
     sh:node ?targetNode ;
     sh:description ?comment  ;
     sh:name        ?className .
     OPTIONAL{ ?s sh:property ?attributes .
               ?attributes sh:name ?attributeName ;
                           sh:path ?attributePath ;
                           OPTIONAL{ ?attributes sh:datatype ?attributeDatatype } .
                           OPTIONAL{ ?attributes sh:minCount ?attributeMinCount } .
                           OPTIONAL{ ?attributes sh:maxCount ?attributeMaxCount } .
                           OPTIONAL{ ?attributes sh:or       ?attributeOr } .
                           OPTIONAL{ ?attributes sh:class    ?attributeClass } .
                           OPTIONAL{ ?attributes sh:nodeKind ?attributeNodeKind } .
                           OPTIONAL{ ?attributes sh:node     ?attributeNode } .
                           OPTIONAL{ ?attributes sh:description ?attributeComment } .
     }.
}
)
        end

        def add_missing_attributes(shapes)
          shapes.each do |shape|
            if shape[1].is_a?(Hash)
              graph_name = shape[1][:target_class].value.split(shape[1][:target_class].path).first
              attributes = shape[1][:attributes]
              unless attributes.key?('id')
                if shape[1][:target_class] == shape[1][:target_node]
                  attributes['id'] = {
                    "path": "#{graph_name}/id",
                    "datatype_rdf": "http://www.w3.org/2001/XMLSchema#string",
                    "datatype": "string",
                    "mincount": 1,
                    "maxcount": 1,
                    "node": nil,
                    "node_kind": nil,
                    "class": nil,
                    "comment": RDF::Literal.new("UUID", datatype: RDF::XSD.string)
                  }

                  shape[1][:attributes] = attributes
                end
              end
            end
          end
          shapes
        end
      end

      parse_graph(graph)
    end
  end
end