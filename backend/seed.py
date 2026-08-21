from db import connect, init_db
from room_catalog import ROOMS

init_db()

with connect() as con:
    if con.execute("SELECT COUNT(*) FROM courses").fetchone()[0] == 0:
        con.execute(
            "INSERT INTO courses(name) VALUES (?)",
            ("Engenharia da Computação",),
        )

    if con.execute("SELECT COUNT(*) FROM professors").fetchone()[0] == 0:
        con.execute(
            "INSERT INTO professors(name, email) VALUES (?, ?)",
            ("Prof. Carlos", "carlos@granmap.local"),
        )
        con.execute(
            "INSERT INTO professors(name, email) VALUES (?, ?)",
            ("Prof. Rafael", "rafael@granmap.local"),
        )

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

    con.commit()

course_id = None
professor_id = None
room_id = None

with connect() as con:
    course_id = con.execute(
        "SELECT id FROM courses WHERE name = ?",
        ("Engenharia da Computação",),
    ).fetchone()[0]
    professor_id = con.execute(
        "SELECT id FROM professors WHERE name = ?",
        ("Prof. Carlos",),
    ).fetchone()[0]
    room_id = con.execute(
        "SELECT id FROM rooms WHERE poi_id = ?",
        ("alan_turing",),
    ).fetchone()[0]

    if con.execute("SELECT COUNT(*) FROM schedules").fetchone()[0] == 0:
        con.execute(
            """
            INSERT INTO schedules(
                course_id, semester, group_name, subject,
                professor_id, room_id, weekday, start_time, end_time
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                course_id,
                4,
                "EC4A",
                "Estrutura de Dados",
                professor_id,
                room_id,
                "Segunda-feira",
                "19:00",
                "20:40",
            ),
        )

    con.commit()

print("GranMap backend: dados de desenvolvimento inseridos.")
