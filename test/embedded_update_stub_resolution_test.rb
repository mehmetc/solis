require 'test_helper'

# Regression tests for updating a parent entity whose embedded relation is itself
# updated with a full payload.
#
# Query#graph_to_object loads embedded relations as id-only stubs. When such a stub
# is passed into the embedded entity's own update() via prefetched_original, building
# the delete graph used to fail in make_graph because a required attribute of the stub
# (e.g. Teacher.first_name, minCount 1) was nil and the stub shadowed the store fetch.
#
# make_graph now resolves an id-only stub to the full stored entity before emitting
# its attributes, so the delete graph is complete and the update succeeds.
class EmbeddedUpdateStubResolutionTest < Minitest::Test
  def setup
    Solis::ConfigFile.path = './test/resources'

    options = Solis::ConfigFile[:solis].merge(embedded_readonly: ['Skill', 'CodeTable'])
    @solis = Solis::Graph.new(Solis::Shape::Reader::File.read(Solis::ConfigFile[:solis][:shacl]), options)

    @solis.flush_all('http://solis.template/')
    Skill.new({ id: '100', label: 'Skill', short_label: 'Skill' }).save
  end

  # ──────────────────────────────────────────────────────────────────────
  # shallow_stub? helper (no SPARQL endpoint needed)
  # ──────────────────────────────────────────────────────────────────────

  def test_shallow_stub_detects_id_only_entity
    stub = Teacher.new({ id: 'stub-1' })
    assert stub.send(:shallow_stub?, stub), "id-only Teacher should be a shallow stub"
  end

  def test_shallow_stub_false_for_populated_entity
    full = Teacher.new({ id: 'full-1', first_name: 'A', last_name: 'B', skill: [{ id: '100' }] })
    refute full.send(:shallow_stub?, full), "populated Teacher should not be a shallow stub"
  end

  # ──────────────────────────────────────────────────────────────────────
  # Updating a parent with an embedded entity carrying a full payload
  # ──────────────────────────────────────────────────────────────────────

  def test_update_schedule_with_full_embedded_teacher_payload
    course = Course.new({ id: '810', course_name: 'Stub Resolution' })
    course.save

    teacher = Teacher.new({ id: '814', first_name: 'Emb', last_name: 'Teacher', skill: [{ id: '100' }] })
    teacher.save(false)

    schedule = Schedule.new({
      id: '815',
      teacher: { id: '814' },
      course: { id: '810' },
      start_date: Time.now,
      end_date: Time.now
    })
    schedule.save(false)

    # The embedded teacher is sent with its OWN attributes. This drives the embedded
    # teacher.update() down the delete-graph path that used to crash on Teacher.first_name.
    schedule.update({
      'id' => '815',
      'teacher' => { 'id' => '814', 'first_name' => 'Changed', 'last_name' => 'Teacher', 'skill' => [{ 'id' => '100' }] },
      'course' => { 'id' => '810' },
      'start_date' => Time.now.to_s,
      'end_date' => Time.now.to_s
    }, false)

    # The embedded teacher's required attribute is intact and the change persisted —
    # i.e. the old triple was deleted (no maxCount-1 cardinality error on read).
    found = TeacherResource.find(id: '814').data
    assert_equal 'Changed', found.first_name, "embedded teacher's first_name should be updated"
    assert_equal 'Teacher', found.last_name, "embedded teacher's last_name should be preserved"

    schedule.destroy
    teacher.destroy
    course.destroy
  end
end
