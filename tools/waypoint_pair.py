"""Create a Waypoint pairing session for mobile clients."""

from __future__ import annotations

import argparse
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import sys

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.waypoint_security import generate_pairing_code
from tools.waypoint_state import PairingSessionStore


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Create a Waypoint pairing code.")
    parser.add_argument("--server", default="http://100.78.165.105:8765")
    parser.add_argument("--runtime-dir", default="/run/waypoint")
    parser.add_argument("--ttl-seconds", type=int, default=300)
    args = parser.parse_args(argv)

    if args.ttl_seconds <= 0:
        parser.error("--ttl-seconds must be positive")

    runtime_dir = Path(args.runtime_dir)
    runtime_dir.mkdir(parents=True, exist_ok=True)

    code = generate_pairing_code()
    expires_at = datetime.now(timezone.utc) + timedelta(seconds=args.ttl_seconds)
    expires_text = expires_at.isoformat().replace("+00:00", "Z")

    store = PairingSessionStore(runtime_dir / "pairing.json")
    store.create_session(args.server, code, expires_text)

    payload = {
        "server_url": args.server,
        "code": code,
        "expires_at": expires_text,
    }
    payload_json = json.dumps(payload, separators=(",", ":"))

    print("Waypoint pairing")
    print(f"Server: {args.server}")
    print(f"Code: {code}")
    print(f"Expires: {expires_text}")
    print("QR payload JSON")
    print(payload_json)
    _print_qr(payload_json)
    return 0


def _print_qr(payload_json: str) -> None:
    try:
        import qrcode
    except ImportError:
        print("QR unavailable; use manual code.")
        return

    qr = qrcode.QRCode()
    qr.add_data(payload_json)
    qr.make(fit=True)
    qr.print_ascii(invert=True)


if __name__ == "__main__":
    raise SystemExit(main())
