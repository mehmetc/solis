require 'json'
require_relative "../parser/shacl"

class JSONEntitiesWriter < Solis::Model::Writer::Generic
  def self.write(repository, options = {})
    return "No repository provided" if repository.nil?
    return "options[:model] missing" unless options.key?(:model)

    model = options[:model]
    shapes = model.shapes
    context_inv = model.context_inv

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

    entities.to_json
  end

  private

end