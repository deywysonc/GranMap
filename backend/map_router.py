from datetime import datetime, timezone
import json
from typing import Any, Literal

from fastapi import APIRouter, Header, HTTPException, Response
from pydantic import BaseModel, Field

from auth_router import require_roles
from db import connect
from map_service import (
    canonical_json,
    decode_map_json,
    edge_id,
    map_checksum,
    utc_now_iso,
    validate_map,
)


router = APIRouter(tags=["Mapa e operação"])
MAP_ADMIN_ROLES = {"coordination", "admin"}


class MapVersionIn(BaseModel):
    version: str = Field(pattern=r"^[a-zA-Z0-9._-]{3,60}$")
    name: str = Field(min_length=3, max_length=160)
    notes: str = Field(default="", max_length=1000)
    map_data: dict[str, Any]


class RouteClosureIn(BaseModel):
    edge_id: str = Field(min_length=3, max_length=240)
    floor: int = Field(ge=0, le=20)
    reason: str = Field(min_length=3, max_length=400)
    starts_at: datetime | None = None
    ends_at: datetime | None = None


class AnchorIn(BaseModel):
    anchor_code: str = Field(pattern=r"^[a-zA-Z0-9._:-]{3,120}$")
    node_id: str = Field(min_length=1, max_length=160)
    kind: Literal["qr", "image", "manual", "visual"] = "qr"
    x: float
    y: float
    z: float
    floor: int = Field(ge=0, le=20)
    heading: float = Field(default=0, ge=-360, le=360)
    metadata: dict[str, Any] = Field(default_factory=dict)


class FingerprintIn(BaseModel):
    x: float
    y: float
    z: float
    floor: int = Field(ge=0, le=20)
    magnetic_x: float
    magnetic_y: float
    magnetic_z: float
    device_model: str = Field(default="", max_length=160)
    quality: float = Field(default=0, ge=0, le=1)


class FingerprintBatchIn(BaseModel):
    map_version_id: int
    samples: list[FingerprintIn] = Field(min_length=1, max_length=1000)


def _audit(action: str, details: str) -> None:
    with connect() as con:
        con.execute(
            "INSERT INTO audit_log(action, details) VALUES (?, ?)",
            (action, details),
        )
        con.commit()


def _map_row(row, include_data: bool = False):
    result = dict(row)
    if include_data:
        result["map_data"] = decode_map_json(result.pop("map_json"))
    else:
        result.pop("map_json", None)
    return result


@router.get("/maps/current")
def current_map(
    response: Response,
    if_none_match: str | None = Header(default=None, alias="If-None-Match"),
):
    with connect() as con:
        row = con.execute(
            """
            SELECT * FROM map_versions
            WHERE status = 'published'
            ORDER BY published_at DESC, id DESC
            LIMIT 1
            """
        ).fetchone()
    if row is None:
        raise HTTPException(status_code=503, detail="Nenhum mapa publicado.")
    etag = f'"{row["checksum"]}"'
    if if_none_match == etag:
        return Response(
            status_code=304,
            headers={"ETag": etag, "Cache-Control": "public, max-age=60"},
        )
    response.headers["ETag"] = etag
    response.headers["Cache-Control"] = "public, max-age=60"
    return _map_row(row, include_data=True)


@router.get("/maps/versions")
def map_versions(authorization: str | None = Header(default=None)):
    require_roles(authorization, MAP_ADMIN_ROLES)
    with connect() as con:
        rows = con.execute(
            """
            SELECT * FROM map_versions
            ORDER BY created_at DESC, id DESC
            """
        ).fetchall()
    return [_map_row(row) for row in rows]


@router.get("/maps/versions/{map_version_id}")
def get_map_version(
    map_version_id: int,
    authorization: str | None = Header(default=None),
):
    require_roles(authorization, MAP_ADMIN_ROLES)
    with connect() as con:
        row = con.execute(
            "SELECT * FROM map_versions WHERE id = ?", (map_version_id,)
        ).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="Versão não encontrada.")
    return _map_row(row, include_data=True)


@router.post("/maps/versions")
def create_map_version(
    data: MapVersionIn,
    authorization: str | None = Header(default=None),
):
    actor = require_roles(authorization, MAP_ADMIN_ROLES)
    validation = validate_map(data.map_data)
    if not validation.valid:
        raise HTTPException(
            status_code=422,
            detail={"message": "Mapa inválido.", "errors": validation.errors},
        )
    checksum = map_checksum(data.map_data)
    try:
        with connect() as con:
            cursor = con.execute(
                """
                INSERT INTO map_versions(
                    version, name, schema_version, status, map_json,
                    checksum, notes, created_by_user_id
                ) VALUES (?, ?, 1, 'draft', ?, ?, ?, ?)
                """,
                (
                    data.version,
                    data.name.strip(),
                    canonical_json(data.map_data),
                    checksum,
                    data.notes.strip(),
                    actor["id"],
                ),
            )
            con.commit()
            created = con.execute(
                "SELECT * FROM map_versions WHERE id = ?",
                (cursor.lastrowid,),
            ).fetchone()
    except Exception as exc:
        if "UNIQUE" in str(exc).upper():
            raise HTTPException(status_code=409, detail="Versão já cadastrada.") from exc
        raise
    _audit("map.version.created", f"{data.version} por {actor['email']}")
    result = _map_row(created)
    result["validation"] = {
        "valid": True,
        "warnings": validation.warnings,
    }
    return result


@router.put("/maps/versions/{map_version_id}")
def update_map_version(
    map_version_id: int,
    data: MapVersionIn,
    authorization: str | None = Header(default=None),
):
    actor = require_roles(authorization, MAP_ADMIN_ROLES)
    validation = validate_map(data.map_data)
    if not validation.valid:
        raise HTTPException(
            status_code=422,
            detail={"message": "Mapa inválido.", "errors": validation.errors},
        )
    with connect() as con:
        current = con.execute(
            "SELECT status FROM map_versions WHERE id = ?", (map_version_id,)
        ).fetchone()
        if current is None:
            raise HTTPException(status_code=404, detail="Versão não encontrada.")
        if current["status"] != "draft":
            raise HTTPException(
                status_code=409,
                detail="Somente versões em rascunho podem ser editadas.",
            )
        try:
            con.execute(
                """
                UPDATE map_versions
                SET version = ?, name = ?, notes = ?, map_json = ?, checksum = ?
                WHERE id = ?
                """,
                (
                    data.version,
                    data.name.strip(),
                    data.notes.strip(),
                    canonical_json(data.map_data),
                    map_checksum(data.map_data),
                    map_version_id,
                ),
            )
            con.commit()
        except Exception as exc:
            if "UNIQUE" in str(exc).upper():
                raise HTTPException(status_code=409, detail="Versão já cadastrada.") from exc
            raise
    _audit("map.version.updated", f"#{map_version_id} por {actor['email']}")
    return {
        "id": map_version_id,
        "updated": True,
        "warnings": validation.warnings,
    }


@router.post("/maps/versions/{map_version_id}/publish")
def publish_map_version(
    map_version_id: int,
    authorization: str | None = Header(default=None),
):
    actor = require_roles(authorization, MAP_ADMIN_ROLES)
    with connect() as con:
        row = con.execute(
            "SELECT * FROM map_versions WHERE id = ?",
            (map_version_id,),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Versão não encontrada.")
        validation = validate_map(decode_map_json(row["map_json"]))
        if not validation.valid:
            raise HTTPException(status_code=422, detail={"errors": validation.errors})
        con.execute(
            "UPDATE map_versions SET status = 'archived' WHERE status = 'published'"
        )
        con.execute(
            """
            UPDATE map_versions
            SET status = 'published', published_at = ?
            WHERE id = ?
            """,
            (utc_now_iso(), map_version_id),
        )
        con.commit()
    _audit("map.version.published", f"{row['version']} por {actor['email']}")
    return {
        "published": True,
        "version": row["version"],
        "warnings": validation.warnings,
    }


@router.delete("/maps/versions/{map_version_id}")
def delete_map_version(
    map_version_id: int,
    authorization: str | None = Header(default=None),
):
    actor = require_roles(authorization, MAP_ADMIN_ROLES)
    with connect() as con:
        row = con.execute(
            "SELECT version, status FROM map_versions WHERE id = ?",
            (map_version_id,),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Versão não encontrada.")
        if row["status"] == "published":
            raise HTTPException(status_code=409, detail="O mapa publicado não pode ser apagado.")
        con.execute("DELETE FROM map_versions WHERE id = ?", (map_version_id,))
        con.commit()
    _audit("map.version.deleted", f"{row['version']} por {actor['email']}")
    return {"deleted": True}


@router.get("/navigation/closures")
def active_closures():
    now = utc_now_iso()
    with connect() as con:
        rows = con.execute(
            """
            SELECT rc.*, creator.name AS created_by_name
            FROM route_closures rc
            JOIN users creator ON creator.id = rc.created_by_user_id
            WHERE rc.status = 'active'
              AND rc.starts_at <= ?
              AND (rc.ends_at IS NULL OR rc.ends_at > ?)
            ORDER BY rc.created_at DESC
            """,
            (now, now),
        ).fetchall()
    return [dict(row) for row in rows]


@router.get("/navigation/closures/all")
def all_closures(authorization: str | None = Header(default=None)):
    require_roles(authorization, MAP_ADMIN_ROLES)
    with connect() as con:
        rows = con.execute(
            """
            SELECT rc.*, creator.name AS created_by_name,
                   resolver.name AS resolved_by_name
            FROM route_closures rc
            JOIN users creator ON creator.id = rc.created_by_user_id
            LEFT JOIN users resolver ON resolver.id = rc.resolved_by_user_id
            ORDER BY rc.created_at DESC
            """
        ).fetchall()
    return [dict(row) for row in rows]


@router.post("/navigation/closures")
def create_closure(
    data: RouteClosureIn,
    authorization: str | None = Header(default=None),
):
    actor = require_roles(authorization, MAP_ADMIN_ROLES)
    if data.ends_at and data.starts_at and data.ends_at <= data.starts_at:
        raise HTTPException(status_code=422, detail="Fim deve ser posterior ao início.")
    current = current_map(Response())
    known_edges = {edge_id(edge) for edge in current["map_data"]["edges"]}
    if data.edge_id not in known_edges:
        raise HTTPException(status_code=422, detail="Edge inexistente no mapa publicado.")
    with connect() as con:
        cursor = con.execute(
            """
            INSERT INTO route_closures(
                edge_id, floor, reason, starts_at, ends_at, created_by_user_id
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                data.edge_id,
                data.floor,
                data.reason.strip(),
                (data.starts_at or datetime.now(timezone.utc)).isoformat(),
                data.ends_at.isoformat() if data.ends_at else None,
                actor["id"],
            ),
        )
        con.commit()
        created = con.execute(
            "SELECT * FROM route_closures WHERE id = ?", (cursor.lastrowid,)
        ).fetchone()
    _audit("navigation.closure.created", f"{data.edge_id} por {actor['email']}")
    return dict(created)


@router.post("/navigation/closures/{closure_id}/resolve")
def resolve_closure(
    closure_id: int,
    authorization: str | None = Header(default=None),
):
    actor = require_roles(authorization, MAP_ADMIN_ROLES)
    with connect() as con:
        cursor = con.execute(
            """
            UPDATE route_closures
            SET status = 'resolved', resolved_by_user_id = ?, resolved_at = ?
            WHERE id = ? AND status = 'active'
            """,
            (actor["id"], utc_now_iso(), closure_id),
        )
        if cursor.rowcount == 0:
            raise HTTPException(status_code=404, detail="Bloqueio ativo não encontrado.")
        con.commit()
    _audit("navigation.closure.resolved", f"#{closure_id} por {actor['email']}")
    return {"resolved": True}


@router.get("/positioning/anchors")
def positioning_anchors():
    with connect() as con:
        rows = con.execute(
            """
            SELECT id, anchor_code, node_id, kind, x, y, z, floor,
                   heading, metadata_json, updated_at
            FROM positioning_anchors
            WHERE enabled = 1
            ORDER BY floor, anchor_code
            """
        ).fetchall()
    result = []
    for row in rows:
        item = dict(row)
        raw = item.pop("metadata_json", "{}")
        item["metadata"] = raw if isinstance(raw, dict) else json.loads(raw)
        result.append(item)
    return result


@router.post("/positioning/anchors")
def create_anchor(
    data: AnchorIn,
    authorization: str | None = Header(default=None),
):
    actor = require_roles(authorization, MAP_ADMIN_ROLES)
    current = current_map(Response())
    node_ids = {node["id"] for node in current["map_data"]["nodes"]}
    if data.node_id not in node_ids:
        raise HTTPException(status_code=422, detail="Node inexistente no mapa publicado.")
    try:
        with connect() as con:
            cursor = con.execute(
                """
                INSERT INTO positioning_anchors(
                    anchor_code, node_id, kind, x, y, z, floor,
                    heading, metadata_json, created_by_user_id
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    data.anchor_code,
                    data.node_id,
                    data.kind,
                    data.x,
                    data.y,
                    data.z,
                    data.floor,
                    data.heading,
                    json.dumps(data.metadata, ensure_ascii=False),
                    actor["id"],
                ),
            )
            con.commit()
    except Exception as exc:
        if "UNIQUE" in str(exc).upper():
            raise HTTPException(status_code=409, detail="Código de âncora já existe.") from exc
        raise
    _audit("positioning.anchor.created", f"{data.anchor_code} por {actor['email']}")
    return {"id": cursor.lastrowid, **data.model_dump()}


@router.put("/positioning/anchors/{anchor_id}")
def update_anchor(
    anchor_id: int,
    data: AnchorIn,
    authorization: str | None = Header(default=None),
):
    actor = require_roles(authorization, MAP_ADMIN_ROLES)
    current = current_map(Response())
    if data.node_id not in {node["id"] for node in current["map_data"]["nodes"]}:
        raise HTTPException(status_code=422, detail="Node inexistente no mapa publicado.")
    with connect() as con:
        cursor = con.execute(
            """
            UPDATE positioning_anchors
            SET anchor_code = ?, node_id = ?, kind = ?, x = ?, y = ?, z = ?,
                floor = ?, heading = ?, metadata_json = ?,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
            """,
            (
                data.anchor_code,
                data.node_id,
                data.kind,
                data.x,
                data.y,
                data.z,
                data.floor,
                data.heading,
                json.dumps(data.metadata, ensure_ascii=False),
                anchor_id,
            ),
        )
        if cursor.rowcount == 0:
            raise HTTPException(status_code=404, detail="Âncora não encontrada.")
        con.commit()
    _audit("positioning.anchor.updated", f"#{anchor_id} por {actor['email']}")
    return {"id": anchor_id, **data.model_dump()}


@router.delete("/positioning/anchors/{anchor_id}")
def disable_anchor(
    anchor_id: int,
    authorization: str | None = Header(default=None),
):
    actor = require_roles(authorization, MAP_ADMIN_ROLES)
    with connect() as con:
        cursor = con.execute(
            """
            UPDATE positioning_anchors
            SET enabled = 0, updated_at = CURRENT_TIMESTAMP
            WHERE id = ? AND enabled = 1
            """,
            (anchor_id,),
        )
        if cursor.rowcount == 0:
            raise HTTPException(status_code=404, detail="Âncora ativa não encontrada.")
        con.commit()
    _audit("positioning.anchor.disabled", f"#{anchor_id} por {actor['email']}")
    return {"disabled": True, "id": anchor_id}


@router.post("/positioning/fingerprints/batch")
def create_fingerprint_batch(
    data: FingerprintBatchIn,
    authorization: str | None = Header(default=None),
):
    actor = require_roles(
        authorization, {"moderator", "coordination", "admin"}
    )
    with connect() as con:
        version = con.execute(
            "SELECT id FROM map_versions WHERE id = ?", (data.map_version_id,)
        ).fetchone()
        if version is None:
            raise HTTPException(status_code=404, detail="Versão do mapa não encontrada.")
        con.executemany(
            """
            INSERT INTO magnetic_fingerprints(
                map_version_id, x, y, z, floor, magnetic_x, magnetic_y,
                magnetic_z, device_model, quality, captured_by_user_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                (
                    data.map_version_id,
                    sample.x,
                    sample.y,
                    sample.z,
                    sample.floor,
                    sample.magnetic_x,
                    sample.magnetic_y,
                    sample.magnetic_z,
                    sample.device_model,
                    sample.quality,
                    actor["id"],
                )
                for sample in data.samples
            ],
        )
        con.commit()
    _audit(
        "positioning.fingerprints.created",
        f"{len(data.samples)} amostras por {actor['email']}",
    )
    return {"created": len(data.samples), "map_version_id": data.map_version_id}


@router.get("/positioning/fingerprints/stats")
def fingerprint_stats(authorization: str | None = Header(default=None)):
    require_roles(authorization, {"moderator", "coordination", "admin"})
    with connect() as con:
        rows = con.execute(
            """
            SELECT map_version_id, floor, COUNT(*) AS samples,
                   AVG(quality) AS average_quality,
                   COUNT(DISTINCT device_model) AS devices
            FROM magnetic_fingerprints
            GROUP BY map_version_id, floor
            ORDER BY map_version_id DESC, floor
            """
        ).fetchall()
    return [dict(row) for row in rows]


@router.get("/positioning/fingerprints/reference")
def fingerprint_reference():
    with connect() as con:
        published = con.execute(
            """
            SELECT id FROM map_versions
            WHERE status = 'published'
            ORDER BY published_at DESC, id DESC LIMIT 1
            """
        ).fetchone()
        if published is None:
            return []
        rows = con.execute(
            """
            SELECT x, y, z, floor, magnetic_x, magnetic_y, magnetic_z, quality
            FROM magnetic_fingerprints
            WHERE map_version_id = ? AND quality >= 0.35
            ORDER BY floor, id
            LIMIT 20000
            """,
            (published["id"],),
        ).fetchall()
    return [dict(row) for row in rows]
