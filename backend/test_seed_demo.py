from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest

import db
import seed_demo
from security import verify_password


class DemoSeedTest(unittest.TestCase):
    def setUp(self):
        self._original_db_path = db.DB_PATH
        self._original_seed_db_path = seed_demo.DB_PATH
        self._original_get_settings = seed_demo.get_settings
        self._temporary = tempfile.TemporaryDirectory()
        demo_path = Path(self._temporary.name) / "granmap_demo.db"
        db.DB_PATH = demo_path
        seed_demo.DB_PATH = demo_path
        seed_demo.get_settings = lambda: SimpleNamespace(database_url=None)

    def tearDown(self):
        seed_demo.get_settings = self._original_get_settings
        seed_demo.DB_PATH = self._original_seed_db_path
        db.DB_PATH = self._original_db_path
        self._temporary.cleanup()

    def test_seed_is_idempotent_and_demo_login_uses_argon2id(self):
        seed_demo.seed_demo()
        with db.connect() as con:
            user = con.execute(
                """
                SELECT password_hash, password_algorithm, password_salt
                FROM users WHERE email = ?
                """,
                ("admin@granmap.demo",),
            ).fetchone()
            history_before = con.execute(
                "SELECT COUNT(*) FROM navigation_history"
            ).fetchone()[0]

        verification = verify_password(
            seed_demo.DEMO_PASSWORD,
            user["password_hash"],
            user["password_algorithm"],
            user["password_salt"],
        )
        self.assertTrue(verification.valid)
        self.assertEqual(user["password_algorithm"], "argon2id")

        seed_demo.seed_demo()
        with db.connect() as con:
            history_after = con.execute(
                "SELECT COUNT(*) FROM navigation_history"
            ).fetchone()[0]
        self.assertEqual(history_after, history_before)


if __name__ == "__main__":
    unittest.main()
