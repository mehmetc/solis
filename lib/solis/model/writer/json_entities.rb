require 'json'
require_relative "../parser/shacl"

class JSONEntitiesWriter < Solis::Model::Writer::Generic
  def self.write(repository, options = {})

    # NOTE:
    # ideally, options[:model] should not be here, but only:
    # - shapes
    # - context
    # - context_inv
    # - ...
    # But also don't want to remove those methods from model and put them here,
    # because they can be useful for model instance too.
    # Solution: in Model, make public class methods, e.g. get_parent_entities_for_entity(name_entity, shapes)
    # Then you can use this both in model instance, than here.

    return "No repository provided" if repository.nil?
    return "options[:model] missing" unless options.key?(:model)

    raw = options[:raw] || false

    model = options[:model]
    shapes = model.shapes
    context_inv = model.context_inv

    graph_namespace = model.namespace
    graph_title = model.title
    graph_version = model.version
    graph_version_counter = model.version_counter
    graph_description = model.description

    entities = {}

    names_entities = Shapes.get_all_classes(shapes)
    names_entities.each do |name_entity|
      # NOTE: infer CLASS property from SHAPE property.
      # If multiple shapes have the same target class (rare but can happen ...), just take one value.
      names_shapes = Shapes.get_shapes_for_class(shapes, name_entity)
      names = names_shapes.collect { |s| shapes[s][:name] }
      name = names[0]
      descriptions = names_shapes.collect { |s| shapes[s][:description] }
      description = descriptions[0]
      plurals = names_shapes.collect { |s| shapes[s][:plural] }
      plural = plurals[0]
      snake_case_name = Solis::Utils::String.camel_to_snake(Solis::Utils::String.extract_name_from_uri(name_entity))
      namespace_entity = Solis::Utils::String.extract_namespace_from_uri(name_entity)
      prefix_entity = context_inv[namespace_entity]
      entities[name_entity] = {
        direct_parents: model.get_parent_entities_for_entity(name_entity),
        all_parents: model.get_all_parent_entities_for_entity(name_entity),
        properties: model.get_properties_info_for_entity(name_entity),
        own_properties: model.get_own_properties_list_for_entity(name_entity),
        name: name,
        prefix: prefix_entity,
        description: description,
        plural: plural,
        snake_case_name: snake_case_name
      }
    end

    data = {
      namespace: graph_namespace,
      title: graph_title,
      version: graph_version,
      version_counter: graph_version_counter,
      description: graph_description,
      entities: entities
    }

    return data if raw
    data.to_json
  end

  private

end