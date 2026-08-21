from pathlib import Path
import tempfile
import unittest

from fastapi.testclient import TestClient

import auth_router
import db
import main


class SecurityFlowTest(unittest.TestCase):
    def setUp(self):
        self._original_db_path = db.DB_PATH
        self._temporary = tempfile.TemporaryDirectory()
        db.DB_PATH = Path(self._temporary.name) / "security.db"
        db.init_db()
        with db.connect() as con:
            con.execute(
                "INSERT INTO courses(name) VALUES (?)",
                ("Engenharia da Computação",),
            )
            con.commit()

        registered = auth_router.register(
            auth_router.RegisterIn(
                name="Admin Seguro",
                email="secure-admin@teste.local",
                password="uma-senha-segura",
                course_name="Engenharia da Computação",
                semester=4,
                group_name="EC4A",
            )
        )
        with db.connect() as con:
            con.execute(
                "UPDATE users SET role = 'admin' WHERE id = ?",
                (registered["user"]["id"],),
            )
            con.commit()

        self.client = TestClient(main.app)

    def tearDown(self):
        self.client.close()
        db.DB_PATH = self._original_db_path
        self._temporary.cleanup()

    def test_web_session_uses_httponly_cookie_and_csrf(self):
        login = self.client.post(
            "/auth/web-login",
            json={
                "email": "secure-admin@teste.local",
                "password": "uma-senha-segura",
            },
        )
        self.assertEqual(login.status_code, 200)
        self.assertNotIn("token", login.json())
        self.assertIn("granmap_session", self.client.cookies)
        self.assertIn("HttpOnly", login.headers.get("set-cookie", ""))

        current = self.client.get("/auth/me")
        self.assertEqual(current.status_code, 200)
        self.assertEqual(current.json()["role"], "admin")

        denied = self.client.post("/courses", json={"name": "Agronomia"})
        self.assertEqual(denied.status_code, 403)

        csrf = self.client.cookies.get("granmap_csrf")
        created = self.client.post(
            "/courses",
            json={"name": "Agronomia"},
            headers={"X-CSRF-Token": csrf},
        )
        self.assertEqual(created.status_code, 200)

    def test_new_passwords_use_argon2id(self):
        with db.connect() as con:
            row = con.execute(
                "SELECT password_algorithm, password_hash FROM users WHERE email = ?",
                ("secure-admin@teste.local",),
            ).fetchone()
        self.assertEqual(row["password_algorithm"], "argon2id")
        self.assertTrue(row["password_hash"].startswith("$argon2id$"))


if __name__ == "__main__":
    unittest.main()
