require "test_helper"

# Unit tests for custom Sideload classes (BelongsTo, HasOne, HasMany)
# These tests verify that load_params and children_for work correctly
# for the SPARQL-based data model where relationship resolution uses
# instance variables rather than ActiveRecord-style foreign keys.
class SideloadTest < Minitest::Test

  # Minimal stub for parent/child objects with instance variables
  class StubModel
    attr_accessor :id

    def initialize(id, relations = {})
      @id = id
      relations.each do |key, value|
        instance_variable_set("@#{key}", value)
      end
    end
  end

  # Minimal stub for the query object passed to load_params
  class StubQuery
    attr_reader :association_name

    def initialize(association_name)
      @association_name = association_name
    end

    def hash
      {}
    end
  end

  # --- sideloading_classes mapping ---

  def test_sideloading_classes_uses_custom_belongs_to
    classes = Solis::SparqlAdaptor.sideloading_classes
    assert_equal Solis::BelongsTo, classes[:belongs_to]
  end

  def test_sideloading_classes_uses_custom_has_one
    classes = Solis::SparqlAdaptor.sideloading_classes
    assert_equal Solis::HasOne, classes[:has_one]
  end

  def test_sideloading_classes_uses_custom_has_many
    classes = Solis::SparqlAdaptor.sideloading_classes
    assert_equal Solis::HasMany, classes[:has_many]
  end

  def test_sideloading_classes_uses_graphiti_many_to_many
    classes = Solis::SparqlAdaptor.sideloading_classes
    assert_equal ::Graphiti::Sideload::ManyToMany, classes[:many_to_many]
  end

  # --- BelongsTo ---

  def test_belongs_to_load_params_extracts_child_ids
    child_a = StubModel.new("child-1")
    child_b = StubModel.new("child-2")
    parent1 = StubModel.new("parent-1", { "skill" => child_a })
    parent2 = StubModel.new("parent-2", { "skill" => child_b })

    sideload = Solis::BelongsTo.allocate
    sideload.instance_variable_set(:@primary_key, :id)
    query = StubQuery.new("skill")

    result = sideload.load_params([parent1, parent2], query)

    assert_includes result[:filter][:id], "child-1"
    assert_includes result[:filter][:id], "child-2"
  end

  def test_belongs_to_load_params_handles_array_relations
    child_a = StubModel.new("child-1")
    child_b = StubModel.new("child-2")
    parent = StubModel.new("parent-1", { "skill" => [child_a, child_b] })

    sideload = Solis::BelongsTo.allocate
    sideload.instance_variable_set(:@primary_key, :id)
    query = StubQuery.new("skill")

    result = sideload.load_params([parent], query)

    assert_includes result[:filter][:id], "child-1"
    assert_includes result[:filter][:id], "child-2"
  end

  def test_belongs_to_load_params_deduplicates_ids
    child = StubModel.new("child-1")
    parent1 = StubModel.new("parent-1", { "skill" => child })
    parent2 = StubModel.new("parent-2", { "skill" => child })

    sideload = Solis::BelongsTo.allocate
    sideload.instance_variable_set(:@primary_key, :id)
    query = StubQuery.new("skill")

    result = sideload.load_params([parent1, parent2], query)

    assert_equal "child-1", result[:filter][:id]
  end

  def test_belongs_to_load_params_skips_nil_relations
    child = StubModel.new("child-1")
    parent1 = StubModel.new("parent-1", { "skill" => child })
    parent2 = StubModel.new("parent-2", { "skill" => nil })

    sideload = Solis::BelongsTo.allocate
    sideload.instance_variable_set(:@primary_key, :id)
    query = StubQuery.new("skill")

    result = sideload.load_params([parent1, parent2], query)

    assert_equal "child-1", result[:filter][:id]
  end

  def test_belongs_to_load_params_preserves_existing_id_filter
    parent = StubModel.new("parent-1", { "skill" => StubModel.new("child-1") })

    sideload = Solis::BelongsTo.allocate
    sideload.instance_variable_set(:@primary_key, :id)
    query = StubQuery.new("skill")
    # Simulate pre-existing id filter
    def query.hash
      { filter: { id: "pre-existing-id" } }
    end

    result = sideload.load_params([parent], query)

    assert_equal "pre-existing-id", result[:filter][:id]
  end

  def test_belongs_to_children_for_returns_all_values
    sideload = Solis::BelongsTo.allocate
    parent = StubModel.new("parent-1")
    map = { "c1" => StubModel.new("c1"), "c2" => StubModel.new("c2") }

    result = sideload.send(:children_for, parent, map)

    assert_equal 2, result.length
  end

  # --- HasOne ---

  def test_has_one_load_params_extracts_child_ids
    child = StubModel.new("agent-1")
    parent = StubModel.new("samensteller-1", { "agent" => child })

    sideload = Solis::HasOne.allocate
    sideload.instance_variable_set(:@primary_key, :id)
    query = StubQuery.new("agent")

    result = sideload.load_params([parent], query)

    assert_equal "agent-1", result[:filter][:id]
  end

  def test_has_one_load_params_handles_multiple_parents
    child_a = StubModel.new("agent-1")
    child_b = StubModel.new("agent-2")
    parent1 = StubModel.new("ss-1", { "agent" => child_a })
    parent2 = StubModel.new("ss-2", { "agent" => child_b })

    sideload = Solis::HasOne.allocate
    sideload.instance_variable_set(:@primary_key, :id)
    query = StubQuery.new("agent")

    result = sideload.load_params([parent1, parent2], query)

    assert_includes result[:filter][:id], "agent-1"
    assert_includes result[:filter][:id], "agent-2"
  end

  def test_has_one_load_params_skips_nil_relations
    child = StubModel.new("agent-1")
    parent1 = StubModel.new("ss-1", { "agent" => child })
    parent2 = StubModel.new("ss-2", { "agent" => nil })

    sideload = Solis::HasOne.allocate
    sideload.instance_variable_set(:@primary_key, :id)
    query = StubQuery.new("agent")

    result = sideload.load_params([parent1, parent2], query)

    assert_equal "agent-1", result[:filter][:id]
  end

  def test_has_one_children_for_returns_single_value
    sideload = Solis::HasOne.allocate
    parent = StubModel.new("parent-1")
    child = StubModel.new("c1")
    map = { "c1" => child }

    result = sideload.send(:children_for, parent, map)

    assert_equal child, result
  end

  # --- HasMany ---

  def test_has_many_load_params_extracts_child_ids
    child_a = StubModel.new("student-1")
    child_b = StubModel.new("student-2")
    parent = StubModel.new("schedule-1", { "students" => [child_a, child_b] })

    sideload = Solis::HasMany.allocate
    sideload.instance_variable_set(:@primary_key, :id)
    query = StubQuery.new("students")

    result = sideload.load_params([parent], query)

    assert_includes result[:filter][:id], "student-1"
    assert_includes result[:filter][:id], "student-2"
  end

  def test_has_many_load_params_handles_multiple_parents
    child_a = StubModel.new("s-1")
    child_b = StubModel.new("s-2")
    child_c = StubModel.new("s-3")
    parent1 = StubModel.new("p-1", { "students" => [child_a, child_b] })
    parent2 = StubModel.new("p-2", { "students" => [child_c] })

    sideload = Solis::HasMany.allocate
    sideload.instance_variable_set(:@primary_key, :id)
    query = StubQuery.new("students")

    result = sideload.load_params([parent1, parent2], query)

    assert_includes result[:filter][:id], "s-1"
    assert_includes result[:filter][:id], "s-2"
    assert_includes result[:filter][:id], "s-3"
  end

  def test_has_many_load_params_deduplicates_ids
    shared_child = StubModel.new("s-1")
    parent1 = StubModel.new("p-1", { "students" => [shared_child] })
    parent2 = StubModel.new("p-2", { "students" => [shared_child] })

    sideload = Solis::HasMany.allocate
    sideload.instance_variable_set(:@primary_key, :id)
    query = StubQuery.new("students")

    result = sideload.load_params([parent1, parent2], query)

    assert_equal "s-1", result[:filter][:id]
  end

  def test_has_many_children_for_returns_all_values_flattened
    sideload = Solis::HasMany.allocate
    parent = StubModel.new("parent-1")
    map = { "c1" => [StubModel.new("c1")], "c2" => [StubModel.new("c2")] }

    result = sideload.send(:children_for, parent, map)

    assert_equal 2, result.length
  end

  def test_has_many_inverse_filter_defaults_to_foreign_key
    sideload = Solis::HasMany.allocate
    sideload.instance_variable_set(:@inverse_filter, nil)
    sideload.instance_variable_set(:@foreign_key, :schedule_id)

    assert_equal :schedule_id, sideload.inverse_filter
  end

  def test_has_many_inverse_filter_uses_override
    sideload = Solis::HasMany.allocate
    sideload.instance_variable_set(:@inverse_filter, :custom_filter)
    sideload.instance_variable_set(:@foreign_key, :schedule_id)

    assert_equal :custom_filter, sideload.inverse_filter
  end

  # --- ManyToMany ---

  def test_many_to_many_is_graphiti_default
    classes = Solis::SparqlAdaptor.sideloading_classes
    assert_equal ::Graphiti::Sideload::ManyToMany, classes[:many_to_many],
      "ManyToMany should use the standard Graphiti implementation"
  end

  # --- Cross-class consistency ---

  def test_all_custom_sideloads_use_same_load_params_pattern
    # All three custom classes should extract child IDs from the parent's
    # association instance variable, not from the parent's own ID.
    child = StubModel.new("child-99")
    parent = StubModel.new("parent-1", { "rel" => child })
    query = StubQuery.new("rel")

    [Solis::BelongsTo, Solis::HasOne, Solis::HasMany].each do |klass|
      sideload = klass.allocate
      sideload.instance_variable_set(:@primary_key, :id)

      result = sideload.load_params([parent], query)

      assert_equal "child-99", result[:filter][:id],
        "#{klass.name} should extract child ID from parent's @rel, not parent's own ID"
    end
  end
end
