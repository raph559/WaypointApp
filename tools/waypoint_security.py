"""Signed request helpers for Waypoint control messages."""

from __future__ import annotations

import base64
import binascii
import hashlib
import re
import secrets
import threading
import time
from collections.abc import Mapping
from typing import Any

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey


CROCKFORD_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
_B64URL_RE = re.compile(r"^[A-Za-z0-9_-]*$")


def b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def b64url_decode(text: str) -> bytes:
    if not isinstance(text, str):
        raise ValueError("base64url value must be text")
    if "=" in text:
        raise ValueError("base64url padding is not allowed")
    if len(text) % 4 == 1:
        raise ValueError("invalid base64url length")
    if not _B64URL_RE.fullmatch(text):
        raise ValueError("invalid base64url characters")

    padding = "=" * (-len(text) % 4)
    try:
        return base64.b64decode((text + padding).encode("ascii"), altchars=b"-_", validate=True)
    except binascii.Error as exc:
        raise ValueError("invalid base64url value") from exc


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical_request(method: str, path: str, timestamp: int, nonce: str, body: bytes) -> str:
    return "\n".join(
        [
            "WAYPOINT-V1",
            method,
            path,
            str(timestamp),
            nonce,
            sha256_hex(body),
        ]
    )


def generate_pairing_code() -> str:
    value = secrets.randbits(64)
    chars: list[str] = []
    for _ in range(10):
        chars.append(CROCKFORD_ALPHABET[value & 31])
        value >>= 5
    return "".join(chars)


class NonceReplayCache:
    def __init__(self, window_seconds: int = 120) -> None:
        self.window_seconds = window_seconds
        self._seen: dict[tuple[str, str], float] = {}
        self._lock = threading.Lock()

    def check_and_store(self, client_id: str, nonce: str, now: int | float) -> bool:
        with self._lock:
            current = float(now)
            cutoff = current - self.window_seconds
            expired = [key for key, seen_at in self._seen.items() if seen_at < cutoff]
            for key in expired:
                del self._seen[key]

            key = (client_id, nonce)
            seen_at = self._seen.get(key)
            if seen_at is not None and seen_at >= cutoff:
                return False

            self._seen[key] = current
            return True


class SignedRequestVerifier:
    def __init__(self, allowed_skew_seconds: int = 120) -> None:
        self.allowed_skew_seconds = allowed_skew_seconds
        self.nonce_cache = NonceReplayCache(window_seconds=allowed_skew_seconds)

    def verify(
        self,
        public_key_b64: str,
        method: str,
        path: str,
        body: bytes,
        headers: Mapping[str, str],
        now: int | float | None = None,
    ) -> bool:
        try:
            client_id = _required_header(headers, "X-Waypoint-Client")
            timestamp_text = _required_header(headers, "X-Waypoint-Timestamp")
            nonce = _required_header(headers, "X-Waypoint-Nonce")
            signature_b64 = _required_header(headers, "X-Waypoint-Signature")
            if not timestamp_text.isdigit():
                return False
            timestamp = int(timestamp_text)
        except (KeyError, TypeError, ValueError):
            return False

        current = time.time() if now is None else float(now)
        # V1 rejects future-dated requests entirely so a nonce cannot be first seen early
        # and then replayed after a first-seen replay window expires.
        if timestamp > current:
            return False
        if current - timestamp > self.allowed_skew_seconds:
            return False

        try:
            public_key = Ed25519PublicKey.from_public_bytes(b64url_decode(public_key_b64))
            signature = b64url_decode(signature_b64)
            b64url_decode(nonce)
            canonical = canonical_request(method, path, timestamp, nonce, body).encode("utf-8")
            public_key.verify(signature, canonical)
        except (binascii.Error, InvalidSignature, TypeError, ValueError):
            return False

        return self.nonce_cache.check_and_store(client_id, nonce, current)


def _required_header(headers: Mapping[str, str], name: str) -> str:
    value: Any = headers[name]
    if not isinstance(value, str) or value == "":
        raise ValueError(f"missing header {name}")
    return value
