require "test_helper"

class ResourceTest < Minitest::Test
  def setup
    Solis::ConfigFile.path = './test/resources'
    @solis = Solis::Graph.new(Solis::Shape::Reader::File.read(Solis::ConfigFile[:solis][:shacl]), Solis::ConfigFile[:solis][:env])
  end

  def test_has_many
    algebra_skill = Skill.new({id: 1, label: 'Algebra'})
    logic_skill = Skill.new({id: 2, label: 'Description Logic'})

    algebra_skill.save
    logic_skill.save
    teacher = Teacher.new({id:3,
                            first_name: 'John',
                            last_name: 'Doe',
                            skill: [{id: "1"}, {id: "2"}]
                          })

    teacher.save
    t = TeacherResource.all({"page"=>{"number"=>"0", "size"=>"5"}, "include"=>"skill", "stats"=>{"total"=>:count}})

    pp t.data

    # teacher.delete
    # algebra_skill.delete
    # logic_skill.delete
    # t = TeacherResource.all({"page"=>{"number"=>"0", "size"=>"5"}, "include"=>"skill", "stats"=>{"total"=>:count}})
  end
end

