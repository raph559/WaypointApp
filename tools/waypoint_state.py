"""Persistent target state for Waypoint location spoofing."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path
import tempfile
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


def validate_coordinates(latitude: Any, longitude: Any) -> tuple[float, float]:
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

        temp_path: str | None = None
        try:
            with tempfile.NamedTemporaryFile(
                "w",
                delete=False,
                dir=self.path.parent,
                encoding="utf-8",
            ) as temp_file:
                temp_path = temp_file.name
                json.dump(payload, temp_file, ensure_ascii=False)
                temp_file.write("\n")
            os.replace(temp_path, self.path)
        except Exception:
            if temp_path is not None:
                try:
                    os.unlink(temp_path)
                except OSError:
                    pass
            raise

        return target


def _optional_string(value: Any) -> str | None:
    if value is None or isinstance(value, str):
        return value
    return None
