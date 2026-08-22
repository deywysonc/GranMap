from datetime import datetime, timedelta, timezone
import secrets
from typing import Literal

from fastapi import APIRouter, BackgroundTasks, Header, HTTPException, Response
from pydantic import BaseModel, Field

from db import connect
from email_service import send_password_reset
from security import (
    LEGACY_PBKDF2_ITERATIONS,
    PASSWORD_ALGORITHM,
    hash_password,
    hash_session_token,
    verify_password,
)
from settings import get_settings


router = APIRouter(tags=["Conta e perfil"])

PASSWORD_ITERATIONS = LEGACY_PBKDF2_ITERATIONS
SESSION_DAYS = get_settings().session_days
SESSION_COOKIE = "granmap_session"
CSRF_COOKIE = "granmap_csrf"

Role = Literal["student", "professor", "moderator", "coordination", "admin"]


class RegisterIn(BaseModel):
    name: str = Field(min_length=2, max_length=100)
    email: str = Field(min_length=5, max_length=160)
    password: str = Field(min_length=10, max_length=128)
    course_name: str = Field(min_length=2, max_length=160)
    semester: int = Field(ge=1, le=20)
    group_name: str = Field(min_length=1, max_length=60)


class LoginIn(BaseModel):
    email: str
    password: str


class ProfileUpdateIn(BaseModel):
    name: str = Field(min_length=2, max_length=100)
    course_name: str = Field(min_length=2, max_length=160)
    semester: int = Field(ge=1, le=20)
    group_name: str = Field(min_length=1, max_length=60)


class PasswordChangeIn(BaseModel):
    current_password: str = Field(min_length=1, max_length=128)
    new_password: str = Field(min_length=10, max_length=128)


class AccountDeleteIn(BaseModel):
    password: str = Field(min_length=1, max_length=128)


class PasswordResetRequestIn(BaseModel):
    email: str = Field(min_length=5, max_length=160)


class PasswordResetConfirmIn(BaseModel):
    token: str = Field(min_length=20, max_length=200)
    new_password: str = Field(min_length=10, max_length=128)


class HistoryIn(BaseModel):
    poi_id: str = Field(min_length=1, max_length=120)
    poi_name: str = Field(min_length=1, max_length=180)


def _utc_now():
    return datetime.now(timezone.utc)


def _token_hash(token: str) -> str:
    return hash_session_token(token)


def _public_user(row):
    return {
        "id": row["id"],
        "name": row["name"],
        "email": row["email"],
        "course_name": row["course_name"],
        "semester": row["semester"],
        "group_name": row["group_name"],
        "role": row["role"],
        "reputation": row["reputation"],
    }


def _course_exists(course_name: str) -> bool:
    with connect() as con:
        row = con.execute(
            "SELECT id FROM courses WHERE name = ? COLLATE NOCASE",
            (course_name.strip(),),
        ).fetchone()
        return row is not None


def _create_session(user_id: int):
    raw_token = secrets.token_urlsafe(40)
    expires = _utc_now() + timedelta(days=SESSION_DAYS)

    with connect() as con:
        con.execute(
            "DELETE FROM sessions WHERE expires_at <= ? OR revoked_at IS NOT NULL",
            (_utc_now().isoformat(),),
        )
        con.execute(
            """
            INSERT INTO sessions(user_id, token_hash, expires_at)
            VALUES (?, ?, ?)
            """,
            (user_id, _token_hash(raw_token), expires.isoformat()),
        )
        con.commit()

    return raw_token


def _require_user(authorization: str | None):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Sessão necessária.")

    raw_token = authorization[7:].strip()
    if not raw_token:
        raise HTTPException(status_code=401, detail="Sessão inválida.")

    token_hash = _token_hash(raw_token)

    with connect() as con:
        row = con.execute(
            """
            SELECT
                u.*,
                s.id AS session_id,
                s.expires_at
            FROM sessions s
            JOIN users u ON u.id = s.user_id
            WHERE s.token_hash = ?
              AND s.revoked_at IS NULL
              AND u.deleted_at IS NULL
            """,
            (token_hash,),
        ).fetchone()

        if row is None:
            raise HTTPException(status_code=401, detail="Sessão inválida.")

        try:
            expires = datetime.fromisoformat(row["expires_at"])
        except ValueError:
            expires = _utc_now() - timedelta(seconds=1)

        if expires <= _utc_now():
            con.execute("DELETE FROM sessions WHERE id = ?", (row["session_id"],))
            con.commit()
            raise HTTPException(status_code=401, detail="Sessão expirada.")

        con.execute(
            "UPDATE sessions SET last_seen_at = ? WHERE id = ?",
            (_utc_now().isoformat(), row["session_id"]),
        )
        con.commit()

        return row, raw_token


def require_user(authorization: str | None):
    """Autentica uma rota fora deste router."""
    return _require_user(authorization)


def optional_user(authorization: str | None):
    if not authorization:
        return None
    row, _ = _require_user(authorization)
    return row


def require_roles(authorization: str | None, allowed: set[str]):
    user, _ = _require_user(authorization)
    if user["role"] not in allowed:
        raise HTTPException(
            status_code=403,
            detail="Seu perfil não tem permissão para esta operação.",
        )
    return user


def _set_web_cookies(response: Response, token: str) -> str:
    settings = get_settings()
    csrf_token = secrets.token_urlsafe(32)
    max_age = settings.session_days * 24 * 60 * 60
    response.set_cookie(
        SESSION_COOKIE,
        token,
        max_age=max_age,
        httponly=True,
        secure=settings.cookie_secure,
        samesite="strict",
        path="/",
    )
    response.set_cookie(
        CSRF_COOKIE,
        csrf_token,
        max_age=max_age,
        httponly=False,
        secure=settings.cookie_secure,
        samesite="strict",
        path="/",
    )
    return csrf_token


def _clear_web_cookies(response: Response) -> None:
    response.delete_cookie(SESSION_COOKIE, path="/")
    response.delete_cookie(CSRF_COOKIE, path="/")


def _authenticate(data: LoginIn):
    email = data.email.strip().lower()
    with connect() as con:
        row = con.execute(
            "SELECT * FROM users WHERE email = ? COLLATE NOCASE",
            (email,),
        ).fetchone()

    if row is None:
        raise HTTPException(status_code=401, detail="E-mail ou senha inválidos.")
    if row["deleted_at"] is not None:
        raise HTTPException(status_code=401, detail="E-mail ou senha inválidos.")

    verification = verify_password(
        data.password,
        row["password_hash"],
        row["password_algorithm"],
        row["password_salt"],
    )
    if not verification.valid:
        raise HTTPException(status_code=401, detail="E-mail ou senha inválidos.")

    if verification.upgraded_hash:
        with connect() as con:
            con.execute(
                """
                UPDATE users
                SET password_hash = ?, password_salt = '',
                    password_algorithm = ?, updated_at = CURRENT_TIMESTAMP
                WHERE id = ?
                """,
                (verification.upgraded_hash, PASSWORD_ALGORITHM, row["id"]),
            )
            con.commit()

    token = _create_session(row["id"])
    return token, row


@router.post("/auth/register")
def register(data: RegisterIn):
    email = data.email.strip().lower()
    course = data.course_name.strip()

    if not _course_exists(course):
        raise HTTPException(
            status_code=400,
            detail="Curso não cadastrado no GranMap Admin.",
        )

    salt = ""
    password_hash = hash_password(data.password)

    try:
        with connect() as con:
            cursor = con.execute(
                """
                INSERT INTO users(
                    name, email, password_hash, password_salt,
                    password_algorithm, course_name, semester, group_name, role
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'student')
                """,
                (
                    data.name.strip(),
                    email,
                    password_hash,
                    salt,
                    PASSWORD_ALGORITHM,
                    course,
                    data.semester,
                    data.group_name.strip(),
                ),
            )
            con.commit()
            user_id = cursor.lastrowid
            row = con.execute(
                "SELECT * FROM users WHERE id = ?",
                (user_id,),
            ).fetchone()
    except Exception as exc:
        if "UNIQUE" in str(exc).upper():
            raise HTTPException(
                status_code=409,
                detail="Já existe uma conta com este e-mail.",
            ) from exc
        raise

    token = _create_session(user_id)
    return {"token": token, "user": _public_user(row)}


@router.post("/auth/login")
def login(data: LoginIn):
    token, row = _authenticate(data)
    return {"token": token, "user": _public_user(row)}


@router.post("/auth/password-reset/request")
def request_password_reset(
    data: PasswordResetRequestIn,
    background_tasks: BackgroundTasks,
):
    email = data.email.strip().lower()
    raw_token = None
    with connect() as con:
        user = con.execute(
            """
            SELECT id, email FROM users
            WHERE email = ? COLLATE NOCASE AND deleted_at IS NULL
            """,
            (email,),
        ).fetchone()
        if user is not None:
            raw_token = secrets.token_urlsafe(32)
            expires = _utc_now() + timedelta(minutes=30)
            con.execute(
                """
                UPDATE account_tokens SET used_at = ?
                WHERE user_id = ? AND purpose = 'password_reset' AND used_at IS NULL
                """,
                (_utc_now().isoformat(), user["id"]),
            )
            con.execute(
                """
                INSERT INTO account_tokens(user_id, token_hash, purpose, expires_at)
                VALUES (?, ?, 'password_reset', ?)
                """,
                (user["id"], _token_hash(raw_token), expires.isoformat()),
            )
            con.commit()

    settings = get_settings()
    if raw_token is not None and settings.smtp_host and settings.smtp_from_email:
        background_tasks.add_task(send_password_reset, email, raw_token)

    result = {
        "accepted": True,
        "message": (
            "Se o e-mail estiver cadastrado, enviaremos um código de recuperação."
        ),
    }
    if raw_token is not None and not settings.is_production and not settings.smtp_host:
        result["development_token"] = raw_token
    return result


@router.post("/auth/password-reset/confirm")
def confirm_password_reset(data: PasswordResetConfirmIn):
    token_hash = _token_hash(data.token.strip())
    with connect() as con:
        token = con.execute(
            """
            SELECT t.id, t.user_id
            FROM account_tokens t
            JOIN users u ON u.id = t.user_id
            WHERE t.token_hash = ?
              AND t.purpose = 'password_reset'
              AND t.used_at IS NULL
              AND t.expires_at > ?
              AND u.deleted_at IS NULL
            """,
            (token_hash, _utc_now().isoformat()),
        ).fetchone()
        if token is None:
            raise HTTPException(
                status_code=400,
                detail="Código inválido ou expirado.",
            )
        now = _utc_now().isoformat()
        con.execute(
            """
            UPDATE users
            SET password_hash = ?, password_salt = '', password_algorithm = ?,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
            """,
            (hash_password(data.new_password), PASSWORD_ALGORITHM, token["user_id"]),
        )
        con.execute(
            "UPDATE account_tokens SET used_at = ? WHERE id = ?",
            (now, token["id"]),
        )
        con.execute(
            "UPDATE sessions SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL",
            (now, token["user_id"]),
        )
        con.execute(
            "INSERT INTO auth_events(user_id, event) VALUES (?, ?)",
            (token["user_id"], "password.reset"),
        )
        con.commit()
    return {"changed": True}


@router.post("/auth/web-login")
def web_login(data: LoginIn, response: Response):
    token, row = _authenticate(data)
    csrf_token = _set_web_cookies(response, token)
    return {"user": _public_user(row), "csrf_token": csrf_token}


@router.get("/auth/me")
def me(authorization: str | None = Header(default=None)):
    row, _ = _require_user(authorization)
    return _public_user(row)


@router.put("/auth/me")
def update_me(
    data: ProfileUpdateIn,
    authorization: str | None = Header(default=None),
):
    row, _ = _require_user(authorization)
    course = data.course_name.strip()

    if not _course_exists(course):
        raise HTTPException(
            status_code=400,
            detail="Curso não cadastrado no GranMap Admin.",
        )

    with connect() as con:
        con.execute(
            """
            UPDATE users
            SET name = ?,
                course_name = ?,
                semester = ?,
                group_name = ?,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
            """,
            (
                data.name.strip(),
                course,
                data.semester,
                data.group_name.strip(),
                row["id"],
            ),
        )
        con.commit()
        updated = con.execute(
            "SELECT * FROM users WHERE id = ?",
            (row["id"],),
        ).fetchone()

    return _public_user(updated)


@router.post("/auth/logout")
def logout(authorization: str | None = Header(default=None)):
    _, raw_token = _require_user(authorization)

    with connect() as con:
        con.execute(
            "UPDATE sessions SET revoked_at = ? WHERE token_hash = ?",
            (_utc_now().isoformat(), _token_hash(raw_token)),
        )
        con.commit()

    return {"logged_out": True}


@router.post("/auth/web-logout")
def web_logout(
    response: Response,
    authorization: str | None = Header(default=None),
):
    result = logout(authorization)
    _clear_web_cookies(response)
    return result


@router.get("/auth/sessions")
def sessions(authorization: str | None = Header(default=None)):
    user, _ = _require_user(authorization)
    with connect() as con:
        items = con.execute(
            """
            SELECT id, created_at, last_seen_at, expires_at
            FROM sessions
            WHERE user_id = ? AND revoked_at IS NULL AND expires_at > ?
            ORDER BY created_at DESC, id DESC
            """,
            (user["id"], _utc_now().isoformat()),
        ).fetchall()
    return [
        {
            "id": item["id"],
            "created_at": item["created_at"],
            "last_seen_at": item["last_seen_at"],
            "expires_at": item["expires_at"],
            "current": item["id"] == user["session_id"],
        }
        for item in items
    ]


@router.delete("/auth/sessions/{session_id}")
def revoke_session(
    session_id: int,
    authorization: str | None = Header(default=None),
):
    user, _ = _require_user(authorization)
    with connect() as con:
        cursor = con.execute(
            """
            UPDATE sessions SET revoked_at = ?
            WHERE id = ? AND user_id = ? AND revoked_at IS NULL
            """,
            (_utc_now().isoformat(), session_id, user["id"]),
        )
        if cursor.rowcount == 0:
            raise HTTPException(status_code=404, detail="Sessão não encontrada.")
        con.commit()
    return {"revoked": True, "current": session_id == user["session_id"]}


@router.post("/auth/change-password")
def change_password(
    data: PasswordChangeIn,
    authorization: str | None = Header(default=None),
):
    user, _ = _require_user(authorization)
    verification = verify_password(
        data.current_password,
        user["password_hash"],
        user["password_algorithm"],
        user["password_salt"],
    )
    if not verification.valid:
        raise HTTPException(status_code=401, detail="Senha atual incorreta.")
    if data.current_password == data.new_password:
        raise HTTPException(
            status_code=400,
            detail="A nova senha precisa ser diferente da atual.",
        )

    with connect() as con:
        con.execute(
            """
            UPDATE users
            SET password_hash = ?, password_salt = '',
                password_algorithm = ?, updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
            """,
            (hash_password(data.new_password), PASSWORD_ALGORITHM, user["id"]),
        )
        con.execute(
            """
            UPDATE sessions SET revoked_at = ?
            WHERE user_id = ? AND id <> ? AND revoked_at IS NULL
            """,
            (_utc_now().isoformat(), user["id"], user["session_id"]),
        )
        con.execute(
            "INSERT INTO auth_events(user_id, email, event) VALUES (?, ?, ?)",
            (user["id"], user["email"], "password.changed"),
        )
        con.commit()
    return {"changed": True, "other_sessions_revoked": True}


@router.get("/auth/export")
def export_account(authorization: str | None = Header(default=None)):
    user, _ = _require_user(authorization)
    user_id = user["id"]
    with connect() as con:
        favorites = con.execute(
            "SELECT poi_id, created_at FROM user_favorites WHERE user_id = ?",
            (user_id,),
        ).fetchall()
        history = con.execute(
            """
            SELECT poi_id, poi_name, visited_at
            FROM navigation_history WHERE user_id = ?
            ORDER BY visited_at DESC
            """,
            (user_id,),
        ).fetchall()
        proposals = con.execute(
            """
            SELECT id, subject, from_room, to_room, reason, status, created_at
            FROM proposals WHERE author_user_id = ? ORDER BY created_at DESC
            """,
            (user_id,),
        ).fetchall()
        votes = con.execute(
            """
            SELECT proposal_id, agrees, created_at
            FROM votes WHERE voter_user_id = ? ORDER BY created_at DESC
            """,
            (user_id,),
        ).fetchall()
    return {
        "exported_at": _utc_now().isoformat(),
        "profile": _public_user(user),
        "favorites": [dict(item) for item in favorites],
        "navigation_history": [dict(item) for item in history],
        "proposals": [dict(item) for item in proposals],
        "votes": [dict(item) for item in votes],
    }


@router.delete("/auth/me", status_code=204)
def delete_account(
    data: AccountDeleteIn,
    authorization: str | None = Header(default=None),
):
    user, _ = _require_user(authorization)
    verification = verify_password(
        data.password,
        user["password_hash"],
        user["password_algorithm"],
        user["password_salt"],
    )
    if not verification.valid:
        raise HTTPException(status_code=401, detail="Senha incorreta.")

    deleted_at = _utc_now().isoformat()
    anonymous_email = f"deleted+{user['id']}+{secrets.token_hex(6)}@invalid.local"
    with connect() as con:
        con.execute(
            "UPDATE sessions SET revoked_at = ? WHERE user_id = ?",
            (deleted_at, user["id"]),
        )
        con.execute("DELETE FROM user_favorites WHERE user_id = ?", (user["id"],))
        con.execute("DELETE FROM navigation_history WHERE user_id = ?", (user["id"],))
        con.execute("DELETE FROM notifications WHERE user_id = ?", (user["id"],))
        con.execute(
            "UPDATE proposals SET author_name = 'Usuário removido' WHERE author_user_id = ?",
            (user["id"],),
        )
        con.execute(
            "UPDATE votes SET voter_name = 'Usuário removido' WHERE voter_user_id = ?",
            (user["id"],),
        )
        con.execute(
            """
            UPDATE users
            SET name = 'Conta excluída', email = ?, password_hash = ?,
                password_salt = '', password_algorithm = ?, course_name = '-',
                semester = 1, group_name = '-', role = 'student', reputation = 0,
                deleted_at = ?, updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
            """,
            (
                anonymous_email,
                hash_password(secrets.token_urlsafe(48)),
                PASSWORD_ALGORITHM,
                deleted_at,
                user["id"],
            ),
        )
        con.execute(
            "INSERT INTO auth_events(user_id, email, event) VALUES (?, '', ?)",
            (user["id"], "account.deleted"),
        )
        con.commit()
    return Response(status_code=204)


@router.get("/me/schedule")
def my_schedule(authorization: str | None = Header(default=None)):
    user, _ = _require_user(authorization)

    with connect() as con:
        rows = con.execute(
            """
            SELECT
                s.*,
                c.name AS course_name,
                p.name AS professor_name,
                r.name AS room_name,
                r.poi_id AS room_poi_id
            FROM schedules s
            JOIN courses c ON c.id = s.course_id
            LEFT JOIN professors p ON p.id = s.professor_id
            JOIN rooms r ON r.id = s.room_id
            WHERE c.name = ? COLLATE NOCASE
              AND s.semester = ?
              AND s.group_name = ? COLLATE NOCASE
            ORDER BY
              CASE s.weekday
                WHEN 'Segunda-feira' THEN 1
                WHEN 'Terça-feira' THEN 2
                WHEN 'Quarta-feira' THEN 3
                WHEN 'Quinta-feira' THEN 4
                WHEN 'Sexta-feira' THEN 5
                WHEN 'Sábado' THEN 6
                WHEN 'Domingo' THEN 7
                ELSE 8
              END,
              s.start_time
            """,
            (
                user["course_name"],
                user["semester"],
                user["group_name"],
            ),
        ).fetchall()

    return [dict(row) for row in rows]


@router.get("/me/favorites")
def favorites(authorization: str | None = Header(default=None)):
    user, _ = _require_user(authorization)

    with connect() as con:
        rows = con.execute(
            """
            SELECT poi_id
            FROM user_favorites
            WHERE user_id = ?
            ORDER BY created_at DESC
            """,
            (user["id"],),
        ).fetchall()

    return [row["poi_id"] for row in rows]


@router.post("/me/favorites/{poi_id}")
def add_favorite(
    poi_id: str,
    authorization: str | None = Header(default=None),
):
    user, _ = _require_user(authorization)

    with connect() as con:
        con.execute(
            """
            INSERT OR IGNORE INTO user_favorites(user_id, poi_id)
            VALUES (?, ?)
            """,
            (user["id"], poi_id),
        )
        con.commit()

    return {"favorite": True, "poi_id": poi_id}


@router.delete("/me/favorites/{poi_id}")
def remove_favorite(
    poi_id: str,
    authorization: str | None = Header(default=None),
):
    user, _ = _require_user(authorization)

    with connect() as con:
        con.execute(
            """
            DELETE FROM user_favorites
            WHERE user_id = ? AND poi_id = ?
            """,
            (user["id"], poi_id),
        )
        con.commit()

    return {"favorite": False, "poi_id": poi_id}


@router.get("/me/history")
def history(authorization: str | None = Header(default=None)):
    user, _ = _require_user(authorization)

    with connect() as con:
        rows = con.execute(
            """
            SELECT poi_id, poi_name, visited_at
            FROM navigation_history
            WHERE user_id = ?
            ORDER BY visited_at DESC, id DESC
            LIMIT 50
            """,
            (user["id"],),
        ).fetchall()

    return [dict(row) for row in rows]


@router.post("/me/history")
def add_history(
    data: HistoryIn,
    authorization: str | None = Header(default=None),
):
    user, _ = _require_user(authorization)

    with connect() as con:
        con.execute(
            """
            INSERT INTO navigation_history(user_id, poi_id, poi_name)
            VALUES (?, ?, ?)
            """,
            (user["id"], data.poi_id, data.poi_name),
        )

        # Mantém no máximo os 50 registros mais recentes por usuário.
        con.execute(
            """
            DELETE FROM navigation_history
            WHERE user_id = ?
              AND id NOT IN (
                  SELECT id
                  FROM navigation_history
                  WHERE user_id = ?
                  ORDER BY visited_at DESC, id DESC
                  LIMIT 50
              )
            """,
            (user["id"], user["id"]),
        )
        con.commit()

    return {"saved": True}


@router.get("/auth/roles")
def available_roles():
    return [
        "student",
        "professor",
        "moderator",
        "coordination",
        "admin",
    ]
