from db import connect


def validate_time_range(start_time: str, end_time: str):
    if start_time >= end_time:
        return "O horário final deve ser posterior ao horário inicial."
    return None


def find_schedule_conflicts(
    *,
    weekday: str,
    start_time: str,
    end_time: str,
    room_id: int,
    professor_id: int | None,
    group_name: str,
    course_id: int,
    exclude_schedule_id: int | None = None,
):
    params: list[object] = [weekday, end_time, start_time]
    exclude = ""
    if exclude_schedule_id is not None:
        exclude = "AND s.id <> ?"
        params.append(exclude_schedule_id)

    with connect() as con:
        candidates = con.execute(
            f"""
            SELECT
                s.*,
                c.name AS course_name,
                p.name AS professor_name,
                r.name AS room_name
            FROM schedules s
            JOIN courses c ON c.id = s.course_id
            LEFT JOIN professors p ON p.id = s.professor_id
            JOIN rooms r ON r.id = s.room_id
            WHERE s.weekday = ? COLLATE NOCASE
              AND s.start_time < ?
              AND s.end_time > ?
              {exclude}
            ORDER BY s.start_time
            """,
            tuple(params),
        ).fetchall()

    conflicts = []
    for row in candidates:
        kinds = []
        if row["room_id"] == room_id:
            kinds.append("room")
        if professor_id is not None and row["professor_id"] == professor_id:
            kinds.append("professor")
        if (
            row["course_id"] == course_id
            and row["group_name"].casefold() == group_name.casefold()
        ):
            kinds.append("group")
        if not kinds:
            continue
        conflicts.append(
            {
                "schedule_id": row["id"],
                "kinds": kinds,
                "subject": row["subject"],
                "course_name": row["course_name"],
                "group_name": row["group_name"],
                "professor_name": row["professor_name"],
                "room_name": row["room_name"],
                "weekday": row["weekday"],
                "start_time": row["start_time"],
                "end_time": row["end_time"],
            }
        )
    return conflicts


def list_existing_conflicts():
    with connect() as con:
        schedules = [
            dict(row)
            for row in con.execute(
                """
                SELECT
                    s.*,
                    c.name AS course_name,
                    p.name AS professor_name,
                    r.name AS room_name
                FROM schedules s
                JOIN courses c ON c.id = s.course_id
                LEFT JOIN professors p ON p.id = s.professor_id
                JOIN rooms r ON r.id = s.room_id
                ORDER BY s.weekday, s.start_time
                """
            ).fetchall()
        ]

    result = []
    for index, left in enumerate(schedules):
        for right in schedules[index + 1 :]:
            if left["weekday"].casefold() != right["weekday"].casefold():
                continue
            if not (
                left["start_time"] < right["end_time"]
                and left["end_time"] > right["start_time"]
            ):
                continue
            kinds = []
            if left["room_id"] == right["room_id"]:
                kinds.append("room")
            if (
                left["professor_id"] is not None
                and left["professor_id"] == right["professor_id"]
            ):
                kinds.append("professor")
            if (
                left["course_id"] == right["course_id"]
                and left["group_name"].casefold()
                == right["group_name"].casefold()
            ):
                kinds.append("group")
            if kinds:
                result.append(
                    {
                        "left": left,
                        "right": right,
                        "kinds": kinds,
                    }
                )
    return result
