require 'test_helper'

# Tests for the configurable :validation option (Solis::Options key :validation):
#   :cardinality (default) — mandatory embedded relations enforced inline; no full
#                            SHACL pass (mandatory scalars and maxCount are NOT checked).
#   :warn                  — full SHACL pass; non-conformances logged, never raised.
#   :full                  — full SHACL pass; any non-conformance raises.
class ValidationModesTest < Minitest::Test
  def setup
    Solis::ConfigFile.path = './test/resources'
  end

  def configure(mode)
    options = Solis::ConfigFile[:solis].merge(validation: mode)
    solis = Solis::Graph.new(Solis::Shape::Reader::File.read(Solis::ConfigFile[:solis][:shacl]), options)
    solis.flush_all('http://solis.template/')
    solis
  end

  # :cardinality does not run a full SHACL pass — a missing mandatory scalar is
  # allowed through (this preserves the pre-refactor behaviour).
  def test_cardinality_mode_allows_missing_scalar_mandatory
    configure(:cardinality)
    result = Student.new({ id: 'vm-card-scalar', last_name: 'Only', age: 30 }).save
    assert_equal 'vm-card-scalar', result.id
  end

  # :cardinality does not enforce maxCount.
  def test_cardinality_mode_allows_maxcount_violation
    configure(:cardinality)
    result = Student.new({ id: 'vm-card-max', first_name: %w[One Two], last_name: 'X', age: 21 }).save
    assert_equal 'vm-card-max', result.id
  end

  # :warn runs SHACL but never raises for non-conformances.
  def test_warn_mode_allows_maxcount_violation
    configure(:warn)
    result = Student.new({ id: 'vm-warn-max', first_name: %w[One Two], last_name: 'X', age: 22 }).save
    assert_equal 'vm-warn-max', result.id, ':warn mode should log but not raise'
  end

  # :full runs SHACL and raises on a missing mandatory scalar.
  def test_full_mode_rejects_missing_scalar_mandatory
    configure(:full)
    err = assert_raises(Solis::Error::InvalidAttributeError) do
      Student.new({ id: 'vm-full-scalar', last_name: 'Only', age: 31 }).save
    end
    assert_match(/SHACL/, err.message)
  end

  # :full runs SHACL and raises on a maxCount violation.
  def test_full_mode_rejects_maxcount_violation
    configure(:full)
    err = assert_raises(Solis::Error::InvalidAttributeError) do
      Student.new({ id: 'vm-full-max', first_name: %w[One Two], last_name: 'X', age: 23 }).save
    end
    assert_match(/SHACL/, err.message)
  end

  # A clean entity saves successfully under the strictest mode.
  def test_full_mode_accepts_valid_entity
    configure(:full)
    result = Student.new({ id: 'vm-full-ok', first_name: 'Valid', last_name: 'Entity', age: 24 }).save
    assert_equal 'vm-full-ok', result.id

    Student.new({ id: 'vm-full-ok' }).destroy
  end
end
