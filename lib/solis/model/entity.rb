

require 'linkeddata'
require 'json'
require 'ostruct'

require_relative '../utils/jsonld'


module Solis
  class Model

    class Entity < OpenStruct

      class MissingRefError < StandardError
        def initialize(ref)
          msg = "missing ref: #{ref}"
          super(msg)
        end
      end

      class ValidationError < StandardError
        def initialize(messages)
          msg = "validation error:\n#{messages}"
          super(msg)
        end
      end

      def initialize(obj, model, type, store)
        @model = model
        @type = type
        @store = store
        super(hash=obj)
        add_ids_if_not_exists!
      end

      def valid?

        # flatten + expand + clean internal data before validating it
        flattened_ordered_expanded = to_jsonld_flattened_ordered_expanded
        Solis::Utils::JSONLD.clean_flattened_expanded_from_unset_data!(flattened_ordered_expanded['@graph'])
        puts "=== flattened + deps sorted + expanded + cleaned JSON-LD:"
        puts JSON.pretty_generate(flattened_ordered_expanded)

        # validate literals
        conform_literals, messages_literals = Solis::Utils::JSONLD.validate_literals(
          flattened_ordered_expanded['@graph'],
          @model.hash_validator_literals
        )
        puts conform_literals
        puts messages_literals

        # add hierarchy triples
        flattened_ordered_expanded['@context'].merge!(Solis::Utils::JSONLD.make_jsonld_hierarchy_context)
        flattened_ordered_expanded['@graph'].concat(Solis::Utils::JSONLD.make_jsonld_triples_from_hierarchy(@model))
        puts "=== flattened + deps sorted + expanded + cleaned + hierarchy JSON-LD:"
        puts JSON.pretty_generate(flattened_ordered_expanded)

        # validate agains SHACL
        conform_shacl, messages_shacl = @model.validator.execute(flattened_ordered_expanded, :jsonld)
        puts conform_shacl
        puts messages_shacl

        [conform_literals, messages_literals, conform_shacl, messages_shacl]

      end

      def save(delayed=false)

        conform_literals, messages_literals, conform_shacl, messages_shacl = valid?

        unless conform_literals
          raise ValidationError.new(messages_literals)
        end
        unless conform_shacl
          raise ValidationError.new(messages_shacl)
        end

        flattened_ordered_expanded = to_jsonld_flattened_ordered_expanded

        flattened_ordered_expanded['@graph'].each do |obj|
          save_instance(obj)
        end

        unless delayed
          @store.run_operations
        end

      end

      def replace(obj)
        set_internal_data(obj)
        add_ids_if_not_exists!
      end

      def patch(obj_patch, opts={})
        # "plays" the patch on instance
        obj = get_internal_data
        patch_internal(obj, obj_patch, opts)
        set_internal_data(obj)
        # in case new references are added, get them an "id" where missing
        add_ids_if_not_exists!
      end

      def load(deep=false)
        obj = get_internal_data
        id = obj['@id']
        @store.get_data_for_id(id, @model.namespace, deep=deep)
        obj_res = @store.run_operations[0]
        replace(obj_res)
        obj_res
      end

      def referenced?
        obj = get_internal_data
        id = obj['@id']
        @store.ask_if_id_is_referenced(id)
        res = @store.run_operations[0]
        res
      end

      def destroy(delayed=false)
        obj = get_internal_data
        id = obj['@id']
        @store.delete_attributes_for_id(id)
        unless delayed
          res = @store.run_operations[0]
        end
        replace({})
      end

      def to_pretty_jsonld
        hash_data_jsonld = to_jsonld(get_internal_data)
        JSON.pretty_generate(hash_data_jsonld)
      end

      def to_pretty_jsonld_flattened_ordered_expanded
        flattened_ordered_expanded = to_jsonld_flattened_ordered_expanded
        JSON.pretty_generate(flattened_ordered_expanded)
      end







      private

      def deep_copy(obj)
        Marshal.load(Marshal.dump(obj))
      end

      def get_internal_data()
        # in case, in the future, diff algorithms are used,
        # deep_copy() would recreate all internal objects ref,
        # not fooling them.
        deep_copy(self.to_h).stringify_keys
      end

      def set_internal_data(obj)
        # deep_copy(): see get_internal_data
        self.marshal_load(deep_copy(obj).symbolize_keys)
      end

      def to_jsonld(hash_data_json)

        # infer "@type"(s) from model, when not available
        Solis::Utils::JSONLD.infer_jsonld_types_from_model!(hash_data_json, @model, @type)

        # make json-ld out of json
        hash_data_jsonld = Solis::Utils::JSONLD.json_object_to_jsonld(hash_data_json, {
          "@vocab" => @model.namespace
        })
        hash_data_jsonld
      end

      def add_ids_if_not_exists!
        obj = get_internal_data
        Solis::Utils::JSONLD.add_ids_if_not_exists!(obj, @model.namespace)
        set_internal_data(obj)
      end

      def expand_obj(obj)

        puts "======= object:"
        puts JSON.pretty_generate(obj)
        context_datatypes = Solis::Utils::JSONLD.make_jsonld_datatypes_context_from_model(obj, @model)

        context = {
          "@vocab" => @model.namespace
        }
        context.merge!(context_datatypes)

        puts "======= compacted single object:"
        hash_jsonld_compacted = Solis::Utils::JSONLD.json_object_to_jsonld(obj, context)
        puts JSON.pretty_generate(hash_jsonld_compacted)

        # benefits of expansion:
        # - all properties names are expanded to URIs
        # - all properties' content is expanded to an object with @type and @value
        # - single elements are converted to single-element array
        # - context is stripped out
        # Benefits above are important for triples upgrades.
        # Don't forget that:
        # - @type is also expanded to array.
        # - the whole object is single-element array
        hash_jsonld_expanded = Solis::Utils::JSONLD.expand(hash_jsonld_compacted)[0]

        hash_jsonld_expanded

      end

      def to_jsonld_flattened_ordered_expanded

        puts "=== internal JSON full:"
        puts JSON.pretty_generate(get_internal_data)

        hash_data_jsonld = to_jsonld(get_internal_data)
        puts "=== internal JSON-LD:"
        puts JSON.pretty_generate(hash_data_jsonld)

        flattened = Solis::Utils::JSONLD.flatten_jsonld(hash_data_jsonld)
        puts "=== flattened JSON-LD:"
        puts JSON.pretty_generate(flattened)
        flattened_ordered = Solis::Utils::JSONLD.sort_flat_jsonld_by_deps(flattened)
        puts "=== flattened + deps sorted JSON-LD:"
        puts JSON.pretty_generate(flattened_ordered)

        # expand single items
        flattened_ordered_expanded = deep_copy(flattened_ordered)
        flattened_ordered_expanded['@context'] = {}
        flattened_ordered_expanded['@graph'].map! do |obj|
          expand_obj(obj)
        end
        puts "=== flattened + deps sorted + expanded JSON-LD:"
        puts JSON.pretty_generate(flattened_ordered_expanded)

        flattened_ordered_expanded

      end

      def save_instance(hash_jsonld_expanded)

        puts "======= expanded single object:"
        puts JSON.pretty_generate(hash_jsonld_expanded)

        data = hash_jsonld_expanded

        id = data['@id']

        @store.save_id_with_type(id, hash_jsonld_expanded['@type'][0])

        data.each do |name_attr, content_attr|

          next if ['@id', '@type'].include?(name_attr)

          content_attr.each do |content|
            if content.key?('@value')
              # a core attribute
              if content['@value'].eql?('@unset')
                @store.delete_attribute_for_id(id, name_attr)
              else
                @store.save_attribute_for_id(id, name_attr, content['@value'], content['@type'])
              end
            elsif content.key?('@id')
              # a reference
              @store.save_attribute_for_id(id, name_attr, content['@id'], 'URI')
            end
          end

        end

      end

      def patch_internal(obj, obj_patch, opts)

        # iterate each object patch attribute
        obj_patch.each do |name_attr_patch, val_attr_patch|

          next if ['@id', '@type'].include?(name_attr_patch)

          # make attribute value always an array
          val_attr_patch = [val_attr_patch] unless val_attr_patch.is_a?(Array)

          # if resetting is requested, indicate it is not done yet
          is_attr_value_reset = true
          unless opts[:append_attributes]
            is_attr_value_reset = false
          end

          # iterate each patch attribute item
          type_attr = nil # will be defined just soon
          val_attr_patch.each do |item_val_patch|

            if item_val_patch.is_a?(Hash)
              # patch item is an embedded entity
              type_attr = 'entity'
              if obj[name_attr_patch].is_a?(Array)
                idx = obj[name_attr_patch].index do |item_val|
                  item_val['@id'] == item_val_patch['@id']
                end
                if idx.nil?
                  if opts[:add_missing_refs]
                    obj[name_attr_patch].push(item_val_patch)
                    # obj_loaded = Entity.new(item_val_patch, @model, obj['@type'], @store).load(deep=true)
                    # obj[name_attr_patch].push(obj_loaded)
                  else
                    raise MissingRefError.new(item_val_patch['@id'])
                  end
                else
                  patch_internal(obj[name_attr_patch][idx], item_val_patch, opts)
                end
              elsif obj[name_attr_patch].is_a?(Hash)
                if obj[name_attr_patch]['@id'] == item_val_patch['@id']
                  patch_internal(obj[name_attr_patch], item_val_patch, opts)
                else
                  if opts[:add_missing_refs]
                    obj[name_attr_patch] = item_val_patch
                  else
                    raise MissingRefError.new(item_val_patch['@id'])
                  end
                end
              else
                raise MissingRefError.new(item_val_patch['@id'])
              end
            else
              # patch item is either:
              # - an atomic type (or nil)
              # - an object like {"@type": "...", "@value": "..."}
              # - the reserved string "@unset"
              # - a meaningless object
              type_attr = 'data'
              unless is_attr_value_reset
                # reset attribute, and turn data into array if not yet
                obj[name_attr_patch] = []
                is_attr_value_reset = true
              end
              obj[name_attr_patch].push(item_val_patch)
            end

          end

          # since type of obj[name_attr_patch] could have been changed to array just above,
          # unroll 1-elem array.
          if type_attr.eql?('data')
            if obj[name_attr_patch].size == 1
              obj[name_attr_patch] = obj[name_attr_patch][0]
            end
          end

        end
      end

    end

  end
end