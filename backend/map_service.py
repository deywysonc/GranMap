from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
from typing import Any

from db import connect


ROOT = Path(__file__).resolve().parents[1]
STRUCTURAL_MAP_PATH = (
    ROOT / "app" / "assets" / "maps" / "gran_tiete_floorplan_v12.json"
)
STRUCTURAL_MAP_VERSION = "floorplan-v12"
LEGACY_V11_CHECKSUM = "c950c72596f5b62989a248ed11d9b0734f1ef68fb7ae5b0c3462731e293f5c88"


@dataclass(frozen=True)
class MapValidation:
    valid: bool
    errors: tuple[str, ...]
    warnings: tuple[str, ...]


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def canonical_json(data: dict[str, Any]) -> str:
    return json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def map_checksum(data: dict[str, Any]) -> str:
    return hashlib.sha256(canonical_json(data).encode("utf-8")).hexdigest()


def edge_id(edge: dict[str, Any]) -> str:
    explicit = str(edge.get("id", "")).strip()
    if explicit:
        return explicit
    return f"{edge.get('from', '')}__{edge.get('to', '')}"


def validate_map(data: dict[str, Any]) -> MapValidation:
    errors: list[str] = []
    warnings: list[str] = []
    required = ("metadata", "floors", "nodes", "edges", "pois", "zones")
    for key in required:
        if key not in data:
            errors.append(f"Campo obrigatório ausente: {key}.")

    nodes = data.get("nodes", [])
    edges = data.get("edges", [])
    pois = data.get("pois", [])
    floors = data.get("floors", [])
    if not isinstance(nodes, list) or not isinstance(edges, list):
        return MapValidation(False, tuple(errors + ["Nodes e Edges devem ser listas."]), ())

    node_ids = [str(item.get("id", "")) for item in nodes if isinstance(item, dict)]
    if len(node_ids) != len(set(node_ids)):
        errors.append("Há IDs duplicados em Nodes.")
    if any(not item for item in node_ids):
        errors.append("Todo Node precisa de ID.")
    node_set = set(node_ids)

    edge_ids: set[str] = set()
    for index, edge in enumerate(edges):
        if not isinstance(edge, dict):
            errors.append(f"Edge {index} não é um objeto.")
            continue
        current_id = edge_id(edge)
        if current_id in edge_ids:
            errors.append(f"Edge duplicada: {current_id}.")
        edge_ids.add(current_id)
        if edge.get("from") not in node_set or edge.get("to") not in node_set:
            errors.append(f"Edge {current_id} referencia Node inexistente.")
        try:
            if float(edge.get("distance", 0)) <= 0:
                errors.append(f"Edge {current_id} precisa de custo positivo.")
        except (TypeError, ValueError):
            errors.append(f"Edge {current_id} possui custo inválido.")

    poi_ids = [str(item.get("id", "")) for item in pois if isinstance(item, dict)]
    if len(poi_ids) != len(set(poi_ids)):
        errors.append("Há IDs duplicados em POIs.")
    for poi in pois:
        if not isinstance(poi, dict):
            continue
        if poi.get("navigationNode") not in node_set:
            errors.append(f"POI {poi.get('id', '?')} não está ligado ao grafo.")

    floor_ids = {
        item.get("level")
        for item in floors
        if isinstance(item, dict) and item.get("level") is not None
    }
    for node in nodes:
        if isinstance(node, dict) and node.get("floor") not in floor_ids:
            errors.append(
                f"Node {node.get('id', '?')} referencia piso não declarado."
            )

    metadata = data.get("metadata", {})
    if metadata.get("geometryStatus") != "validated":
        warnings.append("A geometria ainda não foi validada em campo.")
    if metadata.get("distanceStatus") != "validated":
        warnings.append("As distâncias ainda não são métricas oficiais.")

    return MapValidation(not errors, tuple(errors), tuple(warnings))


def decode_map_json(value) -> dict[str, Any]:
    if isinstance(value, dict):
        return value
    return json.loads(value)


def ensure_initial_map() -> None:
    with connect() as con:
        existing = con.execute(
            "SELECT id FROM map_versions WHERE version = ? LIMIT 1",
            (STRUCTURAL_MAP_VERSION,),
        ).fetchone()
        if existing is not None:
            return

    data = json.loads(STRUCTURAL_MAP_PATH.read_text(encoding="utf-8"))
    checksum = map_checksum(data)
    with connect() as con:
        published = con.execute(
            """
            SELECT version, checksum FROM map_versions
            WHERE status = 'published'
            ORDER BY published_at DESC, id DESC
            LIMIT 1
            """
        ).fetchone()
        should_publish = published is None or published["version"] in {
            "user-corrected-v10",
            "structural-v7",
            "topological-v8",
        }
        if published is not None and published["version"] == "upper-floorplan-v11":
            should_publish = published["checksum"] == LEGACY_V11_CHECKSUM
        if should_publish:
            con.execute(
                "UPDATE map_versions SET status = 'archived' WHERE status = 'published'"
            )
            if published is not None and published["version"] == "upper-floorplan-v11":
                # A closed old segment must remain closed after it is split into
                # a corner or moved onto the circulation outside the court.
                replacements = {
                    "ground_c1_end__ground_spiral_ramp_landing": "ground_ramp_access_corner__ground_spiral_ramp_landing",
                    "upper_spine_5__upper_spine_6": "upper_gallery_turn__upper_gallery_step",
                    "upper_service_spine__upper_bwc_masc": "upper_bwc_passage__upper_bwc_masc",
                    "ground_court_east_north__ground_services_north": "ground_court_east_north__ground_services_north_approach",
                    "ground_services_north__ground_services_mid": "ground_services_north_approach__ground_services_mid_approach",
                    "ground_services_mid__ground_services_south": "ground_services_mid_approach__ground_services_south_approach",
                    "ground_services_south__ground_court_east_south": "ground_services_south_approach__ground_court_east_south",
                }
                for old, new in replacements.items():
                    con.execute(
                        "UPDATE route_closures SET edge_id = ? WHERE edge_id = ? AND status = 'active'",
                        (new, old),
                    )
        con.execute(
            """
            INSERT INTO map_versions(
                version, name, schema_version, status, map_json,
                checksum, notes, published_at
            ) VALUES (?, ?, 1, ?, ?, ?, ?, ?)
            """,
            (
                STRUCTURAL_MAP_VERSION,
                "GranMap: planta superior e térreo esquemático",
                "published" if should_publish else "draft",
                canonical_json(data),
                checksum,
                "Planta superior em escala relativa, com circulação ampla abaixo da galeria e Agronomia à esquerda da rampa conforme as correções do autor. No térreo, lanchonete e rampa de frente à quadra. Dimensões e acessibilidade não aferidas.",
                utc_now_iso() if should_publish else None,
            ),
        )
        con.commit()
