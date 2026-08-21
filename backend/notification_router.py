import json
from typing import Any

from fastapi import APIRouter, Header, HTTPException, Query

from auth_router import require_user
from db import connect
from map_service import utc_now_iso


router = APIRouter(tags=["Notificações"])


def notify_user(
    user_id: int,
    *,
    kind: str,
    title: str,
    body: str,
    data: dict[str, Any] | None = None,
) -> None:
    with connect() as con:
        con.execute(
            """
            INSERT INTO notifications(user_id, kind, title, body, data_json)
            VALUES (?, ?, ?, ?, ?)
            """,
            (user_id, kind, title, body, json.dumps(data or {}, ensure_ascii=False)),
        )
        con.commit()


def notify_academic_audience(
    *,
    course_id: int,
    semester: int,
    group_name: str,
    kind: str,
    title: str,
    body: str,
    data: dict[str, Any] | None = None,
) -> int:
    with connect() as con:
        users = con.execute(
            """
            SELECT u.id
            FROM users u
            JOIN courses c ON c.name = u.course_name
            WHERE c.id = ? AND u.semester = ? AND u.group_name = ?
            """,
            (course_id, semester, group_name),
        ).fetchall()
        for user in users:
            con.execute(
                """
                INSERT INTO notifications(user_id, kind, title, body, data_json)
                VALUES (?, ?, ?, ?, ?)
                """,
                (
                    user["id"],
                    kind,
                    title,
                    body,
                    json.dumps(data or {}, ensure_ascii=False),
                ),
            )
        con.commit()
    return len(users)


def _notification(row):
    result = dict(row)
    raw = result.pop("data_json", "{}")
    result["data"] = raw if isinstance(raw, dict) else json.loads(raw)
    result["read"] = result.get("read_at") is not None
    return result


@router.get("/me/notifications")
def list_notifications(
    unread_only: bool = Query(default=False),
    authorization: str | None = Header(default=None),
):
    user, _ = require_user(authorization)
    where = "AND read_at IS NULL" if unread_only else ""
    with connect() as con:
        items = con.execute(
            f"""
            SELECT * FROM notifications
            WHERE user_id = ? {where}
            ORDER BY created_at DESC, id DESC
            LIMIT 100
            """,
            (user["id"],),
        ).fetchall()
    return [_notification(item) for item in items]


@router.post("/me/notifications/{notification_id}/read")
def mark_notification_read(
    notification_id: int,
    authorization: str | None = Header(default=None),
):
    user, _ = require_user(authorization)
    with connect() as con:
        cursor = con.execute(
            """
            UPDATE notifications SET read_at = ?
            WHERE id = ? AND user_id = ?
            """,
            (utc_now_iso(), notification_id, user["id"]),
        )
        if cursor.rowcount == 0:
            raise HTTPException(status_code=404, detail="Notificação não encontrada.")
        con.commit()
    return {"read": True, "id": notification_id}


@router.post("/me/notifications/read-all")
def mark_all_notifications_read(
    authorization: str | None = Header(default=None),
):
    user, _ = require_user(authorization)
    with connect() as con:
        cursor = con.execute(
            """
            UPDATE notifications SET read_at = ?
            WHERE user_id = ? AND read_at IS NULL
            """,
            (utc_now_iso(), user["id"]),
        )
        con.commit()
    return {"read": True, "updated": cursor.rowcount}
