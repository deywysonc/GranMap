"""Aplica a política de retenção sem remover dados acadêmicos oficiais."""

from datetime import datetime, timedelta, timezone
import json

from db import connect, init_db
from settings import get_settings


def apply_retention(now: datetime | None = None) -> dict[str, int]:
    settings = get_settings()
    reference = now or datetime.now(timezone.utc)
    cutoffs = {
        "history": (
            reference - timedelta(days=settings.retention_history_days)
        ).isoformat(),
        "notifications": (
            reference - timedelta(days=settings.retention_read_notifications_days)
        ).isoformat(),
        "auth_events": (
            reference - timedelta(days=settings.retention_auth_events_days)
        ).isoformat(),
        "fingerprints": (
            reference - timedelta(days=settings.retention_fingerprint_identity_days)
        ).isoformat(),
    }
    reference_value = reference.isoformat()

    with connect() as con:
        results = {
            "navigation_history_deleted": con.execute(
                "DELETE FROM navigation_history WHERE visited_at < ?",
                (cutoffs["history"],),
            ).rowcount,
            "read_notifications_deleted": con.execute(
                """
                DELETE FROM notifications
                WHERE read_at IS NOT NULL AND read_at < ?
                """,
                (cutoffs["notifications"],),
            ).rowcount,
            "auth_events_deleted": con.execute(
                "DELETE FROM auth_events WHERE created_at < ?",
                (cutoffs["auth_events"],),
            ).rowcount,
            "fingerprint_identities_anonymized": con.execute(
                """
                UPDATE magnetic_fingerprints
                SET captured_by_user_id = NULL
                WHERE captured_by_user_id IS NOT NULL AND created_at < ?
                """,
                (cutoffs["fingerprints"],),
            ).rowcount,
            "expired_sessions_deleted": con.execute(
                "DELETE FROM sessions WHERE expires_at < ? OR revoked_at IS NOT NULL",
                (reference_value,),
            ).rowcount,
        }
        con.commit()
    return results


if __name__ == "__main__":
    init_db()
    print(json.dumps(apply_retention(), ensure_ascii=False, indent=2))
