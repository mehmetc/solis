

require 'linkeddata'
require 'json'
require 'ostruct'

require_relative '../utils/jsonld'
require_relative '../utils/json'


module Solis
  class Model

    class Entity < OpenStruct
      attr_reader :errors
      def method_missing(method, *args, &block)
        raise Solis::Error::PropertyNotFound unless get_properties_info.keys.include?(method.to_s)
        super
      end

      class MissingTypeError < StandardError
        def initialize
          msg = "entity has no type"
          super(msg)
        end
      end

      class TypeNotFoundError < StandardError
        def initialize
          msg = "entity has type not found"
          super(msg)
        end
      end

      class TypeMismatchError < StandardError
        def initialize
          msg = "'type' provided to entity constructor and @type (or _type) in 'data' provided to constructor mismatch"
          super(msg)
        end
      end

      class MissingStoreError < StandardError
        def initialize
          msg = "entity was provided no store"
          super(msg)
        end
      end

      class MissingOjbectIdError < StandardError
        def initialize
          msg = "entity has no @id"
          super(msg)
        end
      end

      class MissingRefError < StandardError
        def initialize(ref)
          msg = "missing ref: '#{ref}'"
          super(msg)
        end
      end

      class PatchTypeMismatchError < StandardError
        def initialize(ref)
          msg = "patch for '#{ref}' is an object, but data to patch is not"
          super(msg)
        end
      end

      class ValidationError < StandardError
        def initialize(messages)
          msg = "validation error:\n#{messages}"
          super(msg)
        end
      end

      class LoadError < StandardError
        def initialize(ref)
          msg = "no entity with id '#{ref}'"
          super(msg)
        end
      end

      class DestroyError < StandardError
        def initialize(msg)
          msg = "#{msg}"
          super(msg)
        end
      end

      class InternalObjectMissingTypeError < StandardError
        def initialize(obj)
          msg = "following internal object has no type:\n"
          msg += JSON.pretty_generate(obj)
          super(msg)
        end
      end

      def initialize(obj, model, type, store)
        super(hash={})
        @model = model
        @errors = []
        if type.nil?
          raise MissingTypeError
        end
        # if model.shapes[type].nil?
        #   raise TypeNotFoundError
        # end
        @type = type
        @store = store
        set_internal_data_from_jsonld(obj)
        _obj = get_internal_data_as_jsonld
        if !_obj['@type'].nil? && !_obj['@type'].eql?(type)
          raise TypeMismatchError
        end
        @context = {
          "@vocab" => @model.namespace
        }
        unless _obj['@context'].nil?
          @context = _obj['@context']
          _obj.delete('@context')
        end
        set_internal_data_from_jsonld(_obj)
        add_ids_if_not_exists!
      end

      def to_pre_validate_jsonld

        # flatten + expand + clean internal data before validating it
        flattened_ordered_expanded = to_jsonld_flattened_ordered_expanded
        Solis::Utils::JSONLD.clean_flattened_expanded_from_unset_data!(flattened_ordered_expanded['@graph'])
        @model.logger.debug("=== flattened + deps sorted + expanded + cleaned JSON-LD:")
        @model.logger.debug(JSON.pretty_generate(flattened_ordered_expanded))

        # add hierarchy triples
        flattened_ordered_expanded['@context'].merge!(Solis::Utils::JSONLD.make_jsonld_hierarchy_context)
        flattened_ordered_expanded['@graph'].concat(Solis::Utils::JSONLD.make_jsonld_triples_from_hierarchy(@model))
        @model.logger.debug("=== flattened + deps sorted + expanded + cleaned + hierarchy JSON-LD:")
        @model.logger.debug(JSON.pretty_generate(flattened_ordered_expanded))

        flattened_ordered_expanded

      end

      def to_pretty_pre_validate_jsonld
        JSON.pretty_generate(to_pre_validate_jsonld)
      end

      def validate

        flattened_ordered_expanded = to_pre_validate_jsonld

        # validate literals
        # NOTE: the following can be even moved inside any SHACL validator
        graph_data = RDF::Graph.new << JSON::LD::API.toRdf(flattened_ordered_expanded)
        conform_literals = graph_data.valid?
        messages_literals = []
        #puts flattened_ordered_expanded.to_json

        graph_data.each do |statement|
          begin
            statement.object.validate!
          rescue ArgumentError => e
            messages_literals << [statement.subject.to_s, statement.predicate.to_s, e.message]
          end
        end

        # validate agains SHACL
        conform_shacl, messages_shacl = @model.validator.execute(flattened_ordered_expanded, :jsonld)

        [conform_literals, messages_literals, conform_shacl, messages_shacl]

      end

      def valid?
        @errors = []
        conform_literals, messages_literals, conform_shacl, messages_shacl = validate
        @errors += messages_literals
        @errors += messages_shacl
        res = (conform_literals and conform_shacl)
        res

      end

      def save(delayed=false)

        check_store_exists

        conform_literals, messages_literals, conform_shacl, messages_shacl = validate

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

      def get_internal_data()
        obj = deep_copy(self.to_h).stringify_keys
        obj
      end

      def replace(obj)
        set_internal_data_from_jsonld(obj)
        add_ids_if_not_exists!
      end

      def patch(obj_patch, opts={})
        # make default opts
        _opts = deep_copy(opts)
        _opts[:add_missing_refs] = opts[:add_missing_refs] || false
        _opts[:autoload_missing_refs] = opts[:autoload_missing_refs] || false
        _opts[:append_attributes] = opts[:append_attributes] || false
        # get internal data
        obj = get_internal_data_as_jsonld
        # infer type if reference autoload is requested
        if _opts[:autoload_missing_refs]
          Solis::Utils::JSONLD.infer_jsonld_types_from_model!(obj, @model, @context, @type)
        end
        # "plays" the patch on instance
        _obj_patch = Solis::Utils::JSONUtils.deep_replace_prefix_in_name_attr(obj_patch, '_', '@')
        patch_internal(obj, _obj_patch, _opts)
        set_internal_data_from_jsonld(obj)
        # in case new references are added, get them an "id" where missing
        add_ids_if_not_exists!
      end

      def load(deep=false)
        check_store_exists
        obj = get_internal_data_as_jsonld
        check_obj_has_id(obj)
        id = obj['@id']
        id_op = @store.get_data_for_id(id, @context, deep=deep)
        obj_res, context_res = @store.run_operations(ids=[id_op])[id_op]
        if obj_res.empty?
          raise LoadError.new(id)
        end
        replace(obj_res)
        @type = obj_res['@type'] unless obj_res['@type'].nil?
        @context = context_res
        obj_res
      end

      def referenced?
        check_store_exists
        obj = get_internal_data_as_jsonld
        check_obj_has_id(obj)
        id = obj['@id']
        id_op = @store.ask_if_id_is_referenced(id)
        res = @store.run_operations(ids=[id_op])[id_op]
        res
      end

      def exists?
        check_store_exists
        obj = get_internal_data_as_jsonld
        check_obj_has_id(obj)
        id = obj['@id']
        id_op = @store.ask_if_id_exists(id)
        res = @store.run_operations(ids=[id_op])[id_op]
        res
      end

      def destroy(delayed=false)
        check_store_exists
        obj = get_internal_data_as_jsonld
        check_obj_has_id(obj)
        id = obj['@id']
        id_op = @store.delete_attributes_for_id(id)
        unless delayed
          res = @store.run_operations(ids=[id_op])[id_op]
          unless res['success']
            raise DestroyError.new(res['message'])
          end
        end
        replace({})
        id_op
      end

      def get_shape
        @model.get_shape_for_entity(Solis::Utils::JSONLD.expand_term(@type, @context))
      end

      def get_properties_info
        @model.get_properties_info_for_entity(Solis::Utils::JSONLD.expand_term(@type, @context))
      end

      def to_pretty_jsonld
        hash_data_jsonld = to_jsonld(get_internal_data_as_jsonld)
        JSON.pretty_generate(hash_data_jsonld)
      end

      def to_pretty_jsonld_flattened_ordered_expanded
        flattened_ordered_expanded = to_jsonld_flattened_ordered_expanded
        JSON.pretty_generate(flattened_ordered_expanded)
      end







      private

      def check_store_exists
        if @store.nil?
          raise MissingStoreError
        end
      end

      def check_obj_has_id(obj)
        unless obj.key?('@id')
          raise MissingOjbectIdError
        end
      end

      def deep_copy(obj)
        Marshal.load(Marshal.dump(obj))
      end

      def get_internal_data_as_jsonld()
        # in case, in the future, diff algorithms are used,
        # deep_copy() would recreate all internal objects ref,
        # not fooling them.
        obj = deep_copy(self.to_h).stringify_keys
        obj = Solis::Utils::JSONUtils.deep_replace_prefix_in_name_attr(obj, '_', '@')
        obj
      end

      def set_internal_data_from_jsonld(obj)
        # deep_copy(): see get_internal_data_as_jsonld
        obj2 = deep_copy(obj)
        obj2 = Solis::Utils::JSONUtils.deep_replace_prefix_in_name_attr(obj2, '@', '_')
        self.marshal_load(obj2.symbolize_keys)
      end

      def to_jsonld(hash_data_json)

        # infer "@type"(s) from model, when not available
        Solis::Utils::JSONLD.infer_jsonld_types_from_model!(hash_data_json, @model, @context, @type)

        # make json-ld out of json
        # hash_data_jsonld = Solis::Utils::JSONLD.json_object_to_jsonld(hash_data_json, {
        #   "@vocab" => @model.namespace
        # })
        hash_data_jsonld = Solis::Utils::JSONLD.json_object_to_jsonld(hash_data_json, @context)
        hash_data_jsonld
      end

      def add_ids_if_not_exists!
        obj = get_internal_data_as_jsonld
        Solis::Utils::JSONLD.add_ids_if_not_exists!(obj, @model.namespace)
        set_internal_data_from_jsonld(obj)
      end

      def expand_obj(obj)

        @model.logger.debug("======= object:")
        @model.logger.debug(JSON.pretty_generate(obj))
        context_datatypes = Solis::Utils::JSONLD.make_jsonld_datatypes_context_from_model(obj, @model, @context)

        # context = {
        #   "@vocab" => @model.namespace
        # }
        # context.merge!(context_datatypes)
        context = deep_copy(@context)
        context.merge!(context_datatypes) if context.is_a?(Hash)

        @model.logger.debug("======= compacted single object:")
        hash_jsonld_compacted = Solis::Utils::JSONLD.json_object_to_jsonld(obj, context)
        @model.logger.debug(JSON.pretty_generate(hash_jsonld_compacted))

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

        @model.logger.debug("=== internal JSON full:")
        @model.logger.debug(JSON.pretty_generate(get_internal_data_as_jsonld))

        hash_data_jsonld = to_jsonld(get_internal_data_as_jsonld)
        @model.logger.debug("=== internal JSON-LD:")
        @model.logger.debug(JSON.pretty_generate(hash_data_jsonld))

        flattened = Solis::Utils::JSONLD.flatten_jsonld(hash_data_jsonld)
        @model.logger.debug("=== flattened JSON-LD:")
        @model.logger.debug(JSON.pretty_generate(flattened))
        flattened_ordered = Solis::Utils::JSONLD.sort_flat_jsonld_by_deps(flattened)
        @model.logger.debug("=== flattened + deps sorted JSON-LD:")
        @model.logger.debug(JSON.pretty_generate(flattened_ordered))

        # expand single items
        flattened_ordered_expanded = deep_copy(flattened_ordered)
        # flattened_ordered_expanded['@context'] = {}
        flattened_ordered_expanded['@context'] = deep_copy(@context)
        flattened_ordered_expanded['@graph'].map! do |obj|
          expand_obj(obj)
        end
        @model.logger.debug("=== flattened + deps sorted + expanded JSON-LD:")
        @model.logger.debug(JSON.pretty_generate(flattened_ordered_expanded))

        flattened_ordered_expanded

      end

      def save_instance(hash_jsonld_expanded)

        @model.logger.debug("======= expanded single object:")
        @model.logger.debug(JSON.pretty_generate(hash_jsonld_expanded))

        data = hash_jsonld_expanded

        id = data['@id']

        unless hash_jsonld_expanded.key?('@type')
          raise InternalObjectMissingTypeError.new(hash_jsonld_expanded)
        end
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

            if Solis::Utils::JSONLD.is_object_an_embedded_entity_or_ref(item_val_patch)
              # patch item is an embedded entity
              type_attr = 'entity'
              if obj[name_attr_patch].is_a?(Array)
                idx = obj[name_attr_patch].index do |item_val|
                  item_val['@id'] == item_val_patch['@id']
                end
                if idx.nil?
                  if opts[:add_missing_refs]
                    if opts[:autoload_missing_refs]
                      obj_loaded = Entity.new(item_val_patch, @model, obj['@type'], @store).load(deep=true)
                      obj[name_attr_patch].push(obj_loaded)
                    else
                      obj[name_attr_patch].push(item_val_patch)
                    end
                    idx = obj[name_attr_patch].size - 1
                    patch_internal(obj[name_attr_patch][idx], item_val_patch, opts)
                  else
                    raise MissingRefError.new(item_val_patch['@id'])
                  end
                else
                  patch_internal(obj[name_attr_patch][idx], item_val_patch, opts)
                end
              elsif Solis::Utils::JSONLD.is_object_an_embedded_entity_or_ref(obj[name_attr_patch])
                if obj[name_attr_patch]['@id'] == item_val_patch['@id']
                  patch_internal(obj[name_attr_patch], item_val_patch, opts)
                else
                  if opts[:add_missing_refs]
                    if opts[:autoload_missing_refs]
                      obj_loaded = Entity.new(item_val_patch, @model, obj['@type'], @store).load(deep=true)
                      obj[name_attr_patch] = obj_loaded
                    else
                      obj[name_attr_patch] = item_val_patch
                    end
                    patch_internal(obj[name_attr_patch], item_val_patch, opts)
                  else
                    raise MissingRefError.new(item_val_patch['@id'])
                  end
                end
              else
                raise PatchTypeMismatchError.new(item_val_patch['@id'])
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