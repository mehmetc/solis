require 'solis/store/sparql/client'

class Solis::Query::Runner
    def self.run(entity, query)
      result = {}
      context = JSON.parse %(
{
    "@context": {
        "@vocab": "#{ConfigFile[:solis][:graph_name]}",
        "id": "@id"
    },
    "@type": "#{entity}",
    "@embed": "@always"
}
   )

      c = Solis::Store::Sparql::Client.new(ConfigFile[:solis][:sparql_endpoint], ConfigFile[:solis][:graph_name])
      r = c.query(query)
      if r.is_a?(SPARQL::Client)
        g = RDF::Graph.new
        t = r.query('select * where{?s ?p ?o}')
        t.each do |s|
          g << [s.s, s.p, s.o]
        end

        framed = nil
        JSON::LD::API.fromRDF(g) do |e|
          framed = JSON::LD::API.frame(e, context)
        end
        result = sanitize_result(framed)
      else
        t = []
        r.each do |s|
          t << s.to_h
        end
        result = sanitize_result({'@graph' => t})
      end
      result
    rescue StandardError => e
      puts e.message
      raise e
    end

    private

    def self.sanitize_result(framed)
      data = framed&.key?('@graph') ? framed['@graph'] : [framed]

      data.map do |d|
        d.delete_if { |e| e =~ /^@/ }
        if d.is_a?(Hash)
          new_d = {}
          d.each do |k,v|
            if v.is_a?(Hash)
              if v.key?('@type')
                type = v['@type']
                if v.key?('@value')
                  value = v['@value']
                  case type
                  when "http://www.w3.org/2001/XMLSchema#dateTime"
                    value = Date.parse(value)
                  end
                  v = value
                end
                v = sanitize_result(v) if v.is_a?(Hash)
              end
            end
            new_d[k] = v.class.method_defined?(:value) ? v.value : v
          end
          d = new_d
        end

        d
      end
    end
end