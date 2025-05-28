
require 'linkeddata'

module RDF
  class List
    def self.from_graph(graph, subject)
      parse_as_array = lambda do |arr, graph, sbj_next|
        return if sbj_next == RDF.nil
        first = graph.first_object([sbj_next, RDF.first])
        arr << first if first
        rest = graph.first_object([sbj_next, RDF.rest])
        parse_as_array.call(arr, graph, rest) if rest && rest != RDF.nil
      end
      arr = []
      parse_as_array.call(arr, graph, subject)
      RDF::List[*arr]
    end
  end
end
