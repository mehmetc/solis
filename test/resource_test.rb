require "test_helper"


class ResourceTest < Minitest::Test
  def setup
    Solis::ConfigFile.path = './test/resources' #'./test/resources'
    Solis::ConfigFile.init

    environment = Marshal.load(Marshal.dump(Solis::ConfigFile[:solis][:env]))
    @solis = Solis::Graph.new(Solis::Shape::Reader::File.read(Solis::ConfigFile[:solis][:shacl]), environment)

    #   @solis.flush_all('http://solis.template/')
  end

  def test_flush_all_wrong_graph_name
    error = assert_raises(Solis::Error::NotFoundError) do
      @solis.flush_all('http://example.com/')
    end

    assert_equal("Supplied graph_name 'http://example.com/' does not equal graph name defined in config file 'http://solis.template/', set force to true", error.message)
  end

  def test_flush_graph
    assert_equal(true, @solis.flush_all('http://solis.template/'))
  end


  def test_belongs_to_relationship_load
    @solis.flush_all('http://solis.template/')
    algebra_skill = Skill.new({id: '1', label: 'Algebra'})
    logic_skill = Skill.new({id: '2', label: 'Description Logic'})

    algebra_skill.save
    logic_skill.save

    teacher = Teacher.new({id:3,
                            first_name: 'John',
                            last_name: 'Doe',
                            skill: [{id: '1'}, {id: '2'}]
                          })

    teacher.save
    t = TeacherResource.all({"page"=>{"number"=>"0", "size"=>"5"}, "include"=>"skill", "stats"=>{"total"=>:count}})

    expected= JSON.parse('{"data":[{"id":"3","last_name":"Doe","first_name":"John","skill":{"id":"2","label":"Description Logic","short_label":null}}],"meta":{"stats":{"total":{"count":1}}}}')

    #    s = SkillResource.find({id: t.first.skill.first.id})

    assert_includes(t.data.first.skill.map{|m| m.label}, expected['data'].first['skill']['label'])

    # teacher.destroy
    # algebra_skill.destroy
    # logic_skill.destroy
    # t = TeacherResource.all({"page"=>{"number"=>"0", "size"=>"5"}, "include"=>"skill", "stats"=>{"total"=>:count}})
  end

  def test_predicate_on_relationship
    @solis.flush_all('http://solis.template/')

    algebra_skill = Skill.new({id: '1', label: 'Algebra'})
    logic_skill = Skill.new({id: '2', label: 'Description Logic'})

    algebra_skill.save
    logic_skill.save

    teacher3 = Teacher.new({id:3,
                           first_name: 'John',
                           last_name: 'Doe',
                           skill: [{id: '1'}]
                          })

    teacher4 = Teacher.new({id:4,
                            first_name: 'Jane',
                            last_name: 'Doe',
                            skill: [{id: '2'}]
                           })


    teacher3.save
    teacher4.save

    t = TeacherResource.all({"filter"=>{"skill_id"=>{"eq"=>"1"}}, "include"=>"skill"})
    assert_equal(1, t.data.length)
    assert_equal('John', t.data.first.first_name)
  end

  def test_relation_class
    @solis.flush_all('http://solis.template/')

    algebra_skill = Skill.new({id: '1', label: 'Algebra', short_label: 'Algebra'})
    algebra_skill.save

    course = Course.new({id: '8', course_name: 'Algebra'})
    course.save

    teacher3 = Teacher.new({id:'3',
                            first_name: 'John',
                            last_name: 'Doe',
                            skill: [{id: algebra_skill.id}]
                           })
    teacher3.save(false)

    student5 = Student.new({id:'5',
                            age: 23,
                            first_name: 'Jane',
                            last_name: 'Doe'
                           })
    student5.save

    student6 = Student.new({id:'6',
                            age: 24,
                            first_name: 'Peter',
                            last_name: 'Selie'
                           })
    student6.save

    schedule = Schedule.new({id: '7',
                             students: [ {id: student5.id},
                                        {id: student6.id}],
                             teacher: {id: teacher3.id},
                             course: {id: course.id},
                             start_date: Time.now,
                             end_date: Time.now
                            }
                            )

    schedule.save(false)


    s = ScheduleResource.all({"filter"=>{"id"=>{"eq"=>"7"}}, "include"=>"teacher,students"})

    pp s.data

    puts s.data[0].to_ttl
  end
end

