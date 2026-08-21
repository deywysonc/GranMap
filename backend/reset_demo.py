"""Restaura somente o banco isolado da demonstração."""

from pathlib import Path

from db import DB_PATH


expected_parent = Path(__file__).resolve().parent
resolved = DB_PATH.resolve()

if resolved.parent != expected_parent or resolved.name != "granmap_demo.db":
    raise SystemExit(
        "Reset recusado: o alvo precisa ser backend/granmap_demo.db."
    )

if resolved.exists():
    resolved.unlink()

from seed_demo import seed_demo  # noqa: E402


seed_demo()
