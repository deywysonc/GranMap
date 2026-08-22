import json
from pathlib import Path
import unittest

from room_catalog import LEGACY_ROOM_MAP, ROOMS


ROOT = Path(__file__).resolve().parents[1]
MAP_PATH = ROOT / "app" / "assets" / "maps" / "gran_tiete_upper_floorplan_v11.json"


class MapAlignmentTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.map_data = json.loads(MAP_PATH.read_text(encoding="utf-8"))
        cls.map_poi_ids = {poi["id"] for poi in cls.map_data["pois"]}

    def test_real_room_catalog_uses_existing_map_pois(self):
        room_ids = {poi_id for poi_id, _, _, _ in ROOMS}

        self.assertEqual(len(room_ids), 27)
        self.assertTrue(room_ids.issubset(self.map_poi_ids))

    def test_legacy_destinations_map_to_real_pois(self):
        self.assertTrue(set(LEGACY_ROOM_MAP.values()).issubset(self.map_poi_ids))
        self.assertTrue(set(LEGACY_ROOM_MAP).isdisjoint(self.map_poi_ids))


if __name__ == "__main__":
    unittest.main()
