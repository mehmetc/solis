require 'linkeddata'
require 'active_support/all'

class SHACLParser

  class MissingShapeNameError < StandardError
    def initialize(uri_shape)
      msg = "shape #{uri_shape.to_s} has no 'sh:name'"
      super(msg)
    end
  end

  class MissingPropertyNameError < StandardError
    def initialize(uri_shape, uri_property)
      msg = "shape #{uri_shape.to_s} has a property with no 'sh:name'"
      super(msg)
    end
  end

  attr_reader :shapes_graph

  def initialize(shapes_graph)
    @shapes_graph = shapes_graph
  end

  def parse_shapes
    shapes = {}
    @shapes_graph.query([nil, RDF.type, RDF::Vocab::SHACL.NodeShape]) do |shape|
      shape_uri = shape.subject.to_s
      shape_name = shapes_graph.query([shape.subject, RDF::Vocab::SHACL.name, nil]).first_object.to_s
      if shape_name.empty?
        raise MissingShapeNameError.new(shape.subject)
      end
      shapes[shape_name] = { properties: {}, uri: shape_uri, nodes: [], closed: false, plural: nil }

      @shapes_graph.query([shape.subject, RDF::Vocab::SHACL.node, nil]) do |stmt|
        node_name = stmt.object.to_s
        shapes[shape_name][:nodes] << node_name
      end

      shapes[shape_name][:target_class] = @shapes_graph.first_object([shape.subject, RDF::Vocab::SHACL.targetClass, nil])&.to_s

      shapes[shape_name][:closed] = @shapes_graph.first_object([shape.subject, RDF::Vocab::SHACL.closed, nil])
      shapes[shape_name][:closed] = false if shapes[shape_name][:closed].nil?

      shapes[shape_name][:plural] = @shapes_graph.first_object([shape.subject, RDF::Vocab::SKOS.altLabel, nil])&.to_s

      @shapes_graph.query([shape.subject, RDF::Vocab::SHACL.property, nil]) do |property_shape|
        property_uri = property_shape.object
        property_info = extract_property_info(property_uri)

        if property_info[:name].empty?
          raise MissingPropertyNameError.new(shape.subject, property_uri)
        end

        shapes[shape_name][:properties][property_info[:name]] = property_info
      end
    end
    shapes
  end

  private

  def extract_property_info(property_uri)
    property_name = shapes_graph.query([property_uri, RDF::Vocab::SHACL.name, nil]).first_object.to_s
    property_info = { name: property_name, constraints: {} }

    shapes_graph.query([property_uri, RDF::Vocab::SHACL.description, nil]) do |max_count|
      property_info[:description] = max_count.object.to_s
    end

    shapes_graph.query([property_uri, RDF::Vocab::SHACL.datatype, nil]) do |datatype|
      property_info[:constraints][:datatype] = datatype.object.to_s
    end

    shapes_graph.query([property_uri, RDF::Vocab::SHACL.minCount, nil]) do |min_count|
      property_info[:constraints][:min_count] = min_count.object.to_i
    end

    shapes_graph.query([property_uri, RDF::Vocab::SHACL.maxCount, nil]) do |max_count|
      property_info[:constraints][:max_count] = max_count.object.to_i
    end

    shapes_graph.query([property_uri, RDF::Vocab::SHACL.class, nil]) do |klass|
      property_info[:constraints][:class] = klass.object.path[1..] rescue nil
    end

    property_info
  end
end

module Shapes

  def self.get_property_datatype_for_shape(shapes, name_shape, name_property)
    shapes.dig(name_shape, :properties, name_property, :constraints, :datatype)
  end

  def self.get_property_class_for_shape(shapes, name_shape, name_property)
    shapes.dig(name_shape, :properties, name_property, :constraints, :class)
  end

  def self.get_parent_shapes_for_shape(shapes, name_shape)
    shapes.dig(name_shape, :nodes) || []
  end

  def self.shape_exists?(shapes, name_shape)
    shapes.key?(name_shape)
  end

end