from datetime import datetime, timezone
from pathlib import Path
import tempfile
import unittest

import db
from retention import apply_retention


class RetentionTest(unittest.TestCase):
    def setUp(self):
        self._original_db_path = db.DB_PATH
        self._temporary = tempfile.TemporaryDirectory()
        db.DB_PATH = Path(self._temporary.name) / "retention.db"
        db.init_db()
        with db.connect() as con:
            user_id = con.execute(
                """
                INSERT INTO users(
                    name, email, password_hash, password_salt,
                    course_name, semester, group_name
                ) VALUES ('Pessoa', 'retention@teste.local', 'hash', '', 'Curso', 1, 'A')
                """
            ).lastrowid
            con.execute(
                """
                INSERT INTO navigation_history(user_id, poi_id, poi_name, visited_at)
                VALUES (?, 'sala', 'Sala', '2020-01-01 00:00:00')
                """,
                (user_id,),
            )
            con.execute(
                """
                INSERT INTO notifications(user_id, kind, title, body, read_at, created_at)
                VALUES (?, 'test', 'Teste', 'Teste', '2020-01-01 00:00:00', '2020-01-01 00:00:00')
                """,
                (user_id,),
            )
            con.execute(
                """
                INSERT INTO auth_events(user_id, email, event, created_at)
                VALUES (?, 'retention@teste.local', 'login', '2020-01-01 00:00:00')
                """,
                (user_id,),
            )
            con.execute(
                """
                INSERT INTO magnetic_fingerprints(
                    x, y, z, floor, magnetic_x, magnetic_y, magnetic_z,
                    captured_by_user_id, created_at
                ) VALUES (0, 0, 0, 0, 1, 1, 1, ?, '2020-01-01 00:00:00')
                """,
                (user_id,),
            )
            con.commit()

    def tearDown(self):
        db.DB_PATH = self._original_db_path
        self._temporary.cleanup()

    def test_removes_expired_personal_data_and_anonymizes_fingerprint(self):
        result = apply_retention(datetime(2026, 8, 22, tzinfo=timezone.utc))

        self.assertEqual(result["navigation_history_deleted"], 1)
        self.assertEqual(result["read_notifications_deleted"], 1)
        self.assertEqual(result["auth_events_deleted"], 1)
        self.assertEqual(result["fingerprint_identities_anonymized"], 1)
        with db.connect() as con:
            fingerprint = con.execute(
                "SELECT captured_by_user_id FROM magnetic_fingerprints"
            ).fetchone()
        self.assertIsNone(fingerprint["captured_by_user_id"])


if __name__ == "__main__":
    unittest.main()
