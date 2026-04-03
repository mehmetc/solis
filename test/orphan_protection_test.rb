require 'test_helper'

# Tests for safe orphan handling: top-level entities should not be cascade-deleted
# when unlinked from a parent, unless explicitly opted in via embedded_delete config.
#
# Decision logic (in order of precedence):
# 1. embedded_readonly → never delete (code tables)
# 2. Top-level entity (has own shape) + NOT in embedded_delete → unlink only
# 3. Top-level entity + listed in embedded_delete → delete (opt-in)
# 4. Still referenced elsewhere → never delete (safety net)
class OrphanProtectionTest < Minitest::Test
  def setup
    Solis::ConfigFile.path = './test/resources'

    # Default config: readonly code tables, no embedded_delete
    options = Solis::ConfigFile[:solis].merge(
      embedded_readonly: ['Skill', 'CodeTable'],
      embedded_delete: []
    )
    @solis = Solis::Graph.new(Solis::Shape::Reader::File.read(Solis::ConfigFile[:solis][:shacl]), options)

    build_test_data
  end

  # ──────────────────────────────────────────────────────────────────────
  # Top-level entities should NOT be deleted when unlinked (unlink only)
  # ──────────────────────────────────────────────────────────────────────

  def test_removing_student_from_schedule_does_not_delete_student
    s1 = Student.new({ id: 'orp-s1', first_name: 'Keep', last_name: 'Me', age: 20 })
    s1.save
    s2 = Student.new({ id: 'orp-s2', first_name: 'Also', last_name: 'Keep', age: 21 })
    s2.save

    schedule = Schedule.new({
      id: 'orp-sch1',
      students: [{ id: 'orp-s1' }, { id: 'orp-s2' }],
      teacher: { id: '100' },
      course: { id: '200' },
      start_date: Time.now,
      end_date: Time.now
    })
    schedule.save(false)

    # PUT update: remove s2 from schedule
    schedule.update({
      'id' => 'orp-sch1',
      'students' => [{ 'id' => 'orp-s1' }],
      'teacher' => { 'id' => '100' },
      'course' => { 'id' => '200' },
      'start_date' => Time.now.to_s,
      'end_date' => Time.now.to_s
    }, false)

    # s2 should still exist — it's a top-level entity
    found = StudentResource.find(id: 'orp-s2').data
    assert_equal 'orp-s2', found.id, "Student should NOT be deleted when removed from schedule"

    schedule.destroy
    s2.destroy
    s1.destroy
  end

  def test_removing_course_from_schedule_does_not_delete_course
    extra_course = Course.new({ id: 'orp-c2', course_name: 'Spare Course' })
    extra_course.save

    schedule = Schedule.new({
      id: 'orp-sch2',
      students: [{ id: 'orp-std1' }],
      teacher: { id: '100' },
      course: { id: 'orp-c2' },
      start_date: Time.now,
      end_date: Time.now
    })
    schedule.save(false)

    # PUT update: switch to a different course
    schedule.update({
      'id' => 'orp-sch2',
      'students' => [{ 'id' => 'orp-std1' }],
      'teacher' => { 'id' => '100' },
      'course' => { 'id' => '200' },
      'start_date' => Time.now.to_s,
      'end_date' => Time.now.to_s
    }, false)

    # The original course should still exist
    found = CourseResource.find(id: 'orp-c2').data
    assert_equal 'orp-c2', found.id, "Course should NOT be deleted when replaced in schedule"

    schedule.destroy
    extra_course.destroy
  end

  # ──────────────────────────────────────────────────────────────────────
  # top_level_entity? helper
  # ──────────────────────────────────────────────────────────────────────

  def test_top_level_entity_helper
    student = Student.new({ id: 'orp-top1', first_name: 'Top', last_name: 'Level', age: 20 })
    skill = Skill.new({ id: 'orp-top2', label: 'TopSkill', short_label: 'TS' })
    course = Course.new({ id: 'orp-top3', course_name: 'TopCourse' })

    # All entities in the test schema have their own sh:NodeShape,
    # so they should all be detected as top-level
    assert student.send(:top_level_entity?, student), "Student should be a top-level entity"
    assert skill.send(:top_level_entity?, skill), "Skill should be a top-level entity"
    assert course.send(:top_level_entity?, course), "Course should be a top-level entity"
  end

  # ──────────────────────────────────────────────────────────────────────
  # embedded_delete config: opt-in cascade deletion
  # ──────────────────────────────────────────────────────────────────────

  def test_embedded_delete_config_enables_cascade_deletion
    # Reconfigure with Student in embedded_delete
    options = Solis::ConfigFile[:solis].merge(
      embedded_readonly: ['Skill', 'CodeTable'],
      embedded_delete: ['Student']
    )
    @solis = Solis::Graph.new(Solis::Shape::Reader::File.read(Solis::ConfigFile[:solis][:shacl]), options)
    build_test_data

    orphan_student = Student.new({ id: 'orp-del-s1', first_name: 'Delete', last_name: 'Me', age: 22 })
    orphan_student.save

    schedule = Schedule.new({
      id: 'orp-del-sch1',
      students: [{ id: 'orp-std1' }, { id: 'orp-del-s1' }],
      teacher: { id: '100' },
      course: { id: '200' },
      start_date: Time.now,
      end_date: Time.now
    })
    schedule.save(false)

    # PUT update: remove orphan_student
    schedule.update({
      'id' => 'orp-del-sch1',
      'students' => [{ 'id' => 'orp-std1' }],
      'teacher' => { 'id' => '100' },
      'course' => { 'id' => '200' },
      'start_date' => Time.now.to_s,
      'end_date' => Time.now.to_s
    }, false)

    # orphan_student SHOULD be deleted because Student is in embedded_delete
    assert_raises(Graphiti::Errors::RecordNotFound) do
      StudentResource.find(id: 'orp-del-s1').data
    end

    schedule.destroy
  end

  # ──────────────────────────────────────────────────────────────────────
  # embedded_readonly takes precedence over embedded_delete
  # ──────────────────────────────────────────────────────────────────────

  def test_embedded_readonly_takes_precedence_over_embedded_delete
    # Configure Skill in BOTH readonly and delete lists — readonly should win
    options = Solis::ConfigFile[:solis].merge(
      embedded_readonly: ['Skill', 'CodeTable'],
      embedded_delete: ['Skill']
    )
    @solis = Solis::Graph.new(Solis::Shape::Reader::File.read(Solis::ConfigFile[:solis][:shacl]), options)
    build_test_data

    skill2 = Skill.new({ id: 'orp-ro-sk1', label: 'Protected Skill', short_label: 'PS' })
    skill2.save

    teacher = Teacher.new({
      id: 'orp-ro-t1',
      first_name: 'RO',
      last_name: 'Teacher',
      skill: [{ id: '300' }, { id: 'orp-ro-sk1' }]
    })
    teacher.save(false)

    # Remove skill2 from teacher
    teacher.update({
      'id' => 'orp-ro-t1',
      'skill' => [{ 'id' => '300' }]
    }, false)

    # Skill should still exist — readonly takes precedence
    found = SkillResource.find(id: 'orp-ro-sk1').data
    assert_equal 'orp-ro-sk1', found.id, "Readonly entity should NOT be deleted even if in embedded_delete"

    teacher.destroy
    skill2.destroy
  end

  # ──────────────────────────────────────────────────────────────────────
  # batch_referenced? safety net: don't delete if referenced elsewhere
  # ──────────────────────────────────────────────────────────────────────

  def test_referenced_entity_not_deleted_even_with_embedded_delete
    # Configure Student in embedded_delete
    options = Solis::ConfigFile[:solis].merge(
      embedded_readonly: ['Skill', 'CodeTable'],
      embedded_delete: ['Student']
    )
    @solis = Solis::Graph.new(Solis::Shape::Reader::File.read(Solis::ConfigFile[:solis][:shacl]), options)
    build_test_data

    shared_student = Student.new({ id: 'orp-ref-s1', first_name: 'Shared', last_name: 'Student', age: 23 })
    shared_student.save

    # Two schedules reference the same student
    sch1 = Schedule.new({
      id: 'orp-ref-sch1',
      students: [{ id: 'orp-std1' }, { id: 'orp-ref-s1' }],
      teacher: { id: '100' },
      course: { id: '200' },
      start_date: Time.now,
      end_date: Time.now
    })
    sch1.save(false)

    sch2 = Schedule.new({
      id: 'orp-ref-sch2',
      students: [{ id: 'orp-ref-s1' }],
      teacher: { id: '100' },
      course: { id: '200' },
      start_date: Time.now,
      end_date: Time.now
    })
    sch2.save(false)

    # Remove shared_student from sch1 — still referenced by sch2
    sch1.update({
      'id' => 'orp-ref-sch1',
      'students' => [{ 'id' => 'orp-std1' }],
      'teacher' => { 'id' => '100' },
      'course' => { 'id' => '200' },
      'start_date' => Time.now.to_s,
      'end_date' => Time.now.to_s
    }, false)

    # Student should NOT be deleted — still referenced by sch2
    found = StudentResource.find(id: 'orp-ref-s1').data
    assert_equal 'orp-ref-s1', found.id, "Entity referenced elsewhere should NOT be deleted"

    sch2.destroy
    sch1.destroy
    shared_student.destroy
  end

  # ──────────────────────────────────────────────────────────────────────
  # Without embedded_delete, default behavior is safe for all top-level
  # ──────────────────────────────────────────────────────────────────────

  def test_default_config_protects_all_top_level_entities
    # No embedded_delete config at all — all top-level entities should be safe
    s_orphan = Student.new({ id: 'orp-def-s1', first_name: 'Safe', last_name: 'Default', age: 24 })
    s_orphan.save

    schedule = Schedule.new({
      id: 'orp-def-sch1',
      students: [{ id: 'orp-std1' }, { id: 'orp-def-s1' }],
      teacher: { id: '100' },
      course: { id: '200' },
      start_date: Time.now,
      end_date: Time.now
    })
    schedule.save(false)

    # PUT update: remove orphan student
    schedule.update({
      'id' => 'orp-def-sch1',
      'students' => [{ 'id' => 'orp-std1' }],
      'teacher' => { 'id' => '100' },
      'course' => { 'id' => '200' },
      'start_date' => Time.now.to_s,
      'end_date' => Time.now.to_s
    }, false)

    # Student should still exist — protected by default
    found = StudentResource.find(id: 'orp-def-s1').data
    assert_equal 'orp-def-s1', found.id, "Top-level entity should be protected by default"

    schedule.destroy
    s_orphan.destroy
  end

  private

  def build_test_data
    @solis.flush_all('http://solis.template/')

    # Skill (code table, readonly)
    Skill.new({ id: '300', label: 'Test Skill', short_label: 'TS' }).save

    # Course
    Course.new({ id: '200', course_name: 'Test Course' }).save

    # Teacher with skill
    Teacher.new({ id: '100', first_name: 'Test', last_name: 'Teacher', skill: [{ id: '300' }] }).save(false)

    # A student that stays in schedules
    Student.new({ id: 'orp-std1', first_name: 'Permanent', last_name: 'Student', age: 20 }).save
  end
end
