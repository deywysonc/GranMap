"""Make a consistent read-only snapshot; never reset or edit the source DB."""
import argparse
import json
import os
from pathlib import Path
import sqlite3
import uuid


def snapshot(source: Path, target: Path) -> dict:
    source, target = source.resolve(), target.resolve()
    if source == target or not source.is_file():
        raise ValueError("Origem ausente ou destino igual à origem.")
    if target.exists():
        raise FileExistsError("Backup existente preservado; escolha um destino novo.")
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(f"{target.name}.{uuid.uuid4().hex}.partial")
    original = sqlite3.connect(source.as_uri() + "?mode=ro", uri=True)
    try:
        original.execute("BEGIN")
        tables = {row[0] for row in original.execute(
            "SELECT name FROM sqlite_master WHERE type='table'"
        )}
        if not {"users", "courses", "map_versions", "audit_log"}.issubset(tables):
            raise ValueError("A origem não é um banco operacional do GranMap.")
        backup = sqlite3.connect(temporary)
        try:
            original.backup(backup)
            result = backup.execute("PRAGMA integrity_check").fetchone()[0]
            if result != "ok":
                raise RuntimeError("O backup não passou na verificação de integridade.")
            for table in ("users", "courses", "map_versions", "audit_log"):
                if original.execute(f'SELECT COUNT(*) FROM "{table}"').fetchone()[0] != backup.execute(f'SELECT COUNT(*) FROM "{table}"').fetchone()[0]:
                    raise RuntimeError("Contagem de registros incompatível no backup.")
        finally:
            backup.close()
        # Windows rename does not overwrite an existing destination.
        if target.exists():
            raise FileExistsError("O destino passou a existir e foi preservado.")
        os.rename(temporary, target)
    finally:
        original.close()
    return {"status": "verified", "bytes": target.stat().st_size}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("target", type=Path)
    arguments = parser.parse_args()
    print(json.dumps(snapshot(arguments.source, arguments.target)))
