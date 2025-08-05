

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

      def self.extract_namespace_from_uri(uri)
        uri.gsub(extract_name_from_uri(uri), '')
      end

      def self.is_uri(s)
        # also add "file://" etc.
        return s.start_with?('http')
      end

      def self.prepend_namespace_if_not_uri(namespace, s)
        return s if is_uri(s)
        "#{namespace}#{s}"
      end

    end
  end
end
