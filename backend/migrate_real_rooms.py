from db import connect, init_db
from room_catalog import LEGACY_ROOM_MAP, ROOMS

init_db()

with connect() as con:
    for poi_id, name, floor, building in ROOMS:
        existing = con.execute(
            "SELECT id FROM rooms WHERE poi_id = ?",
            (poi_id,),
        ).fetchone()

        if existing:
            con.execute(
                """
                UPDATE rooms
                SET name = ?, floor = ?, building = ?
                WHERE poi_id = ?
                """,
                (name, floor, building, poi_id),
            )
        else:
            con.execute(
                """
                INSERT INTO rooms(poi_id, name, floor, building)
                VALUES (?, ?, ?, ?)
                """,
                (poi_id, name, floor, building),
            )

    migrated_schedules = 0
    for legacy_poi_id, real_poi_id in LEGACY_ROOM_MAP.items():
        legacy = con.execute(
            "SELECT id FROM rooms WHERE poi_id = ?",
            (legacy_poi_id,),
        ).fetchone()
        real = con.execute(
            "SELECT id FROM rooms WHERE poi_id = ?",
            (real_poi_id,),
        ).fetchone()

        if legacy is None or real is None:
            continue

        cursor = con.execute(
            "UPDATE schedules SET room_id = ? WHERE room_id = ?",
            (real["id"], legacy["id"]),
        )
        migrated_schedules += cursor.rowcount

    if migrated_schedules:
        con.execute(
            "INSERT INTO audit_log(action, details) VALUES (?, ?)",
            (
                "schedule.legacy_rooms_migrated",
                f"{migrated_schedules} ensalamento(s) alinhado(s) ao mapa v6",
            ),
        )

    con.commit()

print("27 ambientes reais da Gran Tietê sincronizados no backend.")
print(f"{migrated_schedules} ensalamento(s) legado(s) alinhado(s) ao mapa v6.")
