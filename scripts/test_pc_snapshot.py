from contextlib import closing
import hashlib
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch

from pc_snapshot import snapshot


class SnapshotTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.source = Path(self.temporary.name) / "source.db"
        self.target = Path(self.temporary.name) / "backup.db"
        with closing(sqlite3.connect(self.source)) as connection:
            for table in ("users", "courses", "map_versions", "audit_log"):
                connection.execute(f'CREATE TABLE "{table}"(id INTEGER PRIMARY KEY, value TEXT)')
                connection.execute(f'INSERT INTO "{table}" VALUES (1, ?)', ("fixture",))
            connection.commit()

    def test_preserves_source_and_all_records(self):
        before = hashlib.sha256(self.source.read_bytes()).hexdigest()
        result = snapshot(self.source, self.target)
        self.assertEqual(result["status"], "verified")
        self.assertEqual(hashlib.sha256(self.source.read_bytes()).hexdigest(), before)
        with closing(sqlite3.connect(self.target)) as backup:
            self.assertEqual(backup.execute("PRAGMA integrity_check").fetchone()[0], "ok")
            self.assertEqual(backup.execute("SELECT COUNT(*) FROM users").fetchone()[0], 1)

    def test_never_overwrites_existing_backup(self):
        snapshot(self.source, self.target)
        before = self.target.read_bytes()
        with self.assertRaises(FileExistsError):
            snapshot(self.source, self.target)
        self.assertEqual(self.target.read_bytes(), before)

    def test_rejects_non_granmap_source_without_final_file(self):
        invalid = Path(self.temporary.name) / "invalid.db"
        with closing(sqlite3.connect(invalid)):
            pass
        with self.assertRaises(ValueError):
            snapshot(invalid, self.target)
        self.assertFalse(self.target.exists())

    def test_failed_publication_never_leaves_final_backup(self):
        with patch("pc_snapshot.os.rename", side_effect=OSError("locked")):
            with self.assertRaises(OSError):
                snapshot(self.source, self.target)
        self.assertFalse(self.target.exists())
        self.assertEqual(len(list(self.target.parent.glob("*.partial"))), 1)


if __name__ == "__main__":
    unittest.main()
