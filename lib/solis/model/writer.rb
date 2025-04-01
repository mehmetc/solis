module Solis
  class Model
    class Writer
      def self.to_uri(params = {})
        raise Solis::Error::MissingParameter, "One :prefix, :namespace, :uri, :model is missing " unless (params.keys & [:prefix, :namespace, :uri, :model]).size == 4

        content_type = RDF::Format.content_types[params[:content_type] || 'text/turtle'].first.to_sym
        namespace = params[:namespace]
        prefix = params[:prefix]
        shacl_graph = params[:model]
        uri = params[:uri]

        if uri.is_a?(StringIO)
          uri.write(shacl_graph.dump(content_type,
                                     prefixes: {prefix.to_sym => namespace,
                                                sh: RDF::Vocab::SHACL,
                                                rdfs: RDF::RDFS,
                                                rdf: RDF::RDFV,
                                                xsd: RDF::XSD
                                     }))
        else
          source = CGI.unescapeHTML(params[:uri])
          Solis::Logger@logger.info("Reading #{params[:uri]}")
          raise Solis::Error::General, 'to_uri expects a scheme like file:// of https://' unless source =~ /:\/\//

          scheme, path = source.split('://')
          source = "#{scheme}://#{URI.encode_www_form_component(path)}"
          uri = URI(source)

          case uri.scheme
          when 'file'
            #file_extension = RDF::Format.content_types[params[:content_type] || 'text/turtle'].first.file_extension.first
            absolute_path = File.absolute_path("#{URI.decode_www_form_component(uri.host)}#{URI.decode_www_form_component(uri.path)}")
            if File.directory?(absolute_path)
              raise Solis::Error::General, "#{source} can not be a directory"
            else
              File.open(absolute_path, 'wb') do |f|
                f.puts shacl_graph.dump(content_type,
                                        prefixes: {prefix.to_sym => namespace,
                                                   sh: RDF::Vocab::SHACL,
                                                   rdfs: RDF::RDFS,
                                                   rdf: RDF::RDFV,
                                                   xsd: RDF::XSD
                                        })
              end
            end
          else
            raise "Do not know how to process #{source}"
          end
        end
      end
    end
  end
end