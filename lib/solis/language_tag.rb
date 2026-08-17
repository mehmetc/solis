module Solis
  # Normalizes language tags so the same language always ends up under the same key,
  # no matter if it came from a 'Label_XX' sheet column or from a parsed rdfs:label
  # (RDF.rb lowercases language tags, ex. 'nl-BE' is read back as :'nl-be')
  module LanguageTag
    # 'nl' -> :nl, 'nl_be' -> :'nl-BE', 'zh_hant' -> :'zh-Hant'
    def self.normalize(tag)
      return nil if tag.nil? || tag.to_s.strip.empty?

      primary, *subtags = tag.to_s.strip.split(/[-_]/)
      subtags.map! do |subtag|
        case subtag.length
        when 2 then subtag.upcase
        when 4 then subtag.capitalize
        else subtag.downcase
        end
      end

      ([primary.downcase] + subtags).join('-').to_sym
    end
  end
end
