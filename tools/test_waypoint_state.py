import json
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from tools.waypoint_state import (
    ClientRegistry,
    CoordinateValidationError,
    PairingSessionStore,
    TargetStore,
    WaypointClient,
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

    def test_validate_coordinates_rejects_bool_values(self):
        with self.assertRaises(CoordinateValidationError):
            validate_coordinates(True, 2.0)
        with self.assertRaises(CoordinateValidationError):
            validate_coordinates(48.0, False)

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

    def test_client_registry_adds_and_loads_client(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "state" / "clients.json"
            registry = ClientRegistry(path)
            client = WaypointClient(
                id="iphone171",
                name="Raph iPhone",
                public_key="base64url-ed25519-public-key",
                created_at="2026-06-16T12:00:00Z",
            )

            registry.add_client(client)

            self.assertTrue(path.exists())
            data = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(data["clients"][0]["id"], "iphone171")

            loaded_registry = ClientRegistry(path)
            self.assertTrue(loaded_registry.has_clients())
            self.assertEqual(loaded_registry.get_client("iphone171"), client)
            self.assertEqual(loaded_registry.list_clients(), [client])

    def test_client_registry_rejects_duplicate_client_id(self):
        with tempfile.TemporaryDirectory() as tmp:
            registry = ClientRegistry(Path(tmp) / "clients.json")
            registry.add_client(
                WaypointClient(
                    id="iphone171",
                    name="Raph iPhone",
                    public_key="base64url-ed25519-public-key",
                    created_at="2026-06-16T12:00:00Z",
                )
            )

            with self.assertRaises(ValueError):
                registry.add_client(
                    WaypointClient(
                        id="iphone171",
                        name="Duplicate iPhone",
                        public_key="other-public-key",
                        created_at="2026-06-16T12:01:00Z",
                    )
                )

    def test_pairing_session_store_accepts_active_code_once(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "runtime" / "pairing.json"
            store = PairingSessionStore(path)

            store.create_session(
                "http://100.78.165.105:8765",
                "7K4M9Q2XPA",
                "2026-06-16T12:05:00Z",
            )

            self.assertTrue(path.exists())
            data = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(data["code"], "7K4M9Q2XPA")

            now = datetime(2026, 6, 16, 12, 0, tzinfo=timezone.utc)
            self.assertTrue(store.consume_code("7K4M9Q2XPA", now=now))
            self.assertFalse(store.consume_code("7K4M9Q2XPA", now=now))
            self.assertIsNone(store.load_session())

    def test_pairing_session_store_rejects_expired_code(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "pairing.json"
            store = PairingSessionStore(path)

            store.create_session(
                "http://100.78.165.105:8765",
                "7K4M9Q2XPA",
                "2026-06-16T12:05:00Z",
            )

            self.assertTrue(path.exists())
            now = datetime(2026, 6, 16, 12, 6, tzinfo=timezone.utc)
            self.assertFalse(store.consume_code("7K4M9Q2XPA", now=now))
