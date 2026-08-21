from collections.abc import Iterator, Mapping, Sequence
from datetime import date, datetime, time
import re
from typing import Any


_INSERT_WITH_ID = {
    "courses",
    "professors",
    "rooms",
    "subjects",
    "academic_groups",
    "schedules",
    "users",
    "sessions",
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
}


class CompatRow(Mapping[str, Any]):
    def __init__(self, mapping: Mapping[str, Any]):
        self._data = {
            key: _portable_value(value) for key, value in dict(mapping).items()
        }
        self._values = tuple(self._data.values())

    def __getitem__(self, key):
        if isinstance(key, int):
            return self._values[key]
        return self._data[key]

    def __iter__(self) -> Iterator[str]:
        return iter(self._data)

    def __len__(self) -> int:
        return len(self._data)


class CompatResult:
    def __init__(self, result, lastrowid=None):
        self._result = result
        self.lastrowid = lastrowid
        self.rowcount = result.rowcount

    def fetchone(self):
        row = self._result.fetchone()
        return None if row is None else CompatRow(row._mapping)

    def fetchall(self):
        return [CompatRow(row._mapping) for row in self._result.fetchall()]


def _prepare(query: str, params: Sequence[Any]):
    query = query.replace("COLLATE NOCASE", "")
    ignored = bool(re.search(r"INSERT\s+OR\s+IGNORE", query, re.IGNORECASE))
    query = re.sub(
        r"INSERT\s+OR\s+IGNORE\s+INTO",
        "INSERT INTO",
        query,
        flags=re.IGNORECASE,
    )
    pieces = query.split("?")
    if len(pieces) - 1 != len(params):
        raise ValueError("Quantidade de parâmetros incompatível com a consulta.")
    converted = pieces[0]
    values: dict[str, Any] = {}
    for index, value in enumerate(params):
        key = f"p{index}"
        converted += f":{key}{pieces[index + 1]}"
        values[key] = _database_value(value)

    if ignored and "ON CONFLICT" not in converted.upper():
        converted = converted.rstrip().rstrip(";") + " ON CONFLICT DO NOTHING"

    match = re.search(r"INSERT\s+INTO\s+([a-z_]+)", converted, re.IGNORECASE)
    returns_id = bool(
        match
        and match.group(1).lower() in _INSERT_WITH_ID
        and "RETURNING" not in converted.upper()
    )
    if returns_id:
        converted = converted.rstrip().rstrip(";") + " RETURNING id"
    return converted, values, returns_id


def _database_value(value: Any):
    if not isinstance(value, str):
        return value
    if re.fullmatch(r"\d{2}:\d{2}(:\d{2})?", value):
        return time.fromisoformat(value)
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}T.*", value):
        try:
            return datetime.fromisoformat(value)
        except ValueError:
            return value
    return value


def _portable_value(value: Any):
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, time):
        return value.isoformat(timespec="minutes")
    if isinstance(value, date):
        return value.isoformat()
    return value


class PostgresCompatConnection:
    """Adapta o contrato SQLite existente a uma conexão SQLAlchemy/PostgreSQL.

    Mantém a demo sem reescrever cada endpoint de uma vez, enquanto Alembic e
    PostgreSQL passam a ser o caminho de produção. Novos módulos devem preferir
    consultas nomeadas ou repositórios dedicados.
    """

    def __init__(self, connection, text):
        self._connection = connection
        self._text = text

    def execute(self, query: str, params: Sequence[Any] = ()):
        converted, values, returns_id = _prepare(query, tuple(params))
        if any(column in query for column in ("map_json", "metadata_json", "data_json")):
            from json import loads
            from psycopg.types.json import Jsonb

            for key, value in list(values.items()):
                if isinstance(value, str) and value.lstrip().startswith(("{", "[")):
                    values[key] = Jsonb(loads(value))
        result = self._connection.execute(self._text(converted), values)
        lastrowid = result.scalar_one_or_none() if returns_id else None
        return CompatResult(result, lastrowid=lastrowid)

    def executemany(self, query: str, params):
        rows = list(params)
        if not rows:
            return CompatResult(self._connection.execute(self._text("SELECT 1 WHERE false")))
        converted, _, returns_id = _prepare(query, tuple(rows[0]))
        if returns_id:
            converted = re.sub(r"\s+RETURNING\s+id\s*$", "", converted, flags=re.I)
        values = []
        for row in rows:
            _, item, _ = _prepare(query, tuple(row))
            values.append(item)
        result = self._connection.execute(self._text(converted), values)
        return CompatResult(result)

    def commit(self):
        self._connection.commit()

    def rollback(self):
        self._connection.rollback()

    def close(self):
        self._connection.close()
