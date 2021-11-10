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


  def test_has_many
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

    expected='{"data":[{"id":"3","last_name":"Doe","first_name":"John","skill":[{"id":"1","short_label":null,"label":null},{"id":"2","short_label":null,"label":null}]}],"meta":{"stats":{"total":{"count":1}}}}'

    puts t.to_json
    assert_equal(expected, t.to_json)

    # teacher.destroy
    # algebra_skill.destroy
    # logic_skill.destroy
    # t = TeacherResource.all({"page"=>{"number"=>"0", "size"=>"5"}, "include"=>"skill", "stats"=>{"total"=>:count}})
  end
end

