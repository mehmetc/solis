require "test_helper"

# Unit tests for SparqlAdaptor filter methods
# These tests verify that all filter method aliases are properly defined
class SparqlAdaptorTest < Minitest::Test
  def setup
    # Create adaptor without resource for method existence tests
    @adaptor = Solis::SparqlAdaptor.allocate
  end

  # Test that default_operators includes all expected datatypes
  def test_default_operators_completeness
    operators = Solis::SparqlAdaptor.default_operators

    # Test all expected datatypes are present
    assert_includes(operators.keys, :string)
    assert_includes(operators.keys, :lang_string)
    assert_includes(operators.keys, :integer)
    assert_includes(operators.keys, :float)
    assert_includes(operators.keys, :big_decimal)
    assert_includes(operators.keys, :date)
    assert_includes(operators.keys, :boolean)
    assert_includes(operators.keys, :uuid)
    assert_includes(operators.keys, :enum)
    assert_includes(operators.keys, :datetime)
    assert_includes(operators.keys, :anyuri)
  end

  # Test date operators include gte and lte
  def test_date_operators_include_gte_lte
    operators = Solis::SparqlAdaptor.default_operators

    assert_includes(operators[:date], :eq)
    assert_includes(operators[:date], :not_eq)
    assert_includes(operators[:date], :gt)
    assert_includes(operators[:date], :gte, 'Date operators should include :gte')
    assert_includes(operators[:date], :lt)
    assert_includes(operators[:date], :lte, 'Date operators should include :lte')
  end

  # Test anyuri operators include eq and not_eq
  def test_anyuri_operators
    operators = Solis::SparqlAdaptor.default_operators

    assert_includes(operators[:anyuri], :eq, 'anyURI operators should include :eq')
    assert_includes(operators[:anyuri], :not_eq, 'anyURI operators should include :not_eq')
  end

  # Test that filter_anyuri_eq method exists
  def test_filter_anyuri_eq_exists
    assert_respond_to(@adaptor, :filter_anyuri_eq, 'SparqlAdaptor should respond to filter_anyuri_eq')
  end

  # Test that filter_anyuri_not_eq method exists
  def test_filter_anyuri_not_eq_exists
    assert_respond_to(@adaptor, :filter_anyuri_not_eq, 'SparqlAdaptor should respond to filter_anyuri_not_eq')
  end

  # Test that filter_date_gte method exists
  def test_filter_date_gte_exists
    assert_respond_to(@adaptor, :filter_date_gte, 'SparqlAdaptor should respond to filter_date_gte')
  end

  # Test that filter_date_lte method exists
  def test_filter_date_lte_exists
    assert_respond_to(@adaptor, :filter_date_lte, 'SparqlAdaptor should respond to filter_date_lte')
  end

  # Test that filter_date_not_gte method exists
  def test_filter_date_not_gte_exists
    assert_respond_to(@adaptor, :filter_date_not_gte, 'SparqlAdaptor should respond to filter_date_not_gte')
  end

  # Test that filter_date_not_lte method exists
  def test_filter_date_not_lte_exists
    assert_respond_to(@adaptor, :filter_date_not_lte, 'SparqlAdaptor should respond to filter_date_not_lte')
  end


  # Test that all standard filter methods exist
  def test_standard_filter_methods_exist
    standard_methods = [
      :filter_eq,
      :filter_not_eq,
      :filter_gt,
      :filter_lt,
      :filter_contains
    ]

    standard_methods.each do |method|
      assert_respond_to(@adaptor, method, "SparqlAdaptor should respond to #{method}")
    end
  end

  # Test that all string filter methods exist
  def test_string_filter_methods_exist
    string_methods = [
      :filter_string_eq,
      :filter_string_not_eq,
      :filter_string_contains,
      :filter_string_gt,
      :filter_string_lt
    ]

    string_methods.each do |method|
      assert_respond_to(@adaptor, method, "SparqlAdaptor should respond to #{method}")
    end
  end

  # Test that all integer filter methods exist
  def test_integer_filter_methods_exist
    integer_methods = [
      :filter_integer_eq,
      :filter_integer_not_eq,
      :filter_integer_gt,
      :filter_integer_lt
    ]

    integer_methods.each do |method|
      assert_respond_to(@adaptor, method, "SparqlAdaptor should respond to #{method}")
    end
  end

  # Test that all date filter methods exist (including new ones)
  def test_date_filter_methods_exist
    date_methods = [
      :filter_date_eq,
      :filter_date_not_eq,
      :filter_date_gt,
      :filter_date_lt,
      :filter_date_gte,
      :filter_date_lte,
      :filter_date_not_gte,
      :filter_date_not_lte
    ]

    date_methods.each do |method|
      assert_respond_to(@adaptor, method, "SparqlAdaptor should respond to #{method}")
    end
  end

  # Test that all boolean filter methods exist
  def test_boolean_filter_methods_exist
    boolean_methods = [
      :filter_boolean_eq,
      :filter_boolean_not_eq
    ]

    boolean_methods.each do |method|
      assert_respond_to(@adaptor, method, "SparqlAdaptor should respond to #{method}")
    end
  end

  # Test that all lang_string filter methods exist
  def test_lang_string_filter_methods_exist
    lang_string_methods = [
      :filter_lang_string_eq,
      :filter_lang_string_not_eq,
      :filter_lang_string_contains
    ]

    lang_string_methods.each do |method|
      assert_respond_to(@adaptor, method, "SparqlAdaptor should respond to #{method}")
    end
  end

end
