
require 'linkeddata'
require 'json/ld'
require 'tsort'
require_relative '../model/parser/shacl'



class TSortableHash < Hash
  include TSort
  alias tsort_each_node each_key
  def tsort_each_child(node, &block)
    fetch(node).each(&block)
  end
end

module Solis
  module Utils
    module JSONLD

      def self.flatten_jsonld(hash_jsonld)
        flattened = JSON::LD::API.flatten(hash_jsonld, hash_jsonld['@context'], options: {
          # add flattening algo options here if necessary
        })
        flattened
      end

      def self.sort_flat_jsonld_by_deps(flattened)
        arr = flattened["@graph"]
        deps = {}
        arr.each do |e|
          dep = []
          deps[e['@id']] = dep
          e.each do |k, v|
            if v.is_a?(Hash)
              d = v['@id']
              dep.push(d) unless (dep.include?(d) or d.nil?)
            elsif v.is_a?(Array)
              v.each do |w|
                if w.is_a?(Hash)
                  d = w['@id']
                  dep.push(d) unless (dep.include?(d) or d.nil?)
                end
              end
            end
          end
        end
        arr_ids_ordered = TSortableHash[deps].tsort
        graph_flattened_ordered = arr.sort do |a, b|
          arr_ids_ordered.find_index(a['@id']) <=> arr_ids_ordered.find_index(b['@id'])
        end
        flattened_ordered = flattened
        flattened_ordered['@graph'] = graph_flattened_ordered
        flattened_ordered
      end

      def self.json_object_to_jsonld(hash_json, context)
        unless hash_json.is_a?(Hash)
          raise TypeError, "hash_json not an hash"
        end
        hash_jsonld = {
          "@context" => context,
          "@graph" => [
            hash_json
          ]
        }
        hash_jsonld
      end

      def self.infer_jsonld_types_from_shapes!(data, shapes, type_root)
        data['@type'] = type_root if data['@type'].nil?
        data.each do |name_attr, val_attr|
          next if ['@id', '@type'].include?(name_attr)
          val_attr = [val_attr] unless val_attr.is_a?(Array)
          val_attr.each do |e|
            if e.is_a?(Hash)
              type_embedded = SHACLSHapes::get_property_class_for_shape(shapes, type_root, name_attr)
              infer_jsonld_types_from_shapes!(e, shapes, type_embedded)
            end
          end
        end
        data.compact!
      end

    end
  end
end
