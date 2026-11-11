from contextlib import closing, redirect_stdout
from datetime import datetime, time, timezone
import io
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch

from sqlalchemy import Column, DateTime, JSON, Time, create_engine, event, text

import db
import pc_bootstrap
from security import PASSWORD_ALGORITHM, hash_password, verify_password


OWNER_PASSWORD = "PC-Owner-Password!2026-Strong"
DEMO_PASSWORD = "copied-demo-fixture-password"


class PcBootstrapTest(unittest.TestCase):
    """Portable transaction tests; the launcher still requires PostgreSQL."""

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        directory = Path(self.temporary.name)
        self.source_path = directory / "source ' quoted.db"
        self.target_path = directory / "target.db"
        self._create_database(self.source_path, target=False)
        self._create_database(self.target_path, target=True)
        self.engine = create_engine(f"sqlite:///{self.target_path}")
        self.addCleanup(self.engine.dispose)

        @event.listens_for(self.engine, "connect")
        def foreign_keys(connection, _):
            connection.execute("PRAGMA foreign_keys = ON")

        self._seed_source()

    def _create_database(self, path, *, target):
        schema = db.SCHEMA
        if target:
            for field in ("map_json", "metadata_json", "data_json"):
                schema = schema.replace(f"{field} TEXT", f"{field} JSON")
            for field in ("start_time", "end_time"):
                schema = schema.replace(f"{field} TEXT", f"{field} TIME")
            schema = schema.replace("_at TEXT", "_at DATETIME")
        with closing(sqlite3.connect(path)) as connection, connection:
            connection.row_factory = sqlite3.Row
            connection.executescript(schema)
            db.migrate_schema(connection)
            if target:
                connection.execute(
                    "ALTER TABLE users ADD COLUMN target_only TEXT "
                    "NOT NULL DEFAULT 'target_default'"
                )
                connection.execute("ALTER TABLE rooms ADD COLUMN geom TEXT")
                connection.execute(
                    "ALTER TABLE courses ADD COLUMN generated_length INTEGER "
                    "GENERATED ALWAYS AS (length(name)) VIRTUAL"
                )
            else:
                connection.execute("ALTER TABLE users ADD COLUMN source_only TEXT")
                connection.execute("ALTER TABLE rooms ADD COLUMN geom TEXT")
            connection.commit()

    def _seed_source(self):
        original_hash = hash_password(DEMO_PASSWORD)
        self.original_hash = original_hash
        users = (
            (3, "Demo Admin", "admin@granmap.demo", "admin"),
            (7, "Demo Professor", "professor@granmap.demo", "professor"),
            (11, "Demo Moderator", "moderator@granmap.demo", "moderator"),
            (13, "Demo Coordination", "coordination@granmap.demo", "coordination"),
            (17, "Demo Student", "student@granmap.demo", "student"),
            (19, "Existing Real Admin", "existing-admin@example.test", "admin"),
        )
        with closing(sqlite3.connect(self.source_path)) as connection, connection:
            connection.execute("PRAGMA foreign_keys = ON")
            connection.execute("INSERT INTO courses(id,name) VALUES (2, 'Engenharia')")
            connection.execute(
                "INSERT INTO professors(id,name,email) VALUES (4, 'Professor', 'p@example.test')"
            )
            connection.execute(
                "INSERT INTO rooms(id,poi_id,name,geom) VALUES (10, 'entrada', 'Entrada', 'ignored')"
            )
            connection.execute(
                "INSERT INTO subjects(id,course_id,name) VALUES (6,2,'Programação')"
            )
            connection.execute(
                "INSERT INTO academic_groups(id,course_id,semester,name) VALUES (8,2,4,'EC4A')"
            )
            connection.execute(
                "INSERT INTO schedules(id,course_id,semester,group_name,subject,"
                "professor_id,room_id,weekday,start_time,end_time,subject_id,group_id) "
                "VALUES (5,2,4,'EC4A','Programação',4,10,'Segunda-feira','19:00','20:40',6,8)"
            )
            connection.executemany(
                "INSERT INTO users(id,name,email,role,password_hash,password_salt,"
                "password_algorithm,course_name,semester,group_name,source_only) "
                "VALUES (?,?,?,?,?,'',?,'Engenharia',4,'EC4A','ignored')",
                [(*user, original_hash, PASSWORD_ALGORITHM) for user in users],
            )
            connection.execute(
                "INSERT INTO user_favorites(user_id,poi_id) VALUES (17,'entrada')"
            )
            connection.execute(
                "INSERT INTO navigation_history(id,user_id,poi_id,poi_name,visited_at) "
                "VALUES (2,17,'entrada','Entrada','2026-10-14T12:30:00Z')"
            )
            connection.execute(
                "INSERT INTO proposals(id,author_name,author_user_id,subject,from_room,"
                "to_room,reason,resolved_by_user_id,applied_schedule_id) "
                "VALUES (20,'Demo Student',17,'Programação','Entrada','Sala A',"
                "'Mudança confirmada',3,5)"
            )
            connection.execute(
                "INSERT INTO votes(id,proposal_id,voter_name,voter_user_id,agrees,intent_version) "
                "VALUES (21,20,'Demo Student',17,1,42)"
            )
            connection.execute(
                "INSERT INTO map_versions(id,version,name,map_json,checksum,created_by_user_id) "
                "VALUES (30,'map-test','Mapa de teste',?,'checksum',3)",
                (json.dumps({"building": {"id": "gran"}, "nodes": [{"id": "n1"}]}),),
            )
            connection.execute(
                "INSERT INTO route_closures(id,edge_id,floor,reason,created_by_user_id) "
                "VALUES (31,'e1',0,'Manutenção',3)"
            )
            connection.execute(
                "INSERT INTO positioning_anchors(id,anchor_code,node_id,x,y,z,floor,"
                "metadata_json,created_by_user_id) "
                "VALUES (32,'qr1','n1',1,2,3,0,?,3)",
                (json.dumps({"verified": True, "nested": {"source": "test"}}),),
            )
            connection.execute(
                "INSERT INTO magnetic_fingerprints(id,map_version_id,x,y,z,floor,"
                "magnetic_x,magnetic_y,magnetic_z,captured_by_user_id) "
                "VALUES (33,30,1,2,3,0,0.1,0.2,0.3,17)"
            )
            connection.execute(
                "INSERT INTO notifications(id,user_id,kind,title,body,data_json) "
                "VALUES (34,17,'changed','Aviso','Sua aula mudou',?)",
                (json.dumps({"schedule_id": 5}),),
            )
            connection.execute(
                "INSERT INTO audit_log(id,action,details) VALUES (40,'fixture',?)",
                ("value'); DROP TABLE users; --",),
            )
            connection.execute(
                "INSERT INTO auth_events(id,user_id,event) VALUES (41,17,'fixture')"
            )
            connection.execute(
                "INSERT INTO sessions(id,user_id,token_hash,expires_at) "
                "VALUES (50,17,'copied_session_fixture','2030-01-01T00:00:00Z')"
            )
            connection.execute(
                "INSERT INTO account_tokens(id,user_id,token_hash,purpose,expires_at) "
                "VALUES (51,3,'copied_reset_fixture','password_reset','2030-01-01T00:00:00Z')"
            )
            connection.execute(
                "INSERT INTO rate_limit_buckets(key,window_start,attempts) VALUES ('fixture',1,7)"
            )
            connection.commit()

    def _run(self, *, digest=None, password=OWNER_PASSWORD, email="admin@granmap.local"):
        email = pc_bootstrap.validate_owner(email, password)
        with pc_bootstrap._read_only_source(self.source_path) as source:
            with self.engine.begin() as connection:
                return pc_bootstrap._import_transaction(
                    source,
                    connection,
                    source_digest=digest or pc_bootstrap._fingerprint(self.source_path),
                    owner_email=email,
                    owner_password=password,
                )

    def test_import_preserves_records_ids_json_times_and_source(self):
        before = self.source_path.read_bytes()
        result = self._run()
        self.assertEqual(result["status"], "ready")
        self.assertEqual(result["rotated_privileged_users"], 4)
        self.assertEqual(result["imported_counts"]["users"], 6)
        self.assertEqual(before, self.source_path.read_bytes())
        self.assertFalse(Path(f"{self.source_path}-wal").exists())
        self.assertFalse(Path(f"{self.source_path}-shm").exists())
        with self.engine.connect() as connection:
            tables = pc_bootstrap._target_tables(connection)
            for name in (
                "courses", "professors", "rooms", "subjects", "academic_groups",
                "schedules", "proposals", "votes", "map_versions", "route_closures",
                "positioning_anchors", "magnetic_fingerprints", "notifications",
                "auth_events", "navigation_history", "user_favorites",
            ):
                self.assertEqual(result["imported_counts"][name], 1, name)
            schedule = connection.execute(tables["schedules"].select()).mappings().one()
            self.assertEqual(schedule["id"], 5)
            self.assertEqual(schedule["start_time"], time(19))
            self.assertEqual(schedule["end_time"], time(20, 40))
            self.assertEqual(schedule["subject_id"], 6)
            self.assertEqual(schedule["group_id"], 8)
            map_row = connection.execute(tables["map_versions"].select()).mappings().one()
            self.assertEqual(map_row["id"], 30)
            self.assertEqual(map_row["map_json"]["nodes"], [{"id": "n1"}])
            anchor = connection.execute(tables["positioning_anchors"].select()).mappings().one()
            self.assertTrue(anchor["metadata_json"]["verified"])
            notification = connection.execute(tables["notifications"].select()).mappings().one()
            self.assertEqual(notification["data_json"], {"schedule_id": 5})
            self.assertIsInstance(notification["created_at"], datetime)
            self.assertEqual(connection.scalar(text("SELECT intent_version FROM votes")), 42)
            self.assertEqual(connection.scalar(text("SELECT geom FROM rooms")), None)
            self.assertEqual(connection.scalar(text("SELECT generated_length FROM courses")), 10)
            self.assertEqual(connection.scalar(text("SELECT target_only FROM users LIMIT 1")), "target_default")
            self.assertEqual(connection.scalar(text("SELECT details FROM audit_log WHERE id=40")), "value'); DROP TABLE users; --")

    def test_only_demo_privileged_passwords_rotate_and_owner_is_new(self):
        self._run()
        with self.engine.connect() as connection:
            rows = connection.execute(text("SELECT * FROM users ORDER BY id")).mappings().all()
            self.assertEqual(len(rows), 7)
            for row in rows[:4]:
                self.assertNotEqual(row["password_hash"], self.original_hash)
                self.assertFalse(verify_password(DEMO_PASSWORD, row["password_hash"], row["password_algorithm"]).valid)
            for row in rows[4:6]:
                self.assertEqual(row["password_hash"], self.original_hash)
            owner = rows[-1]
            self.assertEqual(owner["id"], 20)
            self.assertEqual(owner["role"], "admin")
            self.assertEqual(owner["password_algorithm"], PASSWORD_ALGORITHM)
            self.assertTrue(verify_password(OWNER_PASSWORD, owner["password_hash"], owner["password_algorithm"]).valid)
            for table in pc_bootstrap.EPHEMERAL_TABLES:
                self.assertEqual(connection.scalar(text(f"SELECT COUNT(*) FROM {table}")), 0)
        with pc_bootstrap._read_only_source(self.source_path) as source:
            self.assertEqual(source.execute("SELECT password_hash FROM users WHERE id=3").fetchone()[0], self.original_hash)
            self.assertEqual(source.execute("SELECT COUNT(*) FROM sessions").fetchone()[0], 1)
            self.assertEqual(source.execute("SELECT COUNT(*) FROM account_tokens").fetchone()[0], 1)

    def test_repeat_and_changed_source_do_not_overwrite_or_reset_owner(self):
        first = self._run()
        with self.engine.begin() as connection:
            connection.execute(text("UPDATE courses SET name='Edited after bootstrap'"))
            owner_hash = connection.scalar(text("SELECT password_hash FROM users WHERE id=20"))
        second = self._run(password="New-Owner-Password!2027-Strong")
        self.assertEqual(second["status"], "already_initialized")
        self.assertEqual(second["imported_counts"], first["imported_counts"])
        different = self._run(digest="f" * 64)
        self.assertEqual(different["warning"], "different_source_ignored")
        with self.engine.connect() as connection:
            self.assertEqual(connection.scalar(text("SELECT name FROM courses")), "Edited after bootstrap")
            self.assertEqual(connection.scalar(text("SELECT password_hash FROM users WHERE id=20")), owner_hash)
            self.assertEqual(connection.scalar(text("SELECT COUNT(*) FROM users")), 7)
            self.assertEqual(connection.scalar(text("SELECT COUNT(*) FROM audit_log")), 2)

    def test_any_populated_app_table_rejects_import(self):
        with self.engine.begin() as connection:
            connection.execute(text("INSERT INTO courses(id,name) VALUES (90,'Existing')"))
        with self.assertRaisesRegex(pc_bootstrap.BootstrapError, "destination_not_empty"):
            self._run()
        with self.engine.connect() as connection:
            self.assertEqual(connection.scalar(text("SELECT COUNT(*) FROM users")), 0)
            self.assertEqual(connection.scalar(text("SELECT name FROM courses")), "Existing")

    def _bootstrap_path(self, path):
        with self.engine.begin() as connection:
            return pc_bootstrap._bootstrap_destination(
                connection,
                path,
                owner_email="admin@granmap.local",
                owner_password=OWNER_PASSWORD,
            )

    def test_empty_sqlite_file_is_rejected_without_initializing_target(self):
        empty_source = self.source_path.parent / "empty-backup.db"
        empty_source.touch()
        with self.assertRaisesRegex(pc_bootstrap.BootstrapError, "granmap_source_schema_required"):
            self._bootstrap_path(empty_source)
        with self.engine.connect() as connection:
            self.assertEqual(connection.scalar(text("SELECT COUNT(*) FROM users")), 0)
            self.assertEqual(connection.scalar(text("SELECT COUNT(*) FROM audit_log")), 0)
        self.assertEqual(empty_source.stat().st_size, 0)

    def test_partial_source_schema_is_rejected(self):
        partial_source = self.source_path.parent / "partial-backup.db"
        with closing(sqlite3.connect(partial_source)) as source, source:
            for table in ("users", "courses", "audit_log"):
                source.execute(f"CREATE TABLE {table}(id INTEGER)")
        with self.assertRaisesRegex(pc_bootstrap.BootstrapError, "granmap_source_schema_required"):
            self._bootstrap_path(partial_source)

    def test_valid_marker_allows_restored_destination_without_source_backup(self):
        first = self._run()
        missing_source = self.source_path.parent / "backup-not-restored.db"
        with patch.object(pc_bootstrap, "_read_only_source", side_effect=AssertionError("must not open source")):
            result = self._bootstrap_path(missing_source)
        self.assertEqual(result["status"], "already_initialized")
        self.assertEqual(result["imported_counts"], first["imported_counts"])
        self.assertEqual(result["warning"], "source_backup_unavailable")
        with self.engine.connect() as connection:
            self.assertEqual(connection.scalar(text("SELECT COUNT(*) FROM users")), 7)
            self.assertEqual(connection.scalar(text("SELECT COUNT(*) FROM audit_log")), 2)

    def test_destination_without_marker_still_requires_source_backup(self):
        with self.assertRaisesRegex(pc_bootstrap.BootstrapError, "source_backup_required"):
            self._bootstrap_path(self.source_path.parent / "missing.db")
        with self.engine.connect() as connection:
            self.assertEqual(connection.scalar(text("SELECT COUNT(*) FROM users")), 0)

    def test_invalid_marker_does_not_bypass_missing_source(self):
        with self.engine.begin() as connection:
            connection.execute(
                text("INSERT INTO audit_log(action,details) VALUES (:action,'{}')"),
                {"action": pc_bootstrap.MARKER_ACTION},
            )
        with self.assertRaisesRegex(pc_bootstrap.BootstrapError, "invalid_bootstrap_marker"):
            self._bootstrap_path(self.source_path.parent / "missing.db")

    def test_invalid_json_rolls_back_all_inserted_rows(self):
        before = self.source_path.read_bytes()
        with closing(sqlite3.connect(self.source_path)) as source, source:
            source.execute("UPDATE map_versions SET map_json='invalid JSON fixture'")
        bad_source = self.source_path.read_bytes()
        with self.assertRaises(ValueError):
            self._run()
        self.assertEqual(bad_source, self.source_path.read_bytes())
        self.assertNotEqual(before, bad_source)
        with self.engine.connect() as connection:
            for table in ("courses", "users", "schedules", "audit_log"):
                self.assertEqual(connection.scalar(text(f"SELECT COUNT(*) FROM {table}")), 0)

    def test_owner_collision_rolls_back_import_without_promoting_user(self):
        with self.assertRaisesRegex(pc_bootstrap.BootstrapError, "owner_email_conflicts"):
            self._run(email="existing-admin@example.test")
        with self.engine.connect() as connection:
            self.assertEqual(connection.scalar(text("SELECT COUNT(*) FROM users")), 0)

    def test_unlisted_table_and_values_cannot_inject_sql(self):
        with closing(sqlite3.connect(self.source_path)) as source, source:
            source.execute('CREATE TABLE "users; DROP TABLE courses;--" (id INTEGER)')
            source.execute('INSERT INTO "users; DROP TABLE courses;--" VALUES (1)')
        self._run()
        with self.engine.connect() as connection:
            self.assertEqual(connection.scalar(text("SELECT COUNT(*) FROM courses")), 1)
            self.assertEqual(connection.scalar(text("SELECT COUNT(*) FROM users")), 7)
            self.assertNotIn("users; DROP TABLE courses;--", pc_bootstrap._target_tables(connection))

    def test_reserved_source_marker_is_rejected_and_rolled_back(self):
        with closing(sqlite3.connect(self.source_path)) as source, source:
            source.execute("INSERT INTO audit_log(action,details) VALUES (?,?)", (pc_bootstrap.MARKER_ACTION, "{}"))
        with self.assertRaisesRegex(pc_bootstrap.BootstrapError, "source_contains_reserved_marker"):
            self._run()
        with self.engine.connect() as connection:
            self.assertEqual(connection.scalar(text("SELECT COUNT(*) FROM courses")), 0)

    def test_source_connection_rejects_writes(self):
        before = self.source_path.read_bytes()
        with pc_bootstrap._read_only_source(self.source_path) as source:
            with self.assertRaises(sqlite3.OperationalError):
                source.execute("DELETE FROM users")
        self.assertEqual(before, self.source_path.read_bytes())

    def test_unsafe_source_with_pending_wal_is_rejected(self):
        sidecar = Path(f"{self.source_path}-wal")
        sidecar.write_bytes(b"not-a-checkpointed-backup")
        with self.assertRaisesRegex(pc_bootstrap.BootstrapError, "standalone_sqlite_backup"):
            with pc_bootstrap._read_only_source(self.source_path):
                self.fail("source unexpectedly accepted")

    def test_public_bootstrap_rejects_non_postgres_engine(self):
        with self.assertRaisesRegex(pc_bootstrap.BootstrapError, "postgresql_target_required"):
            pc_bootstrap.bootstrap(self.source_path, self.engine, owner_password=OWNER_PASSWORD)


class BootstrapValidationTest(unittest.TestCase):
    def test_password_policy_accepts_random_hex_and_rejects_weak_values(self):
        strong_hex = "a71b05c6d3e2f984" * 4
        self.assertEqual(pc_bootstrap.validate_owner(" ADMIN@GranMap.Local ", strong_hex), "admin@granmap.local")
        for password in ("", "short", "A" * 64, "abcdefghijklmnopqrst", "Ab1!" * 6, "Password with spaces 2026!"):
            with self.subTest(length=len(password)):
                with self.assertRaises(pc_bootstrap.BootstrapError):
                    pc_bootstrap.validate_owner("admin@granmap.local", password)

    def test_invalid_and_demo_owner_email_are_rejected(self):
        for email in ("invalid", "admin@granmap.demo", "user @example.test"):
            with self.assertRaises(pc_bootstrap.BootstrapError):
                pc_bootstrap.validate_owner(email, OWNER_PASSWORD)

    def test_json_time_and_timezone_conversion(self):
        timestamp = pc_bootstrap._convert_value(Column("at", DateTime(timezone=True)), "2026-10-14 12:30:00")
        self.assertEqual(timestamp.tzinfo, timezone.utc)
        self.assertEqual(pc_bootstrap._convert_value(Column("clock", Time()), "19:15:30"), time(19, 15, 30))
        self.assertEqual(pc_bootstrap._convert_value(Column("map", JSON()), '{"node": [1, 2]}'), {"node": [1, 2]})
        with self.assertRaises(ValueError):
            pc_bootstrap._convert_value(Column("map", JSON()), '{"value": NaN}')

    def test_cli_does_not_print_driver_secrets_or_email(self):
        output = io.StringIO()
        with patch.dict("os.environ", {
            "GRANMAP_PC_ADMIN_PASSWORD": OWNER_PASSWORD,
            "GRANMAP_DATABASE_URL": "postgresql://owner:driver-secret-fixture@localhost/test",
        }, clear=True), patch.object(pc_bootstrap, "create_engine", side_effect=ValueError("driver-secret-fixture")), redirect_stdout(output):
            code = pc_bootstrap.main(["--source", "unused.db", "--owner-email", "owner@example.test"])
        self.assertEqual(code, 1)
        self.assertEqual(json.loads(output.getvalue()), {"status": "error", "code": "bootstrap_failed"})
        self.assertNotIn(OWNER_PASSWORD, output.getvalue())
        self.assertNotIn("driver-secret-fixture", output.getvalue())
        self.assertNotIn("owner@example.test", output.getvalue())


if __name__ == "__main__":
    unittest.main()
