"""Smoke test executado pelo CI contra PostgreSQL/PostGIS real."""

from fastapi import Response

import auth_router
from db import connect, init_db
import map_router
from map_service import ensure_initial_map, validate_map


def main() -> None:
    init_db()
    ensure_initial_map()
    current = map_router.current_map(Response())
    validation = validate_map(current["map_data"])
    if not validation.valid:
        raise RuntimeError(validation.errors)

    with connect() as con:
        con.execute(
            "INSERT OR IGNORE INTO courses(name) VALUES (?)",
            ("Smoke PostgreSQL",),
        )
        con.commit()

    result = auth_router.register(
        auth_router.RegisterIn(
            name="Smoke CI",
            email="smoke-postgres@granmap.invalid",
            password="smoke-password-safe",
            course_name="Smoke PostgreSQL",
            semester=1,
            group_name="CI",
        )
    )
    if not result["token"] or result["user"]["email"] != "smoke-postgres@granmap.invalid":
        raise RuntimeError("Autenticação PostgreSQL não validada.")
    print("PostgreSQL/PostGIS, mapa e autenticação: OK")


if __name__ == "__main__":
    main()
