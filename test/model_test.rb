require "test_helper"

class ModelTest < Minitest::Test
  def setup
    Solis::ConfigFile.path = './test/resources'

    environment = Marshal.load(Marshal.dump(Solis::ConfigFile[:solis][:env]))
    @solis = Solis::Graph.new(Solis::Shape::Reader::File.read(Solis::ConfigFile[:solis][:shacl]), environment)
  end

  def test_model_singular_name
    course = Course.new
    assert_equal('Course', Course.name)
  end

  def test_model_plural_name
    course = Course.new
    assert_equal('Courses', course.name(true))
  end

  def test_model_datatype
    course = Course.new
    assert_equal('Course', course.class.name)
  end

  def test_schema
    schema = Graphiti::Schema.generate

    assert_equal(schema[:resources].length, 7)
    assert_equal(schema[:endpoints].length, 7)
    assert_includes(schema[:endpoints], :"/courses")
    assert_includes(schema[:endpoints], :"/schedules")

    schema_resource = schema[:resources].select{|s| s[:name].eql?('CourseResource')}
    refute_empty(schema_resource)

    assert_equal(schema_resource[0][:filters][:course_name][:operators], ["eq", "not_eq", "contains"])
  end

  def test_find
    course_resource = @solis.shape_as_resource('Course')

    result = course_resource.all({"filter"=>{"course_name"=>{"contains"=>"test"}}, "stats"=>{"total"=>:count}})
    assert_equal(0,result.count)
    assert_empty(result.data)
  end

  def test_after_create_hook
    Skill.model_before_create do |model,graph|
      puts "---------BEFORE"
      puts graph.dump(:jsonld)
      puts model.to_json
    end

    Skill.model_after_create do |model, result|
      puts "---------After"
      pp result
    end

    s = Skill.new({id:5, short_label: 'a short label', label: 'a label'})

    s.save
  end
end