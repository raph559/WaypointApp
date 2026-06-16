"""Persistent target state for Waypoint location spoofing."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path
import tempfile
import threading
from typing import Any


class CoordinateValidationError(ValueError):
    """Raised when latitude or longitude is outside valid Earth coordinate bounds."""


@dataclass(frozen=True)
class WaypointTarget:
    latitude: float
    longitude: float
    label: str | None
    updated_at: str | None
    updated_by: str | None


@dataclass(frozen=True)
class WaypointClient:
    id: str
    name: str
    public_key: str
    created_at: str


def validate_coordinates(latitude: Any, longitude: Any) -> tuple[float, float]:
    if isinstance(latitude, bool) or isinstance(longitude, bool):
        raise CoordinateValidationError("latitude and longitude must be numeric")

    try:
        validated_latitude = float(latitude)
        validated_longitude = float(longitude)
    except (TypeError, ValueError) as exc:
        raise CoordinateValidationError("latitude and longitude must be numeric") from exc

    if not math.isfinite(validated_latitude) or not math.isfinite(validated_longitude):
        raise CoordinateValidationError("latitude and longitude must be finite")
    if not -90.0 <= validated_latitude <= 90.0:
        raise CoordinateValidationError("latitude must be between -90 and 90")
    if not -180.0 <= validated_longitude <= 180.0:
        raise CoordinateValidationError("longitude must be between -180 and 180")
    return validated_latitude, validated_longitude


def load_target_coordinates(path: str | Path) -> tuple[float, float] | None:
    target = TargetStore(path).read_target()
    if target is None:
        return None
    return target.latitude, target.longitude


class TargetStore:
    def __init__(self, path: str | Path) -> None:
        self.path = Path(path)

    def read_target(self) -> WaypointTarget | None:
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
        except (FileNotFoundError, UnicodeDecodeError, json.JSONDecodeError, OSError):
            return None

        if not isinstance(data, dict):
            return None

        try:
            latitude, longitude = validate_coordinates(data.get("latitude"), data.get("longitude"))
        except CoordinateValidationError:
            return None

        return WaypointTarget(
            latitude=latitude,
            longitude=longitude,
            label=_optional_string(data.get("label")),
            updated_at=_optional_string(data.get("updated_at")),
            updated_by=_optional_string(data.get("updated_by")),
        )

    def write_target(
        self,
        latitude: Any,
        longitude: Any,
        label: str | None = None,
        updated_by: str | None = None,
    ) -> WaypointTarget:
        validated_latitude, validated_longitude = validate_coordinates(latitude, longitude)
        target = WaypointTarget(
            latitude=validated_latitude,
            longitude=validated_longitude,
            label=label,
            updated_at=datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            updated_by=updated_by,
        )

        self.path.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "latitude": target.latitude,
            "longitude": target.longitude,
            "label": target.label,
            "updated_at": target.updated_at,
            "updated_by": target.updated_by,
        }

        _write_json_atomic(self.path, payload)

        return target


class ClientRegistry:
    # V1 runs one Python API service process; this protects in-process registry updates.
    # It is not a cross-process file lock.
    _lock = threading.RLock()

    def __init__(self, path: str | Path) -> None:
        self.path = Path(path)

    def add_client(self, client: WaypointClient) -> None:
        with self._lock:
            clients = self._read_clients()
            if any(existing.id == client.id for existing in clients):
                raise ValueError(f"duplicate client id: {client.id}")

            clients.append(client)
            _write_json_atomic(
                self.path,
                {"clients": [_client_to_dict(existing) for existing in clients]},
            )

    def get_client(self, client_id: str) -> WaypointClient | None:
        with self._lock:
            for client in self._read_clients():
                if client.id == client_id:
                    return client
        return None

    def has_clients(self) -> bool:
        return bool(self.list_clients())

    def list_clients(self) -> list[WaypointClient]:
        with self._lock:
            return self._read_clients()

    def _read_clients(self) -> list[WaypointClient]:
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
        except (FileNotFoundError, UnicodeDecodeError, json.JSONDecodeError, OSError):
            return []

        if not isinstance(data, dict):
            return []

        raw_clients = data.get("clients")
        if not isinstance(raw_clients, list):
            return []

        clients: list[WaypointClient] = []
        for raw_client in raw_clients:
            client = _client_from_dict(raw_client)
            if client is not None:
                clients.append(client)
        return clients


class PairingSessionStore:
    # V1 runs one Python API service process; this protects one-time consumes in-process.
    # It is not a cross-process file lock.
    _consume_lock = threading.Lock()

    def __init__(self, path: str | Path) -> None:
        self.path = Path(path)

    def create_session(self, server_url: str, code: str, expires_at: str | datetime) -> None:
        _write_json_atomic(
            self.path,
            {
                "server_url": server_url,
                "code": code,
                "expires_at": _datetime_text(expires_at),
            },
        )

    def load_session(self) -> dict[str, str] | None:
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
        except (FileNotFoundError, UnicodeDecodeError, json.JSONDecodeError, OSError):
            return None

        if not isinstance(data, dict):
            return None

        server_url = data.get("server_url")
        code = data.get("code")
        expires_at = data.get("expires_at")
        if not all(isinstance(value, str) for value in (server_url, code, expires_at)):
            return None

        return {
            "server_url": server_url,
            "code": code,
            "expires_at": expires_at,
        }

    def consume_code(self, code: str, now: datetime | int | float | None = None) -> bool:
        with self._consume_lock:
            session = self.load_session()
            if session is None or session["code"] != code:
                return False

            expires_at = _parse_datetime(session["expires_at"])
            if expires_at is None:
                return False

            if _coerce_datetime(now) >= expires_at:
                self._delete_session()
                return False

            self._delete_session()
            return True

    def _delete_session(self) -> None:
        try:
            self.path.unlink()
        except FileNotFoundError:
            pass


def _optional_string(value: Any) -> str | None:
    if value is None or isinstance(value, str):
        return value
    return None


def _client_to_dict(client: WaypointClient) -> dict[str, str]:
    return {
        "id": client.id,
        "name": client.name,
        "public_key": client.public_key,
        "created_at": client.created_at,
    }


def _client_from_dict(value: Any) -> WaypointClient | None:
    if not isinstance(value, dict):
        return None

    client_id = value.get("id")
    name = value.get("name")
    public_key = value.get("public_key")
    created_at = value.get("created_at")
    if not all(isinstance(item, str) for item in (client_id, name, public_key, created_at)):
        return None

    return WaypointClient(
        id=client_id,
        name=name,
        public_key=public_key,
        created_at=created_at,
    )


def _write_json_atomic(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)

    temp_path: str | None = None
    try:
        with tempfile.NamedTemporaryFile(
            "w",
            delete=False,
            dir=path.parent,
            encoding="utf-8",
        ) as temp_file:
            temp_path = temp_file.name
            json.dump(payload, temp_file, ensure_ascii=False)
            temp_file.write("\n")
        os.replace(temp_path, path)
    except Exception:
        if temp_path is not None:
            try:
                os.unlink(temp_path)
            except OSError:
                pass
        raise


def _datetime_text(value: str | datetime) -> str:
    if isinstance(value, datetime):
        return _coerce_datetime(value).isoformat().replace("+00:00", "Z")
    return value


def _parse_datetime(value: str) -> datetime | None:
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return _coerce_datetime(parsed)


def _coerce_datetime(value: datetime | int | float | None) -> datetime:
    if value is None:
        return datetime.now(timezone.utc)
    if isinstance(value, datetime):
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)
    return datetime.fromtimestamp(value, timezone.utc)
