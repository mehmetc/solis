
require_relative "../validator/validatorV1"
require_relative "../validator/validatorV2"


module Solis
  class ModelMock

    attr_reader :shapes, :validator, :namespace, :hierarchy

    def initialize(params = {})
      @graph = params[:graph]
      @parser = SHACLParser.new(@graph)
      @shapes = @parser.parse_shapes
      @validator = Solis::SHACLValidatorV2.new(@graph, :graph, {
        path_dir: params[:tmp_dir]
      })
      @prefix = params[:prefix]
      @namespace = params[:namespace]
      @hierarchy = params[:hierarchy] || {}
    end

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
