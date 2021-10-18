--
-- SOLIS template - 0.1 - 2021-10-18 10:52:14 +0200
-- description: Template for the SOLIS gem
-- author: Mehmet Celik
--


CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
DROP SCHEMA IF EXISTS t CASCADE;
CREATE SCHEMA t;


CREATE TABLE t.code_tables(
	id SERIAL NOT NULL PRIMARY KEY, 
	short_label text, 
	label text NOT NULL
);
COMMENT ON TABLE t.code_tables 'Abstract code table entity';
COMMENT ON COLUMN t.code_tables.id IS 'unique record identifier';
COMMENT ON COLUMN t.code_tables.short_label IS 'lookup key, short label';
COMMENT ON COLUMN t.code_tables.label IS 'prefered display label';

CREATE TABLE t.courses(
	id SERIAL NOT NULL PRIMARY KEY, 
	name text NOT NULL
);
COMMENT ON TABLE t.courses 'Name of a course';
COMMENT ON COLUMN t.courses.id IS 'unique record identifier';
COMMENT ON COLUMN t.courses.name IS 'name of a course';

CREATE TABLE t.people(
	id SERIAL NOT NULL PRIMARY KEY, 
	first_name text NOT NULL, 
	last_name text NOT NULL
);
COMMENT ON TABLE t.people 'Abstract entity';
COMMENT ON COLUMN t.people.id IS 'unique record identifier';
COMMENT ON COLUMN t.people.first_name IS 'Persons first name';
COMMENT ON COLUMN t.people.last_name IS 'Persons last name';

CREATE TABLE t.schedules(
	id SERIAL NOT NULL PRIMARY KEY, 
	teacher_id int NOT NULL REFERENCES t.teachers(id), 
	students_id int REFERENCES t.students(id), 
	course_id int NOT NULL REFERENCES t.courses(id), 
	start_date date NOT NULL, 
	end_date date NOT NULL
);
COMMENT ON TABLE t.schedules 'Teachers course schedule';
COMMENT ON COLUMN t.schedules.id IS 'unique record identifier';
COMMENT ON COLUMN t.schedules.teacher_id IS 'schedule belongs to';
COMMENT ON COLUMN t.schedules.students_id IS 'list of enrolled students';
COMMENT ON COLUMN t.schedules.course_id IS 'course within schedule';

CREATE TABLE t.students(
	age integer NOT NULL
);
COMMENT ON TABLE t.students 'A student taking a course';
COMMENT ON COLUMN t.students.age IS 'Age of student';

CREATE TABLE t.teachers(
	skill_id int NOT NULL REFERENCES t.skills(id)
);
COMMENT ON TABLE t.teachers 'Name of a teacher';
COMMENT ON COLUMN t.teachers.skill_id IS 'field teacher is skilled in';

CREATE TABLE t.skills(
	id SERIAL NOT NULL PRIMARY KEY
);
COMMENT ON TABLE t.skills 'List of skills';
COMMENT ON COLUMN t.skills.id IS 'systeem UUID';
