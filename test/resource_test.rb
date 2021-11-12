require "test_helper"

class ResourceTest < Minitest::Test
  def setup
    Solis::ConfigFile.path = './test/resources'
    @solis = Solis::Graph.new(Solis::Shape::Reader::File.read(Solis::ConfigFile[:solis][:shacl]), Solis::ConfigFile[:solis][:env])

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

    assert_equal(expected['data'].first['skill']['label'], t.data.first.skill.label)

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

end

