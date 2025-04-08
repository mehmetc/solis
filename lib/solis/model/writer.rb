require_relative 'writer/mermaid'
require_relative 'writer/plantuml'
require_relative 'writer/json_schema'
require_relative 'writer/form'

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
          Solis.logger.info("Writing #{params[:uri]}")
          uri.write(shacl_graph.dump(content_type,
                                     prefixes: {prefix.to_sym => namespace,
                                                sh: RDF::Vocab::SHACL,
                                                rdfs: RDF::RDFS,
                                                rdf: RDF::RDFV,
                                                xsd: RDF::XSD
                                     }))
          uri.rewind
        else
          source = CGI.unescapeHTML(params[:uri])
          uri = URI(source)
          Solis.logger.info("Writing #{params[:uri]}")
          raise Solis::Error::General, 'to_uri expects a scheme like file:// of https://' if uri.scheme.nil?

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
          when 'http', 'https'
            HTTP.post(uri.to_s, )
            URI.open(uri, "wb") do |f|
              f.puts shacl_graph.dump(content_type,
                                      prefixes: {prefix.to_sym => namespace,
                                                 sh: RDF::Vocab::SHACL,
                                                 rdfs: RDF::RDFS,
                                                 rdf: RDF::RDFV,
                                                 xsd: RDF::XSD
                                      })
            end
          when 'mermaid'
            MermaidWriter.write(shacl_graph)
          when 'plantuml'
            PlantUMLWriter.write(shacl_graph)
          when 'jsonschema'
            JSONSchemaWriter.write(shacl_graph, params)
          when 'form'
            FormWriter.write(shacl_graph, params)
          else
            raise "Do not know how to process #{source}"
          end
        end
      end
    end
  end
end