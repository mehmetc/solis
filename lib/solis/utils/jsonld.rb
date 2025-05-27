
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
        # unless "@type" was already specified externally.
        # For now, when the type is like that, it is deleted.
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
        # NOTE: following patch is necessary because JSON::LD::API.flatten()
        # does an expansion on top of the wanted flattening.
        # If attribute names belong to known ontologies, then it expands to those, wrongly;
        # there seems to be no way to avoid this, so the only choice seems overwriting attribute names,
        # from full uri back to the base attribute name
        flattened['@graph'].map! do |obj|
          obj2 = Marshal.load(Marshal.dump(obj))
          obj.each_key do |name_attr|
            next if ['@id', '@type'].include?(name_attr)
            uri = URI(name_attr)
            # take part either after # or last /
            name_attr_new = uri.fragment || uri.path.split('/').last
            obj2.transform_keys!({"#{name_attr}" => name_attr_new})
          end
          obj2
        end
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
              type_embedded = Shapes::get_property_class_for_shape(shapes, type_root, name_attr)
              infer_jsonld_types_from_shapes!(e, shapes, type_embedded)
            end
          end
        end
        data.compact!
      end

      def self.infer_jsonld_types_from_model!(data, model, type_root)
        # NOTE: currently only meant for a _compacted_ JSON-LD object
        data['@type'] = type_root if data['@type'].nil?
        data.each do |name_attr, val_attr|
          next if ['@id', '@type'].include?(name_attr)
          val_attr = [val_attr] unless val_attr.is_a?(Array)
          val_attr.each do |e|
            if is_object_an_embedded_entity_or_ref(e)
              type_embedded = model.get_embedded_entity_type_for_entity(type_root, name_attr)
              infer_jsonld_types_from_model!(e, model, type_embedded)
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

      def self.make_jsonld_datatypes_context_from_model(obj, model)
        # NOTE: currently only meant for a _compacted_ JSON-LD object
        context = {}
        obj.each do |name_attr, value_attr|
          next if ['@id', '@type'].include?(name_attr)
          datatype = model.get_datatype_for_entity(obj['@type'], name_attr)
          context[name_attr] = {
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

      def self.is_object_a_ref(obj)
        obj.is_a?(Hash) and obj.key?('@id') and (obj.keys - ['@id', '@type']).empty?
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

      def self.make_jsonld_hierarchy_context
        context = {
          # the following to allow easily adding inheritance triples
          "rdfs" => "http://www.w3.org/2000/01/rdf-schema#",
          "rdfs:subClassOf" => {
            "@type" => "@id"
          }
        }
        context
      end

      def self.make_jsonld_triples_from_hierarchy(model)
        triples = []
        model.hierarchy.each do |name_class, names_classes_parents|
          names_classes_parents.each do |name_class_parent|
            triples.append({
                             "@id" => URI.join(model.namespace, name_class).to_s,
                             "rdfs:subClassOf" => URI.join(model.namespace, name_class_parent).to_s
                           })
          end
        end
        triples
      end

      def self.compact_type(obj)
        obj2 = Marshal.load(Marshal.dump(obj))
        obj.each do |name_attr, content_attr|
          next if ['@id'].include?(name_attr)
          if name_attr.eql?('http://www.w3.org/1999/02/22-rdf-syntax-ns#type')
            obj2.delete(name_attr)
            obj2['@type'] = content_attr[0]['@value']
          end
        end
        obj2
      end

      def self.anyuris_to_uris(obj)
        obj2 = Marshal.load(Marshal.dump(obj))
        obj.each do |name_attr, content_attr|
          next if ['@id', '@type'].include?(name_attr)
          content_attr.each_with_index do |e, i|
            if e['@type'].eql?('http://www.w3.org/2001/XMLSchema#anyURI')
              obj2[name_attr][i] = {
                '@id' => e['@value']
              }
            end
          end
        end
        obj2
      end

      def self.compact_values(obj, f_conv)
        obj2 = Marshal.load(Marshal.dump(obj))
        obj.each do |name_attr, content_attr|
          next if ['@id', '@type'].include?(name_attr)
          content_attr.each_with_index do |e, i|
            unless e.key?('@id')
              obj2[name_attr][i] = f_conv.call(e['@value'], e['@type'])
            end
          end
        end
        obj2
      end

      def self.validate_literals(graph, hv)
        conform = true
        messages = []
        graph.each do |obj|
          obj.each do |name_attr, content_attr|
            next if ['@id', '@type'].include?(name_attr)
            content_attr.each do |e|
              if e.key?('@type')
                type = e['@type']
                value = e['@value']
                if hv.key?(type)
                  key = type
                else
                  key = hv.keys.find { |k| k.match?(type) }
                end
                if key.nil?
                  # conform &&= false
                  messages << "#{obj['@id']}, #{name_attr}, no validator found for type <#{type}>"
                else
                  conform &&= hv[key].call(hv, value)
                  messages << "#{obj['@id']}, #{name_attr}, value does not conform type <#{type}>"
                end
              end
            end
          end
        end
        [conform, messages]
      end

    end
  end
end
