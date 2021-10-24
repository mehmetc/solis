require "test_helper"

class ModelTest < Minitest::Test
  def setup
    Solis::ConfigFile.path = './test/resources'
    @solis = Solis::Graph.new(Solis::Shape::Reader::File.read(Solis::ConfigFile[:solis][:shacl]), Solis::ConfigFile[:solis][:env])
  end

  def test_model_singular_name
    course = Course.new
    assert_equal('Course', Course.name)
  end

  def test_model_plural_name
    course = Course.new
    assert_equal('Courses', Course.name(true))
  end
end