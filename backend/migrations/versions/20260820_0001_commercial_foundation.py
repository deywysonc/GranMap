"""Base comercial PostgreSQL/PostGIS do GranMap."""

from pathlib import Path

from alembic import op


revision = "20260820_0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    schema_path = Path(__file__).resolve().parents[2] / "postgres_schema.sql"
    sql = schema_path.read_text(encoding="utf-8")
    connection = op.get_bind()
    for statement in sql.split(";"):
        statement = statement.strip()
        if statement:
            connection.exec_driver_sql(statement)


def downgrade() -> None:
    raise RuntimeError(
        "O downgrade inicial é deliberadamente bloqueado para evitar perda total de dados."
    )
