"""Confiabilidade offline, ciclo de conta e limite distribuído."""

from alembic import op


revision = "20260822_0002"
down_revision = "20260820_0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ")
    op.execute("ALTER TABLE proposals ADD COLUMN IF NOT EXISTS idempotency_key TEXT")
    op.execute(
        """
        CREATE UNIQUE INDEX IF NOT EXISTS idx_proposals_author_idempotency
        ON proposals(author_user_id, idempotency_key)
        WHERE author_user_id IS NOT NULL AND idempotency_key IS NOT NULL
        """
    )
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS account_tokens (
            id BIGSERIAL PRIMARY KEY,
            user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            token_hash TEXT NOT NULL UNIQUE,
            purpose TEXT NOT NULL,
            expires_at TIMESTAMPTZ NOT NULL,
            used_at TIMESTAMPTZ,
            created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
        """
    )
    op.execute(
        """
        CREATE INDEX IF NOT EXISTS idx_account_tokens_lookup
        ON account_tokens(token_hash, purpose, expires_at, used_at)
        """
    )
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS rate_limit_buckets (
            key TEXT PRIMARY KEY,
            window_start BIGINT NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
        """
    )


def downgrade() -> None:
    raise RuntimeError(
        "Downgrade bloqueado para preservar idempotência e exclusões de conta."
    )
