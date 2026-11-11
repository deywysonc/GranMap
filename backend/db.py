from pathlib import Path
import sqlite3
from contextlib import contextmanager
import os

from settings import get_settings


DB_PATH = Path(
    os.environ.get(
        "GRANMAP_DB_PATH",
        str(Path(__file__).with_name("granmap.db")),
    )
)
_POSTGRES_ENGINES = {}

SCHEMA = """
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS courses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS professors (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    email TEXT DEFAULT ''
);

CREATE TABLE IF NOT EXISTS rooms (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    poi_id TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    floor INTEGER NOT NULL DEFAULT 0,
    building TEXT NOT NULL DEFAULT 'Gran'
);

CREATE TABLE IF NOT EXISTS subjects (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    course_id INTEGER NOT NULL,
    name TEXT NOT NULL,
    UNIQUE(course_id, name),
    FOREIGN KEY(course_id) REFERENCES courses(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS academic_groups (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    course_id INTEGER NOT NULL,
    semester INTEGER NOT NULL,
    name TEXT NOT NULL,
    UNIQUE(course_id, semester, name),
    FOREIGN KEY(course_id) REFERENCES courses(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS schedules (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    course_id INTEGER NOT NULL,
    semester INTEGER NOT NULL,
    group_name TEXT NOT NULL,
    subject TEXT NOT NULL,
    professor_id INTEGER,
    room_id INTEGER NOT NULL,
    weekday TEXT NOT NULL,
    start_time TEXT NOT NULL,
    end_time TEXT NOT NULL,
    subject_id INTEGER,
    group_id INTEGER,
    FOREIGN KEY(course_id) REFERENCES courses(id),
    FOREIGN KEY(professor_id) REFERENCES professors(id),
    FOREIGN KEY(room_id) REFERENCES rooms(id),
    FOREIGN KEY(subject_id) REFERENCES subjects(id),
    FOREIGN KEY(group_id) REFERENCES academic_groups(id)
);

CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE COLLATE NOCASE,
    password_hash TEXT NOT NULL,
    password_salt TEXT NOT NULL,
    password_algorithm TEXT NOT NULL DEFAULT 'pbkdf2_sha256',
    course_name TEXT NOT NULL,
    semester INTEGER NOT NULL,
    group_name TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'student',
    reputation INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TEXT
);

CREATE TABLE IF NOT EXISTS sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    token_hash TEXT NOT NULL UNIQUE,
    expires_at TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen_at TEXT,
    revoked_at TEXT,
    FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS user_favorites (
    user_id INTEGER NOT NULL,
    poi_id TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY(user_id, poi_id),
    FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS navigation_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    poi_id TEXT NOT NULL,
    poi_name TEXT NOT NULL,
    visited_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS proposals (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    author_name TEXT NOT NULL,
    author_user_id INTEGER,
    subject TEXT NOT NULL,
    from_room TEXT NOT NULL,
    to_room TEXT NOT NULL,
    reason TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'unverified',
    official_priority INTEGER NOT NULL DEFAULT 0,
    reputation_awarded INTEGER NOT NULL DEFAULT 0,
    moderation_note TEXT NOT NULL DEFAULT '',
    resolved_by_user_id INTEGER,
    resolved_at TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    idempotency_key TEXT,
    FOREIGN KEY(author_user_id) REFERENCES users(id),
    FOREIGN KEY(resolved_by_user_id) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS votes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    proposal_id INTEGER NOT NULL,
    voter_name TEXT NOT NULL,
    voter_user_id INTEGER,
    agrees INTEGER NOT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(proposal_id) REFERENCES proposals(id) ON DELETE CASCADE,
    FOREIGN KEY(voter_user_id) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS audit_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    action TEXT NOT NULL,
    details TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS map_versions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    version TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    schema_version INTEGER NOT NULL DEFAULT 1,
    status TEXT NOT NULL DEFAULT 'draft',
    map_json TEXT NOT NULL,
    checksum TEXT NOT NULL,
    notes TEXT NOT NULL DEFAULT '',
    created_by_user_id INTEGER,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    published_at TEXT,
    FOREIGN KEY(created_by_user_id) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS route_closures (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    edge_id TEXT NOT NULL,
    floor INTEGER NOT NULL,
    reason TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    starts_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ends_at TEXT,
    created_by_user_id INTEGER NOT NULL,
    resolved_by_user_id INTEGER,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resolved_at TEXT,
    FOREIGN KEY(created_by_user_id) REFERENCES users(id),
    FOREIGN KEY(resolved_by_user_id) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS positioning_anchors (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    anchor_code TEXT NOT NULL UNIQUE,
    node_id TEXT NOT NULL,
    kind TEXT NOT NULL DEFAULT 'qr',
    x REAL NOT NULL,
    y REAL NOT NULL,
    z REAL NOT NULL,
    floor INTEGER NOT NULL,
    heading REAL NOT NULL DEFAULT 0,
    enabled INTEGER NOT NULL DEFAULT 1,
    metadata_json TEXT NOT NULL DEFAULT '{}',
    created_by_user_id INTEGER,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(created_by_user_id) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS magnetic_fingerprints (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    map_version_id INTEGER,
    x REAL NOT NULL,
    y REAL NOT NULL,
    z REAL NOT NULL,
    floor INTEGER NOT NULL,
    magnetic_x REAL NOT NULL,
    magnetic_y REAL NOT NULL,
    magnetic_z REAL NOT NULL,
    device_model TEXT NOT NULL DEFAULT '',
    quality REAL NOT NULL DEFAULT 0,
    captured_by_user_id INTEGER,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(map_version_id) REFERENCES map_versions(id),
    FOREIGN KEY(captured_by_user_id) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS auth_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER,
    email TEXT NOT NULL DEFAULT '',
    event TEXT NOT NULL,
    ip_hash TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(user_id) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS notifications (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    kind TEXT NOT NULL,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    data_json TEXT NOT NULL DEFAULT '{}',
    read_at TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS rate_limit_buckets (
    key TEXT PRIMARY KEY,
    window_start INTEGER NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS account_tokens (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    token_hash TEXT NOT NULL UNIQUE,
    purpose TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    used_at TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);
"""


@contextmanager
def connect():
    settings = get_settings()
    database_url = settings.database_url
    if database_url:
        from sqlalchemy import create_engine, text

        from postgres_compat import PostgresCompatConnection

        url = database_url.replace("postgresql://", "postgresql+psycopg://", 1)
        engine = _POSTGRES_ENGINES.get(url)
        if engine is None:
            engine = create_engine(
                url,
                pool_pre_ping=True,
                pool_size=settings.database_pool_size,
                max_overflow=settings.database_max_overflow,
                pool_timeout=settings.database_pool_timeout_seconds,
                pool_recycle=settings.database_pool_recycle_seconds,
            )
            _POSTGRES_ENGINES[url] = engine
        connection = engine.connect()
        compat = PostgresCompatConnection(connection, text)
        try:
            yield compat
        except Exception:
            compat.rollback()
            raise
        finally:
            compat.close()
        return

    connection = sqlite3.connect(DB_PATH)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys = ON")
    try:
        yield connection
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


def _columns(connection: sqlite3.Connection, table: str) -> set[str]:
    return {
        row["name"]
        for row in connection.execute(f"PRAGMA table_info({table})").fetchall()
    }


def _add_column_if_missing(
    connection: sqlite3.Connection,
    table: str,
    name: str,
    definition: str,
):
    if name not in _columns(connection, table):
        connection.execute(
            f"ALTER TABLE {table} ADD COLUMN {name} {definition}"
        )


def migrate_schema(connection: sqlite3.Connection):
    """Atualiza bancos antigos sem apagar os dados existentes."""
    _add_column_if_missing(
        connection, "users", "reputation", "INTEGER NOT NULL DEFAULT 0"
    )
    _add_column_if_missing(connection, "users", "deleted_at", "TEXT")
    _add_column_if_missing(
        connection,
        "users",
        "password_algorithm",
        "TEXT NOT NULL DEFAULT 'pbkdf2_sha256'",
    )
    _add_column_if_missing(connection, "sessions", "last_seen_at", "TEXT")
    _add_column_if_missing(connection, "sessions", "revoked_at", "TEXT")
    _add_column_if_missing(connection, "proposals", "author_user_id", "INTEGER")
    _add_column_if_missing(
        connection,
        "proposals",
        "official_priority",
        "INTEGER NOT NULL DEFAULT 0",
    )
    _add_column_if_missing(
        connection,
        "proposals",
        "reputation_awarded",
        "INTEGER NOT NULL DEFAULT 0",
    )
    _add_column_if_missing(
        connection,
        "proposals",
        "moderation_note",
        "TEXT NOT NULL DEFAULT ''",
    )
    _add_column_if_missing(
        connection, "proposals", "resolved_by_user_id", "INTEGER"
    )
    _add_column_if_missing(connection, "proposals", "resolved_at", "TEXT")
    _add_column_if_missing(connection, "proposals", "applied_at", "TEXT")
    _add_column_if_missing(connection, "proposals", "applied_schedule_id", "INTEGER")
    _add_column_if_missing(connection, "proposals", "idempotency_key", "TEXT")
    _add_column_if_missing(
        connection,
        "proposals",
        "updated_at",
        "TEXT",
    )
    _add_column_if_missing(connection, "votes", "voter_user_id", "INTEGER")
    _add_column_if_missing(
        connection, "votes", "intent_version", "INTEGER NOT NULL DEFAULT 0"
    )
    _add_column_if_missing(connection, "schedules", "subject_id", "INTEGER")
    _add_column_if_missing(connection, "schedules", "group_id", "INTEGER")
    connection.execute(
        "UPDATE proposals SET updated_at = created_at WHERE updated_at IS NULL"
    )

    connection.executescript(
        """
        CREATE INDEX IF NOT EXISTS idx_sessions_token_hash
        ON sessions(token_hash);

        CREATE INDEX IF NOT EXISTS idx_history_user_time
        ON navigation_history(user_id, visited_at DESC);

        CREATE INDEX IF NOT EXISTS idx_proposals_status_created
        ON proposals(status, created_at DESC);

        CREATE UNIQUE INDEX IF NOT EXISTS idx_proposals_author_idempotency
        ON proposals(author_user_id, idempotency_key)
        WHERE author_user_id IS NOT NULL AND idempotency_key IS NOT NULL;

        CREATE INDEX IF NOT EXISTS idx_votes_proposal
        ON votes(proposal_id);

        CREATE UNIQUE INDEX IF NOT EXISTS idx_votes_proposal_user
        ON votes(proposal_id, voter_user_id)
        WHERE voter_user_id IS NOT NULL;

        CREATE INDEX IF NOT EXISTS idx_schedules_room_time
        ON schedules(weekday, room_id, start_time, end_time);

        CREATE INDEX IF NOT EXISTS idx_schedules_professor_time
        ON schedules(weekday, professor_id, start_time, end_time);

        CREATE INDEX IF NOT EXISTS idx_sessions_user_active
        ON sessions(user_id, expires_at, revoked_at);

        CREATE INDEX IF NOT EXISTS idx_subjects_course
        ON subjects(course_id, name);

        CREATE INDEX IF NOT EXISTS idx_groups_course
        ON academic_groups(course_id, semester, name);

        CREATE INDEX IF NOT EXISTS idx_map_versions_status
        ON map_versions(status, published_at DESC);

        CREATE INDEX IF NOT EXISTS idx_route_closures_active
        ON route_closures(status, starts_at, ends_at);

        CREATE INDEX IF NOT EXISTS idx_anchors_floor
        ON positioning_anchors(floor, enabled);

        CREATE INDEX IF NOT EXISTS idx_fingerprints_floor
        ON magnetic_fingerprints(floor, map_version_id);

        CREATE INDEX IF NOT EXISTS idx_auth_events_email_time
        ON auth_events(email, created_at DESC);

        CREATE INDEX IF NOT EXISTS idx_notifications_user_time
        ON notifications(user_id, created_at DESC);

        CREATE INDEX IF NOT EXISTS idx_notifications_unread
        ON notifications(user_id, read_at, created_at DESC);

        CREATE TABLE IF NOT EXISTS rate_limit_buckets (
            key TEXT PRIMARY KEY,
            window_start INTEGER NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS account_tokens (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            token_hash TEXT NOT NULL UNIQUE,
            purpose TEXT NOT NULL,
            expires_at TEXT NOT NULL,
            used_at TEXT,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        );

        CREATE INDEX IF NOT EXISTS idx_account_tokens_lookup
        ON account_tokens(token_hash, purpose, expires_at, used_at);
        """
    )


def init_db():
    if get_settings().database_url:
        # Em produção o schema é aplicado antes dos workers por `alembic upgrade head`.
        with connect() as con:
            con.execute("SELECT 1")
        return
    with connect() as con:
        con.executescript(SCHEMA)
        migrate_schema(con)
        con.commit()
