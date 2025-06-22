require 'http'
module Solis
  module Utils

    class PrefixResolver
      CACHE = {}

      def self.resolve_prefix(namespace)
        return CACHE[namespace] if CACHE[namespace]

        # Try multiple sources in order of preference
        prefix = try_rdf_vocab(namespace) || try_lov(namespace) || try_prefix_cc(namespace) ||
          generate_fallback_prefix(namespace)

        CACHE[namespace] = prefix
        prefix
      end

      private

      def self.try_lov(namespace)
          url = "https://lov.linkeddata.es/dataset/lov/api/v2/vocabulary/autocomplete"
          params = { q: namespace }

          response = HTTP.get(url, params: params)
          if response.status.success?
            data = JSON.parse(response.body)
            data.dig('results')&.first&.dig('prefix')&.first
          end
        rescue
          nil
      end

      # works best for prefix -> namespace lookups
      def self.try_prefix_cc(namespace)
        encoded_ns = CGI.escape(namespace)
        response = HTTP.get("https://prefix.cc/#{encoded_ns}.file.json")

        if response.success?
          data = JSON.parse(response.body)
          data.keys.first
        end
      rescue
        nil
      end

      def self.try_rdf_vocab(namespace)
        RDF::Vocabulary.each do |vocab|
          if vocab.to_s == namespace
            return vocab.to_s.split('/').last.downcase.gsub(/\W*/,'')
          end
        end
        nil
      end

      def self.generate_fallback_prefix(namespace)
        # Extract domain or generate a reasonable prefix
        uri = URI.parse(namespace)
        if uri.host
          uri.host.split('.').first
        else
          'ns'
        end
      end
    end
  end
end
