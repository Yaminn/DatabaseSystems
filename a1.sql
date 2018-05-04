-- COMP3311 18s1 Assignment 1
-- Written by YAMINN AUNG (z5061216), April 2018

-- Q1: ...
create or replace view Q1(unswid, name)
as
SELECT People.unswid, People.name
FROM People, Course_Enrolments
WHERE People.id=Course_Enrolments.student
GROUP BY People.unswid, people.name
HAVING COUNT(Course_Enrolments.student) > 65;

-- Q2: ...

create or replace view Q2(nstudents, nstaff, nboth)
as
SELECT DISTINCT
	(SELECT COUNT(*) FROM Students WHERE NOT EXISTS(SELECT * FROM Staff WHERE Students.id=Staff.id)) nstudents,
	(SELECT COUNT(*) FROM Staff WHERE NOT EXISTS(SELECT * FROM Students WHERE Staff.id=Students.id )) nstaff,
	(SELECT COUNT(*) FROM People 
		WHERE EXISTS (SELECT * FROM Staff WHERE Staff.id=People.id) 
		AND EXISTS(SELECT * FROM Students WHERE Students.id=People.id)) nboth
FROM People;

-- Q3: ...
create or replace view Q3Helper as
select staff, count(role) as ncourses
from course_staff
join staff_roles roles on roles.id=course_staff.role
where roles.name='Course Convenor'
group by course_staff.staff;

create or replace view Q3(name, ncourses)
as
select name, ncourses
from people
join Q3Helper on people.id=Q3Helper.staff
where ncourses  = (select max(ncourses) from Q3Helper);

-- Q4: ...
create or replace view Q4a(id) as
select people.unswid as id
from program_enrolments enrolments
left join people on enrolments.student=people.id
left join programs on enrolments.program=programs.id
left join semesters on enrolments.semester=semesters.id 
where programs.name='Computer Science' and programs.code='3978' and semesters.year='2005' and semesters.term='S2';

create or replace view Q4b(id)
as
select people.unswid as id
from program_enrolments
left join people on program_enrolments.student=people.id
left join semesters on program_enrolments.semester=semesters.id
join stream_enrolments on program_enrolments.id=stream_enrolments.partof
join streams on stream_enrolments.stream=streams.id
where semesters.year='2005' and semesters.term='S2' and streams.code='SENGA1';

create or replace view Q4c(id)
as
select People.unswid as id
from Program_Enrolments
LEFT JOIN People on Program_Enrolments.Student=People.id
LEFT JOIN Semesters on Program_Enrolments.Semester=Semesters.id
LEFT JOIN Programs on Program_Enrolments.Program=Programs.id
LEFT JOIN Orgunits on Programs.Offeredby=Orgunits.id
WHERE Semesters.Year='2005' and Semesters.Term='S2' and Orgunits.Longname='School of Computer Science and Engineering';


-- Q5: ...
create or replace view Q5Helper
as
SELECT Orgunits.name as name, facultyOf(Orgunits.id) as facultyId
FROM Orgunits
INNER JOIN Orgunit_Types on Orgunits.utype=Orgunit_types.id
WHERE facultyOf(Orgunits.id) IS NOT NULL and Orgunit_Types.name='Committee'
GROUP BY Orgunits.name, Orgunits.id;

create or replace view Q5Helper2
as
SELECT Orgunits.name, COUNT(*) as count
FROM Orgunits
LEFT JOIN Q5Helper on facultyId=Orgunits.id
GROUP BY OrgUnits.name;

create or replace view Q5(name)
as
SELECT Q5Helper2.name
FROM Q5Helper2
WHERE count=(SELECT MAX(count) FROM Q5Helper2);

-- Q6: ...
create or replace function Q6(integer) returns text
as
$$
SELECT name
FROM People
WHERE People.unswid=$1 OR People.id=$1
$$ language sql;

-- Q7: ...
create or replace function Q7(text)
returns table (course text, year integer, term text, convenor text)
as $$
SELECT CAST(Subjects.code AS text) as course, Semesters.year as year, CAST(Semesters.term AS text) as term, People.name as convenor
FROM Course_Staff
LEFT JOIN Courses on Course_Staff.course=Courses.id
LEFT JOIN Subjects on Courses.subject=Subjects.id
LEFT JOIN People on Course_Staff.staff=People.id 
LEFT JOIN Semesters on Courses.semester=Semesters.id
LEFT JOIN Staff_Roles on Course_Staff.role=Staff_Roles.id
WHERE Staff_Roles.name='Course Convenor' AND Subjects.code=$1
$$ language sql
;

-- Q8: ...
create or replace function Q8(integer)
	returns setof NewTranscriptRecord
as $$
declare
	rec NewTranscriptRecord;
	UOCtotal integer := 0;
	UOCpassed integer := 0;
	wsum integer := 0;
	wam integer := 0;
	x integer;	
begin
	select s.id into x
	from Students s join People p on (s.id=p.id)
	where p.unswid=$1;
	if (not found) then
		raise EXCEPTION 'Invalid student %', _sid;
	end if;
	for rec in
		select distinct su.code,
			substr(t.year::text, 3,2)||lower(t.term) as term,
			prog.code as prog,
			substr(su.name,1,20),
			e.mark, e.grade, su.uoc
		from People p
			join Students s on (p.id=s.id)
			join Program_Enrolments pe on (p.id=pe.student)
			join Programs prog on (pe.program=prog.id)
			join Course_Enrolments e on (e.student=s.id)
			join Courses c on (c.id=e.course)
			join Subjects su on (c.subject=su.id)
			join Semesters t on (c.semester=t.id)
		where p.unswid=$1 and pe.semester=c.semester
		order by term
	loop
		if (rec.grade = 'SY') then
			UOCpassed := UOCpassed + rec.uoc;
		elseif (rec.mark is not null) then
			if (rec.grade in ('PT', 'PC', 'PS', 'CR', 'DN', 'HD', 'A', 'B', 'C')) then
				UOCpassed:= UOCpassed + rec.uoc;
			end if;

			UOCtotal := UOCtotal + rec.uoc;
	
			wsum := wsum + (rec.mark * rec.uoc);

			if(rec.grade not in ('PT', 'PC', 'PS', 'CR', 'DN', 'HD', 'A', 'B', 'C')) then
				rec.uoc := 0;
			end if;
		end if;
		return next rec;
	end loop;
	if (UOCtotal = 0) then
		rec := (null, null, null, 'No WAM available', null, null, null);
	else
		wam := wsum / UOCtotal;
		rec := (null, null, null, 'Overall WAM', wam, null, UOCpassed);
	end if;
	return next rec;
end;
$$ language plpgsql;


-- Q9: ...

create or replace function Q9(integer)
	returns setof AcObjRecord
as $$
declare
--	... PLpgSQL variable delcarations ...
	rec AcObjRecord;
	objtype text;
	objdef	text;
	course_code text;
	group_code text;
begin
	--gather the academic object's type and definition for later queries
	select gtype, definition
	into objtype, objdef 
	from acad_object_groups
	where id=$1 and gdefby='pattern' and negated='f';


	-- conditionally run through the object definitions
	if objdef~'\{|\}|\/' then
		return;
	end if;

	-- if there is FREE.{0,4} or [A-Z]GEN.{0,4} or GEN[A-Z].{0,4}
	for group_code in 
		select * from regexp_split_to_table(objdef, ',')
		loop	
			if group_code~'FREE' then
				rec := (objtype, group_code);
				return next rec;
			
			elseif group_code~'GEN' then
				rec := (objtype, group_code);
				return next rec;
			
			elseif objtype='program' then
				for course_code in 
					select distinct programs.code
					from programs
					where programs.code~(SELECT REPLACE(REPLACE (group_code, '#', '.'), 'x','.'))
				loop
					rec := (objtype, course_code);
					return next rec;
				end loop;

			elseif objtype='subject' then
				for course_code in
					select distinct subjects.code
					from subjects
					where subjects.code~(SELECT REPLACE(REPLACE(group_code, '#', '.'), 'x','.'))
				loop
					rec:=(objtype, course_code);
					return next rec;
				end loop;

			else --then it's a stream						
				for course_code in
					select distinct streams.code
					from streams
					where streams.code~(SELECT REPLACE(REPLACE(group_code, '#', '.'), 'x', '.'))
				loop
					rec := (objtype, course_code);
					return next rec;
				end loop;
			end if;
		end loop;		
end;
$$ language plpgsql
;

