require "test_helper"

class SolisTest < Minitest::Test
  def setup
    #    Solis::ConfigFile.path = './test/resources'
    @solis = Solis::Graph.new(Solis::Shape::Reader::File.read(Solis::ConfigFile[:solis][:shacl]), Solis::ConfigFile[:solis])
  end

  def test_should_have_a_course_entity
    assert(@solis.list_shapes.length > 1, 'no shapes')
    assert_includes(@solis.list_shapes, 'Course', 'Course not found in shape list')
  end

  def test_should_have_a_model_template_with_attributes
    course = @solis.shape_as_model('Course')
    template = course.model_template

    assert_equal(template[:type], 'courses')
    assert_includes(template, :attributes)
    assert_includes(template[:attributes], :course_name)
  end

  def test_should_have_setup_a_course_model
    course = @solis.shape_as_model('Course')
    assert_same(course, Course)
  end

  def test_create_an_instance
    course_name='Algebra 101'
    course = Course.new({course_name: course_name})

    assert_kind_of(Course, course)
    assert_equal(course.course_name["@value"], course_name)
  end

  def test_course_returns_ttl
    course_name='Algebra 101'
    course = Course.new({id:1, course_name: course_name})
    file_course = File.read('./test/resources/course_1.ttl').gsub("\n", '').gsub(/ */, ' ')
    dump_course = course.to_ttl.gsub("\n", '').gsub(/ */, ' ')

    assert_equal(file_course, dump_course)
  end

  def test_that_it_has_a_version_number
    refute_nil ::Solis::VERSION
  end

end
