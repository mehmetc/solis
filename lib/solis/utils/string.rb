

module Solis
  module Utils
    module String

      def self.camel_to_snake(string)
        string.gsub(/::/, '/').
          gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').
          gsub(/([a-z\d])([A-Z])/, '\1_\2').
          tr("-", "_").
          downcase
      end

      def self.extract_name_from_uri(uri)
        return "" unless uri
        if uri.include?('#')
          uri.split('#').last
        else
          uri.split('/').last
        end
      end

    end
  end
end
