require "test_helper"

# Unit tests for SPARQL sort/ORDER BY generation logic
# These tests verify that sorting produces valid SPARQL with a single ORDER BY clause
class SparqlSortGenerationTest < Minitest::Test
  def setup
    @solis = Solis::Graph.new(Solis::Shape::Reader::File.read(Solis::ConfigFile[:solis][:shacl]), Solis::ConfigFile[:solis])
  end

  # Helper: create a query and apply sort params, return the Query object
  def build_sorted_query(model_class, sort_params = {})
    model = model_class.new
    query = model.query
    query.sort(sort_params) unless sort_params.empty?
    query
  end

  # Test that the default sort uses ?concept (the subquery variable)
  def test_default_sort_uses_concept
    query = build_sorted_query(Course)
    sort_value = query.instance_variable_get(:@sort)
    assert_equal('ORDER BY ?concept', sort_value,
                 'Default sort should use ?concept for the subquery')
  end

  # Test ascending sort generates correct ORDER BY
  def test_sort_ascending
    query = build_sorted_query(Course, sort: { course_name: :asc })
    sort_value = query.instance_variable_get(:@sort)
    assert_equal('ORDER BY ASC(?__course_name)', sort_value)
  end

  # Test descending sort generates correct ORDER BY
  def test_sort_descending
    query = build_sorted_query(Course, sort: { course_name: :desc })
    sort_value = query.instance_variable_get(:@sort)
    assert_equal('ORDER BY DESC(?__course_name)', sort_value)
  end

  # Test that sort_select binds the sort variable with a triple pattern
  def test_sort_select_binds_variable
    query = build_sorted_query(Course, sort: { course_name: :asc })
    sort_select = query.instance_variable_get(:@sort_select)
    assert_includes(sort_select, '?__course_name',
                    'sort_select should bind the sort variable')
    assert_includes(sort_select, '?concept',
                    'sort_select should use ?concept as subject')
  end

  # Test sorting by multiple fields
  def test_sort_multiple_fields
    query = build_sorted_query(Student, sort: { first_name: :asc, last_name: :desc })
    sort_value = query.instance_variable_get(:@sort)
    assert_equal('ORDER BY ASC(?__first_name),DESC(?__last_name)', sort_value)
  end

  # Test that core_query with custom sort has exactly one ORDER BY
  def test_core_query_with_sort_has_single_order_by
    query = build_sorted_query(Course, sort: { course_name: :asc })
    core = query.send(:core_query, '')
    order_by_count = core.scan(/ORDER BY/i).length
    assert_equal(1, order_by_count,
                 "core_query should contain exactly one ORDER BY, got #{order_by_count}")
  end

  # Test that core_query without custom sort has exactly one ORDER BY
  def test_core_query_without_sort_has_single_order_by
    query = build_sorted_query(Course)
    core = query.send(:core_query, '')
    order_by_count = core.scan(/ORDER BY/i).length
    assert_equal(1, order_by_count,
                 "core_query should contain exactly one ORDER BY, got #{order_by_count}")
  end
end
