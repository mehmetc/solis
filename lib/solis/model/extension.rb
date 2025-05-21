require_relative "../validator/validatorV1"
require_relative "../validator/validatorV2"
require_relative "validator_literals"
require_relative "literals/edtf"
require_relative "literals/iso8601"

#TODO: move into Solis::Model
module Solis
  class Model
    module Extension
      def get_embedded_entity_type_for_entity(name_entity, name_attr)
        _get_embedded_entity_type_for_entity(name_entity, name_attr)
      end

      def get_datatype_for_entity(name_entity, name_attr)
        _get_datatype_for_entity(name_entity, name_attr)
      end

      def get_parent_entities_for_entity(name_entity)
        _get_parent_entities_for_entity(name_entity)
      end

      def get_all_parent_entities_for_entity(name_entity)
        list = [name_entity]
        idx = 0
        while true
          if idx > list.length
            break
          end
          list += _get_parent_entities_for_entity(list[idx])
          idx += 1
        end
        list[1..]
      end

      def get_info_for_entity(name_entity)
        @shapes[name_entity]
      end

      def get_properties_info_for_entity(name_entity)
        properties = @shapes[name_entity][:properties]
        names_parent_classes = get_all_parent_entities_for_entity(name_entity)
        names_parent_classes.each do |name_parent_class|
          properties.merge!(@shapes[name_parent_class][:properties])
        end
        properties
      end

      private

      def _get_embedded_entity_type_for_entity(name_entity, name_attr)
        res = nil
        # first check in the SHACL shapes
        if SHACLSHapes.shape_exists?(@shapes, name_entity)
          res = SHACLSHapes.get_property_class_for_shape(@shapes, name_entity, name_attr)
        end
        if res.nil?
          # otherwise navigate classes hierarchy up and try again
          names_entities_parents = @hierarchy[name_entity]
          names_entities_parents.each do |name_entity_parent|
            next unless res.nil?
            res = _get_embedded_entity_type_for_entity(name_entity_parent, name_attr)
          end unless names_entities_parents.nil?
        end
        res
      end

      def _get_datatype_for_entity(name_entity, name_attr)
        res = nil
        # first check in the SHACL shapes
        if SHACLSHapes.shape_exists?(@shapes, name_entity)
          res = SHACLSHapes.get_property_datatype_for_shape(@shapes, name_entity, name_attr)
        end
        if res.nil?
          # otherwise navigate classes hierarchy up and try again
          names_entities_parents = @hierarchy[name_entity]
          names_entities_parents.each do |name_entity_parent|
            next unless res.nil?
            res = _get_datatype_for_entity(name_entity_parent, name_attr)
          end unless names_entities_parents.nil?
        end
        res
      end

      def _get_parent_entities_for_entity(name_entity)
        names_entities_parents = []
        names_nodes_parents = SHACLSHapes.get_parent_shapes_for_shape(@shapes, name_entity)
        names_entities_parents += names_nodes_parents.map do |uri|
          res = nil
          @shapes.each do |k, v|
            next unless v[:uri] == uri
            res = k
          end
          res
        end
        names_entities_parents += @hierarchy[name_entity] || []
        names_entities_parents
      end

    end
  end
end
