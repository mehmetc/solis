require 'rdf'
require 'rdf/turtle'
require 'shacl'
require 'json'
require_relative 'generic'

class JSONSchemaWriter < Solis::Model::Writer
  def self.write(shacl_file)
    graph = RDF::Graph.load(shacl_file, format: :ttl)
    json_schema = {
      "$schema" => "http://json-schema.org/draft-07/schema#",
      "type" => "object",
      "properties" => {},
      "required" => []
    }

    graph.query([nil, RDF.type, SHACL.NodeShape]) do |shape|
      shape_subject = shape.subject

      graph.query([shape_subject, SHACL.property, nil]) do |prop_stmt|
        prop_subject = prop_stmt.object
        prop_name = graph.query([prop_subject, SHACL.path, nil]).first&.object.to_s
        datatype = graph.query([prop_subject, SHACL.datatype, nil]).first&.object
        min_count = graph.query([prop_subject, SHACL.minCount, nil]).first&.object&.to_i
        max_count = graph.query([prop_subject, SHACL.maxCount, nil]).first&.object&.to_i
        pattern = graph.query([prop_subject, SHACL.pattern, nil]).first&.object&.to_s

        json_schema["properties"][prop_name] = {}
        json_schema["properties"][prop_name]["type"] = datatype.to_s.split("#").last.downcase if datatype
        json_schema["properties"][prop_name]["pattern"] = pattern if pattern

        json_schema["required"] << prop_name if min_count && min_count > 0
        json_schema["properties"][prop_name]["maxItems"] = max_count if max_count
      end
    end

    JSON.pretty_generate(json_schema)
  end
end