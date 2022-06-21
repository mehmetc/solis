$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "solis"
Solis::ConfigFile.path = './test/resources'

require "minitest/autorun"

def build_data(solis)
  solis.flush_all('http://solis.template/')

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
end