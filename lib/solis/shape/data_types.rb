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
    Dry::Types["coercible.integer"][input || 0]
  }),
  read: Dry::Types["strict.array"].of(Graphiti::Types.create(::Integer) { |input|
    Dry::Types["coercible.integer"][input || 0] if input
  }),
  write: Dry::Types["strict.array"].of(Graphiti::Types.create(::Integer) { |input|
    Dry::Types["coercible.integer"][input || 0] if input
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

    # case i
    # when i.is_a?(Array)
    #   Dry::Types["strict.array"][i]
    # when i.is_a?(Hash)
    #   Dry::Types["strict.hash"][i]
    # end

    i
  },
  write: Dry::Types["coercible.string"],
  kind: "scalar",
  description: "contains a json object"
}

duration_definition = Dry::Types['strict.string']
read_duration_type = duration_definition.constructor do |i|
  if i.is_a?(Array)
    (i[0].send(:months) + i[1].send(:seconds)).iso8601
  elsif i.is_a?(Float) || i.is_a?(Integer)
    ActiveSupport::Duration.build(i).iso8601
  end
  #ActiveSupport::Duration.parse(i[0]) if i.is_a?(String)
end

write_duration_type = duration_definition.constructor do |i|
  if i.is_a?(String)
    ActiveSupport::Duration.parse(i).iso8601
  else
    ActiveSupport::Duration.build(i&.to_i || 0).iso8601
  end
end

Graphiti::Types[:duration] = {
  canonical_name: :duration,
  params: read_duration_type,
  read: read_duration_type,
  write: write_duration_type,
  kind: "scalar",
  description: "contains ISO8601 Duration"
}

Graphiti::Types[:array_of_durations] = {
  canonical_name: :duration,
  params: Dry::Types["strict.array"].of(Graphiti::Types[:duration]),
  read: Dry::Types["strict.array"].of(Graphiti::Types[:duration]),
  write: Dry::Types["strict.array"].of(Graphiti::Types[:duration]),
  kind: "array",
  description: "contains a list of durations"
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