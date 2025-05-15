require_relative "../validator/validatorV1"
require_relative "../validator/validatorV2"
require_relative "validator_literals"
require_relative "literals/edtf"
require_relative "literals/iso8601"

#TODO: move into Solis::Model
module Solis
  class Model
    module Extension
      def get_embedded_class_type_for_class_property(name_class, name_attr)
        _get_embedded_class_type_for_class_property(name_class, name_attr)
      end

      def get_datatype_for_class_property(name_class, name_attr)
        _get_datatype_for_class_property(name_class, name_attr)
      end

      private

      def _get_embedded_class_type_for_class_property(name_class, name_attr)
        res = nil
        # first check in the SHACL shapes
        if SHACLSHapes.shape_exists?(@shapes, name_class)
          res = SHACLSHapes.get_property_class_for_shape(@shapes, name_class, name_attr)
        end
        if res.nil?
          # otherwise navigate classes hierarchy up and try again
          names_classes_parents = @hierarchy[name_class]
          names_classes_parents.each do |name_class_parent|
            next unless res.nil?
            res = _get_embedded_class_type_for_class_property(name_class_parent, name_attr)
          end unless names_classes_parents.nil?
        end
        res
      end

      def _get_datatype_for_class_property(name_class, name_attr)
        res = nil
        # first check in the SHACL shapes
        if SHACLSHapes.shape_exists?(@shapes, name_class)
          res = SHACLSHapes.get_property_datatype_for_shape(@shapes, name_class, name_attr)
        end
        if res.nil?
          # otherwise navigate classes hierarchy up and try again
          names_classes_parents = @hierarchy[name_class]
          names_classes_parents.each do |name_class_parent|
            next unless res.nil?
            res = _get_datatype_for_class_property(name_class_parent, name_attr)
          end unless names_classes_parents.nil?
        end
        res
      end

    end
  end
end
