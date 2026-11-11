"""Import a standalone SQLite backup into an empty, migrated PC database.

Run before the API workers: python pc_bootstrap.py --source /bootstrap/source.db
Credentials come exclusively from GRANMAP_PC_ADMIN_PASSWORD and environment
configuration. This module never initializes or migrates the SQLite source.
"""

from __future__ import annotations

import argparse
from contextlib import contextmanager
from datetime import date, datetime, time, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import sqlite3
from typing import Iterator
import warnings

from sqlalchemy import (
    Boolean,
    Date,
    DateTime,
    Integer,
    JSON,
    MetaData,
    Time,
    create_engine,
    delete,
    func,
    insert,
    inspect,
    select,
    text,
)
from sqlalchemy.engine import Connection, Engine
from sqlalchemy.exc import SAWarning
from sqlalchemy.pool import NullPool

from security import PASSWORD_ALGORITHM, hash_password


# Identifiers always come from this allowlist or reflected target columns.
# SQLite internal tables, Alembic, extensions and arbitrary backup tables are
# never selected for import.
APP_TABLES = (
    "courses",
    "professors",
    "rooms",
    "subjects",
    "academic_groups",
    "schedules",
    "users",
    "sessions",
    "user_favorites",
    "navigation_history",
    "proposals",
    "votes",
    "audit_log",
    "map_versions",
    "route_closures",
    "positioning_anchors",
    "magnetic_fingerprints",
    "auth_events",
    "notifications",
    "rate_limit_buckets",
    "account_tokens",
)
EPHEMERAL_TABLES = frozenset({"sessions", "account_tokens", "rate_limit_buckets"})
DEMO_PRIVILEGED_ROLES = frozenset({"admin", "moderator", "coordination", "professor"})
_SOURCE_REQUIRED_COLUMNS = {
    "courses": frozenset({"id", "name"}),
    "users": frozenset({"id", "email", "password_hash", "password_salt", "role"}),
    "audit_log": frozenset({"id", "action", "details"}),
}
MARKER_ACTION = "pc_bootstrap_completed_v1"
_ADVISORY_LOCK = 2026101401
_BATCH_SIZE = 250


class BootstrapError(Exception):
    """A safe, value-free failure code suitable for CLI output."""

    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


def validate_owner(email: str, password: str) -> str:
    email = email.strip().casefold()
    if (
        not 5 <= len(email) <= 160
        or not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", email)
        or email.endswith("@granmap.demo")
    ):
        raise BootstrapError("invalid_owner_email")
    if not isinstance(password, str) or not 20 <= len(password) <= 128:
        raise BootstrapError("strong_owner_password_required")
    classes = sum(
        (
            any(character.islower() for character in password),
            any(character.isupper() for character in password),
            any(character.isdigit() for character in password),
            any(not character.isalnum() for character in password),
        )
    )
    # Long random hex/base64 tokens also qualify without artificial symbols.
    if (
        any(character.isspace() for character in password)
        or len(set(password)) < 10
        or (classes < 3 and len(password) < 40)
    ):
        raise BootstrapError("strong_owner_password_required")
    return email


@contextmanager
def _read_only_source(path: Path) -> Iterator[sqlite3.Connection]:
    path = path.resolve(strict=True)
    if not path.is_file():
        raise BootstrapError("source_not_a_file")
    for suffix in ("-wal", "-journal"):
        sidecar = Path(f"{path}{suffix}")
        if sidecar.exists() and sidecar.stat().st_size:
            raise BootstrapError("standalone_sqlite_backup_required")
    # The input is a checkpointed backup, never the running application DB.
    # immutable prevents SQLite from creating journals or shared-memory files.
    source = sqlite3.connect(
        f"{path.as_uri()}?mode=ro&immutable=1", uri=True, timeout=5
    )
    source.row_factory = sqlite3.Row
    try:
        source.execute("PRAGMA query_only = ON")
        source.execute("PRAGMA trusted_schema = OFF")
        source.execute("BEGIN")
        if source.execute("PRAGMA quick_check").fetchone()[0] != "ok":
            raise BootstrapError("invalid_sqlite_backup")
        _validate_source_schema(source)
        yield source
    finally:
        source.close()


def _validate_source_schema(source: sqlite3.Connection) -> set[str]:
    tables = {
        row[0] for row in source.execute("SELECT name FROM sqlite_master WHERE type = 'table'")
    }
    if not _SOURCE_REQUIRED_COLUMNS.keys() <= tables:
        raise BootstrapError("granmap_source_schema_required")
    for table, required_columns in _SOURCE_REQUIRED_COLUMNS.items():
        columns = {row[1] for row in source.execute(f'PRAGMA table_info("{table}")')}
        if not required_columns <= columns:
            raise BootstrapError("granmap_source_schema_required")
    return tables


def _fingerprint(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source_file:
        for chunk in iter(lambda: source_file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _target_tables(connection: Connection) -> dict:
    schema = "public" if connection.dialect.name == "postgresql" else None
    available = set(inspect(connection).get_table_names(schema=schema))
    names = [name for name in APP_TABLES if name in available]
    if not {"users", "audit_log"}.issubset(names):
        raise BootstrapError("migrated_target_schema_required")
    metadata = MetaData(schema=schema)
    with warnings.catch_warnings():
        # PostGIS geometry is deliberately omitted: SQLite carries map JSON
        # and numeric coordinates, not a PostgreSQL geometry representation.
        warnings.filterwarnings(
            "ignore", message="Did not recognize type 'geometry'.*", category=SAWarning
        )
        metadata.reflect(bind=connection, only=names)
    return {
        table.name: table
        for table in metadata.sorted_tables
        if table.name in APP_TABLES
    }


def _lock_destination(connection: Connection, tables: dict) -> None:
    if connection.dialect.name != "postgresql":
        return
    connection.execute(text("SELECT set_config('lock_timeout', '5s', true)"))
    connection.execute(text("SELECT set_config('statement_timeout', '120s', true)"))
    locked = connection.scalar(
        text("SELECT pg_try_advisory_xact_lock(:lock_id)"),
        {"lock_id": _ADVISORY_LOCK},
    )
    if not locked:
        raise BootstrapError("bootstrap_busy")
    quote = connection.dialect.identifier_preparer.quote
    names = ", ".join(f"public.{quote(name)}" for name in sorted(tables))
    connection.exec_driver_sql(f"LOCK TABLE {names} IN ACCESS EXCLUSIVE MODE")


def _marker(connection: Connection, audit_table, source_digest: str | None) -> dict | None:
    details = connection.execute(
        select(audit_table.c.details).where(audit_table.c.action == MARKER_ACTION)
    ).scalars().all()
    if not details:
        return None
    if len(details) != 1:
        raise BootstrapError("invalid_bootstrap_marker")
    try:
        marker = json.loads(details[0])
        counts = marker["imported_counts"]
        if (
            marker["version"] != 1
            or not isinstance(counts, dict)
            or any(name not in APP_TABLES for name in counts)
            or any(type(count) is not int or count < 0 for count in counts.values())
            or not isinstance(marker["source_sha256"], str)
            or re.fullmatch(r"[0-9a-f]{64}", marker["source_sha256"]) is None
        ):
            raise ValueError
    except (KeyError, TypeError, ValueError):
        raise BootstrapError("invalid_bootstrap_marker") from None
    result = {"status": "already_initialized", "imported_counts": counts}
    if source_digest is not None and marker["source_sha256"] != source_digest:
        result["warning"] = "different_source_ignored"
    return result


def _assert_empty(connection: Connection, tables: dict) -> None:
    for table in tables.values():
        if connection.execute(select(table).limit(1)).first() is not None:
            raise BootstrapError("destination_not_empty")


def _reject_json_constant(_: str):
    raise ValueError("invalid_json_constant")


def _convert_value(column, value):
    if value is None:
        return None
    if isinstance(column.type, JSON):
        if isinstance(value, (str, bytes, bytearray)):
            value = json.loads(value, parse_constant=_reject_json_constant)
        json.dumps(value, allow_nan=False)
        return value
    if isinstance(column.type, DateTime):
        if isinstance(value, str):
            if not value.strip() and column.nullable:
                return None
            value = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
        if not isinstance(value, datetime):
            raise ValueError("invalid_timestamp")
        if column.type.timezone and value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        return value
    if isinstance(column.type, Time):
        if isinstance(value, str):
            value = time.fromisoformat(value.strip())
        if not isinstance(value, time):
            raise ValueError("invalid_time")
        return value
    if isinstance(column.type, Date):
        return date.fromisoformat(value) if isinstance(value, str) else value
    if isinstance(column.type, Boolean):
        if value not in (0, 1, False, True):
            raise ValueError("invalid_boolean")
        return bool(value)
    return value


def _rotate_demo_user(row: dict) -> bool:
    privileged_demo = (
        str(row.get("email", "")).strip().casefold().endswith("@granmap.demo")
        and str(row.get("role", "")).casefold() in DEMO_PRIVILEGED_ROLES
    )
    if privileged_demo:
        row["password_hash"] = hash_password(secrets.token_urlsafe(48))
        row["password_salt"] = ""
        row["password_algorithm"] = PASSWORD_ALGORITHM
    return privileged_demo


def _copy_rows(source: sqlite3.Connection, connection: Connection, table) -> tuple[int, int]:
    # table.name is reflected AND restricted to APP_TABLES; backup-provided
    # identifiers are never interpolated into a statement.
    if table.name not in APP_TABLES:
        raise BootstrapError("table_not_allowed")
    cursor = source.execute(f'SELECT * FROM "{table.name}"')
    columns = {
        column.name: column
        for column in table.columns
        if column.computed is None and column.name != "geom"
    }
    copied = rotated = 0
    while raw_rows := cursor.fetchmany(_BATCH_SIZE):
        batch = []
        for raw in raw_rows:
            row = {
                name: _convert_value(columns[name], raw[name])
                for name in raw.keys()
                if name in columns
            }
            if table.name == "audit_log" and row.get("action") == MARKER_ACTION:
                raise BootstrapError("source_contains_reserved_marker")
            if table.name == "users":
                rotated += int(_rotate_demo_user(row))
            batch.append(row)
        connection.execute(insert(table), batch)
        copied += len(batch)
    return copied, rotated


def _next_id(connection: Connection, table) -> int:
    return int(connection.scalar(select(func.max(table.c.id))) or 0) + 1


def _provision_owner(connection: Connection, tables: dict, email: str, password: str) -> None:
    users = tables["users"]
    if connection.scalar(
        select(users.c.id).where(func.lower(users.c.email) == email)
    ) is not None:
        raise BootstrapError("owner_email_conflicts_with_imported_user")
    course_name = "Administração local"
    if "courses" in tables:
        course_name = connection.scalar(
            select(tables["courses"].c.name).order_by(tables["courses"].c.id).limit(1)
        ) or course_name
    connection.execute(
        insert(users),
        {
            "id": _next_id(connection, users),
            "name": "Administrador local",
            "email": email,
            "password_hash": hash_password(password),
            "password_salt": "",
            "password_algorithm": PASSWORD_ALGORITHM,
            "course_name": course_name,
            "semester": 1,
            "group_name": "ADMIN",
            "role": "admin",
            "reputation": 0,
        },
    )


def _reset_sequences(connection: Connection, tables: dict) -> None:
    if connection.dialect.name != "postgresql":
        return
    quote = connection.dialect.identifier_preparer.quote
    for table in tables.values():
        for column in table.primary_key.columns:
            if not isinstance(column.type, Integer):
                continue
            sequence = connection.execute(
                text(
                    "SELECT n.nspname, c.relname FROM pg_class c "
                    "JOIN pg_namespace n ON n.oid = c.relnamespace "
                    "WHERE c.oid = pg_get_serial_sequence(:relation, :column)::regclass"
                ),
                {"relation": f'public."{table.name}"', "column": column.name},
            ).first()
            if sequence is None:
                continue
            maximum = connection.scalar(select(func.max(column)))
            next_value = max(1, int(maximum or 0) + 1)
            sequence_name = f"{quote(sequence[0])}.{quote(sequence[1])}"
            # Unlike setval(), RESTART participates in this transaction.
            connection.exec_driver_sql(
                f"ALTER SEQUENCE {sequence_name} RESTART WITH {next_value}"
            )


def _import_transaction(
    source: sqlite3.Connection,
    connection: Connection,
    *,
    source_digest: str,
    owner_email: str,
    owner_password: str,
    _locked_tables: dict | None = None,
) -> dict:
    """Portable import core; callers must own a transaction on connection."""
    tables = _locked_tables if _locked_tables is not None else _target_tables(connection)
    if _locked_tables is None:
        _lock_destination(connection, tables)
    existing = _marker(connection, tables["audit_log"], source_digest)
    if existing is not None:
        return existing
    _assert_empty(connection, tables)
    source_tables = _validate_source_schema(source)
    counts = {}
    rotated = 0
    for name, table in tables.items():
        if name in EPHEMERAL_TABLES or name not in source_tables:
            counts[name] = 0
            continue
        counts[name], table_rotated = _copy_rows(source, connection, table)
        rotated += table_rotated
    # Never transfer a dev browser session, reset token or rate-limit bucket.
    for name in EPHEMERAL_TABLES.intersection(tables):
        connection.execute(delete(tables[name]))
    _provision_owner(connection, tables, owner_email, owner_password)
    marker = {
        "version": 1,
        "source_sha256": source_digest,
        "imported_counts": counts,
    }
    audit = tables["audit_log"]
    connection.execute(
        insert(audit),
        {
            "id": _next_id(connection, audit),
            "action": MARKER_ACTION,
            "details": json.dumps(marker, sort_keys=True),
        },
    )
    _reset_sequences(connection, tables)
    return {
        "status": "ready",
        "imported_counts": counts,
        "rotated_privileged_users": rotated,
    }


def _bootstrap_destination(
    connection: Connection,
    source_path: Path,
    *,
    owner_email: str,
    owner_password: str,
) -> dict:
    tables = _target_tables(connection)
    _lock_destination(connection, tables)
    existing = _marker(connection, tables["audit_log"], None)
    if existing is not None:
        # A restored PostgreSQL volume is authoritative. The one-time import
        # file must never be a dependency of an already initialized API.
        try:
            digest = _fingerprint(source_path)
        except OSError:
            existing["warning"] = "source_backup_unavailable"
            return existing
        return _marker(connection, tables["audit_log"], digest)
    _assert_empty(connection, tables)
    if not source_path.is_file():
        raise BootstrapError("source_backup_required")
    with _read_only_source(source_path) as source:
        return _import_transaction(
            source,
            connection,
            source_digest=_fingerprint(source_path),
            owner_email=owner_email,
            owner_password=owner_password,
            _locked_tables=tables,
        )


def bootstrap(
    source_path: str | Path,
    engine: Engine,
    *,
    owner_email: str = "admin@granmap.local",
    owner_password: str,
) -> dict:
    owner_email = validate_owner(owner_email, owner_password)
    if engine.dialect.name != "postgresql":
        raise BootstrapError("postgresql_target_required")
    source_path = Path(source_path).resolve()
    with engine.begin() as connection:
        return _bootstrap_destination(
            connection,
            source_path,
            owner_email=owner_email,
            owner_password=owner_password,
        )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument(
        "--owner-email",
        default=os.environ.get("GRANMAP_PC_ADMIN_EMAIL", "admin@granmap.local"),
    )
    arguments = parser.parse_args(argv)
    engine = None
    try:
        password = os.environ.get("GRANMAP_PC_ADMIN_PASSWORD", "")
        validate_owner(arguments.owner_email, password)
        database_url = os.environ.get("GRANMAP_DATABASE_URL", "")
        if not database_url.startswith(("postgresql://", "postgresql+psycopg://")):
            raise BootstrapError("postgresql_target_required")
        engine = create_engine(
            database_url.replace("postgresql://", "postgresql+psycopg://", 1),
            poolclass=NullPool,
            hide_parameters=True,
            connect_args={"connect_timeout": 10},
        )
        result = bootstrap(
            arguments.source,
            engine,
            owner_email=arguments.owner_email,
            owner_password=password,
        )
        print(json.dumps(result, sort_keys=True))
        return 0
    except BootstrapError as error:
        print(json.dumps({"status": "error", "code": error.code}))
        return 1
    except Exception:
        # Driver/SQL exceptions can include bound values and connection URLs.
        print(json.dumps({"status": "error", "code": "bootstrap_failed"}))
        return 1
    finally:
        if engine is not None:
            engine.dispose()


if __name__ == "__main__":
    raise SystemExit(main())
