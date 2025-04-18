
require 'linkeddata'
require 'json/ld'
require 'tsort'
require 'uri'
require 'securerandom'

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

      def self.expand(obj)
        arr = JSON::LD::API.expand(obj, options: {
        })
        # The library method above seems to provide the same "@type"
        # "http://www.w3.org/2001/XMLSchema#string" to everything,
        # unless "@type" was alreadty specified externally.
        # For now, whden the type is like that, it is deleted.
        # For the validation, the type is let be inferred by the SHACL validator.
        arr.each do |obj|
          obj.each do |name_attr, val_attr|
            next if ['@id', '@type'].include?(name_attr)
            val_attr.each do |spec|
              if spec.key?('@value')
                if spec.key?('@type') and spec['@type'].eql?('http://www.w3.org/2001/XMLSchema#string')
                  spec.delete('@type')
                end
              end
            end
          end
        end
        arr
      end
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
        # NOTE: currently only meant for a _compacted_ JSON-LD object
        data['@type'] = type_root if data['@type'].nil?
        data.each do |name_attr, val_attr|
          next if ['@id', '@type'].include?(name_attr)
          val_attr = [val_attr] unless val_attr.is_a?(Array)
          val_attr.each do |e|
            if is_object_an_embedded_entity_or_ref(e)
              type_embedded = SHACLSHapes::get_property_class_for_shape(shapes, type_root, name_attr)
              infer_jsonld_types_from_shapes!(e, shapes, type_embedded)
            end
          end
        end
        data.compact!
      end

      def self.make_jsonld_datatypes_context_from_shape(shape)
        # NOTE: currently only meant for a _compacted_ JSON-LD object
        context = {}
        props = shape[:properties]
        props.each do |name_prop, value_prop|
          datatype = value_prop[:constraints][:datatype]
          context[name_prop] = {
            '@type' => datatype
          } unless datatype.nil?
        end
        context
      end

      def self.clean_flattened_expanded_from_unset_data!(flattened_expanded)
        flattened_expanded.each do |obj|
          obj.each do |name_attr, content_attr|
            next if ['@id', '@type'].include?(name_attr)
            content_attr.map! do |content|
              (content.key?('@value') and content['@value'].eql?('@unset')) ? nil : content
            end
            content_attr.compact!
          end
        end
      end

      def self.is_object_an_embedded_entity_or_ref(obj)
        obj.is_a?(Hash) and (obj.key?('@id') or (!obj.key?('@value') and !obj.key?('@list') and !obj.key?('@set')))
      end

      def self.add_ids_if_not_exists!(obj, namespace)
        obj['@id'] = obj['@id'] || URI.join(namespace, SecureRandom.uuid).to_s
        obj.each do |name_attr, val_attr|
          val_attr = [val_attr] unless val_attr.is_a?(Array)
          val_attr.each do |e|
            if e.is_a?(Hash) and !e.key?('@value')
              add_ids_if_not_exists!(e, namespace)
            end
          end
        end
      end

    end
  end
end
