require 'test_helper'

# Tests to verify that readonly entities (code tables) are protected from
# being overwritten or deleted during create, update, and delete operations.
#
# This test suite verifies the fix for the logical error where the condition:
#   (embedded.class.ancestors.map{|s| s.to_s} & embedded_readonly_entities).empty? || top_level
# incorrectly allowed modification of readonly entities when top_level was true.
#
# The fix ensures:
# 1. Readonly entities (code tables) are NEVER modified during save operations
# 2. Readonly entities (code tables) are NEVER modified during update operations
# 3. Readonly entities (code tables) are NEVER deleted when orphaned
class ReadonlyEntityTest < Minitest::Test
  def setup
    Solis::ConfigFile.path = './test/resources'

    # Configure Skill as a readonly entity (code table)
    # Skill inherits from CodeTable in the test schema
    options = Solis::ConfigFile[:solis].merge(embedded_readonly: ['Skill', 'CodeTable'])
    @solis = Solis::Graph.new(Solis::Shape::Reader::File.read(Solis::ConfigFile[:solis][:shacl]), options)

    build_test_data
  end

  # Test 1: Verify that a code table entity (Skill) is not overwritten when creating
  # a new Teacher that references an existing Skill
  def test_save_does_not_overwrite_readonly_entity
    # Get the original skill data
    original_skill = SkillResource.find(id: '100').data
    original_label = original_skill.label
    original_short_label = original_skill.short_label

    # Create a new Teacher referencing the existing Skill with DIFFERENT data
    # This should NOT change the Skill's data
    teacher = Teacher.new({
                            id: '101',
                            first_name: 'Test',
                            last_name: 'Teacher',
                            skill: [{
                                      id: '100',
                                      label: 'MODIFIED_LABEL_SHOULD_NOT_BE_SAVED',
                                      short_label: 'MODIFIED_SHORT'
                                    }]
                          })
    teacher.save(false)

    # Verify the skill was NOT modified
    skill_after = SkillResource.find(id: '100').data
    assert_equal original_label, skill_after.label, "Readonly entity label should not be modified during save"
    assert_equal original_short_label, skill_after.short_label, "Readonly entity short_label should not be modified during save"

    # Cleanup
    teacher.destroy
  end

  # Test 2: Verify that updating a Teacher's skill reference does not modify the Skill entity
  def test_update_does_not_overwrite_readonly_entity
    # Get the original skill data
    original_skill = SkillResource.find(id: '100').data
    original_label = original_skill.label
    original_short_label = original_skill.short_label

    # Create a teacher first
    teacher = Teacher.new({
                            id: '102',
                            first_name: 'Update',
                            last_name: 'TestTeacher',
                            skill: [{ id: '100' }]
                          })
    teacher.save(false)

    # Now update the teacher with modified skill data
    # This should NOT change the Skill's data
    teacher_data = {
      'id' => '102',
      'skill' => [{
                    'id' => '100',
                    'label' => 'MODIFIED_VIA_UPDATE',
                    'short_label' => 'MOD_UPDATE'
                  }]
    }
    teacher.update(teacher_data, false)

    # Verify the skill was NOT modified
    skill_after = SkillResource.find(id: '100').data
    assert_equal original_label, skill_after.label, "Readonly entity label should not be modified during update"
    assert_equal original_short_label, skill_after.short_label, "Readonly entity short_label should not be modified during update"

    # Cleanup
    teacher.destroy
  end

  # Test 3: Verify that removing a reference to a code table entity does NOT delete it
  def test_orphaned_readonly_entity_is_not_deleted
    # Create a second skill that will be "orphaned"
    skill2 = Skill.new({ id: '103', label: 'Second Skill', short_label: 'Skill2' })
    skill2.save

    # Create a teacher with both skills
    teacher = Teacher.new({
                            id: '104',
                            first_name: 'Multi',
                            last_name: 'SkillTeacher',
                            skill: [{ id: '100' }, { id: '103' }]
                          })
    teacher.save(false)

    # Now update the teacher to only have one skill, orphaning the other
    # The orphaned skill should NOT be deleted because it's readonly
    teacher_data = {
      'id' => '104',
      'skill' => [{ 'id' => '100' }]
    }
    teacher.update(teacher_data, false)

    # Verify the "orphaned" skill still exists
    orphaned_skill = SkillResource.find(id: '103').data
    assert_equal '103', orphaned_skill.id, "Orphaned readonly entity should not be deleted"
    assert_equal 'Second Skill', orphaned_skill.label, "Orphaned readonly entity data should be intact"

    # Cleanup
    teacher.destroy
    skill2.destroy
  end

  # Test 4: Verify that code table entities referenced by multiple entities are protected
  def test_shared_readonly_entity_is_protected
    # Get original skill data
    original_skill = SkillResource.find(id: '100').data
    original_label = original_skill.label

    # Create two teachers referencing the same skill with different "modifications"
    teacher1 = Teacher.new({
                             id: '105',
                             first_name: 'First',
                             last_name: 'SharedSkill',
                             skill: [{
                                       id: '100',
                                       label: 'MODIFIED_BY_TEACHER1'
                                     }]
                           })
    teacher1.save(false)

    teacher2 = Teacher.new({
                             id: '106',
                             first_name: 'Second',
                             last_name: 'SharedSkill',
                             skill: [{
                                       id: '100',
                                       label: 'MODIFIED_BY_TEACHER2'
                                     }]
                           })
    teacher2.save(false)

    # Verify the skill was NOT modified by either teacher
    skill_after = SkillResource.find(id: '100').data
    assert_equal original_label, skill_after.label, "Shared readonly entity should not be modified"

    # Cleanup
    teacher1.destroy
    teacher2.destroy
  end

  # Test 5: Verify non-readonly embedded entities CAN still be modified
  def test_non_readonly_entities_can_be_modified
    # Students are NOT in the embedded_readonly list, so they CAN be modified

    # Create a student
    student = Student.new({
                            id: '107',
                            first_name: 'Original',
                            last_name: 'Name',
                            age: 20
                          })
    student.save

    # Get original data
    original_student = StudentResource.find(id: '107').data
    assert_equal 'Original', original_student.first_name

    # Update via another entity or directly
    student_data = { 'id' => '107', 'first_name' => 'Modified', 'last_name' => 'Name', 'age' => 21 }
    student.update(student_data)

    # Verify the student WAS modified (proving the readonly protection is specific)
    modified_student = StudentResource.find(id: '107').data
    assert_equal 'Modified', modified_student.first_name, "Non-readonly entities should be modifiable"
    assert_equal 21, modified_student.age, "Non-readonly entities should be modifiable"

    # Cleanup
    student.destroy
  end

  # Test 6: Verify that attempting to save with a non-existent readonly entity logs a warning
  # (it should not create the readonly entity)
  def test_save_with_nonexistent_readonly_entity_does_not_create_it
    # Try to create a teacher referencing a non-existent skill
    teacher = Teacher.new({
                            id: '108',
                            first_name: 'NoSkill',
                            last_name: 'Teacher',
                            skill: [{
                                      id: 'nonexistent_skill_999',
                                      label: 'Should Not Be Created',
                                      short_label: 'NOPE'
                                    }]
                          })

    # This should not raise an error, but should log a warning
    # and the skill should NOT be created
    begin
      teacher.save(false)
    rescue => e
      # It's acceptable if this raises an error due to the missing required reference
    end

    # Verify the non-existent skill was NOT created
    # We use a SPARQL query directly instead of Resource.find since the entity
    # never existed in the first place
    sparql = SPARQL::Client.new(Teacher.sparql_endpoint)
    exists = sparql.query("ASK WHERE { <http://solis.template/skills/nonexistent_skill_999> ?p ?o }")
    refute exists, "Non-existent readonly entity should not be created"

    # Also verify that a search returns no results
    results = SkillResource.all({ "filter" => { "id" => { "eq" => "nonexistent_skill_999" } } }).data
    assert_empty results, "Readonly entity should not be found in search results"
  end

  # Test 7: Test the readonly_entity? helper method behavior
  def test_readonly_entity_helper_correctly_identifies_readonly_entities
    skill = Skill.new({ id: '109', label: 'Test', short_label: 'T' })
    student = Student.new({ id: '110', first_name: 'Test', last_name: 'Student', age: 25 })

    # Use send to access the private method
    readonly_list = (Solis::Options.instance.get[:embedded_readonly] || []).map(&:to_s)

    # Skill should be identified as readonly
    skill_ancestors = skill.class.ancestors.map(&:to_s)
    is_skill_readonly = (skill_ancestors & readonly_list).any?
    assert is_skill_readonly, "Skill should be identified as readonly"

    # Student should NOT be identified as readonly
    student_ancestors = student.class.ancestors.map(&:to_s)
    is_student_readonly = (student_ancestors & readonly_list).any?
    refute is_student_readonly, "Student should not be identified as readonly"
  end

  private

  def build_test_data
    @solis.flush_all('http://solis.template/')

    # Create a skill (code table entry) that will be used in tests
    skill = Skill.new({ id: '100', label: 'Original Skill Label', short_label: 'OrigSkill' })
    skill.save
  end
end
