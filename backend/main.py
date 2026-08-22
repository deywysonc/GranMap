from contextlib import asynccontextmanager
from typing import Literal, Optional

from fastapi import FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from auth_router import (
    optional_user,
    require_roles,
    require_user,
    router as auth_router,
)
from db import connect, init_db
from http_middleware import install_http_middleware
from integration_router import router as integration_router
from map_router import router as map_router
from map_service import ensure_initial_map
from notification_router import (
    notify_academic_audience,
    router as notification_router,
)
from schedule_rules import (
    find_schedule_conflicts,
    list_existing_conflicts,
    validate_time_range,
)
from settings import get_settings


ADMIN_ROLES = {"coordination", "admin"}
MODERATION_ROLES = {"moderator", "coordination", "admin"}
USER_ADMIN_ROLES = {"admin"}
APP_VERSION = "0.12.0"
settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI):
    get_settings().validate_production()
    init_db()
    ensure_initial_map()
    yield


app = FastAPI(
    title="GranMap API",
    version=APP_VERSION,
    description=(
        "Dados acadêmicos oficiais, conta pessoal e inteligência comunitária "
        "do GranMap."
    ),
    lifespan=lifespan,
    docs_url="/docs" if settings.api_docs_enabled else None,
    redoc_url="/redoc" if settings.api_docs_enabled else None,
    openapi_url="/openapi.json" if settings.api_docs_enabled else None,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.public_origins,
    allow_origin_regex=(
        None
        if settings.is_production
        else r"^http://(localhost|127\.0\.0\.1)(:\d+)?$"
    ),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
install_http_middleware(app, settings)
app.include_router(auth_router)
app.include_router(map_router)
app.include_router(notification_router)
app.include_router(integration_router)


class CourseIn(BaseModel):
    name: str = Field(min_length=2, max_length=160)


class ProfessorIn(BaseModel):
    name: str = Field(min_length=2, max_length=160)
    email: str = Field(default="", max_length=160)


class RoomIn(BaseModel):
    poi_id: str = Field(min_length=1, max_length=120)
    name: str = Field(min_length=2, max_length=180)
    floor: int = Field(default=0, ge=0, le=20)
    building: str = Field(default="Gran", min_length=1, max_length=100)


class SubjectIn(BaseModel):
    course_id: int
    name: str = Field(min_length=2, max_length=180)


class AcademicGroupIn(BaseModel):
    course_id: int
    semester: int = Field(ge=1, le=20)
    name: str = Field(min_length=1, max_length=60)


class ScheduleIn(BaseModel):
    course_id: int
    semester: int = Field(ge=1, le=20)
    group_name: str = Field(min_length=1, max_length=60)
    subject: str = Field(min_length=2, max_length=180)
    professor_id: Optional[int] = None
    room_id: int
    weekday: str = Field(min_length=3, max_length=30)
    start_time: str = Field(min_length=4, max_length=8)
    end_time: str = Field(min_length=4, max_length=8)
    subject_id: Optional[int] = None
    group_id: Optional[int] = None


class RoleUpdateIn(BaseModel):
    role: Literal[
        "student",
        "professor",
        "moderator",
        "coordination",
        "admin",
    ]


class ProposalIn(BaseModel):
    subject: str = Field(min_length=3, max_length=180)
    from_room: str = Field(min_length=1, max_length=180)
    to_room: str = Field(min_length=1, max_length=180)
    reason: str = Field(min_length=5, max_length=600)


class VoteIn(BaseModel):
    agrees: bool


class ModerationIn(BaseModel):
    status: Literal["voting", "confirmed", "contested", "rejected"]
    moderation_note: str = Field(default="", max_length=600)
    official_priority: bool = False


class ApplyProposalIn(BaseModel):
    schedule_id: int = Field(gt=0)


def rows(query: str, params=()):
    with connect() as con:
        return [dict(row) for row in con.execute(query, params).fetchall()]


def insert(query: str, params=()):
    with connect() as con:
        cursor = con.execute(query, params)
        con.commit()
        return cursor.lastrowid


def audit(action: str, details: str):
    insert(
        "INSERT INTO audit_log(action, details) VALUES (?, ?)",
        (action, details),
    )


def _notify_schedule_change(
    data: ScheduleIn,
    schedule_id: int,
    *,
    action: str,
    previous_room: str | None = None,
):
    with connect() as con:
        room = con.execute(
            "SELECT name, poi_id FROM rooms WHERE id = ?", (data.room_id,)
        ).fetchone()
    room_name = room["name"] if room else "sala a confirmar"
    if action == "created":
        title = "Nova aula na sua grade"
        body = f"{data.subject.strip()} foi adicionada em {room_name}."
    elif action == "deleted":
        title = "Aula removida da grade"
        body = f"{data.subject.strip()} foi removida do ensalamento oficial."
    else:
        title = "Sala ou horário atualizado"
        origin = f" (antes: {previous_room})" if previous_room else ""
        body = f"{data.subject.strip()} agora está em {room_name}{origin}."
    notify_academic_audience(
        course_id=data.course_id,
        semester=data.semester,
        group_name=data.group_name.strip(),
        kind=f"schedule.{action}",
        title=title,
        body=body,
        data={
            "schedule_id": schedule_id,
            "room_id": data.room_id,
            "room_poi_id": room["poi_id"] if room else None,
            "subject": data.subject.strip(),
        },
    )


def _proposal_with_votes(proposal_id: int, user_id: int | None = None):
    with connect() as con:
        row = con.execute(
            """
            SELECT
                p.*,
                COALESCE(u.reputation, 0) AS author_reputation,
                resolver.name AS resolved_by_name,
                COALESCE(SUM(CASE WHEN v.agrees = 1 THEN 1 ELSE 0 END), 0)
                    AS yes_votes,
                COALESCE(SUM(CASE WHEN v.agrees = 0 THEN 1 ELSE 0 END), 0)
                    AS no_votes
            FROM proposals p
            LEFT JOIN users u ON u.id = p.author_user_id
            LEFT JOIN users resolver ON resolver.id = p.resolved_by_user_id
            LEFT JOIN votes v ON v.proposal_id = p.id
            WHERE p.id = ?
            GROUP BY p.id, u.reputation, resolver.name
            """,
            (proposal_id,),
        ).fetchone()
        if row is None:
            return None

        item = dict(row)
        total = item["yes_votes"] + item["no_votes"]
        item["confidence"] = item["yes_votes"] / total if total else 0
        item["official_priority"] = bool(item["official_priority"])
        item["my_vote"] = None
        if user_id is not None:
            own_vote = con.execute(
                """
                SELECT agrees
                FROM votes
                WHERE proposal_id = ? AND voter_user_id = ?
                """,
                (proposal_id, user_id),
            ).fetchone()
            if own_vote is not None:
                item["my_vote"] = bool(own_vote["agrees"])
        return item


def _consensus_status(yes: int, no: int) -> str:
    total = yes + no
    if total == 0:
        return "unverified"
    if total < 5:
        return "voting"
    confidence = yes / total
    if confidence >= 0.75:
        return "confirmed"
    if confidence <= 0.35:
        return "contested"
    return "voting"


def _award_confirmation_reputation(con, proposal):
    if (
        proposal["author_user_id"] is not None
        and proposal["reputation_awarded"] == 0
    ):
        con.execute(
            "UPDATE users SET reputation = reputation + 2 WHERE id = ?",
            (proposal["author_user_id"],),
        )
        con.execute(
            "UPDATE proposals SET reputation_awarded = 1 WHERE id = ?",
            (proposal["id"],),
        )


@app.get("/health")
def health():
    return {
        "status": "ok",
        "service": "granmap-api",
        "version": APP_VERSION,
        "environment": settings.environment,
    }


@app.get("/app-config")
def app_config():
    return {
        "schema_version": 1,
        "minimum_app_build": settings.minimum_app_build,
        "latest_app_build": settings.latest_app_build,
        "maintenance_mode": settings.maintenance_mode,
        "features": {
            "ar": settings.feature_ar_enabled,
            "physical_positioning": settings.feature_physical_positioning_enabled,
            "community_writes": settings.feature_community_writes_enabled,
        },
    }


@app.get("/courses")
def list_courses():
    return rows("SELECT * FROM courses ORDER BY name")


@app.post("/courses")
def create_course(
    data: CourseIn,
    authorization: str | None = Header(default=None),
):
    actor = require_roles(authorization, ADMIN_ROLES)
    try:
        item_id = insert(
            "INSERT INTO courses(name) VALUES (?)",
            (data.name.strip(),),
        )
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    audit("course.created", f"{actor['id']}:{item_id}:{data.name.strip()}")
    return {"id": item_id, "name": data.name.strip()}


@app.put("/courses/{course_id}")
def update_course(
    course_id: int,
    data: CourseIn,
    authorization: str | None = Header(default=None),
):
    actor = require_roles(authorization, ADMIN_ROLES)
    try:
        with connect() as con:
            cursor = con.execute(
                "UPDATE courses SET name = ? WHERE id = ?",
                (data.name.strip(), course_id),
            )
            if cursor.rowcount == 0:
                raise HTTPException(status_code=404, detail="Curso não encontrado.")
            con.commit()
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    audit("course.updated", f"{actor['id']}:{course_id}:{data.name.strip()}")
    return {"id": course_id, "name": data.name.strip()}


@app.delete("/courses/{course_id}")
def delete_course(
    course_id: int,
    authorization: str | None = Header(default=None),
):
    actor = require_roles(authorization, ADMIN_ROLES)
    try:
        with connect() as con:
            cursor = con.execute("DELETE FROM courses WHERE id = ?", (course_id,))
            if cursor.rowcount == 0:
                raise HTTPException(status_code=404, detail="Curso não encontrado.")
            con.commit()
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(
            status_code=409,
            detail="Curso vinculado a usuários ou horários não pode ser excluído.",
        ) from exc
    audit("course.deleted", f"{actor['id']}:{course_id}")
    return {"deleted": True, "id": course_id}


@app.get("/professors")
def list_professors():
    return rows("SELECT * FROM professors ORDER BY name")


@app.post("/professors")
def create_professor(
    data: ProfessorIn,
    authorization: str | None = Header(default=None),
):
    actor = require_roles(authorization, ADMIN_ROLES)
    item_id = insert(
        "INSERT INTO professors(name, email) VALUES (?, ?)",
        (data.name.strip(), data.email.strip()),
    )
    audit("professor.created", f"{actor['id']}:{item_id}:{data.name.strip()}")
    return {"id": item_id, "name": data.name.strip(), "email": data.email.strip()}


@app.put("/professors/{professor_id}")
def update_professor(
    professor_id: int,
    data: ProfessorIn,
    authorization: str | None = Header(default=None),
):
    actor = require_roles(authorization, ADMIN_ROLES)
    with connect() as con:
        cursor = con.execute(
            "UPDATE professors SET name = ?, email = ? WHERE id = ?",
            (data.name.strip(), data.email.strip(), professor_id),
        )
        if cursor.rowcount == 0:
            raise HTTPException(status_code=404, detail="Professor não encontrado.")
        con.commit()
    audit("professor.updated", f"{actor['id']}:{professor_id}")
    return {"id": professor_id, "name": data.name.strip(), "email": data.email.strip()}


@app.delete("/professors/{professor_id}")
def delete_professor(
    professor_id: int,
    authorization: str | None = Header(default=None),
):
    actor = require_roles(authorization, ADMIN_ROLES)
    try:
        with connect() as con:
            cursor = con.execute(
                "DELETE FROM professors WHERE id = ?", (professor_id,)
            )
            if cursor.rowcount == 0:
                raise HTTPException(
                    status_code=404, detail="Professor não encontrado."
                )
            con.commit()
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(
            status_code=409,
            detail="Professor com horários vinculados não pode ser excluído.",
        ) from exc
    audit("professor.deleted", f"{actor['id']}:{professor_id}")
    return {"deleted": True, "id": professor_id}


@app.get("/rooms")
def list_rooms():
    return rows("SELECT * FROM rooms ORDER BY floor, name")


@app.post("/rooms")
def create_room(
    data: RoomIn,
    authorization: str | None = Header(default=None),
):
    actor = require_roles(authorization, ADMIN_ROLES)
    try:
        item_id = insert(
            "INSERT INTO rooms(poi_id, name, floor, building) VALUES (?, ?, ?, ?)",
            (
                data.poi_id.strip(),
                data.name.strip(),
                data.floor,
                data.building.strip(),
            ),
        )
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    audit("room.created", f"{actor['id']}:{item_id}:{data.name.strip()}")
    return {"id": item_id, **data.model_dump()}


@app.put("/rooms/{room_id}")
def update_room(
    room_id: int,
    data: RoomIn,
    authorization: str | None = Header(default=None),
):
    actor = require_roles(authorization, ADMIN_ROLES)
    try:
        with connect() as con:
            cursor = con.execute(
                """
                UPDATE rooms
                SET poi_id = ?, name = ?, floor = ?, building = ?
                WHERE id = ?
                """,
                (
                    data.poi_id.strip(),
                    data.name.strip(),
                    data.floor,
                    data.building.strip(),
                    room_id,
                ),
            )
            if cursor.rowcount == 0:
                raise HTTPException(status_code=404, detail="Ambiente não encontrado.")
            con.commit()
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    audit("room.updated", f"{actor['id']}:{room_id}:{data.name.strip()}")
    return {"id": room_id, **data.model_dump()}


@app.delete("/rooms/{room_id}")
def delete_room(
    room_id: int,
    authorization: str | None = Header(default=None),
):
    actor = require_roles(authorization, ADMIN_ROLES)
    try:
        with connect() as con:
            cursor = con.execute("DELETE FROM rooms WHERE id = ?", (room_id,))
            if cursor.rowcount == 0:
                raise HTTPException(status_code=404, detail="Ambiente não encontrado.")
            con.commit()
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(
            status_code=409,
            detail="Ambiente com horários vinculados não pode ser excluído.",
        ) from exc
    audit("room.deleted", f"{actor['id']}:{room_id}")
    return {"deleted": True, "id": room_id}


@app.get("/subjects")
def list_subjects():
    return rows(
        """
        SELECT s.*, c.name AS course_name
        FROM subjects s
        JOIN courses c ON c.id = s.course_id
        ORDER BY c.name, s.name
        """
    )


@app.post("/subjects")
def create_subject(
    data: SubjectIn,
    authorization: str | None = Header(default=None),
):
    actor = require_roles(authorization, ADMIN_ROLES)
    try:
        item_id = insert(
            "INSERT INTO subjects(course_id, name) VALUES (?, ?)",
            (data.course_id, data.name.strip()),
        )
    except Exception as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    audit("subject.created", f"{actor['id']}:{item_id}:{data.name.strip()}")
    return {"id": item_id, **data.model_dump()}


@app.put("/subjects/{subject_id}")
def update_subject(
    subject_id: int,
    data: SubjectIn,
    authorization: str | None = Header(default=None),
):
    actor = require_roles(authorization, ADMIN_ROLES)
    try:
        with connect() as con:
            cursor = con.execute(
                "UPDATE subjects SET course_id = ?, name = ? WHERE id = ?",
                (data.course_id, data.name.strip(), subject_id),
            )
            if cursor.rowcount == 0:
                raise HTTPException(status_code=404, detail="Disciplina não encontrada.")
            con.commit()
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    audit("subject.updated", f"{actor['id']}:{subject_id}")
    return {"id": subject_id, **data.model_dump()}


@app.delete("/subjects/{subject_id}")
def delete_subject(
    subject_id: int,
    authorization: str | None = Header(default=None),
):
    actor = require_roles(authorization, ADMIN_ROLES)
    with connect() as con:
        cursor = con.execute("DELETE FROM subjects WHERE id = ?", (subject_id,))
        if cursor.rowcount == 0:
            raise HTTPException(status_code=404, detail="Disciplina não encontrada.")
        con.commit()
    audit("subject.deleted", f"{actor['id']}:{subject_id}")
    return {"deleted": True, "id": subject_id}


@app.get("/groups")
def list_groups():
    return rows(
        """
        SELECT g.*, c.name AS course_name
        FROM academic_groups g
        JOIN courses c ON c.id = g.course_id
        ORDER BY c.name, g.semester, g.name
        """
    )


@app.post("/groups")
def create_group(
    data: AcademicGroupIn,
    authorization: str | None = Header(default=None),
):
    actor = require_roles(authorization, ADMIN_ROLES)
    try:
        item_id = insert(
            """
            INSERT INTO academic_groups(course_id, semester, name)
            VALUES (?, ?, ?)
            """,
            (data.course_id, data.semester, data.name.strip()),
        )
    except Exception as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    audit("group.created", f"{actor['id']}:{item_id}:{data.name.strip()}")
    return {"id": item_id, **data.model_dump()}


@app.put("/groups/{group_id}")
def update_group(
    group_id: int,
    data: AcademicGroupIn,
    authorization: str | None = Header(default=None),
):
    actor = require_roles(authorization, ADMIN_ROLES)
    try:
        with connect() as con:
            cursor = con.execute(
                """
                UPDATE academic_groups
                SET course_id = ?, semester = ?, name = ?
                WHERE id = ?
                """,
                (data.course_id, data.semester, data.name.strip(), group_id),
            )
            if cursor.rowcount == 0:
                raise HTTPException(status_code=404, detail="Turma não encontrada.")
            con.commit()
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    audit("group.updated", f"{actor['id']}:{group_id}")
    return {"id": group_id, **data.model_dump()}


@app.delete("/groups/{group_id}")
def delete_group(
    group_id: int,
    authorization: str | None = Header(default=None),
):
    actor = require_roles(authorization, ADMIN_ROLES)
    with connect() as con:
        cursor = con.execute("DELETE FROM academic_groups WHERE id = ?", (group_id,))
        if cursor.rowcount == 0:
            raise HTTPException(status_code=404, detail="Turma não encontrada.")
        con.commit()
    audit("group.deleted", f"{actor['id']}:{group_id}")
    return {"deleted": True, "id": group_id}


@app.get("/schedules")
def list_schedules():
    return rows(
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
        ORDER BY s.weekday, s.start_time
        """
    )


@app.post("/schedules")
def create_schedule(
    data: ScheduleIn,
    authorization: str | None = Header(default=None),
):
    actor = require_roles(authorization, ADMIN_ROLES)
    time_error = validate_time_range(data.start_time.strip(), data.end_time.strip())
    if time_error:
        raise HTTPException(status_code=422, detail=time_error)
    conflicts = find_schedule_conflicts(
        weekday=data.weekday.strip(),
        start_time=data.start_time.strip(),
        end_time=data.end_time.strip(),
        room_id=data.room_id,
        professor_id=data.professor_id,
        group_name=data.group_name.strip(),
        course_id=data.course_id,
    )
    if conflicts:
        raise HTTPException(
            status_code=409,
            detail={
                "message": "Conflito de sala, professor ou turma detectado.",
                "conflicts": conflicts,
            },
        )
    try:
        item_id = insert(
            """
            INSERT INTO schedules(
                course_id, semester, group_name, subject,
                professor_id, room_id, weekday, start_time, end_time,
                subject_id, group_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                data.course_id,
                data.semester,
                data.group_name.strip(),
                data.subject.strip(),
                data.professor_id,
                data.room_id,
                data.weekday.strip(),
                data.start_time.strip(),
                data.end_time.strip(),
                data.subject_id,
                data.group_id,
            ),
        )
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    audit("schedule.created", f"{actor['id']}:{item_id}:{data.subject.strip()}")
    _notify_schedule_change(data, item_id, action="created")
    return {"id": item_id, **data.model_dump()}


@app.put("/schedules/{schedule_id}")
def update_schedule(
    schedule_id: int,
    data: ScheduleIn,
    authorization: str | None = Header(default=None),
):
    actor = require_roles(authorization, ADMIN_ROLES)
    time_error = validate_time_range(data.start_time.strip(), data.end_time.strip())
    if time_error:
        raise HTTPException(status_code=422, detail=time_error)
    conflicts = find_schedule_conflicts(
        weekday=data.weekday.strip(),
        start_time=data.start_time.strip(),
        end_time=data.end_time.strip(),
        room_id=data.room_id,
        professor_id=data.professor_id,
        group_name=data.group_name.strip(),
        course_id=data.course_id,
        exclude_schedule_id=schedule_id,
    )
    if conflicts:
        raise HTTPException(
            status_code=409,
            detail={
                "message": "Conflito de sala, professor ou turma detectado.",
                "conflicts": conflicts,
            },
        )

    with connect() as con:
        previous = con.execute(
            """
            SELECT r.name AS room_name
            FROM schedules s JOIN rooms r ON r.id = s.room_id
            WHERE s.id = ?
            """,
            (schedule_id,),
        ).fetchone()
        cursor = con.execute(
            """
            UPDATE schedules
            SET course_id = ?, semester = ?, group_name = ?, subject = ?,
                professor_id = ?, room_id = ?, weekday = ?, start_time = ?,
                end_time = ?, subject_id = ?, group_id = ?
            WHERE id = ?
            """,
            (
                data.course_id,
                data.semester,
                data.group_name.strip(),
                data.subject.strip(),
                data.professor_id,
                data.room_id,
                data.weekday.strip(),
                data.start_time.strip(),
                data.end_time.strip(),
                data.subject_id,
                data.group_id,
                schedule_id,
            ),
        )
        if cursor.rowcount == 0:
            raise HTTPException(status_code=404, detail="Horário não encontrado.")
        con.commit()
    audit("schedule.updated", f"{actor['id']}:{schedule_id}:{data.subject.strip()}")
    _notify_schedule_change(
        data,
        schedule_id,
        action="updated",
        previous_room=previous["room_name"] if previous else None,
    )
    return {"id": schedule_id, **data.model_dump()}


@app.delete("/schedules/{schedule_id}")
def delete_schedule(
    schedule_id: int,
    authorization: str | None = Header(default=None),
):
    actor = require_roles(authorization, ADMIN_ROLES)
    with connect() as con:
        previous = con.execute(
            "SELECT * FROM schedules WHERE id = ?", (schedule_id,)
        ).fetchone()
        if previous is None:
            raise HTTPException(status_code=404, detail="Horário não encontrado.")
        cursor = con.execute("DELETE FROM schedules WHERE id = ?", (schedule_id,))
        if cursor.rowcount == 0:
            raise HTTPException(status_code=404, detail="Horário não encontrado.")
        con.commit()
    audit("schedule.deleted", f"{actor['id']}:{schedule_id}")
    _notify_schedule_change(
        ScheduleIn(**dict(previous)), schedule_id, action="deleted"
    )
    return {"deleted": True, "id": schedule_id}


@app.get("/schedule-conflicts")
def schedule_conflicts(authorization: str | None = Header(default=None)):
    require_roles(authorization, ADMIN_ROLES)
    return list_existing_conflicts()


@app.get("/users")
def list_users(authorization: str | None = Header(default=None)):
    require_roles(authorization, USER_ADMIN_ROLES)
    return rows(
        """
        SELECT
            id, name, email, course_name, semester, group_name,
            role, reputation, created_at, updated_at
        FROM users
        ORDER BY name
        """
    )


@app.put("/users/{user_id}/role")
def update_user_role(
    user_id: int,
    data: RoleUpdateIn,
    authorization: str | None = Header(default=None),
):
    actor = require_roles(authorization, USER_ADMIN_ROLES)
    with connect() as con:
        cursor = con.execute(
            """
            UPDATE users
            SET role = ?, updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
            """,
            (data.role, user_id),
        )
        if cursor.rowcount == 0:
            raise HTTPException(status_code=404, detail="Usuário não encontrado.")
        con.commit()
    audit("user.role_updated", f"{actor['id']}:{user_id}:{data.role}")
    return {"id": user_id, "role": data.role}


@app.get("/proposals")
def list_proposals(authorization: str | None = Header(default=None)):
    user = optional_user(authorization)
    ids = rows(
        """
        SELECT id
        FROM proposals
        ORDER BY official_priority DESC, created_at DESC, id DESC
        """
    )
    user_id = user["id"] if user is not None else None
    return [_proposal_with_votes(item["id"], user_id) for item in ids]


@app.post("/proposals")
def create_proposal(
    data: ProposalIn,
    authorization: str | None = Header(default=None),
    idempotency_key: str | None = Header(default=None, alias="Idempotency-Key"),
):
    user, _ = require_user(authorization)
    if not isinstance(idempotency_key, str):
        idempotency_key = None
    if idempotency_key:
        idempotency_key = idempotency_key.strip()
        if len(idempotency_key) > 120 or not all(
            character.isalnum() or character in "-_.:"
            for character in idempotency_key
        ):
            raise HTTPException(
                status_code=400,
                detail="Chave de idempotência inválida.",
            )
    with connect() as con:
        if idempotency_key:
            existing = con.execute(
                """
                SELECT id FROM proposals
                WHERE author_user_id = ? AND idempotency_key = ?
                """,
                (user["id"], idempotency_key),
            ).fetchone()
            if existing is not None:
                return _proposal_with_votes(existing["id"], user["id"])
        cursor = con.execute(
            """
            INSERT INTO proposals(
                author_name, author_user_id, subject,
                from_room, to_room, reason, status, idempotency_key
            ) VALUES (?, ?, ?, ?, ?, ?, 'unverified', ?)
            """,
            (
                user["name"],
                user["id"],
                data.subject.strip(),
                data.from_room.strip(),
                data.to_room.strip(),
                data.reason.strip(),
                idempotency_key,
            ),
        )
        item_id = cursor.lastrowid
        con.execute(
            "UPDATE users SET reputation = reputation + 1 WHERE id = ?",
            (user["id"],),
        )
        con.execute(
            "INSERT INTO audit_log(action, details) VALUES (?, ?)",
            ("proposal.created", f"{user['id']}:{item_id}:{data.subject.strip()}"),
        )
        con.commit()

    return _proposal_with_votes(item_id, user["id"])


@app.post("/proposals/{proposal_id}/votes")
def vote(
    proposal_id: int,
    data: VoteIn,
    authorization: str | None = Header(default=None),
):
    user, _ = require_user(authorization)
    with connect() as con:
        proposal = con.execute(
            "SELECT * FROM proposals WHERE id = ?",
            (proposal_id,),
        ).fetchone()
        if proposal is None:
            raise HTTPException(status_code=404, detail="Proposta não encontrada.")
        if proposal["status"] == "rejected":
            raise HTTPException(
                status_code=409,
                detail="Esta proposta foi encerrada pela moderação.",
            )

        existing = con.execute(
            """
            SELECT id
            FROM votes
            WHERE proposal_id = ? AND voter_user_id = ?
            """,
            (proposal_id, user["id"]),
        ).fetchone()
        if existing is None:
            con.execute(
                """
                INSERT INTO votes(
                    proposal_id, voter_name, voter_user_id, agrees
                ) VALUES (?, ?, ?, ?)
                """,
                (proposal_id, user["name"], user["id"], int(data.agrees)),
            )
        else:
            con.execute(
                """
                UPDATE votes
                SET agrees = ?, voter_name = ?, created_at = CURRENT_TIMESTAMP
                WHERE id = ?
                """,
                (int(data.agrees), user["name"], existing["id"]),
            )

        counts = con.execute(
            """
            SELECT
                COALESCE(SUM(CASE WHEN agrees = 1 THEN 1 ELSE 0 END), 0) AS yes,
                COALESCE(SUM(CASE WHEN agrees = 0 THEN 1 ELSE 0 END), 0) AS no
            FROM votes
            WHERE proposal_id = ?
            """,
            (proposal_id,),
        ).fetchone()
        status = _consensus_status(counts["yes"], counts["no"])
        con.execute(
            """
            UPDATE proposals
            SET status = ?, updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
            """,
            (status, proposal_id),
        )
        if status == "confirmed":
            _award_confirmation_reputation(con, proposal)
        con.execute(
            "INSERT INTO audit_log(action, details) VALUES (?, ?)",
            (
                "proposal.voted",
                f"{user['id']}:{proposal_id}:{data.agrees}:{status}",
            ),
        )
        con.commit()

    return _proposal_with_votes(proposal_id, user["id"])


@app.post("/proposals/{proposal_id}/moderate")
def moderate_proposal(
    proposal_id: int,
    data: ModerationIn,
    authorization: str | None = Header(default=None),
):
    moderator = require_roles(authorization, MODERATION_ROLES)
    with connect() as con:
        proposal = con.execute(
            "SELECT * FROM proposals WHERE id = ?",
            (proposal_id,),
        ).fetchone()
        if proposal is None:
            raise HTTPException(status_code=404, detail="Proposta não encontrada.")

        con.execute(
            """
            UPDATE proposals
            SET status = ?,
                official_priority = ?,
                moderation_note = ?,
                resolved_by_user_id = ?,
                resolved_at = CURRENT_TIMESTAMP,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
            """,
            (
                data.status,
                int(data.official_priority),
                data.moderation_note.strip(),
                moderator["id"],
                proposal_id,
            ),
        )
        if data.status == "confirmed":
            _award_confirmation_reputation(con, proposal)
        con.execute(
            "INSERT INTO audit_log(action, details) VALUES (?, ?)",
            (
                "proposal.moderated",
                f"{moderator['id']}:{proposal_id}:{data.status}",
            ),
        )
        con.commit()

    return _proposal_with_votes(proposal_id, moderator["id"])


@app.post("/proposals/{proposal_id}/apply")
def apply_proposal(
    proposal_id: int,
    data: ApplyProposalIn,
    authorization: str | None = Header(default=None),
):
    actor = require_roles(authorization, ADMIN_ROLES)
    with connect() as con:
        proposal = con.execute(
            "SELECT * FROM proposals WHERE id = ?", (proposal_id,)
        ).fetchone()
        if proposal is None:
            raise HTTPException(status_code=404, detail="Proposta não encontrada.")
        if proposal["status"] != "confirmed":
            raise HTTPException(
                status_code=409,
                detail="Somente uma contribuição confirmada pode alterar a base oficial.",
            )
        if proposal["applied_at"] is not None:
            raise HTTPException(status_code=409, detail="Contribuição já aplicada.")
        schedule = con.execute(
            "SELECT * FROM schedules WHERE id = ?", (data.schedule_id,)
        ).fetchone()
        if schedule is None:
            raise HTTPException(status_code=404, detail="Aula não encontrada.")
        if schedule["subject"].strip().lower() != proposal["subject"].strip().lower():
            raise HTTPException(
                status_code=422,
                detail="A disciplina da aula não corresponde à contribuição.",
            )
        room = con.execute(
            "SELECT * FROM rooms WHERE LOWER(name) = LOWER(?)", (proposal["to_room"],)
        ).fetchone()
        if room is None:
            raise HTTPException(
                status_code=422,
                detail="A sala proposta ainda não existe no cadastro oficial.",
            )

    conflicts = find_schedule_conflicts(
        weekday=schedule["weekday"],
        start_time=schedule["start_time"],
        end_time=schedule["end_time"],
        room_id=room["id"],
        professor_id=schedule["professor_id"],
        group_name=schedule["group_name"],
        course_id=schedule["course_id"],
        exclude_schedule_id=schedule["id"],
    )
    if conflicts:
        raise HTTPException(
            status_code=409,
            detail={
                "message": "A alteração confirmada gera conflito no cadastro oficial.",
                "conflicts": conflicts,
            },
        )

    with connect() as con:
        con.execute(
            "UPDATE schedules SET room_id = ? WHERE id = ?",
            (room["id"], schedule["id"]),
        )
        con.execute(
            """
            UPDATE proposals
            SET official_priority = 1, applied_at = CURRENT_TIMESTAMP,
                applied_schedule_id = ?, resolved_by_user_id = ?,
                resolved_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
            """,
            (schedule["id"], actor["id"], proposal_id),
        )
        con.execute(
            "INSERT INTO audit_log(action, details) VALUES (?, ?)",
            (
                "proposal.applied",
                f"{actor['id']}:{proposal_id}:{schedule['id']}:{room['id']}",
            ),
        )
        con.commit()

    schedule_data = ScheduleIn(**{**dict(schedule), "room_id": room["id"]})
    _notify_schedule_change(
        schedule_data,
        schedule["id"],
        action="updated",
        previous_room=proposal["from_room"],
    )
    return {
        "applied": True,
        "proposal_id": proposal_id,
        "schedule_id": schedule["id"],
        "room_id": room["id"],
        "room_name": room["name"],
    }


@app.get("/community/me")
def community_profile(authorization: str | None = Header(default=None)):
    user, _ = require_user(authorization)
    with connect() as con:
        proposal_count = con.execute(
            "SELECT COUNT(*) AS total FROM proposals WHERE author_user_id = ?",
            (user["id"],),
        ).fetchone()["total"]
        vote_count = con.execute(
            "SELECT COUNT(*) AS total FROM votes WHERE voter_user_id = ?",
            (user["id"],),
        ).fetchone()["total"]
    return {
        "reputation": user["reputation"],
        "proposal_count": proposal_count,
        "vote_count": vote_count,
    }


@app.get("/audit")
def list_audit(authorization: str | None = Header(default=None)):
    require_roles(authorization, MODERATION_ROLES)
    return rows("SELECT * FROM audit_log ORDER BY id DESC LIMIT 200")
