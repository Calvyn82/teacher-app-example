require 'cuba'
require 'mote'
require 'mote/render'
require 'basica'
require 'nomadize/config'
require 'sql_capsule'

db = SQLCapsule.wrap(Nomadize::Config.db)
db.register(:add_student, "INSERT INTO students (name, hour, student_id) VALUES ($1, $2, $3) RETURNING student_id;", :name, :hour, :student_id)
db.register(:find_student, "SELECT * FROM students WHERE student_id = $1;", :student_id)
db.register(:find_all_students, "SELECT * FROM students;")
db.register(:update_student_grade, "UPDATE students SET grade = $1 WHERE student_id = $2 RETURNING student_id;", :grade, :student_id)
db.register(:delete_student, "DELETE FROM students WHERE student_id = $1;", :student_id)

Cuba.plugin(Mote::Render)
Cuba.plugin(Basica)
Cuba.settings[:mote][:views] = "./views/"

# name string, hour string, student_id string, grade string

Cuba.define do

  def auth(env, res)
    if env.include?("HTTP_AUTHORIZATION")
      result = basic_auth(env) do |user, pass|
        user == ENV.fetch("USER") && pass == ENV.fetch("PASS")
      end

      if result
        yield
      else
        res.write("Access Denied")
      end
    else
      res.headers["WWW-Authenticate"] = 'Basic realm="User Visible Realm"'
      res.status = 401
    end
  end

  on post do

    on "lookup-student", param("student-id") do |id|
      student = db.run(:find_student, student_id: id.to_i).first
      if student
        res.write(view("lookup-student", grade: student["grade"]))
      else
        res.redirect("/")
      end
    end

    on 'admin/add-student', param('name'), param('hour'), param('student-id') do |name, hour, student_id|
      db.run(:add_student, name: name, hour: hour, student_id: student_id)
      res.redirect("/admin/add-student")
    end

    on 'admin/enter-grades' do
      student_grades = req.params["student"]
      student_grades.each do |student_id, grade|
        db.run(:update_student_grade, student_id: student_id, grade: grade)
      end

      res.redirect("/admin/enter-grades")
    end

  end

  on 'admin' do

    on 'add-student' do
      auth(env, res) do
        res.write(view("add-student"))
      end
    end

    on 'enter-grades' do
      auth(env, res) do
        students = db.run(:find_all_students)
        res.write(view("enter-grades", students: students))
      end
    end

    on 'delete-students/:id' do |id|
      auth(env, res) do
        db.run(:delete_student, student_id: id)
        res.redirect("/admin/delete-students")
      end
    end


    on 'delete-students' do
      auth(env, res) do
        students = db.run(:find_all_students)
        res.write(view("delete-students", students: students))
      end
    end

    on default do
      auth(env, res) do
        res.write(view("admin"))
      end
    end
  end

  on default do
    res.write(view("index"))
  end

end
