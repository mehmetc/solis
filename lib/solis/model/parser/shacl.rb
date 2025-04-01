require 'linkeddata'
require 'active_support/all'

class SHACLParser
  attr_reader :shapes_graph

  def initialize(shacl_file)
    @shapes_graph = RDF::Graph.load(shacl_file, format: :ttl)
  end

  def parse_shapes
    shapes = {}

    shapes_graph.query([nil, RDF.type, RDF::Vocab::SHACL.NodeShape]) do |shape|
      class_uri = shape.subject.to_s
      shape_name = shapes_graph.query([shape.subject, RDF::Vocab::SHACL.name, nil]).first_object.to_s
      shapes[shape_name] = {properties: {}, shape: {raw: shape, uri: class_uri}}

      shapes_graph.query([shape.subject, RDF::Vocab::SHACL.property, nil]) do |property_shape|
        property_uri = property_shape.object
        property_info = extract_property_info(property_uri)

        shapes[shape_name][:properties][property_info[:name]] = property_info
      end
    end

    shapes
  end

  private

  def extract_property_info(property_uri)
    property_name = shapes_graph.query([property_uri, RDF::Vocab::SHACL.name, nil]).first_object.to_s
    property_info = { name: property_name.underscore, constraints: {}, shape:{name: property_name} }

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

    property_info
  end
end

parser = SHACLParser.new('bibframe.ttl')
shacl_rules = parser.parse_shapes

puts JSON.pretty_generate(shacl_rules)
