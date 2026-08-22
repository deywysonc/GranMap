"""Cria o cenário determinístico usado na apresentação do GranMap."""

import os

from db import DB_PATH, connect, init_db
from map_service import ensure_initial_map
from room_catalog import ROOMS
from security import PASSWORD_ALGORITHM, hash_password
from settings import get_settings


DEMO_PASSWORD = "GranMap123!"
DEMO_PASSWORDS_MARKER = "demo.passwords.argon2id.v1"
DEMO_USER_EMAILS = (
    "aluno@granmap.demo",
    "bruno@granmap.demo",
    "professor@granmap.demo",
    "moderador@granmap.demo",
    "admin@granmap.demo",
)


def repair_demo_passwords(con):
    already_repaired = con.execute(
        "SELECT 1 FROM audit_log WHERE action = ? LIMIT 1",
        (DEMO_PASSWORDS_MARKER,),
    ).fetchone()
    if already_repaired:
        return False

    for email in DEMO_USER_EMAILS:
        con.execute(
            """
            UPDATE users
            SET password_hash = ?, password_salt = '', password_algorithm = ?,
                updated_at = CURRENT_TIMESTAMP
            WHERE email = ?
            """,
            (hash_password(DEMO_PASSWORD), PASSWORD_ALGORITHM, email),
        )
    con.execute(
        "INSERT INTO audit_log(action, details) VALUES (?, ?)",
        (
            DEMO_PASSWORDS_MARKER,
            "Credenciais demo armazenadas com Argon2id",
        ),
    )
    con.commit()
    return True


def ensure_course(con, name: str):
    con.execute("INSERT OR IGNORE INTO courses(name) VALUES (?)", (name,))
    return con.execute("SELECT id FROM courses WHERE name = ?", (name,)).fetchone()[0]


def ensure_professor(con, name: str, email: str):
    row = con.execute("SELECT id FROM professors WHERE email = ?", (email,)).fetchone()
    if row:
        con.execute("UPDATE professors SET name = ? WHERE id = ?", (name, row[0]))
        return row[0]
    return con.execute(
        "INSERT INTO professors(name, email) VALUES (?, ?)",
        (name, email),
    ).lastrowid


def ensure_subject(con, course_id: int, name: str):
    con.execute(
        "INSERT OR IGNORE INTO subjects(course_id, name) VALUES (?, ?)",
        (course_id, name),
    )
    return con.execute(
        "SELECT id FROM subjects WHERE course_id = ? AND name = ?",
        (course_id, name),
    ).fetchone()[0]


def ensure_group(con, course_id: int, semester: int, name: str):
    con.execute(
        """
        INSERT OR IGNORE INTO academic_groups(course_id, semester, name)
        VALUES (?, ?, ?)
        """,
        (course_id, semester, name),
    )
    return con.execute(
        """
        SELECT id FROM academic_groups
        WHERE course_id = ? AND semester = ? AND name = ?
        """,
        (course_id, semester, name),
    ).fetchone()[0]


def ensure_user(
    con,
    *,
    name: str,
    email: str,
    course: str,
    semester: int,
    group_name: str,
    role: str,
    reputation: int,
):
    password_hash = hash_password(DEMO_PASSWORD)
    con.execute(
        """
        INSERT INTO users(
            name, email, password_hash, password_salt, password_algorithm,
            course_name, semester, group_name, role, reputation
        ) VALUES (?, ?, ?, '', ?, ?, ?, ?, ?, ?)
        ON CONFLICT(email) DO UPDATE SET
            name = excluded.name,
            password_hash = excluded.password_hash,
            password_salt = excluded.password_salt,
            password_algorithm = excluded.password_algorithm,
            course_name = excluded.course_name,
            semester = excluded.semester,
            group_name = excluded.group_name,
            role = excluded.role,
            reputation = excluded.reputation,
            updated_at = CURRENT_TIMESTAMP
        """,
        (
            name,
            email,
            password_hash,
            PASSWORD_ALGORITHM,
            course,
            semester,
            group_name,
            role,
            reputation,
        ),
    )
    return con.execute("SELECT id FROM users WHERE email = ?", (email,)).fetchone()[0]


def room_id(con, poi_id: str):
    return con.execute("SELECT id FROM rooms WHERE poi_id = ?", (poi_id,)).fetchone()[0]


def seed_demo():
    settings = get_settings()
    remote_seed_allowed = (
        os.environ.get("GRANMAP_ALLOW_REMOTE_DEMO_SEED", "false").lower()
        == "true"
    )
    if settings.database_url and not remote_seed_allowed:
        raise SystemExit(
            "Seed remoto recusado. Defina "
            "GRANMAP_ALLOW_REMOTE_DEMO_SEED=true somente na demo hospedada."
        )
    if not settings.database_url and DB_PATH.name != "granmap_demo.db":
        raise SystemExit(
            "Por segurança, seed_demo.py só opera em granmap_demo.db. "
            "Defina GRANMAP_DB_PATH para o banco de demonstração."
        )

    init_db()
    with connect() as con:
        already_seeded = con.execute(
            "SELECT 1 FROM audit_log WHERE action = ? LIMIT 1",
            ("demo.seeded",),
        ).fetchone()
        if already_seeded:
            if repair_demo_passwords(con):
                print("Credenciais da demo atualizadas com Argon2id.")
            else:
                print("GranMap demo já estava preparada; nenhuma alteração aplicada.")
            return

        courses = {
            name: ensure_course(con, name)
            for name in [
                "Engenharia da Computação",
                "Administração",
                "Agronomia",
            ]
        }
        professors = {
            "Carlos": ensure_professor(
                con, "Prof. Carlos Mendes", "carlos@granmap.demo"
            ),
            "Rafael": ensure_professor(
                con, "Prof. Rafael Lima", "rafael@granmap.demo"
            ),
            "Ada": ensure_professor(con, "Profa. Ada Costa", "ada@granmap.demo"),
            "Marina": ensure_professor(
                con, "Profa. Marina Alves", "marina@granmap.demo"
            ),
        }

        con.executemany(
            """
            INSERT INTO rooms(poi_id, name, floor, building)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(poi_id) DO UPDATE SET
                name = excluded.name,
                floor = excluded.floor,
                building = excluded.building
            """,
            ROOMS,
        )

        subject_specs = [
            ("Engenharia da Computação", "Estrutura de Dados"),
            ("Engenharia da Computação", "Programação Mobile"),
            ("Engenharia da Computação", "Redes de Computadores"),
            ("Engenharia da Computação", "Projeto Integrador"),
            ("Administração", "Gestão de Projetos"),
            ("Agronomia", "Manejo de Culturas"),
        ]
        subjects = {
            (course, name): ensure_subject(con, courses[course], name)
            for course, name in subject_specs
        }
        groups = {
            "EC4A": ensure_group(
                con, courses["Engenharia da Computação"], 4, "EC4A"
            ),
            "ADM2A": ensure_group(con, courses["Administração"], 2, "ADM2A"),
            "AGR3A": ensure_group(con, courses["Agronomia"], 3, "AGR3A"),
        }

        users = {
            "student": ensure_user(
                con,
                name="Ana Demo",
                email="aluno@granmap.demo",
                course="Engenharia da Computação",
                semester=4,
                group_name="EC4A",
                role="student",
                reputation=7,
            ),
            "student2": ensure_user(
                con,
                name="Bruno Demo",
                email="bruno@granmap.demo",
                course="Engenharia da Computação",
                semester=4,
                group_name="EC4A",
                role="student",
                reputation=3,
            ),
            "professor": ensure_user(
                con,
                name="Ada Costa",
                email="professor@granmap.demo",
                course="Engenharia da Computação",
                semester=4,
                group_name="EC4A",
                role="professor",
                reputation=12,
            ),
            "moderator": ensure_user(
                con,
                name="Marina Moderadora",
                email="moderador@granmap.demo",
                course="Administração",
                semester=2,
                group_name="ADM2A",
                role="moderator",
                reputation=25,
            ),
            "admin": ensure_user(
                con,
                name="Coordenação GranMap",
                email="admin@granmap.demo",
                course="Engenharia da Computação",
                semester=4,
                group_name="EC4A",
                role="admin",
                reputation=50,
            ),
        }

        schedule_specs = [
            (
                "Engenharia da Computação",
                4,
                "EC4A",
                "Estrutura de Dados",
                "Carlos",
                "alan_turing",
                "Segunda-feira",
                "19:00",
                "20:40",
            ),
            (
                "Engenharia da Computação",
                4,
                "EC4A",
                "Programação Mobile",
                "Ada",
                "lab_informatica",
                "Terça-feira",
                "19:00",
                "20:40",
            ),
            (
                "Engenharia da Computação",
                4,
                "EC4A",
                "Redes de Computadores",
                "Rafael",
                "isaac_newton",
                "Quinta-feira",
                "19:00",
                "20:40",
            ),
            (
                "Engenharia da Computação",
                4,
                "EC4A",
                "Projeto Integrador",
                "Marina",
                "auditorio",
                "Sexta-feira",
                "20:50",
                "22:30",
            ),
            (
                "Administração",
                2,
                "ADM2A",
                "Gestão de Projetos",
                "Marina",
                "henry_ford",
                "Quarta-feira",
                "19:00",
                "20:40",
            ),
            (
                "Agronomia",
                3,
                "AGR3A",
                "Manejo de Culturas",
                "Carlos",
                "van_gogh",
                "Sábado",
                "08:00",
                "09:40",
            ),
        ]
        for (
            course,
            semester,
            group_name,
            subject,
            professor,
            poi_id,
            weekday,
            start_time,
            end_time,
        ) in schedule_specs:
            con.execute(
                """
                INSERT OR IGNORE INTO schedules(
                    course_id, semester, group_name, subject, professor_id,
                    room_id, weekday, start_time, end_time, subject_id, group_id
                )
                SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
                WHERE NOT EXISTS (
                    SELECT 1 FROM schedules
                    WHERE course_id = ? AND group_name = ? AND subject = ?
                      AND weekday = ? AND start_time = ?
                )
                """,
                (
                    courses[course],
                    semester,
                    group_name,
                    subject,
                    professors[professor],
                    room_id(con, poi_id),
                    weekday,
                    start_time,
                    end_time,
                    subjects[(course, subject)],
                    groups[group_name],
                    courses[course],
                    group_name,
                    subject,
                    weekday,
                    start_time,
                ),
            )

        for poi_id in ["biblioteca", "lanchonete", "lab_informatica"]:
            con.execute(
                "INSERT OR IGNORE INTO user_favorites(user_id, poi_id) VALUES (?, ?)",
                (users["student"], poi_id),
            )
        for poi_id, name in [
            ("alan_turing", "Alan Turing (Informática)"),
            ("biblioteca", "Biblioteca"),
            ("auditorio", "Auditório"),
        ]:
            con.execute(
                """
                INSERT INTO navigation_history(user_id, poi_id, poi_name)
                VALUES (?, ?, ?)
                """,
                (users["student"], poi_id, name),
            )

        proposal_specs = [
            (
                users["student"],
                "Ana Demo",
                "Estrutura de Dados",
                "Alan Turing (Informática)",
                "Laboratório de Informática",
                "Professor informou a mudança para uso dos computadores.",
                "confirmed",
                [True, True, True, True, False],
            ),
            (
                users["student2"],
                "Bruno Demo",
                "Programação Mobile",
                "Laboratório de Informática",
                "Isaac Newton",
                "Aviso ainda não confirmado pela coordenação.",
                "contested",
                [True, False, False, False, False],
            ),
        ]
        voter_ids = list(users.values())
        for (
            author_id,
            author_name,
            subject,
            from_room,
            to_room,
            reason,
            status,
            votes,
        ) in proposal_specs:
            existing = con.execute(
                "SELECT id FROM proposals WHERE subject = ? AND author_user_id = ?",
                (subject, author_id),
            ).fetchone()
            if existing:
                proposal_id = existing[0]
            else:
                proposal_id = con.execute(
                    """
                    INSERT INTO proposals(
                        author_name, author_user_id, subject, from_room, to_room,
                        reason, status, official_priority, reputation_awarded
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)
                    """,
                    (
                        author_name,
                        author_id,
                        subject,
                        from_room,
                        to_room,
                        reason,
                        status,
                        int(status == "confirmed"),
                    ),
                ).lastrowid
            for voter_id, agrees in zip(voter_ids, votes):
                voter_name = con.execute(
                    "SELECT name FROM users WHERE id = ?", (voter_id,)
                ).fetchone()[0]
                con.execute(
                    """
                    INSERT OR IGNORE INTO votes(
                        proposal_id, voter_name, voter_user_id, agrees
                    ) VALUES (?, ?, ?, ?)
                    """,
                    (proposal_id, voter_name, voter_id, int(agrees)),
                )

        con.execute(
            """
            INSERT INTO audit_log(action, details)
            SELECT 'demo.seeded', 'Cenário oficial da demonstração preparado'
            WHERE NOT EXISTS (
                SELECT 1 FROM audit_log WHERE action = 'demo.seeded'
            )
            """
        )
        con.execute(
            """
            INSERT INTO audit_log(action, details)
            SELECT ?, 'Credenciais demo armazenadas com Argon2id'
            WHERE NOT EXISTS (
                SELECT 1 FROM audit_log WHERE action = ?
            )
            """,
            (DEMO_PASSWORDS_MARKER, DEMO_PASSWORDS_MARKER),
        )
        con.commit()

    ensure_initial_map()
    anchors = [
        ("GRAN-ENTRADA-01", "ground_c1_start", 0.0, 32.0, 0.0, 0, 0.0),
        ("GRAN-TYTO-01", "ground_c2_start", 0.0, 12.0, 0.0, 0, 0.0),
        (
            "GRAN-RAMPA-TERREO",
            "ground_spiral_ramp_landing",
            124.0,
            8.0,
            0.0,
            0,
            0.0,
        ),
        (
            "GRAN-RAMPA-SUPERIOR",
            "upper_spiral_ramp",
            124.0,
            8.0,
            1.0,
            1,
            180.0,
        ),
    ]
    with connect() as con:
        for code, node_id, x, y, z, floor, heading in anchors:
            con.execute(
                """
                INSERT OR IGNORE INTO positioning_anchors(
                    anchor_code, node_id, kind, x, y, z, floor,
                    heading, metadata_json, created_by_user_id
                ) VALUES (?, ?, 'qr', ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    code,
                    node_id,
                    x,
                    y,
                    z,
                    floor,
                    heading,
                    '{"demo": true}',
                    users["admin"],
                ),
            )
        con.commit()

    target = "PostgreSQL remoto" if settings.database_url else str(DB_PATH)
    print(f"GranMap demo pronta em: {target}")
    print("Aluno: aluno@granmap.demo / GranMap123!")
    print("Admin: admin@granmap.demo / GranMap123!")


if __name__ == "__main__":
    seed_demo()
