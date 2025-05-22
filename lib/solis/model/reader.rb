require 'solis/error'
require 'solis/config'
require_relative 'reader/sheet'
require_relative 'reader/rdf'
require_relative 'reader/shacl'
require 'data_collector'
require 'uri'

module Solis
  class Model
    class Reader
      def self.from_uri(params)
        data = nil
        params[:content_type] = 'text/turtle' unless params.key?(:content_type)
        Solis.config.path = params[:config_path] if params[:config_path]
        Solis.config.name = params[:config_name] if params[:config_name]

        if params.keys.include?(:uri) && params[:uri].is_a?(StringIO)
          raise Solis::Error::BadParameter, 'Not a IO object' unless params[:uri].is_a?(StringIO)
          data = DataCollector::Input.new.from_uri(params[:uri], content_type: params[:content_type], raw: true)
        elsif params.keys.include?(:uri)
          uri = URI.parse(params[:uri])
          case uri.scheme
          when 'google+sheet'
            raise Solis::Error::MissingParameter, 'Missing key parameter. This is your Google Auth key.' unless params.key?(:key) || Solis.config.include?(:key)
            google_key = params[:key] || Solis.config[:key]
            spreadsheet_id = uri.host
            data = Sheet.read(google_key, spreadsheet_id, params)
          else
            raise Solis::Error::MissingParameter, 'Missing content_type parameter' unless params.key?(:content_type)
            data = DataCollector::Input.new.from_uri(params[:uri], content_type: params[:content_type], raw: true)
            raise Solis::Error::General, "Unable to load Graph" unless data.is_a?(RDF::Graph)
            if Rdf.is_rdf?(data)
              data = Rdf.read(data)
            elsif Shacl.is_shacl?(data)
              data = Shacl.read(data)
            else
              raise Solis::Error::General, "Unable to load Shacl graph. No entities found."
            end
          end
        else
          raise Solis::Error::MissingParameter, 'Missing io or uri parameter'
        end

        if data.is_a?(RDF::Graph)
          data = RDF::Repository.new.insert(data)
        end
        data
      rescue => e
        if e.is_a?(Solis::Error::MissingParameter)
          raise(e)
        else
          raise Solis::Error::General, e.message
        end
      end
    end
  end
end