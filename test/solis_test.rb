require "test_helper"

class SolisTest < Minitest::Test
  def setup
    Solis::ConfigFile.path = './test/resources'
    @solis = Solis::Graph.new(Solis::Shape::Reader::File.read(Solis::ConfigFile[:solis][:shacl]), Solis::ConfigFile[:solis][:env])
  end

  def test_should_have_a_course_entity
    assert(@solis.list_shapes.length > 1, 'no shapes')
    assert_includes(@solis.list_shapes, 'Course', 'Course not found in shape list')
  end

  def test_that_it_has_a_version_number
    refute_nil ::Solis::VERSION
  end

end
