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
        self.token = registered["token"]
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

    def test_account_sessions_password_export_and_deletion(self):
        headers = {"Authorization": f"Bearer {self.token}"}
        sessions = self.client.get("/auth/sessions", headers=headers)
        self.assertEqual(sessions.status_code, 200)
        self.assertTrue(any(item["current"] for item in sessions.json()))

        exported = self.client.get("/auth/export", headers=headers)
        self.assertEqual(exported.status_code, 200)
        self.assertEqual(
            exported.json()["profile"]["email"],
            "secure-admin@teste.local",
        )

        changed = self.client.post(
            "/auth/change-password",
            headers=headers,
            json={
                "current_password": "uma-senha-segura",
                "new_password": "uma-nova-senha-segura",
            },
        )
        self.assertEqual(changed.status_code, 200)
        self.assertEqual(
            self.client.post(
                "/auth/login",
                json={
                    "email": "secure-admin@teste.local",
                    "password": "uma-senha-segura",
                },
            ).status_code,
            401,
        )

        deleted = self.client.request(
            "DELETE",
            "/auth/me",
            headers=headers,
            json={"password": "uma-nova-senha-segura"},
        )
        self.assertEqual(deleted.status_code, 204)
        self.assertEqual(self.client.get("/auth/me", headers=headers).status_code, 401)
        with db.connect() as con:
            row = con.execute(
                "SELECT name, email, deleted_at FROM users WHERE id = ?",
                (1,),
            ).fetchone()
        self.assertEqual(row["name"], "Conta excluída")
        self.assertTrue(row["email"].endswith("@invalid.local"))
        self.assertIsNotNone(row["deleted_at"])

    def test_password_reset_token_is_single_use_and_revokes_sessions(self):
        requested = self.client.post(
            "/auth/password-reset/request",
            json={"email": "secure-admin@teste.local"},
        )
        self.assertEqual(requested.status_code, 200)
        token = requested.json()["development_token"]

        changed = self.client.post(
            "/auth/password-reset/confirm",
            json={"token": token, "new_password": "senha-recuperada-segura"},
        )
        self.assertEqual(changed.status_code, 200)
        self.assertEqual(
            self.client.get(
                "/auth/me",
                headers={"Authorization": f"Bearer {self.token}"},
            ).status_code,
            401,
        )
        reused = self.client.post(
            "/auth/password-reset/confirm",
            json={"token": token, "new_password": "outra-senha-segura"},
        )
        self.assertEqual(reused.status_code, 400)
        logged_in = self.client.post(
            "/auth/login",
            json={
                "email": "secure-admin@teste.local",
                "password": "senha-recuperada-segura",
            },
        )
        self.assertEqual(logged_in.status_code, 200)


if __name__ == "__main__":
    unittest.main()
