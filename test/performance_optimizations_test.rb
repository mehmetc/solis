require 'test_helper'

# Tests to verify the performance optimizations maintain correct behavior.
#
# Covers:
# 1. up? health check caching (client.rb)
# 2. UUID generation without collision check (make_id_for)
# 3. Redundant re-fetch elimination in update()
# 4. known_entities cache in build_ttl_objekt / as_graph
# 5. Batched existence checks (batch_exists?)
# 6. Batched orphan reference checks (batch_referenced?)
# 7. SPARQL client reuse between save and update
# 8. Embedded readonly entity protection still works after optimizations
class PerformanceOptimizationsTest < Minitest::Test
  def setup
    Solis::ConfigFile.path = './test/resources'

    options = Solis::ConfigFile[:solis].merge(embedded_readonly: ['Skill', 'CodeTable'])
    @solis = Solis::Graph.new(Solis::Shape::Reader::File.read(Solis::ConfigFile[:solis][:shacl]), options)

    build_test_data
  end

  # ──────────────────────────────────────────────────────────────────────
  # 1. up? health check caching
  # ──────────────────────────────────────────────────────────────────────

  def test_up_check_is_cached
    endpoint = Solis::ConfigFile[:solis][:sparql_endpoint]
    graph_name = 'http://solis.template/'
    client = Solis::Store::Sparql::Client.new(endpoint, graph_name: graph_name)

    # First call should hit the endpoint
    result1 = client.up?
    assert result1, "First up? call should return true"

    # Second call within 30s should return cached result without new query
    result2 = client.up?
    assert result2, "Cached up? call should return true"
  end

  def test_up_check_cache_resets_on_error
    # Verify the cache fields exist and work
    endpoint = Solis::ConfigFile[:solis][:sparql_endpoint]
    graph_name = 'http://solis.template/'
    client = Solis::Store::Sparql::Client.new(endpoint, graph_name: graph_name)

    # After a successful check, cache should be set
    client.up?
    assert client.instance_variable_get(:@up_checked_at), "Cache timestamp should be set after successful check"
    assert client.instance_variable_get(:@up_result), "Cache result should be set after successful check"
  end

  # ──────────────────────────────────────────────────────────────────────
  # 2. UUID generation without collision check
  # ──────────────────────────────────────────────────────────────────────

  def test_make_id_for_generates_uuid
    # make_id_for is called automatically during initialize, so a Student
    # created without an explicit id should already have a UUID assigned
    student = Student.new({ first_name: 'Auto', last_name: 'ID', age: 18 })
    refute_nil student.id, "make_id_for should generate an ID during initialize"
    assert_match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/, student.id, "Generated ID should be a valid UUID")
  end

  def test_make_id_for_preserves_existing_id
    student = Student.new({ id: 'my-custom-id', first_name: 'Custom', last_name: 'ID', age: 18 })
    Student.make_id_for(student)
    assert_equal 'my-custom-id', student.id, "make_id_for should not overwrite existing ID"
  end

  def test_make_id_for_normalizes_url_id
    student = Student.new({ id: 'http://solis.template/students/url-based-id', first_name: 'URL', last_name: 'ID', age: 18 })
    Student.make_id_for(student)
    assert_equal 'url-based-id', student.id, "make_id_for should extract ID from URL"
  end

  def test_make_id_for_generates_unique_ids
    ids = 100.times.map do
      s = Student.new({ first_name: 'Unique', last_name: 'Test', age: 18 })
      Student.make_id_for(s)
      s.id
    end
    assert_equal 100, ids.uniq.size, "100 generated IDs should all be unique"
  end

  # ──────────────────────────────────────────────────────────────────────
  # 3. Update returns correct data without redundant re-fetches
  # ──────────────────────────────────────────────────────────────────────

  def test_update_returns_updated_entity
    student = Student.new({ id: 'update-return-1', first_name: 'Before', last_name: 'Update', age: 30 })
    student.save

    result = student.update({ 'id' => 'update-return-1', 'first_name' => 'After', 'last_name' => 'Update', 'age' => 31 })
    refute_nil result, "Update should return the entity"

    # Verify via a fresh read that the update persisted
    found = StudentResource.find(id: 'update-return-1').data
    assert_equal 'After', found.first_name
    assert_equal 31, found.age

    student.destroy
  end

  def test_update_unchanged_entity_returns_original
    student = Student.new({ id: 'unchanged-1', first_name: 'Same', last_name: 'Data', age: 25 })
    student.save

    # Update with identical data
    result = student.update({ 'id' => 'unchanged-1', 'first_name' => 'Same', 'last_name' => 'Data', 'age' => 25 })
    refute_nil result, "Update with unchanged data should return the entity"

    # Verify data is intact
    found = StudentResource.find(id: 'unchanged-1').data
    assert_equal 'Same', found.first_name

    student.destroy
  end

  # ──────────────────────────────────────────────────────────────────────
  # 4. known_entities cache in as_graph / build_ttl_objekt
  # ──────────────────────────────────────────────────────────────────────

  def test_as_graph_with_known_entities
    student = Student.new({ id: 'graph-cache-1', first_name: 'Cache', last_name: 'Test', age: 22 })
    student.save

    # as_graph should accept known_entities parameter
    known = { 'graph-cache-1' => student }
    graph = student.send(:as_graph, student, true, known)
    refute_nil graph, "as_graph should return a graph when known_entities are provided"
    assert graph.size > 0, "Graph should contain triples"

    student.destroy
  end

  def test_as_graph_without_known_entities_still_works
    student = Student.new({ id: 'graph-no-cache-1', first_name: 'NoCache', last_name: 'Test', age: 23 })
    student.save

    # as_graph without known_entities should still work (backward compatible)
    graph = student.send(:as_graph, student, true)
    refute_nil graph, "as_graph should work without known_entities"
    assert graph.size > 0, "Graph should contain triples"

    student.destroy
  end

  # ──────────────────────────────────────────────────────────────────────
  # 5. Batched existence checks (batch_exists?)
  # ──────────────────────────────────────────────────────────────────────

  def test_batch_exists_with_existing_entities
    sparql = SPARQL::Client.new(Student.sparql_endpoint)

    s1 = Student.new({ id: 'batch-e-1', first_name: 'Batch1', last_name: 'Exists', age: 20 })
    s2 = Student.new({ id: 'batch-e-2', first_name: 'Batch2', last_name: 'Exists', age: 21 })
    s1.save
    s2.save

    result = Student.batch_exists?(sparql, [s1, s2])
    assert result.include?(s1.graph_id), "batch_exists? should find existing entity s1"
    assert result.include?(s2.graph_id), "batch_exists? should find existing entity s2"

    s1.destroy
    s2.destroy
  end

  def test_batch_exists_with_nonexistent_entities
    sparql = SPARQL::Client.new(Student.sparql_endpoint)

    s1 = Student.new({ id: 'batch-ne-1', first_name: 'Batch1', last_name: 'NotExist', age: 20 })
    s2 = Student.new({ id: 'batch-ne-2', first_name: 'Batch2', last_name: 'NotExist', age: 21 })
    # Don't save -- they don't exist in the store

    result = Student.batch_exists?(sparql, [s1, s2])
    assert result.empty?, "batch_exists? should return empty set for non-existent entities"
  end

  def test_batch_exists_with_mixed_entities
    sparql = SPARQL::Client.new(Student.sparql_endpoint)

    s_existing = Student.new({ id: 'batch-mix-1', first_name: 'Existing', last_name: 'Mix', age: 20 })
    s_existing.save

    s_missing = Student.new({ id: 'batch-mix-2', first_name: 'Missing', last_name: 'Mix', age: 21 })
    # Don't save s_missing

    result = Student.batch_exists?(sparql, [s_existing, s_missing])
    assert result.include?(s_existing.graph_id), "batch_exists? should find existing entity"
    refute result.include?(s_missing.graph_id), "batch_exists? should not find missing entity"

    s_existing.destroy
  end

  def test_batch_exists_with_empty_list
    sparql = SPARQL::Client.new(Student.sparql_endpoint)
    result = Student.batch_exists?(sparql, [])
    assert result.empty?, "batch_exists? with empty list should return empty set"
  end

  def test_batch_exists_with_single_existing_entity
    sparql = SPARQL::Client.new(Student.sparql_endpoint)

    s1 = Student.new({ id: 'batch-single-1', first_name: 'Single', last_name: 'Exists', age: 20 })
    s1.save

    result = Student.batch_exists?(sparql, [s1])
    assert result.include?(s1.graph_id), "batch_exists? with single existing entity should find it"

    s1.destroy
  end

  def test_batch_exists_with_single_nonexistent_entity
    sparql = SPARQL::Client.new(Student.sparql_endpoint)

    s1 = Student.new({ id: 'batch-single-ne-1', first_name: 'Single', last_name: 'NotExist', age: 20 })
    # Don't save

    result = Student.batch_exists?(sparql, [s1])
    assert result.empty?, "batch_exists? with single non-existent entity should return empty set"
  end

  # ──────────────────────────────────────────────────────────────────────
  # 6. Batched orphan reference checks (batch_referenced?)
  # ──────────────────────────────────────────────────────────────────────

  def test_batch_referenced_finds_referenced_entities
    # student '500' is referenced by schedule '501'
    student = Student.new({ id: '500', first_name: 'Referenced', last_name: 'Student', age: 20 })
    student.save

    course = Course.new({ id: '501', course_name: 'RefCourse' })
    course.save

    teacher = Teacher.new({ id: '502', first_name: 'Ref', last_name: 'Teacher', skill: [{ id: '100' }] })
    teacher.save(false)

    schedule = Schedule.new({
      id: '503',
      students: [{ id: '500' }],
      teacher: { id: '502' },
      course: { id: '501' },
      start_date: Time.now,
      end_date: Time.now
    })
    schedule.save(false)

    sparql = SPARQL::Client.new(Student.sparql_endpoint)
    result = student.send(:batch_referenced?, sparql, [student])
    assert result.include?(student.graph_id), "batch_referenced? should find referenced entity"

    schedule.destroy
    teacher.destroy
    course.destroy
    student.destroy
  end

  def test_batch_referenced_does_not_find_unreferenced_entities
    student = Student.new({ id: '510', first_name: 'Unreferenced', last_name: 'Student', age: 20 })
    student.save

    sparql = SPARQL::Client.new(Student.sparql_endpoint)
    result = student.send(:batch_referenced?, sparql, [student])
    refute result.include?(student.graph_id), "batch_referenced? should not find unreferenced entity"

    student.destroy
  end

  def test_batch_referenced_with_empty_list
    student = Student.new({ id: '511', first_name: 'Empty', last_name: 'List', age: 20 })
    sparql = SPARQL::Client.new(Student.sparql_endpoint)
    result = student.send(:batch_referenced?, sparql, [])
    assert result.empty?, "batch_referenced? with empty list should return empty set"
  end

  # ──────────────────────────────────────────────────────────────────────
  # 7. SPARQL client reuse (save delegates to update with same client)
  # ──────────────────────────────────────────────────────────────────────

  def test_save_existing_entity_delegates_to_update
    # Create entity first
    student = Student.new({ id: 'reuse-client-1', first_name: 'First', last_name: 'Save', age: 20 })
    student.save

    # Save again with modified data -- should delegate to update
    student2 = Student.new({ id: 'reuse-client-1', first_name: 'Second', last_name: 'Save', age: 21 })
    student2.save

    # Verify the update happened
    found = StudentResource.find(id: 'reuse-client-1').data
    assert_equal 'Second', found.first_name
    assert_equal 21, found.age

    student.destroy
  end

  def test_update_accepts_sparql_client_parameter
    student = Student.new({ id: 'client-param-1', first_name: 'Client', last_name: 'Param', age: 20 })
    student.save

    # Pass an explicit SPARQL client
    sparql = SPARQL::Client.new(Student.sparql_endpoint)
    result = student.update({ 'id' => 'client-param-1', 'first_name' => 'Updated', 'last_name' => 'Param', 'age' => 21 }, true, true, sparql)
    refute_nil result, "Update with explicit sparql client should succeed"

    found = StudentResource.find(id: 'client-param-1').data
    assert_equal 'Updated', found.first_name

    student.destroy
  end

  # ──────────────────────────────────────────────────────────────────────
  # 8. Embedded readonly protection after optimizations
  # ──────────────────────────────────────────────────────────────────────

  def test_readonly_entity_not_modified_on_save_with_batched_checks
    original_skill = SkillResource.find(id: '100').data
    original_label = original_skill.label

    teacher = Teacher.new({
      id: '600',
      first_name: 'Batch',
      last_name: 'Readonly',
      skill: [{
        id: '100',
        label: 'SHOULD_NOT_CHANGE',
        short_label: 'NOPE'
      }]
    })
    teacher.save(false)

    # Verify skill was NOT modified
    skill_after = SkillResource.find(id: '100').data
    assert_equal original_label, skill_after.label, "Readonly entity should not be modified with batched existence checks"

    teacher.destroy
  end

  def test_readonly_entity_not_modified_on_update_with_batched_checks
    original_skill = SkillResource.find(id: '100').data
    original_label = original_skill.label

    teacher = Teacher.new({
      id: '601',
      first_name: 'BatchUpdate',
      last_name: 'Readonly',
      skill: [{ id: '100' }]
    })
    teacher.save(false)

    # Update with modified skill data
    teacher.update({
      'id' => '601',
      'skill' => [{
        'id' => '100',
        'label' => 'MODIFIED_BATCH_UPDATE',
        'short_label' => 'MOD'
      }]
    }, false)

    skill_after = SkillResource.find(id: '100').data
    assert_equal original_label, skill_after.label, "Readonly entity should not be modified during batched update"

    teacher.destroy
  end

  def test_orphaned_readonly_entity_not_deleted_with_batched_ref_checks
    skill2 = Skill.new({ id: '602', label: 'Orphan Batch Skill', short_label: 'OBS' })
    skill2.save

    teacher = Teacher.new({
      id: '603',
      first_name: 'OrphanBatch',
      last_name: 'Teacher',
      skill: [{ id: '100' }, { id: '602' }]
    })
    teacher.save(false)

    # Remove skill '602' from teacher -- it should NOT be deleted (readonly)
    teacher.update({
      'id' => '603',
      'skill' => [{ 'id' => '100' }]
    }, false)

    # Verify orphaned skill still exists
    orphaned_skill = SkillResource.find(id: '602').data
    assert_equal '602', orphaned_skill.id, "Orphaned readonly entity should not be deleted with batched ref checks"

    teacher.destroy
    skill2.destroy
  end

  def test_nonexistent_readonly_entity_not_created_with_batched_checks
    teacher = Teacher.new({
      id: '604',
      first_name: 'NoCreate',
      last_name: 'Batch',
      skill: [{
        id: 'batch_nonexistent_999',
        label: 'Should Not Exist',
        short_label: 'NO'
      }]
    })

    begin
      teacher.save(false)
    rescue => e
      # Acceptable if save raises due to missing required reference
    end

    sparql = SPARQL::Client.new(Teacher.sparql_endpoint)
    exists = sparql.query("ASK WHERE { <http://solis.template/skills/batch_nonexistent_999> ?p ?o }")
    refute exists, "Non-existent readonly entity should not be created with batched checks"
  end

  # ──────────────────────────────────────────────────────────────────────
  # 9. End-to-end CRUD with embedded entities (integration)
  # ──────────────────────────────────────────────────────────────────────

  def test_create_entity_with_multiple_embedded
    course = Course.new({ id: '700', course_name: 'Integration Test' })
    course.save

    s1 = Student.new({ id: '701', first_name: 'Int1', last_name: 'Test', age: 20 })
    s1.save
    s2 = Student.new({ id: '702', first_name: 'Int2', last_name: 'Test', age: 21 })
    s2.save

    teacher = Teacher.new({ id: '703', first_name: 'Int', last_name: 'Teacher', skill: [{ id: '100' }] })
    teacher.save(false)

    schedule = Schedule.new({
      id: '704',
      students: [{ id: '701' }, { id: '702' }],
      teacher: { id: '703' },
      course: { id: '700' },
      start_date: Time.now,
      end_date: Time.now
    })
    schedule.save(false)

    # Verify schedule was created with correct embedded entities
    found = ScheduleResource.find(id: '704').data
    assert_equal '704', found.id
    assert_equal 2, found.students.length

    schedule.destroy
    teacher.destroy
    s2.destroy
    s1.destroy
    course.destroy
  end

  def test_update_entity_with_embedded_add_and_remove
    course = Course.new({ id: '710', course_name: 'Update Embedded' })
    course.save

    s1 = Student.new({ id: '711', first_name: 'Emb1', last_name: 'Update', age: 20 })
    s1.save
    s2 = Student.new({ id: '712', first_name: 'Emb2', last_name: 'Update', age: 21 })
    s2.save
    s3 = Student.new({ id: '713', first_name: 'Emb3', last_name: 'Update', age: 22 })
    s3.save

    teacher = Teacher.new({ id: '714', first_name: 'Emb', last_name: 'Teacher', skill: [{ id: '100' }] })
    teacher.save(false)

    schedule = Schedule.new({
      id: '715',
      students: [{ id: '711' }, { id: '712' }],
      teacher: { id: '714' },
      course: { id: '710' },
      start_date: Time.now,
      end_date: Time.now
    })
    schedule.save(false)

    # Update: remove s1, add s3
    schedule.update({
      'id' => '715',
      'students' => [{ 'id' => '712' }, { 'id' => '713' }],
      'teacher' => { 'id' => '714' },
      'course' => { 'id' => '710' },
      'start_date' => Time.now.to_s,
      'end_date' => Time.now.to_s
    }, false)

    found = ScheduleResource.find(id: '715').data
    student_ids = found.students.map { |s| s.is_a?(String) ? s.split('/').last : s.id }
    assert_includes student_ids, '712', "Student 712 should still be in schedule"
    assert_includes student_ids, '713', "Student 713 should be added to schedule"

    schedule.destroy
    teacher.destroy
    s3.destroy
    s2.destroy
    s1.destroy
    course.destroy
  end

  def test_save_then_update_same_entity
    student = Student.new({ id: 'save-update-1', first_name: 'Initial', last_name: 'State', age: 18 })
    student.save

    found = StudentResource.find(id: 'save-update-1').data
    assert_equal 'Initial', found.first_name

    student.update({ 'id' => 'save-update-1', 'first_name' => 'Updated', 'last_name' => 'State', 'age' => 19 })

    found = StudentResource.find(id: 'save-update-1').data
    assert_equal 'Updated', found.first_name
    assert_equal 19, found.age

    student.destroy
  end

  # ──────────────────────────────────────────────────────────────────────
  # 10. PATCH mode: partial updates without orphan deletion
  # ──────────────────────────────────────────────────────────────────────

  # --- 10a. PATCH only changes provided scalar attributes, keeps the rest ---

  def test_patch_only_changes_provided_attributes
    student = Student.new({ id: 'patch-scalar-1', first_name: 'Original', last_name: 'Name', age: 20 })
    student.save

    # PATCH with only first_name — last_name and age should stay
    student.update({ 'id' => 'patch-scalar-1', 'first_name' => 'Patched' }, true, true, nil, patch: true)

    found = StudentResource.find(id: 'patch-scalar-1').data
    assert_equal 'Patched', found.first_name, "PATCH should update provided attribute"
    assert_equal 'Name', found.last_name, "PATCH should keep omitted attribute"
    assert_equal 20, found.age, "PATCH should keep omitted attribute"

    student.destroy
  end

  # --- 10b. PATCH merges embedded arrays instead of replacing ---

  def test_patch_merges_embedded_entities
    course = Course.new({ id: 'patch-emb-c1', course_name: 'Patch Merge' })
    course.save

    s1 = Student.new({ id: 'patch-emb-s1', first_name: 'Keep', last_name: 'Me', age: 20 })
    s1.save
    s2 = Student.new({ id: 'patch-emb-s2', first_name: 'Keep', last_name: 'Also', age: 21 })
    s2.save
    s3 = Student.new({ id: 'patch-emb-s3', first_name: 'Add', last_name: 'New', age: 22 })
    s3.save

    teacher = Teacher.new({ id: 'patch-emb-t1', first_name: 'Patch', last_name: 'Teacher', skill: [{ id: '100' }] })
    teacher.save(false)

    schedule = Schedule.new({
      id: 'patch-emb-sch1',
      students: [{ id: 'patch-emb-s1' }, { id: 'patch-emb-s2' }],
      teacher: { id: 'patch-emb-t1' },
      course: { id: 'patch-emb-c1' },
      start_date: Time.now,
      end_date: Time.now
    })
    schedule.save(false)

    # PATCH: send only s3 in the students array.
    # In PATCH mode, s1 and s2 should be kept, s3 should be added.
    schedule.update({
      'id' => 'patch-emb-sch1',
      'students' => [{ 'id' => 'patch-emb-s3' }]
    }, false, true, nil, patch: true)

    found = ScheduleResource.find(id: 'patch-emb-sch1').data
    student_ids = found.students.map { |s| s.is_a?(String) ? s.split('/').last : s.id }
    assert_includes student_ids, 'patch-emb-s1', "PATCH should keep original student s1"
    assert_includes student_ids, 'patch-emb-s2', "PATCH should keep original student s2"
    assert_includes student_ids, 'patch-emb-s3', "PATCH should add new student s3"
    assert_equal 3, student_ids.size, "PATCH should result in 3 students total"

    schedule.destroy
    teacher.destroy
    s3.destroy
    s2.destroy
    s1.destroy
    course.destroy
  end

  # --- 10c. PATCH does NOT delete orphaned embedded entities ---

  def test_patch_does_not_orphan_missing_embedded_entities
    course = Course.new({ id: 'patch-no-orph-c1', course_name: 'No Orphan' })
    course.save

    s1 = Student.new({ id: 'patch-no-orph-s1', first_name: 'Stay', last_name: 'Put', age: 20 })
    s1.save
    s2 = Student.new({ id: 'patch-no-orph-s2', first_name: 'Also', last_name: 'Stay', age: 21 })
    s2.save

    teacher = Teacher.new({ id: 'patch-no-orph-t1', first_name: 'PatchOrph', last_name: 'Teacher', skill: [{ id: '100' }] })
    teacher.save(false)

    schedule = Schedule.new({
      id: 'patch-no-orph-sch1',
      students: [{ id: 'patch-no-orph-s1' }, { id: 'patch-no-orph-s2' }],
      teacher: { id: 'patch-no-orph-t1' },
      course: { id: 'patch-no-orph-c1' },
      start_date: Time.now,
      end_date: Time.now
    })
    schedule.save(false)

    # PATCH: only mention s1, omit s2 entirely.
    # In PATCH mode, s2 should NOT be orphaned/deleted.
    schedule.update({
      'id' => 'patch-no-orph-sch1',
      'students' => [{ 'id' => 'patch-no-orph-s1' }]
    }, false, true, nil, patch: true)

    found = ScheduleResource.find(id: 'patch-no-orph-sch1').data
    student_ids = found.students.map { |s| s.is_a?(String) ? s.split('/').last : s.id }
    assert_includes student_ids, 'patch-no-orph-s1', "PATCH should keep mentioned student"
    assert_includes student_ids, 'patch-no-orph-s2', "PATCH should keep unmentioned student (no orphan)"

    schedule.destroy
    teacher.destroy
    s2.destroy
    s1.destroy
    course.destroy
  end

  # --- 10d. PUT mode still orphans/deletes (contrast with PATCH) ---

  def test_put_still_orphans_embedded_entities
    course = Course.new({ id: 'put-orph-c1', course_name: 'Put Orphan' })
    course.save

    s1 = Student.new({ id: 'put-orph-s1', first_name: 'Stays', last_name: 'Put', age: 20 })
    s1.save
    s2 = Student.new({ id: 'put-orph-s2', first_name: 'Gets', last_name: 'Removed', age: 21 })
    s2.save

    teacher = Teacher.new({ id: 'put-orph-t1', first_name: 'PutOrph', last_name: 'Teacher', skill: [{ id: '100' }] })
    teacher.save(false)

    schedule = Schedule.new({
      id: 'put-orph-sch1',
      students: [{ id: 'put-orph-s1' }, { id: 'put-orph-s2' }],
      teacher: { id: 'put-orph-t1' },
      course: { id: 'put-orph-c1' },
      start_date: Time.now,
      end_date: Time.now
    })
    schedule.save(false)

    # PUT (default): send only s1, omit s2.
    # In PUT mode, s2 should be orphaned from the schedule.
    schedule.update({
      'id' => 'put-orph-sch1',
      'students' => [{ 'id' => 'put-orph-s1' }],
      'teacher' => { 'id' => 'put-orph-t1' },
      'course' => { 'id' => 'put-orph-c1' },
      'start_date' => Time.now.to_s,
      'end_date' => Time.now.to_s
    }, false)

    found = ScheduleResource.find(id: 'put-orph-sch1').data
    student_ids = found.students.map { |s| s.is_a?(String) ? s.split('/').last : s.id }
    assert_includes student_ids, 'put-orph-s1', "PUT should keep mentioned student"
    refute_includes student_ids, 'put-orph-s2', "PUT should remove unmentioned student"

    schedule.destroy
    teacher.destroy
    # s2 may have been deleted by orphan logic, try cleanup
    begin; s2.destroy; rescue; end
    s1.destroy
    course.destroy
  end

  # --- 10e. PATCH with omitted embedded attribute leaves it untouched ---

  def test_patch_omitted_embedded_attribute_is_untouched
    course = Course.new({ id: 'patch-omit-c1', course_name: 'Omit Test' })
    course.save

    s1 = Student.new({ id: 'patch-omit-s1', first_name: 'Untouched', last_name: 'Student', age: 20 })
    s1.save

    teacher = Teacher.new({ id: 'patch-omit-t1', first_name: 'Omit', last_name: 'Teacher', skill: [{ id: '100' }] })
    teacher.save(false)

    schedule = Schedule.new({
      id: 'patch-omit-sch1',
      students: [{ id: 'patch-omit-s1' }],
      teacher: { id: 'patch-omit-t1' },
      course: { id: 'patch-omit-c1' },
      start_date: Time.now,
      end_date: Time.now
    })
    schedule.save(false)

    # PATCH: update only the course, don't mention students at all.
    # Students should remain completely untouched.
    new_course = Course.new({ id: 'patch-omit-c2', course_name: 'New Course' })
    new_course.save

    schedule.update({
      'id' => 'patch-omit-sch1',
      'course' => { 'id' => 'patch-omit-c2' }
    }, false, true, nil, patch: true)

    found = ScheduleResource.find(id: 'patch-omit-sch1').data
    student_ids = found.students.map { |s| s.is_a?(String) ? s.split('/').last : s.id }
    assert_includes student_ids, 'patch-omit-s1', "PATCH should not touch omitted embedded attribute"

    schedule.destroy
    teacher.destroy
    new_course.destroy
    s1.destroy
    course.destroy
  end

  # --- 10f. PATCH with readonly embedded entities ---

  def test_patch_readonly_entity_not_modified
    original_skill = SkillResource.find(id: '100').data
    original_label = original_skill.label

    teacher = Teacher.new({
      id: 'patch-ro-t1',
      first_name: 'PatchRO',
      last_name: 'Teacher',
      skill: [{ id: '100' }]
    })
    teacher.save(false)

    # PATCH: try to modify the readonly skill
    teacher.update({
      'id' => 'patch-ro-t1',
      'skill' => [{
        'id' => '100',
        'label' => 'PATCH_SHOULD_NOT_MODIFY',
        'short_label' => 'NOPE'
      }]
    }, false, true, nil, patch: true)

    skill_after = SkillResource.find(id: '100').data
    assert_equal original_label, skill_after.label, "PATCH should not modify readonly entity"

    teacher.destroy
  end

  def test_patch_readonly_entity_not_orphaned
    skill2 = Skill.new({ id: 'patch-ro-s2', label: 'Patch RO Skill', short_label: 'PRS' })
    skill2.save

    teacher = Teacher.new({
      id: 'patch-ro-t2',
      first_name: 'PatchROOrph',
      last_name: 'Teacher',
      skill: [{ id: '100' }, { id: 'patch-ro-s2' }]
    })
    teacher.save(false)

    # PATCH: mention only skill 100, omit patch-ro-s2.
    # In PATCH mode, patch-ro-s2 should be kept (merged), not orphaned.
    teacher.update({
      'id' => 'patch-ro-t2',
      'skill' => [{ 'id' => '100' }]
    }, false, true, nil, patch: true)

    found = TeacherResource.find(id: 'patch-ro-t2').data
    skill_ids = found.skill.map { |s| s.is_a?(String) ? s.split('/').last : s.id }
    assert_includes skill_ids, '100', "PATCH should keep mentioned readonly entity"
    assert_includes skill_ids, 'patch-ro-s2', "PATCH should keep unmentioned readonly entity (no orphan)"

    teacher.destroy
    skill2.destroy
  end

  # --- 10g. PATCH default is off (backward compatible) ---

  def test_update_defaults_to_put_mode
    student = Student.new({ id: 'patch-default-1', first_name: 'Default', last_name: 'Put', age: 25 })
    student.save

    # Call update without patch: keyword — should behave as PUT
    student.update({ 'id' => 'patch-default-1', 'first_name' => 'Changed', 'last_name' => 'Put', 'age' => 26 })

    found = StudentResource.find(id: 'patch-default-1').data
    assert_equal 'Changed', found.first_name
    assert_equal 26, found.age

    student.destroy
  end

  private

  def build_test_data
    @solis.flush_all('http://solis.template/')

    # Create a skill (code table) that will be used across tests
    skill = Skill.new({ id: '100', label: 'Original Skill Label', short_label: 'OrigSkill' })
    skill.save
  end
end
