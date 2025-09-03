
require 'linkeddata'

module RDF
  # class Graph
  class Repository
    def extract_prefixes
      prefixes = {}
      uris = []
      each_statement do |statement|
        [statement.subject, statement.predicate, statement.object].each do |term|
          if term.is_a?(RDF::URI)
            # Extract potential prefix (everything before the last # or /)
            uri_str = term.to_s
            if uri_str =~ /(.*[#\/])([^#\/]+)$/
              base_uri = $1

              uris << base_uri unless uris.include?(base_uri)
            end
          end
        end
      end

      anonymous_prefix_index = 0
      uris.each do |prefix|
        if RDF::URI(prefix).qname.nil?
          prefixes["ns#{anonymous_prefix_index}".to_sym] = prefix
          anonymous_prefix_index += 1
        else
          prefixes[RDF::URI(prefix).qname&.first] = prefix
        end
      end
      prefixes
    end
  end
end
