# Graphiti::Types[:year] = {
#   canonical_name: :year,
#   params: Graphiti::Types.create(::Integer) { |input|
#     Dry::Types["coercible.integer"][input]
#   },
#   read: Graphiti::Types.create(::Integer) { |input|
#     Dry::Types["coercible.integer"][input] if input
#   },
#   write: Graphiti::Types.create(::Integer) { |input|
#     Dry::Types["coercible.integer"][input] if input
#   },
#   kind: "scalar",
#   description: "contains only the year of a date"
# }

Graphiti::Types[:array_of_years] = {
  canonical_name: :year,
  params: Dry::Types["strict.array"].of(Graphiti::Types.create(::Integer) { |input|
    Dry::Types["coercible.integer"][input]
  }),
  read: Dry::Types["strict.array"].of(Graphiti::Types.create(::Integer) { |input|
    Dry::Types["coercible.integer"][input] if input
  }),
  write: Dry::Types["strict.array"].of(Graphiti::Types.create(::Integer) { |input|
    Dry::Types["coercible.integer"][input] if input
  }),
  kind: "array",
  description: "contains a list of the year of a date"
}

Graphiti::Types[:double] = {
  canonical_name: :double,
  params: Graphiti::Types.create(::Float) { |input|
    Dry::Types["coercible.float"][input]
  },
  read: Graphiti::Types.create(::Float) { |input|
    Dry::Types["coercible.float"][input] if input
  },
  write: Graphiti::Types.create(::Float) { |input|
    Dry::Types["coercible.float"][input] if input
  },
  kind: "scalar",
  description: "double type"
}

Graphiti::Types[:time] = {
  canonical_name: :time,
  params: Graphiti::Types::PresentParamsDateTime,
  read: Graphiti::Types::ReadDateTime,
  write: Graphiti::Types::WriteDateTime,
  kind: "scalar",
  description: "time type"
}


Graphiti::Types[:json] = {
  canonical_name: :json,
  params: Dry::Types["coercible.string"],
  read: Graphiti::Types.create(::JSON){|i|
    i = JSON.parse(i) if i.is_a?(String)
    Dry::Types["strict.array"][i]
  },
  write: Dry::Types["coercible.string"],
  kind: "scalar",
  description: "contains a json object"
}

duration_definition = Dry::Types['strict.date_time']
read_duration_type = duration_definition.constructor do |i|
  ActiveSupport::Duration.parse(i) if i.is_a?(String)
end

write_duration_type = duration_definition.constructor do |i|
  ActiveSupport::Duration.build(i&.to_i || 0).iso8601 if i.is_a?(String)
end

Graphiti::Types[:duration] = {
  canonical_name: :duration,
  params: read_duration_type,
  read: read_duration_type,
  write: write_duration_type,
  kind: "scalar",
  description: "contains ISO8601 Duration"
}

write_year = Graphiti::Types.create(:Year) do |i|
  input = RDF::Literal::Year.new(i)
  raise Graphiti::Errors::InvalidType unless input.valid?
  Dry::Types["strict.date"][input.object] if input
end

read_year = Graphiti::Types.create(:Year) do |i|
  if i.is_a?(RDF::Literal::Year)
    input = i
  else
    input = RDF::Literal::Year.new(i)
  end

  raise Graphiti::Errors::InvalidType unless input.valid?
  Dry::Types["strict.date"][input.object] if input
end

present_year = Graphiti::Types.create(:Year) do |i|
  input = i.object
  Dry::Types["strict.date"][input]
end

Graphiti::Types[:year] = {
  canonical_name: :year,
  params: present_year,
  read: read_year,
  write: write_year,
  kind: "scalar",
  description: "contains only the year of a date"
}