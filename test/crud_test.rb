require 'test_helper'

class CrudTest < Minitest::Test
  def setup
    Solis::ConfigFile.path = './test/resources'

    @solis = Solis::Graph.new(Solis::Shape::Reader::File.read(Solis::ConfigFile[:solis][:shacl]), Solis::ConfigFile[:solis])
    build_data(@solis)
  end

  def test_create_or_read
    data = create_read_student
    assert_equal(35, data.age)
  end

  def test_update
    data = create_read_student
    data.age = 25
    data.save

    data = create_read_student
    assert_equal(25, data.age)
  end

  def test_update_embedded
    data = ScheduleResource.find(id:7).data
    data.students << {id: 8}
    data.save

    data = ScheduleResource.find(id:7).data
    assert_equal(3, data.students.length)
  end

  def test_delete
    data = create_read_student
    data.destroy

    assert_raises(Graphiti::Errors::RecordNotFound) do
      student_read = StudentResource.find(id: '8')
      data = student_read.data
    end
  end

  def test_refuse_to_delete_entity_with_referenced
    student_read = StudentResource.find(id: '5') #belongs to schedule.id=7
    data = student_read.data

    assert_raises(Solis::Error::QueryError) do
      data.destroy
    end
  end

  private

  def create_read_student
    begin
      student_read = StudentResource.find(id: '8')
      data = student_read.data
    rescue Graphiti::Errors::RecordNotFound => e
      student_create = Student.new({ id: '8',
                                     age: 35,
                                     first_name: 'Margareta',
                                     last_name: 'Von Draperei'
                                   }).save
      student_read = StudentResource.find(id: '8')
      data = student_read.data
    end
    data
  end

end