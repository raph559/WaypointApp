import json
import tempfile
import time
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

from tools.waypoint_control_api import WaypointControlService
from tools.waypoint_security import b64url_encode, canonical_request
from tools.waypoint_state import (
    ClientRegistry,
    PairingSessionStore,
    TargetStore,
    WaypointClient,
)


CLIENT_ID = "iphone171"
CLIENT_NAME = "Raph iPhone"
PAIRING_CODE = "7K4M9Q2XPA"
SERVER_URL = "http://100.78.165.105:8765"


class WaypointControlApiTests(unittest.TestCase):
    def test_health_reports_target_and_pairing_state(self):
        with self._state() as state:
            service = state.service()
            state.target_store.write_target(
                48.85837,
                2.294481,
                label="Eiffel Tower",
                updated_by=CLIENT_ID,
            )
            state.client_registry.add_client(state.client())

            status, response = service.health()

            self.assertEqual(status, 200)
            self.assertTrue(response["ok"])
            self.assertTrue(response["paired"])
            self.assertEqual(response["target"]["latitude"], 48.85837)
            self.assertEqual(response["target"]["longitude"], 2.294481)
            self.assertEqual(response["target"]["label"], "Eiffel Tower")
            self.assertEqual(response["target"]["updated_by"], CLIENT_ID)

    def test_pair_registers_client_with_active_code(self):
        with self._state() as state:
            service = state.service()
            state.create_pairing_session()
            body = state.pair_body(code=PAIRING_CODE)

            status, response = service.pair(body)

            self.assertEqual(status, 200)
            self.assertEqual(response, {"ok": True, "client_id": CLIENT_ID})
            registered = state.client_registry.get_client(CLIENT_ID)
            self.assertIsNotNone(registered)
            self.assertEqual(registered.name, CLIENT_NAME)
            self.assertEqual(registered.public_key, state.public_key_b64)
            self.assertIsNone(state.pairing_store.load_session())

    def test_pair_rejects_invalid_code(self):
        with self._state() as state:
            service = state.service()
            state.create_pairing_session()
            body = state.pair_body(code="BADCODE123")

            status, response = service.pair(body)

            self.assertIn(status, (400, 403))
            self.assertFalse(response["ok"])
            self.assertIn("error", response)
            self.assertIsNone(state.client_registry.get_client(CLIENT_ID))
            self.assertIsNotNone(state.pairing_store.load_session())

    def test_target_update_requires_known_client(self):
        with self._state() as state:
            service = state.service()
            body = state.target_body(48.85837, 2.294481)
            headers = state.signed_headers(body, client_id="unknown-client")

            status, response = service.update_target(body, headers)

            self.assertEqual(status, 403)
            self.assertFalse(response["ok"])
            self.assertIn("client", response["error"])
            self.assertIsNone(state.target_store.read_target())

    def test_target_update_accepts_valid_signature_and_writes_target(self):
        with self._state() as state:
            service = state.service()
            state.client_registry.add_client(state.client())
            body = state.target_body(48.85837, 2.294481, label="Eiffel Tower")
            headers = state.signed_headers(body)

            status, response = service.update_target(body, headers)

            self.assertEqual(status, 200)
            self.assertTrue(response["ok"])
            self.assertEqual(response["target"]["latitude"], 48.85837)
            self.assertEqual(response["target"]["longitude"], 2.294481)
            self.assertEqual(response["target"]["label"], "Eiffel Tower")
            self.assertEqual(response["target"]["updated_by"], CLIENT_ID)
            stored = state.target_store.read_target()
            self.assertEqual(stored.latitude, 48.85837)
            self.assertEqual(stored.longitude, 2.294481)
            self.assertEqual(stored.label, "Eiffel Tower")
            self.assertEqual(stored.updated_by, CLIENT_ID)

    def test_target_update_rejects_invalid_coordinates(self):
        with self._state() as state:
            service = state.service()
            state.client_registry.add_client(state.client())
            body = state.target_body(91.0, 2.294481)
            headers = state.signed_headers(body)

            status, response = service.update_target(body, headers)

            self.assertEqual(status, 400)
            self.assertFalse(response["ok"])
            self.assertIn("latitude", response["error"])
            self.assertIsNone(state.target_store.read_target())

    def test_target_update_rejects_replayed_nonce(self):
        with self._state() as state:
            service = state.service()
            state.client_registry.add_client(state.client())
            body = state.target_body(48.85837, 2.294481)
            headers = state.signed_headers(body, nonce_text="replay-nonce")

            first_status, first_response = service.update_target(body, headers)
            second_status, second_response = service.update_target(body, headers)

            self.assertEqual(first_status, 200)
            self.assertTrue(first_response["ok"])
            self.assertEqual(second_status, 403)
            self.assertFalse(second_response["ok"])
            self.assertIn("signature", second_response["error"])

    def _state(self):
        return _TemporaryWaypointState()


class _TemporaryWaypointState:
    def __enter__(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.state_dir = Path(self._tmp.name)
        self.target_store = TargetStore(self.state_dir / "target.json")
        self.client_registry = ClientRegistry(self.state_dir / "clients.json")
        self.pairing_store = PairingSessionStore(self.state_dir / "pairing.json")
        self.private_key = Ed25519PrivateKey.generate()
        self.public_key_b64 = self._public_key_b64(self.private_key)
        return self

    def __exit__(self, exc_type, exc, traceback):
        self._tmp.cleanup()

    def service(self):
        return WaypointControlService(
            self.target_store,
            self.client_registry,
            self.pairing_store,
        )

    def client(self):
        return WaypointClient(
            id=CLIENT_ID,
            name=CLIENT_NAME,
            public_key=self.public_key_b64,
            created_at="2026-06-16T12:00:00Z",
        )

    def create_pairing_session(self):
        expires_at = datetime.now(timezone.utc) + timedelta(minutes=5)
        self.pairing_store.create_session(SERVER_URL, PAIRING_CODE, expires_at)

    def pair_body(self, *, code):
        return json.dumps(
            {
                "code": code,
                "client_id": CLIENT_ID,
                "client_name": CLIENT_NAME,
                "public_key": self.public_key_b64,
            },
            separators=(",", ":"),
        ).encode("utf-8")

    def target_body(self, latitude, longitude, *, label=None):
        payload = {
            "latitude": latitude,
            "longitude": longitude,
        }
        if label is not None:
            payload["label"] = label
        return json.dumps(payload, separators=(",", ":")).encode("utf-8")

    def signed_headers(self, body, *, client_id=CLIENT_ID, nonce_text="abc123nonce"):
        timestamp = int(time.time())
        nonce = b64url_encode(nonce_text.encode("utf-8"))
        canonical = canonical_request("POST", "/v1/target", timestamp, nonce, body)
        signature = self.private_key.sign(canonical.encode("utf-8"))
        return {
            "X-Waypoint-Client": client_id,
            "X-Waypoint-Timestamp": str(timestamp),
            "X-Waypoint-Nonce": nonce,
            "X-Waypoint-Signature": b64url_encode(signature),
        }

    def _public_key_b64(self, private_key):
        public_key = private_key.public_key().public_bytes(
            encoding=Encoding.Raw,
            format=PublicFormat.Raw,
        )
        return b64url_encode(public_key)


if __name__ == "__main__":
    unittest.main()
