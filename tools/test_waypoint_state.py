import json
import tempfile
import unittest
from pathlib import Path

from tools.waypoint_state import (
    CoordinateValidationError,
    TargetStore,
    load_target_coordinates,
    validate_coordinates,
)


class WaypointStateTests(unittest.TestCase):
    def test_validate_coordinates_accepts_valid_values(self):
        self.assertEqual(validate_coordinates(48.85837, 2.294481), (48.85837, 2.294481))

    def test_validate_coordinates_rejects_out_of_range_values(self):
        with self.assertRaises(CoordinateValidationError):
            validate_coordinates(91.0, 2.0)
        with self.assertRaises(CoordinateValidationError):
            validate_coordinates(48.0, 181.0)

    def test_target_store_writes_and_reads_target(self):
        with tempfile.TemporaryDirectory() as tmp:
            store = TargetStore(Path(tmp) / "target.json")
            store.write_target(48.85837, 2.294481, label="Eiffel Tower", updated_by="test-phone")

            data = json.loads((Path(tmp) / "target.json").read_text(encoding="utf-8"))
            self.assertEqual(data["latitude"], 48.85837)
            self.assertEqual(data["longitude"], 2.294481)
            self.assertEqual(data["label"], "Eiffel Tower")
            self.assertEqual(data["updated_by"], "test-phone")

            loaded = store.read_target()
            self.assertEqual(loaded.latitude, 48.85837)
            self.assertEqual(loaded.longitude, 2.294481)

    def test_load_target_coordinates_returns_none_for_missing_or_corrupt_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "target.json"
            self.assertIsNone(load_target_coordinates(path))
            path.write_text("{broken", encoding="utf-8")
            self.assertIsNone(load_target_coordinates(path))

    def test_load_target_coordinates_returns_none_for_invalid_utf8_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "target.json"
            path.write_bytes(b"\xff\xfe\xfa")
            self.assertIsNone(load_target_coordinates(path))
