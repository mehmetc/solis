require_relative 'writer/mermaid'
require_relative 'writer/plantuml'
require_relative 'writer/json_schema'
require_relative 'writer/form'
require_relative 'writer/open_api'

module Solis
  class Model
    class Writer
      def self.to_uri(params = {})
        raise Solis::Error::MissingParameter, "One :prefix, :namespace, :uri, :graph is missing " unless (params.keys & [:prefix, :namespace, :uri, :graph]).size == 4

        content_type = RDF::Format.content_types[params[:content_type] || 'text/turtle'].first.to_sym
        namespace = params[:namespace]
        prefix = params[:prefix]
        shacl_graph = params[:graph]
        uri = params[:uri]

        all_prefixes = extract_prefixes(shacl_graph, prefix, namespace)

        if uri.is_a?(StringIO)
          Solis.logger.info("Writing #{params[:uri]}")
          uri.write(shacl_graph.dump(content_type,
                                     prefixes: all_prefixes))
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
                                        prefixes: all_prefixes)
              end
            end
          when 'http', 'https'
            HTTP.post(uri.to_s, )
            URI.open(uri, "wb") do |f|
              f.puts shacl_graph.dump(content_type,
                                      prefixes: all_prefixes)
            end
          when 'mermaid'
            MermaidWriter.write(shacl_graph, params)
          when 'plantuml'
            PlantUMLWriter.write(shacl_graph, params)
          when 'jsonschema'
            JSONSchemaWriter.write(shacl_graph, params)
          when 'form'
            FormWriter.write(shacl_graph, params)
          when 'openapi'
            OpenApiWriter.write(shacl_graph, params)
          else
            raise "Do not know how to process #{source}"
          end
        end
      end
      private
      def self.extract_prefixes(repository, prefix, namespace)
        prefixes = {}
        uris = []
        repository.each_statement do |statement|
          [statement.subject, statement.predicate, statement.object].each do |term|
            if term.is_a?(RDF::URI)
              # Extract potential prefix (everything before the last # or /)
              uri_str = term.to_s
              if uri_str =~ /(.*[#\/])([^#\/]+)$/
                base_uri = $1
                next if base_uri.eql?(namespace)

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
        prefixes[prefix.to_sym] = namespace
        prefixes
      end

    end
  end
end