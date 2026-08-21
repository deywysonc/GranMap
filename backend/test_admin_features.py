from pathlib import Path
import tempfile
import unittest

from fastapi import HTTPException

import auth_router
import db
import main


class AdminFeaturesTest(unittest.TestCase):
    def setUp(self):
        self._original_db_path = db.DB_PATH
        self._temporary = tempfile.TemporaryDirectory()
        db.DB_PATH = Path(self._temporary.name) / "test.db"
        db.init_db()

        with db.connect() as con:
            con.execute(
                "INSERT INTO courses(name) VALUES (?)",
                ("Engenharia da Computação",),
            )
            con.commit()

        result = auth_router.register(
            auth_router.RegisterIn(
                name="Admin Demo",
                email="admin@teste.local",
                password="segredo123",
                course_name="Engenharia da Computação",
                semester=4,
                group_name="EC4A",
            )
        )
        self.token = result["token"]
        with db.connect() as con:
            con.execute(
                "UPDATE users SET role = 'admin' WHERE email = ?",
                ("admin@teste.local",),
            )
            con.commit()

    def tearDown(self):
        db.DB_PATH = self._original_db_path
        self._temporary.cleanup()

    @property
    def authorization(self):
        return f"Bearer {self.token}"

    def test_subject_group_user_role_and_conflict_detection(self):
        course_id = main.list_courses()[0]["id"]
        professor = main.create_professor(
            main.ProfessorIn(name="Prof. Ada", email="ada@teste.local"),
            authorization=self.authorization,
        )
        room = main.create_room(
            main.RoomIn(
                poi_id="alan_turing",
                name="Alan Turing",
                floor=0,
                building="Gran Tietê",
            ),
            authorization=self.authorization,
        )
        subject = main.create_subject(
            main.SubjectIn(course_id=course_id, name="Estrutura de Dados"),
            authorization=self.authorization,
        )
        group = main.create_group(
            main.AcademicGroupIn(
                course_id=course_id,
                semester=4,
                name="EC4A",
            ),
            authorization=self.authorization,
        )

        first = main.create_schedule(
            main.ScheduleIn(
                course_id=course_id,
                semester=4,
                group_name="EC4A",
                subject="Estrutura de Dados",
                professor_id=professor["id"],
                room_id=room["id"],
                weekday="Segunda-feira",
                start_time="19:00",
                end_time="20:40",
                subject_id=subject["id"],
                group_id=group["id"],
            ),
            authorization=self.authorization,
        )
        self.assertGreater(first["id"], 0)

        with self.assertRaises(HTTPException) as raised:
            main.create_schedule(
                main.ScheduleIn(
                    course_id=course_id,
                    semester=4,
                    group_name="EC4A",
                    subject="Outra disciplina",
                    professor_id=professor["id"],
                    room_id=room["id"],
                    weekday="Segunda-feira",
                    start_time="20:00",
                    end_time="21:20",
                ),
                authorization=self.authorization,
            )
        self.assertEqual(raised.exception.status_code, 409)
        self.assertTrue(raised.exception.detail["conflicts"])

        users = main.list_users(authorization=self.authorization)
        updated = main.update_user_role(
            users[0]["id"],
            main.RoleUpdateIn(role="coordination"),
            authorization=self.authorization,
        )
        self.assertEqual(updated["role"], "coordination")


if __name__ == "__main__":
    unittest.main()
