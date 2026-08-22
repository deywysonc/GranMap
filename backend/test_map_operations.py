from pathlib import Path
import tempfile
import unittest

from fastapi import HTTPException, Response

import auth_router
import db
import map_router
from map_service import edge_id, ensure_initial_map, validate_map


class MapOperationsTest(unittest.TestCase):
    def setUp(self):
        self._original_db_path = db.DB_PATH
        self._temporary = tempfile.TemporaryDirectory()
        db.DB_PATH = Path(self._temporary.name) / "maps.db"
        db.init_db()
        with db.connect() as con:
            con.execute(
                "INSERT INTO courses(name) VALUES (?)",
                ("Engenharia da Computação",),
            )
            con.commit()
        registered = auth_router.register(
            auth_router.RegisterIn(
                name="Coordenação",
                email="mapas@teste.local",
                password="senha-muito-segura",
                course_name="Engenharia da Computação",
                semester=4,
                group_name="EC4A",
            )
        )
        with db.connect() as con:
            con.execute(
                "UPDATE users SET role = 'coordination' WHERE id = ?",
                (registered["user"]["id"],),
            )
            con.commit()
        self.authorization = f"Bearer {registered['token']}"
        ensure_initial_map()

    def tearDown(self):
        db.DB_PATH = self._original_db_path
        self._temporary.cleanup()

    def test_conceptual_map_is_valid_and_published(self):
        response = Response()
        current = map_router.current_map(response)
        validation = validate_map(current["map_data"])
        self.assertTrue(validation.valid, validation.errors)
        self.assertEqual(current["status"], "published")
        self.assertTrue(validation.warnings)
        cached = map_router.current_map(
            Response(),
            if_none_match=response.headers["etag"],
        )
        self.assertEqual(cached.status_code, 304)

    def test_closure_lifecycle(self):
        current = map_router.current_map(Response())
        edge = current["map_data"]["edges"][0]
        closure = map_router.create_closure(
            map_router.RouteClosureIn(
                edge_id=edge_id(edge),
                floor=0,
                reason="Manutenção preventiva",
            ),
            authorization=self.authorization,
        )
        active = map_router.active_closures()
        self.assertEqual([item["id"] for item in active], [closure["id"]])

        resolved = map_router.resolve_closure(
            closure["id"], authorization=self.authorization
        )
        self.assertTrue(resolved["resolved"])
        self.assertEqual(map_router.active_closures(), [])

    def test_unknown_edge_cannot_be_closed(self):
        with self.assertRaises(HTTPException) as raised:
            map_router.create_closure(
                map_router.RouteClosureIn(
                    edge_id="edge_inexistente",
                    floor=0,
                    reason="Teste",
                ),
                authorization=self.authorization,
            )
        self.assertEqual(raised.exception.status_code, 422)

    def test_draft_edit_publish_anchor_and_fingerprints(self):
        current = map_router.current_map(Response())
        data = current["map_data"]
        draft = map_router.create_map_version(
            map_router.MapVersionIn(
                version="conceptual-v6-test",
                name="Revisão testável",
                notes="teste automatizado",
                map_data=data,
            ),
            authorization=self.authorization,
        )
        updated = map_router.update_map_version(
            draft["id"],
            map_router.MapVersionIn(
                version="conceptual-v6-test",
                name="Revisão testável atualizada",
                notes="teste automatizado",
                map_data=data,
            ),
            authorization=self.authorization,
        )
        self.assertTrue(updated["updated"])
        map_router.publish_map_version(draft["id"], authorization=self.authorization)

        node = data["nodes"][0]
        anchor = map_router.create_anchor(
            map_router.AnchorIn(
                anchor_code="GRAN-TESTE-QR",
                node_id=node["id"],
                x=node["x"],
                y=node["y"],
                z=node["z"],
                floor=node["floor"],
            ),
            authorization=self.authorization,
        )
        self.assertEqual(anchor["anchor_code"], "GRAN-TESTE-QR")
        batch = map_router.create_fingerprint_batch(
            map_router.FingerprintBatchIn(
                map_version_id=draft["id"],
                samples=[
                    map_router.FingerprintIn(
                        x=node["x"], y=node["y"], z=node["z"],
                        floor=node["floor"], magnetic_x=31,
                        magnetic_y=22, magnetic_z=19, quality=.9,
                    )
                ],
            ),
            authorization=self.authorization,
        )
        self.assertEqual(batch["created"], 1)
        reference = map_router.fingerprint_reference()
        self.assertEqual(len(reference), 1)
        self.assertEqual(reference[0]["floor"], node["floor"])


if __name__ == "__main__":
    unittest.main()
