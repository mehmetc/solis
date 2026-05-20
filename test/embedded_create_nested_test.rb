require 'test_helper'

# Regression test: creating an entity with a nested (grandchild) embedded entity must
# persist the nested entity itself, not just an id reference to it.
#
# build_ttl_objekt used to force resolve_all=false whenever the entity was found in
# known_entities. In the create path that cache is pre-populated by collect_known_entities
# with the in-memory NEW entities, so the force-false stopped grandchild entities from
# being emitted into the graph — only their URI reference was written.
class EmbeddedCreateNestedTest < Minitest::Test
  def setup
    Solis::ConfigFile.path = './test/resources'

    options = Solis::ConfigFile[:solis].merge(embedded_readonly: [])
    @solis = Solis::Graph.new(Solis::Shape::Reader::File.read(Solis::ConfigFile[:solis][:shacl]), options)

    @solis.flush_all('http://solis.template/')
  end

  def test_create_persists_nested_grandchild_embedded_entity
    # Schedule -> Teacher (embedded child) -> Skill (embedded grandchild), all brand new.
    schedule = Schedule.new({
      id: 'nest-sch1',
      teacher: {
        id: 'nest-t1', first_name: 'Nest', last_name: 'Teacher',
        skill: [{ id: 'nest-sk1', label: 'Fresh Skill', short_label: 'FS' }]
      },
      course: { id: 'nest-c1', course_name: 'Nest Course' },
      start_date: Time.now,
      end_date: Time.now
    })
    schedule.save

    # The grandchild skill must exist as a full entity, not just a dangling reference.
    found_skill = SkillResource.find(id: 'nest-sk1').data
    assert_equal 'nest-sk1', found_skill.id
    assert_equal 'Fresh Skill', found_skill.label

    # The intermediate teacher is created too.
    found_teacher = TeacherResource.find(id: 'nest-t1').data
    assert_equal 'Nest', found_teacher.first_name

    schedule.destroy
    Teacher.new({ id: 'nest-t1' }).destroy
    Skill.new({ id: 'nest-sk1' }).destroy
    Course.new({ id: 'nest-c1' }).destroy
  end
end
