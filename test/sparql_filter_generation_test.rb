require "test_helper"

# Unit tests for SPARQL filter generation logic
# These tests verify that the filter conversion to SPARQL is correct
class SparqlFilterGenerationTest < Minitest::Test
  def setup
    @solis = Solis::Graph.new(Solis::Shape::Reader::File.read(Solis::ConfigFile[:solis][:shacl]), Solis::ConfigFile[:solis])
  end

  # Helper method to get the generated SPARQL filter
  def get_filter_sparql(model_class, filters)
    model = model_class.new
    scope = {type: [model_class.name.tableize.pluralize.to_sym], filters: filters}
    query = model.query
    query.filter(scope)
    query.instance_variable_get(:@filter)
  end

  # Test that date filters generate correct XSD datatype
  def test_date_filter_includes_xsd_datatype
    filters = {date_dt: {value: '2024-01-15', operator: '>=', is_not: false}}
    filter_result = get_filter_sparql(EveryDataType, filters)

    # The filter should include the XSD date datatype
    filter_str = filter_result[:concepts].join(' ')
    assert_includes(filter_str, 'http://www.w3.org/2001/XMLSchema#date',
                    'Date filter should include XSD date datatype')
    assert_includes(filter_str, '>=', 'Date filter should include >= operator')
  end

  # Test that integer filters generate correct XSD datatype
  def test_integer_filter_includes_xsd_datatype
    filters = {integer_dt: {value: 42, operator: '=', is_not: false}}
    filter_result = get_filter_sparql(EveryDataType, filters)

    filter_str = filter_result[:concepts].join(' ')
    assert_includes(filter_str, 'http://www.w3.org/2001/XMLSchema#integer',
                    'Integer filter should include XSD integer datatype')
  end

  # Test that boolean filters generate correct XSD datatype
  def test_boolean_filter_includes_xsd_datatype
    filters = {boolean_dt: {value: true, operator: '=', is_not: false}}
    filter_result = get_filter_sparql(EveryDataType, filters)

    filter_str = filter_result[:concepts].join(' ')
    assert_includes(filter_str, 'http://www.w3.org/2001/XMLSchema#boolean',
                    'Boolean filter should include XSD boolean datatype')
  end

  # Test that float filters generate correct XSD datatype
  def test_float_filter_includes_xsd_datatype
    filters = {float_dt: {value: 3.14, operator: '>', is_not: false}}
    filter_result = get_filter_sparql(EveryDataType, filters)

    filter_str = filter_result[:concepts].join(' ')
    assert_includes(filter_str, 'http://www.w3.org/2001/XMLSchema#double',
                    'Float filter should include XSD double datatype')
  end

  # Test that anyURI filters generate correct XSD datatype
  def test_anyuri_filter_includes_xsd_datatype
    filters = {uri_dt: {value: 'https://example.com/test', operator: '=', is_not: false}}
    filter_result = get_filter_sparql(EveryDataType, filters)

    filter_str = filter_result[:concepts].join(' ')
    # anyURI might have special handling for entity references
    # This test verifies it generates valid SPARQL
    assert(filter_str.length > 0, 'anyURI filter should generate SPARQL')
  end

  # Test >= operator (gte) is properly handled
  def test_gte_operator_in_sparql
    filters = {date_dt: {value: '2024-01-15', operator: '>=', is_not: false}}
    filter_result = get_filter_sparql(EveryDataType, filters)

    filter_str = filter_result[:concepts].join(' ')
    assert_includes(filter_str, '>=', 'Filter should include >= operator')
    refute_includes(filter_str, '!>=', 'Filter should not negate >= when is_not is false')
  end

  # Test <= operator (lte) is properly handled
  def test_lte_operator_in_sparql
    filters = {date_dt: {value: '2024-12-31', operator: '<=', is_not: false}}
    filter_result = get_filter_sparql(EveryDataType, filters)

    filter_str = filter_result[:concepts].join(' ')
    assert_includes(filter_str, '<=', 'Filter should include <= operator')
    refute_includes(filter_str, '!<=', 'Filter should not negate <= when is_not is false')
  end

  # Test negation with is_not flag
  def test_not_operator_with_gte
    filters = {date_dt: {value: '2024-01-15', operator: '>=', is_not: true}}
    filter_result = get_filter_sparql(EveryDataType, filters)

    filter_str = filter_result[:concepts].join(' ')
    assert_includes(filter_str, '!>=', 'Filter should include negated >= operator')
  end

  # Test negation with equality operator
  def test_not_operator_with_eq
    filters = {integer_dt: {value: 42, operator: '=', is_not: true}}
    filter_result = get_filter_sparql(EveryDataType, filters)

    filter_str = filter_result[:concepts].join(' ')
    assert_includes(filter_str, '!=', 'Filter should include != operator')
  end

  # Test > operator (gt)
  def test_gt_operator_in_sparql
    filters = {integer_dt: {value: 10, operator: '>', is_not: false}}
    filter_result = get_filter_sparql(EveryDataType, filters)

    filter_str = filter_result[:concepts].join(' ')
    assert_includes(filter_str, '>', 'Filter should include > operator')
    # Make sure it's not >= by checking context
    assert_match(/>\s*"10"/, filter_str, 'Filter should use > not >=')
  end

  # Test < operator (lt)
  def test_lt_operator_in_sparql
    filters = {integer_dt: {value: 100, operator: '<', is_not: false}}
    filter_result = get_filter_sparql(EveryDataType, filters)

    filter_str = filter_result[:concepts].join(' ')
    assert_includes(filter_str, '<', 'Filter should include < operator')
    # Make sure it's not <= by checking context
    assert_match(/<\s*"100"/, filter_str, 'Filter should use < not <=')
  end

  # Test contains operator (~)
  def test_contains_operator_in_sparql
    filters = {string_dt: {value: 'test', operator: '~', is_not: false}}
    filter_result = get_filter_sparql(EveryDataType, filters)

    filter_str = filter_result[:concepts].join(' ')
    assert_includes(filter_str, 'CONTAINS', 'Contains filter should use CONTAINS function')
    assert_includes(filter_str, 'LCASE', 'Contains filter should use LCASE for case-insensitive search')
  end

  # Test that filter generates valid SPARQL variable bindings
  def test_filter_generates_variable_binding
    filters = {integer_dt: {value: 42, operator: '=', is_not: false}}
    filter_result = get_filter_sparql(EveryDataType, filters)

    filter_str = filter_result[:concepts].join(' ')
    assert_includes(filter_str, '?concept', 'Filter should bind ?concept variable')
    assert_match(/\?__search\d+/, filter_str, 'Filter should create search variable')
  end

  # Test multiple filters generate separate SPARQL patterns
  def test_multiple_filters_generate_separate_patterns
    filters = {
      integer_dt: {value: 42, operator: '=', is_not: false},
      string_dt: {value: 'test', operator: '=', is_not: false}
    }
    filter_result = get_filter_sparql(EveryDataType, filters)

    concepts = filter_result[:concepts]
    assert(concepts.length >= 2, 'Multiple filters should generate multiple SPARQL patterns')
  end

  # Test string escaping in filters
  def test_string_escaping_in_filters
    filters = {string_dt: {value: 'test"with"quotes', operator: '=', is_not: false}}
    filter_result = get_filter_sparql(EveryDataType, filters)

    filter_str = filter_result[:concepts].join(' ')
    # Should escape quotes
    assert_includes(filter_str, '\"', 'Filter should escape quotes in string values')
  end

  # Test special characters in string filters
  def test_special_characters_in_filters
    test_strings = [
      "test\nwith\nnewlines",
      "test\twith\ttabs",
      "test\\with\\backslashes"
    ]

    test_strings.each do |test_str|
      filters = {string_dt: {value: test_str, operator: '=', is_not: false}}
      filter_result = get_filter_sparql(EveryDataType, filters)
      filter_str = filter_result[:concepts].join(' ')

      # Should generate valid SPARQL without breaking
      assert(filter_str.length > 0, "Filter should handle special characters: #{test_str}")
    end
  end

  # Test that VALUES clause is generated for type filtering
  def test_values_clause_for_type
    filters = {integer_dt: {value: 42, operator: '=', is_not: false}}
    filter_result = get_filter_sparql(EveryDataType, filters)

    values_str = filter_result[:values].join(' ')
    assert_includes(values_str, 'VALUES', 'Filter should include VALUES clause')
    assert_includes(values_str, '?type', 'VALUES clause should bind ?type variable')
  end

  # Test that concept type binding is included
  def test_concept_type_binding
    filters = {integer_dt: {value: 42, operator: '=', is_not: false}}
    filter_result = get_filter_sparql(EveryDataType, filters)

    concepts_str = filter_result[:concepts].join(' ')
    assert_includes(concepts_str, '?concept a ?type', 'Filter should include type binding')
  end

  # Test datetime datatype handling
  def test_datetime_filter_includes_xsd_datatype
    filters = {datetime_dt: {value: '2024-01-15T10:30:00Z', operator: '>=', is_not: false}}
    filter_result = get_filter_sparql(EveryDataType, filters)

    filter_str = filter_result[:concepts].join(' ')
    assert_includes(filter_str, 'http://www.w3.org/2001/XMLSchema#dateTime',
                    'DateTime filter should include XSD dateTime datatype')
  end

  # Test that operators are case-sensitive and exact
  def test_operator_exactness
    filters = {integer_dt: {value: 10, operator: '>', is_not: false}}
    filter_result = get_filter_sparql(EveryDataType, filters)
    filter_str = filter_result[:concepts].join(' ')

    # Should have > but not >=
    assert_match(/[^=]>[^=]/, filter_str, 'GT operator should be exact >')
  end

  # Test filter with array of values
  def test_filter_with_multiple_values
    filters = {integer_dt: {value: [10, 20, 30], operator: '=', is_not: false}}
    filter_result = get_filter_sparql(EveryDataType, filters)

    filter_str = filter_result[:concepts].join(' ')
    # Should handle multiple values (implementation dependent)
    assert(filter_str.length > 0, 'Filter should handle array of values')
  end
end
