from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
from typing import Any

from db import connect


ROOT = Path(__file__).resolve().parents[1]
STRUCTURAL_MAP_PATH = (
    ROOT / "app" / "assets" / "maps" / "gran_tiete_user_corrected_v10.json"
)


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
        existing = con.execute("SELECT id FROM map_versions LIMIT 1").fetchone()
        if existing is not None:
            return

    data = json.loads(STRUCTURAL_MAP_PATH.read_text(encoding="utf-8"))
    checksum = map_checksum(data)
    with connect() as con:
        con.execute(
            """
            INSERT INTO map_versions(
                version, name, schema_version, status, map_json,
                checksum, notes, published_at
            ) VALUES (?, ?, 1, 'published', ?, ?, ?, ?)
            """,
            (
                "user-corrected-v10",
                "Planta corrigida pelos vídeos e marcações do autor",
                canonical_json(data),
                checksum,
                "Dois corredores paralelos, quadra depois deles, serviços além da quadra e lanchonete/rampa no fim do corredor Gran; escala ainda provisória.",
                utc_now_iso(),
            ),
        )
        con.commit()
