require 'test_helper'

# Regression test for the production failure seen on solis 0.122.0:
#
#   POST /verwantschappen  { "agent": { "id": "OR10-…" }, … }
#   => 500  "Agent(OR10-…)~Agent.naam min=1 and max="
#
# Creating a NEW top-level entity that references an EXISTING entity by an
# id-only stub must NOT deep-serialize and re-validate the referenced entity's
# mandatory subgraph. In 0.122.0 the old make_graph/build_ttl_objekt pipeline
# recursed into the referenced stub and, because the stub's children were never
# resolved from the store on the create path, raised the referenced entity's
# mincount (its mandatory `naam`/`first_name`/…) as missing.
#
# The 0.123.0 serialize pipeline emits a shallow_stub? child as a plain URI
# reference (serialize_attribute, deep:false in save) and never recurses into
# it, so the reference's own mandatory attributes are not validated here.
#
# Mapping to the production shapes:
#   verwantschap --agent--> Agent (mandatory naam, min=1)
#   Schedule     --teacher-> Teacher (mandatory first_name/last_name/skill, min=1)
class CreateWithReferencedStubTest < Minitest::Test
  def setup
    Solis::ConfigFile.path = './test/resources'

    options = Solis::ConfigFile[:solis].merge(embedded_readonly: [])
    @solis = Solis::Graph.new(Solis::Shape::Reader::File.read(Solis::ConfigFile[:solis][:shacl]), options)

    @solis.flush_all('http://solis.template/')

    # An existing, fully-populated "referenced" entity, analogous to the agent
    # that already exists in the store with its mandatory naam.
    Skill.new({ id: 'ref-sk1', label: 'Algebra', short_label: 'Alg' }).save
    @teacher = Teacher.new({
      id: 'ref-t1', first_name: 'Existing', last_name: 'Teacher',
      skill: [{ id: 'ref-sk1' }]
    })
    @teacher.save(false)

    Course.new({ id: 'ref-c1', course_name: 'Algebra' }).save
  end

  def teardown
    Schedule.new({ id: 'ref-sch1' }).destroy rescue nil
    Teacher.new({ id: 'ref-t1' }).destroy rescue nil
    Skill.new({ id: 'ref-sk1' }).destroy rescue nil
    Course.new({ id: 'ref-c1' }).destroy rescue nil
  end

  def test_create_referencing_existing_entity_by_id_only_stub_does_not_revalidate_reference
    # New Schedule referencing the existing teacher by id only — mirrors the
    # verwantschap payload that only sends { "agent": { "id": "…" } }.
    schedule = Schedule.new({
      id: 'ref-sch1',
      teacher: { id: @teacher.id },
      course: { id: 'ref-c1' },
      start_date: Time.now,
      end_date: Time.now
    })

    # Must not raise InvalidAttributeError for the referenced teacher's
    # mandatory first_name/last_name/skill — that was the 0.122.0 500.
    schedule.save

    found = ScheduleResource.find(id: 'ref-sch1').data
    assert_equal 'ref-sch1', found.id

    # The referenced teacher is preserved exactly as it was — creating the
    # schedule reference must not drop or blank the teacher's mandatory data.
    teacher = TeacherResource.find(id: 'ref-t1').data
    assert_equal 'Existing', teacher.first_name
    assert_equal 'Teacher', teacher.last_name
  end

  def test_referenced_stub_is_emitted_as_uri_not_inlined
    schedule = Schedule.new({
      id: 'ref-sch1',
      teacher: { id: @teacher.id },
      course: { id: 'ref-c1' },
      start_date: Time.now,
      end_date: Time.now
    })

    # Serialize without deep resolution (the save path). The teacher must appear
    # as a URI reference, not re-serialized with its own type/attribute triples.
    graph = schedule.to_graph(false)
    teacher_uri = RDF::URI("http://solis.template/teachers/#{@teacher.id}")

    refs = graph.query([nil, RDF::URI('http://solis.template/teacher'), nil]).objects
    assert_includes refs, teacher_uri

    # No Teacher type/attribute triples for the referenced teacher in this graph.
    teacher_type_triples = graph.query([teacher_uri, RDF.type, nil]).to_a
    assert_empty teacher_type_triples, 'referenced teacher must not be inlined into the create graph'
  end

  # --- Polymorphic reference resolution (the real ODIS verwantschap->agent case) ---
  # Schedule#person is sh:class t:Person; the stored instance is a Teacher (a
  # Person subclass) at /teachers/. Mirrors verwantschap#agent -> Organisatie.

  def build_schedule_with_person(person_value)
    Schedule.new({
      id: 'ref-sch1',
      teacher: { id: @teacher.id },
      course: { id: 'ref-c1' },
      person: person_value,
      start_date: Time.now,
      end_date: Time.now
    })
  end

  def assert_person_resolved_to_teacher(schedule)
    schedule.save

    # The base-class stub must be re-typed to the concrete subclass...
    assert_equal 'Teacher', schedule.instance_variable_get('@person').class.name

    # ...and emitted with the subclass storage path, not /people/.
    graph = schedule.to_graph(false)
    person_refs = graph.query([nil, RDF::URI('http://solis.template/person'), nil]).objects.map(&:to_s)
    assert_includes person_refs, "http://solis.template/teachers/#{@teacher.id}"
    refute_includes person_refs, "http://solis.template/people/#{@teacher.id}"

    # Reference only: the Teacher is not re-created/rewritten and keeps its data.
    teacher = TeacherResource.find(id: 'ref-t1').data
    assert_equal 'Existing', teacher.first_name
  end

  def test_polymorphic_bare_id_resolves_to_subclass_via_store
    assert_person_resolved_to_teacher(build_schedule_with_person({ id: @teacher.id }))
  end

  def test_polymorphic_full_uri_resolves_to_subclass
    assert_person_resolved_to_teacher(
      build_schedule_with_person({ id: "http://solis.template/teachers/#{@teacher.id}" })
    )
  end

  def test_polymorphic_explicit_type_resolves_to_subclass
    assert_person_resolved_to_teacher(
      build_schedule_with_person({ id: @teacher.id, type: 'Teacher' })
    )
  end

  def test_polymorphic_reference_to_missing_entity_raises_not_found
    schedule = build_schedule_with_person({ id: 'does-not-exist-xyz' })
    assert_raises(Solis::Error::NotFoundError) { schedule.save }
  end

  def test_polymorphic_reference_resolves_on_update
    build_schedule_with_person({ id: @teacher.id }).save

    # PATCH the schedule with the polymorphic person reference as a bare id —
    # must resolve to the Teacher subclass instead of crashing on Person.naam.
    Schedule.new.update({
      'id' => 'ref-sch1',
      'person' => { 'id' => @teacher.id }
    }, true, true, nil, patch: true)

    teacher = TeacherResource.find(id: 'ref-t1').data
    assert_equal 'Existing', teacher.first_name
  end
end
