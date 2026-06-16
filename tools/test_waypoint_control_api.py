from http import HTTPStatus
from io import BytesIO
import json
import tempfile
import time
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

from tools.waypoint_control_api import WaypointControlService, WaypointRequestHandler
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

    def test_pair_rejects_invalid_code_for_existing_client_without_leaking_registration(self):
        with self._state() as state:
            service = state.service()
            state.create_pairing_session()
            state.client_registry.add_client(state.client())
            body = state.pair_body(code="BADCODE123")

            status, response = service.pair(body)

            self.assertEqual(status, 403)
            self.assertFalse(response["ok"])
            self.assertIn("invalid or expired pairing code", response["error"])
            self.assertIsNotNone(state.pairing_store.load_session())

    def test_pair_duplicate_client_consumes_valid_code_after_validation(self):
        with self._state() as state:
            service = state.service()
            state.create_pairing_session()
            state.client_registry.add_client(state.client())
            body = state.pair_body(code=PAIRING_CODE)

            status, response = service.pair(body)

            self.assertEqual(status, 409)
            self.assertFalse(response["ok"])
            self.assertIn("already paired", response["error"])
            self.assertIsNone(state.pairing_store.load_session())

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

    def test_target_update_rejects_non_string_label(self):
        with self._state() as state:
            service = state.service()
            state.client_registry.add_client(state.client())
            body = state.target_body(48.85837, 2.294481, label=123)
            headers = state.signed_headers(body)

            status, response = service.update_target(body, headers)

            self.assertEqual(status, 400)
            self.assertFalse(response["ok"])
            self.assertIn("label", response["error"])
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


class WaypointRequestHandlerTests(unittest.TestCase):
    def test_get_health_route_returns_service_health(self):
        with self._state() as state:
            state.target_store.write_target(48.85837, 2.294481, label="Eiffel Tower")
            response = self._request(state.service(), "GET", "/v1/health")

            self.assertEqual(response.status, HTTPStatus.OK)
            self.assertTrue(response.json["ok"])
            self.assertEqual(response.json["target"]["label"], "Eiffel Tower")

    def test_post_pair_route_forwards_body(self):
        with self._state() as state:
            state.create_pairing_session()
            body = state.pair_body(code=PAIRING_CODE)

            response = self._request(state.service(), "POST", "/v1/pair", body=body)

            self.assertEqual(response.status, HTTPStatus.OK)
            self.assertEqual(response.json, {"ok": True, "client_id": CLIENT_ID})
            self.assertIsNotNone(state.client_registry.get_client(CLIENT_ID))

    def test_post_target_route_forwards_signed_headers(self):
        with self._state() as state:
            state.client_registry.add_client(state.client())
            body = state.target_body(48.85837, 2.294481, label="Eiffel Tower")
            headers = state.signed_headers(body)

            response = self._request(state.service(), "POST", "/v1/target", body=body, headers=headers)

            self.assertEqual(response.status, HTTPStatus.OK)
            self.assertTrue(response.json["ok"])
            self.assertEqual(response.json["target"]["updated_by"], CLIENT_ID)
            stored = state.target_store.read_target()
            self.assertEqual(stored.label, "Eiffel Tower")

    def test_unknown_route_returns_404(self):
        with self._state() as state:
            response = self._request(state.service(), "GET", "/v1/missing")

            self.assertEqual(response.status, HTTPStatus.NOT_FOUND)
            self.assertFalse(response.json["ok"])

    def _state(self):
        return _TemporaryWaypointState()

    def _request(self, service, method, path, *, body=b"", headers=None):
        return _HandlerHarness(service).request(method, path, body=body, headers=headers or {})


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


class _HandlerHarness:
    def __init__(self, service):
        self.service = service

    def request(self, method, path, *, body, headers):
        request_bytes = self._request_bytes(method, path, body, headers)
        socket = _FakeSocket(request_bytes)
        original_service = WaypointRequestHandler.service
        try:
            WaypointRequestHandler.service = self.service
            WaypointRequestHandler(socket, ("127.0.0.1", 1), object())
        finally:
            WaypointRequestHandler.service = original_service
        return _HandlerResponse(socket.output.getvalue())

    def _request_bytes(self, method, path, body, headers):
        lines = [
            f"{method} {path} HTTP/1.1",
            "Host: waypoint.test",
            f"Content-Length: {len(body)}",
        ]
        for name, value in headers.items():
            lines.append(f"{name}: {value}")
        header_bytes = ("\r\n".join(lines) + "\r\n\r\n").encode("ascii")
        return header_bytes + body


class _FakeSocket:
    def __init__(self, request_bytes):
        self.input = BytesIO(request_bytes)
        self.output = BytesIO()

    def makefile(self, mode, buffering=None):
        if "r" in mode:
            return self.input
        if "w" in mode:
            return self.output
        raise ValueError(f"unsupported mode: {mode}")

    def sendall(self, data):
        self.output.write(data)


class _HandlerResponse:
    def __init__(self, response_bytes):
        header_bytes, body = response_bytes.split(b"\r\n\r\n", 1)
        status_line = header_bytes.splitlines()[0].decode("ascii")
        self.status = int(status_line.split(" ", 2)[1])
        self.body = body
        self.json = json.loads(body.decode("utf-8"))


if __name__ == "__main__":
    unittest.main()
