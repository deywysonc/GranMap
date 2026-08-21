from pathlib import Path
import tempfile
import unittest

import auth_router
import db
import main
import notification_router


class NotificationFlowTest(unittest.TestCase):
    def setUp(self):
        self._original_db_path = db.DB_PATH
        self._temporary = tempfile.TemporaryDirectory()
        db.DB_PATH = Path(self._temporary.name) / "notifications.db"
        db.init_db()
        with db.connect() as con:
            course_id = con.execute(
                "INSERT INTO courses(name) VALUES (?)", ("Computação",)
            ).lastrowid
            room_id = con.execute(
                "INSERT INTO rooms(poi_id, name) VALUES (?, ?)",
                ("alan_turing", "Alan Turing"),
            ).lastrowid
            con.commit()
        result = auth_router.register(
            auth_router.RegisterIn(
                name="Aluno Operação",
                email="aluno@teste.local",
                password="senha-muito-segura",
                course_name="Computação",
                semester=2,
                group_name="CMP2A",
            )
        )
        self.user_token = result["token"]
        with db.connect() as con:
            con.execute("UPDATE users SET role = 'admin' WHERE id = ?", (result["user"]["id"],))
            con.commit()
        self.authorization = f"Bearer {self.user_token}"
        self.course_id = course_id
        self.room_id = room_id

    def tearDown(self):
        db.DB_PATH = self._original_db_path
        self._temporary.cleanup()

    def test_schedule_change_creates_and_reads_notification(self):
        main.create_schedule(
            main.ScheduleIn(
                course_id=self.course_id,
                semester=2,
                group_name="CMP2A",
                subject="Algoritmos",
                room_id=self.room_id,
                weekday="Segunda-feira",
                start_time="19:00",
                end_time="20:40",
            ),
            authorization=self.authorization,
        )
        items = notification_router.list_notifications(
            unread_only=True, authorization=self.authorization
        )
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0]["kind"], "schedule.created")
        notification_router.mark_notification_read(
            items[0]["id"], authorization=self.authorization
        )
        self.assertEqual(
            notification_router.list_notifications(
                unread_only=True, authorization=self.authorization
            ),
            [],
        )


if __name__ == "__main__":
    unittest.main()
