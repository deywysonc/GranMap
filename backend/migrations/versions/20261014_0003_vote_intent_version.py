"""Preserve newest offline vote when requests arrive out of order."""

from alembic import op

revision = "20261014_0003"
down_revision = "20260822_0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        "ALTER TABLE votes ADD COLUMN IF NOT EXISTS "
        "intent_version BIGINT NOT NULL DEFAULT 0"
    )


def downgrade() -> None:
    raise RuntimeError("Downgrade bloqueado para preservar a ordem dos votos.")
