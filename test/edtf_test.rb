require "test_helper"

class EDTFTest < Minitest::Test
  def test_basic_edtf_date_parsing
    date = Date.edtf('1984')

    refute_nil date
    assert_equal '1984', date.edtf
    assert_instance_of Date, date
  end

  def test_uncertain_date
    uncertain_date = Date.edtf('1984?')

    refute_nil uncertain_date
    assert_equal '1984?', uncertain_date.edtf
    assert uncertain_date.uncertain?
  end

  def test_approximate_date
    approx_date = Date.edtf('1984~')

    refute_nil approx_date
    assert_equal '1984~', approx_date.edtf
    assert approx_date.approximate?
  end

  def test_uncertain_and_approximate_date
    date = Date.edtf('1984?~')

    refute_nil date
    assert_equal '1984?~', date.edtf
    assert date.uncertain?
    assert date.approximate?
  end

  def test_interval
    interval = Date.edtf('1984/2004')

    refute_nil interval
    assert_equal '1984/2004', interval.edtf
    assert_instance_of EDTF::Interval, interval
    assert interval.respond_to?(:length)
  end

  def test_uncertain_interval
    interval = Date.edtf('1984-06?/2004-08?')

    refute_nil interval
    assert_equal '1984-06?/2004-08?', interval.edtf
    assert_instance_of EDTF::Interval, interval
  end

  def test_season_spring
    season = Date.edtf('2001-21')

    refute_nil season
    assert_equal '2001-21', season.edtf
    assert_instance_of EDTF::Season, season
    assert season.spring?
  end

  def test_season_summer
    season = Date.edtf('2001-22')

    refute_nil season
    assert_equal '2001-22', season.edtf
    assert_instance_of EDTF::Season, season
    assert season.summer?
  end

  def test_season_autumn
    season = Date.edtf('2001-23')

    refute_nil season
    assert_equal '2001-23', season.edtf
    assert_instance_of EDTF::Season, season
    assert season.autumn?
  end

  def test_season_winter
    season = Date.edtf('2001-24')

    refute_nil season
    assert_equal '2001-24', season.edtf
    assert_instance_of EDTF::Season, season
    assert season.winter?
  end

  def test_rdf_literal_edtf_basic
    rdf_edtf = RDF::Literal::EDTF.new('1984')

    refute_nil rdf_edtf
    assert_equal '1984', rdf_edtf.value
    assert_equal RDF::URI('http://id.loc.gov/datatypes/edtf'), rdf_edtf.datatype
    assert rdf_edtf.valid?
  end

  def test_rdf_literal_edtf_uncertain
    rdf_edtf = RDF::Literal::EDTF.new('1984?')

    refute_nil rdf_edtf
    assert_equal '1984?', rdf_edtf.value
    assert rdf_edtf.valid?
    assert rdf_edtf.uncertain?
  end

  def test_rdf_literal_edtf_approximate
    rdf_edtf = RDF::Literal::EDTF.new('1984~')

    refute_nil rdf_edtf
    assert_equal '1984~', rdf_edtf.value
    assert rdf_edtf.valid?
    assert rdf_edtf.approximate?
  end

  def test_rdf_literal_edtf_interval
    rdf_edtf = RDF::Literal::EDTF.new('1984/2004')

    refute_nil rdf_edtf
    assert_equal '1984/2004', rdf_edtf.value
    assert rdf_edtf.valid?
    assert rdf_edtf.interval?
  end

  def test_rdf_literal_edtf_season
    rdf_edtf = RDF::Literal::EDTF.new('2001-21')

    refute_nil rdf_edtf
    assert_equal '2001-21', rdf_edtf.value
    assert rdf_edtf.valid?
    assert rdf_edtf.season?
  end

  def test_rdf_literal_edtf_canonicalize
    rdf_edtf = RDF::Literal::EDTF.new('1984?')
    canonical = rdf_edtf.canonicalize

    refute_nil canonical
    assert_instance_of RDF::Literal::EDTF, canonical
    assert_equal '1984?', canonical.value
  end

  def test_precise_date_with_month
    date = Date.edtf('1984-05')

    refute_nil date
    assert_equal '1984-05', date.edtf
  end

  def test_precise_date_with_day
    date = Date.edtf('1984-05-26')

    refute_nil date
    assert_equal '1984-05-26', date.edtf
  end

  def test_decade_with_x
    date = Date.edtf('198X')

    refute_nil date
    assert_equal '198X', date.edtf
  end

  def test_century_with_x
    date = Date.edtf('19XX')

    refute_nil date
    assert_equal '19XX', date.edtf
  end

  def test_set_of_dates
    set = Date.edtf('[1667,1668,1670..1672]')

    refute_nil set
    assert_equal '[1667,1668,1670..1672]', set.edtf
    assert_instance_of EDTF::Set, set
  end

  def test_rdf_literal_to_edtf
    rdf_edtf = RDF::Literal::EDTF.new('1984?')
    edtf_obj = rdf_edtf.to_edtf

    refute_nil edtf_obj
    assert edtf_obj.respond_to?(:edtf)
    assert_equal '1984?', edtf_obj.edtf
  end

  def test_invalid_edtf_string
    # This should not raise an error but return nil for the parsed value
    rdf_edtf = RDF::Literal::EDTF.new('not-a-valid-edtf')

    # The literal is created but may not be valid
    refute rdf_edtf.valid?
  end
end
