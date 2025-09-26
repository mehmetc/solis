require 'solis/store/sparql/client'
require 'solis/config_file'

class Solis::Query::Runner
    def self.run(entity, query, options = {})
      result = {}
      context = JSON.parse %(
{
    "@context": {
        "@vocab": "#{graph_name}",
        "id": "@id"
    },
    "@type": "#{entity}",
    "@embed": "@always"
}
   )

      c = Solis::Store::Sparql::Client.new(Solis::Options.instance.get[:sparql_endpoint], graph_name: graph_name)
      r = c.query(query, options)
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

      sanitatize_data_in_result(data)
    end

    def self.sanitatize_data_in_result(data)
      data.map do |d|
        d.delete_if { |e| e =~ /^@/ }
        if d.is_a?(Hash)
          new_d = {}
          d.each do |k, v|
            if v.is_a?(Hash)
              if v.key?('@type')
                type = v['@type']
                if v.key?('@value')
                  value = v['@value']
                  case type
                  when "http://www.w3.org/2001/XMLSchema#dateTime"
                    value = DateTime.parse(value)
                  when "http://www.w3.org/2001/XMLSchema#date"
                    value = Date.parse(value)
                  when "http://www.w3.org/2006/time#DateTimeInterval"
                    value = ISO8601::TimeInterval.parse(value)
                  when "http://www.w3.org/2001/XMLSchema#boolean"
                    value = value == "true"
                  end
                  v = value
                end
                v = sanitize_result(v) if v.is_a?(Hash)
              end
              if v.is_a?(Hash)
                new_d[k] = v.class.method_defined?(:value) ? v.value : sanitize_result(v)
              else
                new_d[k] = v.class.method_defined?(:value) ? v.value : v
              end
            elsif v.is_a?(Array) #todo: make recursive
              new_d[k] = []
              v.each do |vt|
                if vt.is_a?(Hash)
                  if vt.key?('@value')
                    new_d[k] << vt['@value']
                  else
                    new_d[k] << (vt.is_a?(String) ? vt : sanitize_result(vt))
                  end
                else
                  new_d[k] << (vt.is_a?(String) ? vt : sanitize_result(vt))
                end
              end
              new_d[k].flatten!
            else
              new_d[k] = v.class.method_defined?(:value) ? v.value : v
            end
          end
          d = new_d
        end

        d
      end
    rescue StandardError => e
      Solis::LOGGER.error(e.message)
      data
    end

    def self.graph_name
      Solis::Options.instance.get.key?(:graphs) ? Solis::Options.instance.get[:graphs].select{|s| s['type'].eql?(:main)}&.first['name'] : ''
    end
end