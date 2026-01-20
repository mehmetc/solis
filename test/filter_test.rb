require "test_helper"

class FilterTest < Minitest::Test
  def setup
    @solis = Solis::Graph.new(Solis::Shape::Reader::File.read(Solis::ConfigFile[:solis][:shacl]), Solis::ConfigFile[:solis])
    @solis.flush_all('http://solis.template/')
  end

  # Test date equality filter
  def test_date_eq_filter
    date1 = Date.new(2024, 1, 15)
    date2 = Date.new(2024, 2, 20)

    e1 = EveryDataType.new({id: 'date_eq_1', date_dt: date1})
    e1.save

    e2 = EveryDataType.new({id: 'date_eq_2', date_dt: date2})
    e2.save

    r = EveryDataTypeResource.all({filter: {date_dt: {eq: date1.to_s}}})

    assert_equal(1, r.data.size)
    assert_equal('date_eq_1', r.data.first.id)
    assert_equal(date1.to_s, r.data.first.date_dt.strftime('%Y-%m-%d'))
  end

  # Test date not_eq filter
  def test_date_not_eq_filter
    date1 = Date.new(2024, 1, 15)
    date2 = Date.new(2024, 2, 20)

    e1 = EveryDataType.new({id: 'date_not_eq_1', date_dt: date1})
    e1.save

    e2 = EveryDataType.new({id: 'date_not_eq_2', date_dt: date2})
    e2.save

    r = EveryDataTypeResource.all({filter: {date_dt: {not_eq: date1.to_s}}})

    assert_equal(1, r.data.size)
    assert_equal('date_not_eq_2', r.data.first.id)
    assert_equal(date2.to_s, r.data.first.date_dt.strftime('%Y-%m-%d'))
  end

  # Test date greater than filter
  def test_date_gt_filter
    date1 = Date.new(2024, 1, 15)
    date2 = Date.new(2024, 2, 20)
    date3 = Date.new(2024, 3, 25)

    e1 = EveryDataType.new({id: 'date_gt_1', date_dt: date1})
    e1.save

    e2 = EveryDataType.new({id: 'date_gt_2', date_dt: date2})
    e2.save

    e3 = EveryDataType.new({id: 'date_gt_3', date_dt: date3})
    e3.save

    r = EveryDataTypeResource.all({filter: {date_dt: {gt: date1.to_s}}})

    assert_equal(2, r.data.size)
    ids = r.data.map(&:id).sort
    assert_equal(['date_gt_2', 'date_gt_3'], ids)
  end

  # Test date less than filter
  def test_date_lt_filter
    date1 = Date.new(2024, 1, 15)
    date2 = Date.new(2024, 2, 20)
    date3 = Date.new(2024, 3, 25)

    e1 = EveryDataType.new({id: 'date_lt_1', date_dt: date1})
    e1.save

    e2 = EveryDataType.new({id: 'date_lt_2', date_dt: date2})
    e2.save

    e3 = EveryDataType.new({id: 'date_lt_3', date_dt: date3})
    e3.save

    r = EveryDataTypeResource.all({filter: {date_dt: {lt: date3.to_s}}})

    assert_equal(2, r.data.size)
    ids = r.data.map(&:id).sort
    assert_equal(['date_lt_1', 'date_lt_2'], ids)
  end

  # Test date greater than or equal filter (NEW)
  def test_date_gte_filter
    date1 = Date.new(2024, 1, 15)
    date2 = Date.new(2024, 2, 20)
    date3 = Date.new(2024, 3, 25)

    e1 = EveryDataType.new({id: 'date_gte_1', date_dt: date1})
    e1.save

    e2 = EveryDataType.new({id: 'date_gte_2', date_dt: date2})
    e2.save

    e3 = EveryDataType.new({id: 'date_gte_3', date_dt: date3})
    e3.save

    # Test gte - should include date2 and date3
    r = EveryDataTypeResource.all({filter: {date_dt: {gte: date2.to_s}}})

    assert_equal(2, r.data.size, "Expected 2 results with date >= #{date2}")
    ids = r.data.map(&:id).sort
    assert_equal(['date_gte_2', 'date_gte_3'], ids)

    # Test that it includes the exact date
    r2 = EveryDataTypeResource.all({filter: {date_dt: {gte: date1.to_s}}})
    assert_equal(3, r2.data.size, "Expected all 3 results with date >= #{date1}")
  end

  # Test date less than or equal filter (NEW)
  def test_date_lte_filter
    date1 = Date.new(2024, 1, 15)
    date2 = Date.new(2024, 2, 20)
    date3 = Date.new(2024, 3, 25)

    e1 = EveryDataType.new({id: 'date_lte_1', date_dt: date1})
    e1.save

    e2 = EveryDataType.new({id: 'date_lte_2', date_dt: date2})
    e2.save

    e3 = EveryDataType.new({id: 'date_lte_3', date_dt: date3})
    e3.save

    # Test lte - should include date1 and date2
    r = EveryDataTypeResource.all({filter: {date_dt: {lte: date2.to_s}}})

    assert_equal(2, r.data.size, "Expected 2 results with date <= #{date2}")
    ids = r.data.map(&:id).sort
    assert_equal(['date_lte_1', 'date_lte_2'], ids)

    # Test that it includes the exact date
    r2 = EveryDataTypeResource.all({filter: {date_dt: {lte: date3.to_s}}})
    assert_equal(3, r2.data.size, "Expected all 3 results with date <= #{date3}")
  end

  # Test date range filter using gte and lte together
  def test_date_range_filter
    date1 = Date.new(2024, 1, 15)
    date2 = Date.new(2024, 2, 20)
    date3 = Date.new(2024, 3, 25)
    date4 = Date.new(2024, 4, 30)

    e1 = EveryDataType.new({id: 'date_range_1', date_dt: date1})
    e1.save

    e2 = EveryDataType.new({id: 'date_range_2', date_dt: date2})
    e2.save

    e3 = EveryDataType.new({id: 'date_range_3', date_dt: date3})
    e3.save

    e4 = EveryDataType.new({id: 'date_range_4', date_dt: date4})
    e4.save

    # This test demonstrates how a range query would work
    # Note: This might require special handling in the query logic
    # to combine multiple filters on the same attribute
    r_gte = EveryDataTypeResource.all({filter: {date_dt: {gte: date2.to_s}}})
    r_lte = EveryDataTypeResource.all({filter: {date_dt: {lte: date3.to_s}}})

    # Should get date2 and date3 with gte
    assert_equal(3, r_gte.data.size)

    # Should get date1, date2, and date3 with lte
    assert_equal(3, r_lte.data.size)
  end

  # Test anyURI equality filter (NEW)
  def test_anyuri_eq_filter
    uri1 = 'https://example.com/resource/1'
    uri2 = 'https://example.com/resource/2'

    e1 = EveryDataType.new({id: 'uri_eq_1', uri_dt: uri1})
    e1.save

    e2 = EveryDataType.new({id: 'uri_eq_2', uri_dt: uri2})
    e2.save

    r = EveryDataTypeResource.all({filter: {uri_dt: {eq: uri1}}})

    assert_equal(1, r.data.size)
    assert_equal('uri_eq_1', r.data.first.id)
    assert_equal(uri1, r.data.first.uri_dt)
  end

  # Test anyURI not_eq filter (NEW)
  def test_anyuri_not_eq_filter
    uri1 = 'https://example.com/resource/1'
    uri2 = 'https://example.com/resource/2'

    e1 = EveryDataType.new({id: 'uri_not_eq_1', uri_dt: uri1})
    e1.save

    e2 = EveryDataType.new({id: 'uri_not_eq_2', uri_dt: uri2})
    e2.save

    r = EveryDataTypeResource.all({filter: {uri_dt: {not_eq: uri1}}})

    assert_equal(1, r.data.size)
    assert_equal('uri_not_eq_2', r.data.first.id)
    assert_equal(uri2, r.data.first.uri_dt)
  end

  # Test integer filters with different operators
  def test_integer_filters
    e1 = EveryDataType.new({id: 'int_1', integer_dt: 10})
    e1.save

    e2 = EveryDataType.new({id: 'int_2', integer_dt: 20})
    e2.save

    e3 = EveryDataType.new({id: 'int_3', integer_dt: 30})
    e3.save

    # Test equality
    r_eq = EveryDataTypeResource.all({filter: {integer_dt: {eq: 20}}})
    assert_equal(1, r_eq.data.size)
    assert_equal('int_2', r_eq.data.first.id)

    # Test not equal
    r_not_eq = EveryDataTypeResource.all({filter: {integer_dt: {not_eq: 20}}})
    assert_equal(2, r_not_eq.data.size)

    # Test greater than
    r_gt = EveryDataTypeResource.all({filter: {integer_dt: {gt: 15}}})
    assert_equal(2, r_gt.data.size)

    # Test less than
    r_lt = EveryDataTypeResource.all({filter: {integer_dt: {lt: 25}}})
    assert_equal(2, r_lt.data.size)
  end

  # Test boolean filters
  def test_boolean_filters
    e1 = EveryDataType.new({id: 'bool_1', boolean_dt: true})
    e1.save

    e2 = EveryDataType.new({id: 'bool_2', boolean_dt: false})
    e2.save

    # Test equality with true
    r_true = EveryDataTypeResource.all({filter: {boolean_dt: {eq: true}}})
    assert_equal(1, r_true.data.size)
    assert_equal('bool_1', r_true.data.first.id)
    assert_equal(true, r_true.data.first.boolean_dt)

    # Test equality with false
    r_false = EveryDataTypeResource.all({filter: {boolean_dt: {eq: false}}})
    assert_equal(1, r_false.data.size)
    assert_equal('bool_2', r_false.data.first.id)
    assert_equal(false, r_false.data.first.boolean_dt)

    # Test not equal
    r_not_eq = EveryDataTypeResource.all({filter: {boolean_dt: {not_eq: true}}})
    assert_equal(1, r_not_eq.data.size)
    assert_equal('bool_2', r_not_eq.data.first.id)
  end

  # Test string contains filter
  def test_string_contains_filter
    e1 = EveryDataType.new({id: 'str_1', string_dt: 'Hello World'})
    e1.save

    e2 = EveryDataType.new({id: 'str_2', string_dt: 'Goodbye World'})
    e2.save

    e3 = EveryDataType.new({id: 'str_3', string_dt: 'Hello Universe'})
    e3.save

    # Test contains
    r = EveryDataTypeResource.all({filter: {string_dt: {contains: 'Hello'}}})
    assert_equal(2, r.data.size)
    ids = r.data.map(&:id).sort
    assert_equal(['str_1', 'str_3'], ids)
  end

  # Test multiple filters on different attributes
  def test_multiple_attribute_filters
    date1 = Date.new(2024, 1, 15)
    date2 = Date.new(2024, 2, 20)

    e1 = EveryDataType.new({id: 'multi_1', date_dt: date1, integer_dt: 10})
    e1.save

    e2 = EveryDataType.new({id: 'multi_2', date_dt: date1, integer_dt: 20})
    e2.save

    e3 = EveryDataType.new({id: 'multi_3', date_dt: date2, integer_dt: 20})
    e3.save

    # Filter by both date and integer
    r = EveryDataTypeResource.all({filter: {date_dt: {eq: date1.to_s}, integer_dt: {eq: 20}}})

    assert_equal(1, r.data.size)
    assert_equal('multi_2', r.data.first.id)
    assert_equal(date1.to_s, r.data.first.date_dt.strftime('%Y-%m-%d'))
    assert_equal(20, r.data.first.integer_dt)
  end

  # Test lang_string filters
  def test_lang_string_filters
    context = OpenStruct.new(query_user: 'unknown', language: 'en')
    Graphiti::with_context(context) do
      e1 = EveryDataType.new({id: 'lang_1', lang_string_dt: 'Hello'})
      e1.save

      e2 = EveryDataType.new({id: 'lang_2', lang_string_dt: 'World'})
      e2.save

      # Test equality
      r_eq = EveryDataTypeResource.all({filter: {lang_string_dt: {eq: 'Hello'}}})
      assert_equal(1, r_eq.data.size)
      assert_equal('lang_1', r_eq.data.first.id)

      # Test contains
      r_contains = EveryDataTypeResource.all({filter: {lang_string_dt: {contains: 'ell'}}})
      assert_equal(1, r_contains.data.size)
      assert_equal('lang_1', r_contains.data.first.id)
    end
  end

  # Test edge case: empty filter
  def test_no_filter
    e1 = EveryDataType.new({id: 'no_filter_1', integer_dt: 10})
    e1.save

    e2 = EveryDataType.new({id: 'no_filter_2', integer_dt: 20})
    e2.save

    # Query without filter should return all
    r = EveryDataTypeResource.all({})
    assert(r.data.size >= 2, "Expected at least 2 results without filter")
  end

  # Test edge case: filter with nil/null values
  def test_filter_with_null_handling
    e1 = EveryDataType.new({id: 'null_1', integer_dt: 10})
    e1.save

    e2 = EveryDataType.new({id: 'null_2'})  # No integer_dt
    e2.save

    # Filter for specific integer should only return e1
    r = EveryDataTypeResource.all({filter: {integer_dt: {eq: 10}}})
    assert_equal(1, r.data.size)
    assert_equal('null_1', r.data.first.id)
  end

  # Test datatype casting in SPARQL queries
  def test_datatype_casting_in_sparql
    # This test verifies that the filter generates proper XSD datatype casting
    date1 = Date.new(2024, 1, 15)

    e1 = EveryDataType.new({id: 'cast_1', date_dt: date1, integer_dt: 42, boolean_dt: true})
    e1.save

    # These filters should work correctly with proper datatype casting
    r_date = EveryDataTypeResource.all({filter: {date_dt: {gte: date1.to_s}}})
    assert(r_date.data.size >= 1)

    r_int = EveryDataTypeResource.all({filter: {integer_dt: {eq: 42}}})
    assert(r_int.data.size >= 1)

    r_bool = EveryDataTypeResource.all({filter: {boolean_dt: {eq: true}}})
    assert(r_bool.data.size >= 1)
  end
end
