"""HTTP control API for Waypoint target updates and pairing."""

from __future__ import annotations

import argparse
from collections.abc import Mapping
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from json import JSONDecodeError
from pathlib import Path
import sys
from typing import Any
from urllib.parse import urlparse

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.waypoint_security import (
    NonceReplayCache,
    SignedRequestVerifier,
    b64url_decode,
)
from tools.waypoint_state import (
    ClientRegistry,
    CoordinateValidationError,
    PairingSessionStore,
    TargetStore,
    WaypointClient,
    WaypointTarget,
)


TARGET_PATH = "/v1/target"
MAX_BODY_BYTES = 64 * 1024


class WaypointControlService:
    def __init__(
        self,
        target_store: TargetStore,
        client_registry: ClientRegistry,
        pairing_store: PairingSessionStore,
        nonce_cache: NonceReplayCache | None = None,
    ) -> None:
        self.target_store = target_store
        self.client_registry = client_registry
        self.pairing_store = pairing_store
        self.verifier = SignedRequestVerifier()
        if nonce_cache is not None:
            self.verifier.nonce_cache = nonce_cache

    def health(self) -> tuple[int, dict[str, Any]]:
        return 200, {
            "ok": True,
        }

    def pair(self, body: bytes) -> tuple[int, dict[str, Any]]:
        payload, error = _json_object(body)
        if error is not None:
            return _error(400, error)

        code = _required_text(payload, "code")
        client_id = _required_text(payload, "client_id")
        client_name = _required_text(payload, "client_name")
        public_key = _required_text(payload, "public_key")
        if None in (code, client_id, client_name, public_key):
            return _error(400, "missing required pairing field")

        try:
            public_key_bytes = b64url_decode(public_key)
        except ValueError:
            return _error(400, "invalid public_key")
        if len(public_key_bytes) != 32:
            return _error(400, "invalid public_key")

        if not self.pairing_store.consume_code(code):
            return _error(403, "invalid or expired pairing code")
        if self.client_registry.get_client(client_id) is not None:
            return _error(409, "client already paired")

        try:
            self.client_registry.add_client(
                WaypointClient(
                    id=client_id,
                    name=client_name,
                    public_key=public_key,
                    created_at=_utc_now_text(),
                )
            )
        except ValueError:
            return _error(409, "client already paired")
        return 200, {"ok": True, "client_id": client_id}

    def update_target(
        self,
        body: bytes,
        headers: Mapping[str, str],
    ) -> tuple[int, dict[str, Any]]:
        client_id = _header(headers, "X-Waypoint-Client")
        if client_id is None:
            return _error(403, "unknown client")

        client = self.client_registry.get_client(client_id)
        if client is None:
            return _error(403, "unknown client")

        if not isinstance(body, bytes):
            return _error(400, "request body must be bytes")

        if not self.verifier.verify(client.public_key, "POST", TARGET_PATH, body, headers):
            return _error(403, "invalid signature or replayed nonce")

        payload, error = _json_object(body)
        if error is not None:
            return _error(400, error)

        label = None
        if "label" in payload:
            if not isinstance(payload["label"], str):
                return _error(400, "label must be a string")
            label = payload["label"]

        try:
            target = self.target_store.write_target(
                payload.get("latitude"),
                payload.get("longitude"),
                label=label,
                updated_by=client_id,
            )
        except CoordinateValidationError as exc:
            return _error(400, str(exc))

        return 200, {"ok": True, "target": _target_to_dict(target)}


class WaypointRequestHandler(BaseHTTPRequestHandler):
    service: WaypointControlService | None = None
    server_version = "WaypointControlAPI/1.0"

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path == "/v1/health":
            self._send(*self._service().health())
            return
        self._send(*_error(404, "not found"))

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        body, error = self._read_body()
        if error is not None:
            self._send(*_error(400, error))
            return

        if path == "/v1/pair":
            self._send(*self._service().pair(body))
            return
        if path == TARGET_PATH:
            self._send(*self._service().update_target(body, self.headers))
            return
        self._send(*_error(404, "not found"))

    def _service(self) -> WaypointControlService:
        if self.service is None:
            raise RuntimeError("WaypointRequestHandler.service is not configured")
        return self.service

    def _read_body(self) -> tuple[bytes, str | None]:
        content_length = self.headers.get("Content-Length", "0")
        try:
            length = int(content_length)
        except (TypeError, ValueError):
            return b"", "invalid Content-Length"
        if length < 0:
            return b"", "invalid Content-Length"
        if length > MAX_BODY_BYTES:
            return b"", "request body too large"
        return self.rfile.read(length), None

    def _send(self, status: int, payload: dict[str, Any]) -> None:
        response = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(response)))
        self.end_headers()
        self.wfile.write(response)

    def log_message(self, format: str, *args: Any) -> None:
        return


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run the Waypoint VPS control API.")
    parser.add_argument("--host", default="100.78.165.105")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--state-dir", default="/etc/waypoint")
    parser.add_argument("--runtime-dir", default="/run/waypoint")
    args = parser.parse_args(argv)

    state_dir = Path(args.state_dir)
    runtime_dir = Path(args.runtime_dir)
    service = WaypointControlService(
        TargetStore(state_dir / "target.json"),
        ClientRegistry(state_dir / "clients.json"),
        PairingSessionStore(runtime_dir / "pairing.json"),
        NonceReplayCache(),
    )
    WaypointRequestHandler.service = service

    server = ThreadingHTTPServer((args.host, args.port), WaypointRequestHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


def _json_object(body: bytes) -> tuple[dict[str, Any], str | None]:
    if not isinstance(body, bytes):
        return {}, "request body must be bytes"
    try:
        payload = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, JSONDecodeError):
        return {}, "invalid JSON body"
    if not isinstance(payload, dict):
        return {}, "JSON body must be an object"
    return payload, None


def _required_text(payload: dict[str, Any], key: str) -> str | None:
    value = payload.get(key)
    if not isinstance(value, str) or value == "":
        return None
    return value


def _header(headers: Mapping[str, str], name: str) -> str | None:
    try:
        value = headers[name]
    except (KeyError, TypeError):
        return None
    if not isinstance(value, str) or value == "":
        return None
    return value


def _target_to_dict(target: WaypointTarget | None) -> dict[str, Any] | None:
    if target is None:
        return None
    return {
        "latitude": target.latitude,
        "longitude": target.longitude,
        "label": target.label,
        "updated_at": target.updated_at,
        "updated_by": target.updated_by,
    }


def _utc_now_text() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _error(status: int, message: str) -> tuple[int, dict[str, Any]]:
    return status, {"ok": False, "error": message}


if __name__ == "__main__":
    raise SystemExit(main())
