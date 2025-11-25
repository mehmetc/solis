class Solis::Query::ResultTransformer
  def initialize(model)
    @model = model
    @type_mappings = load_type_mappings
    @cardinality_map = build_cardinality_map
  end

  def transform(data)
    items = data.key?('@graph') ? data['@graph'] : [data]
    items.map { |item| transform_item(item) }
  end

  private

  def transform_item(item)
    clean_item = remove_json_ld_metadata(item)
    cast_and_shape(clean_item)
  end

  def cast_and_shape(item)
    item.each_with_object({}) do |(key, value), result|
      value = cast_value(value)
      result[key] = enforce_cardinality(key, value)
    end
  end

  # def cast_and_shape(item)
  #   item.each_with_object({}) do |(key, value), result|
  #     value = cast_value(value)
  #     value = enforce_cardinality(key, value)
  #     value = transform_nested_entity(key, value)
  #     result[key] = value
  #   end
  # end

  def transform_nested_entity(property_key, value)
    return value if @model.nil?

    metadata = @cardinality_map[property_key]
    return value if metadata.nil?

    datatype = metadata[:datatype]
    node = metadata[:node]

    # Check if datatype points to another entity (has a node)
    if node.is_a?(RDF::URI) && value.is_a?(Hash)
      # Recursively transform nested entity if we have its model
      # You'd need a way to resolve the node URI to the model class
      nested_model = resolve_model_from_node(datatype)
      Solis::Query::ResultTransformer.new(nested_model).transform(value) if nested_model
    elsif value.is_a?(Array) && value.all?(Hash)
      # Transform array of nested entities
      value.map { |v| transform_nested_entity(property_key, v) }
    else
      value
    end
  end

  def resolve_model_from_node(datatype_node)
    @model.graph.shape_as_model(datatype_node.to_s)
  end


  def remove_json_ld_metadata(item)
    item.reject { |key| key.start_with?('@') }
  end

  def cast_value(value)
    case value
    when Hash
      handle_typed_value(value)
    when Array
      value.map { |v| cast_value(v) }
    else
      value
    end
  end

  def handle_typed_value(value)
    return value unless value.key?('@type') && value.key?('@value')

    type = value['@type']
    raw_value = value['@value']

    cast_by_type(type, raw_value)
  end

  def cast_by_type(type, value)
    caster = @type_mappings[type]
    caster ? caster.call(value) : value
  end

  def enforce_cardinality(property_key, value)
    return value if @model.nil?

    metadata = @cardinality_map[property_key]
    return value if metadata.nil?

    maxcount = metadata[:maxcount]

    # If maxcount is nil or > 1, ensure it's an array
    if maxcount.nil? || maxcount > 1
      value.is_a?(Array) ? value : [value]
      # If maxcount is 0 or 1, ensure it's a single value
    else
      value.is_a?(Array) ? value.first : value
    end
  end

  def build_cardinality_map
    return {} if @model.nil? || @model.metadata.nil?

    attributes = @model.metadata[:attributes] || {}

    attributes.each_with_object({}) do |(property_name, property_metadata), map|
      map[property_name.to_s] = property_metadata
    end
  end

  def load_type_mappings
    {
      "http://www.w3.org/2001/XMLSchema#dateTime" => ->(v) { DateTime.parse(v) },
      "http://www.w3.org/2001/XMLSchema#date" => ->(v) { Date.parse(v) },
      "http://www.w3.org/2006/time#DateTimeInterval" => ->(v) { ISO8601::TimeInterval.parse(v) },
      "http://www.w3.org/2001/XMLSchema#boolean" => ->(v) { v == "true" },
      "http://www.w3.org/2001/XMLSchema#integer" => ->(v) { v.to_i },
      "http://www.w3.org/2001/XMLSchema#decimal" => ->(v) { BigDecimal(v) }
    }
  end
end