
require 'sparql'

module SPARQL
  class Client

    def parse_report(response)
      # NOTE: all below tested on Virtuoso only
      # following fixes a response content bug
      response.body.gsub!('rdf:type', '<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>')
      parsed = parse_response(response)
      report = {}
      if parsed.is_a?(RDF::NTriples::Reader)
        graph = RDF::Graph.new
        graph << parsed
        str_report = graph.query([nil, RDF::URI('http://www.w3.org/2005/sparql-results#value'), nil]).first_object.to_s
        if str_report.start_with?('Delete')
          report[:count_delete] = str_report.scan(/[0-9]+/)[0].to_i
        elsif str_report.start_with?('Insert')
          report[:count_insert] = str_report.scan(/[0-9]+/)[0].to_i
        elsif str_report.start_with?('Modify')
          report[:count_delete], report[:count_insert] = str_report.scan(/[0-9]+/).collect { |v| v.to_i }
        end
      end
      report
    end

  end
end
