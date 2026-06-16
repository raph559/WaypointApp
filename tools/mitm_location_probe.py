"""mitmproxy addon for logging Apple location/map probe requests.

Run with:
  mitmdump -p 8888 -s tools/mitm_location_probe.py --set flow_detail=0
"""

from __future__ import annotations

from datetime import datetime
import os
from pathlib import Path
import sys
from urllib.parse import quote_plus

from mitmproxy import http

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.apple_wloc import rewrite_wloc_response_body
from tools.waypoint_state import CoordinateValidationError, load_target_coordinates, validate_coordinates


EXACT_LOCATION_HOSTS = {
    "gs-loc.apple.com",
    "gs-loc-cn.apple.com",
    "gsp-ssl.ls.apple.com",
    "wps.apple.com",
    "iphone-ld.apple.com",
}
LOW_LEVEL_POST_DUMP_HOSTS = {
    "gs-loc.apple.com",
    "gs-loc-cn.apple.com",
    "wps.apple.com",
    "iphone-ld.apple.com",
}
BODY_DUMP_DIR = Path("logs/mitm-bodies")
MAX_DUMP_BYTES = 2_000_000
SPOOF_ENABLED_ENV = "WAYPOINT_SPOOF_ENABLED"
SPOOF_LAT_ENV = "WAYPOINT_SPOOF_LAT"
SPOOF_LON_ENV = "WAYPOINT_SPOOF_LON"
TARGET_FILE_ENV = "WAYPOINT_TARGET_FILE"


def is_location_candidate_host(host: str) -> bool:
    normalized = host.lower().rstrip(".")
    if normalized in EXACT_LOCATION_HOSTS:
        return True
    if normalized.endswith(".apple-mapkit.com"):
        return True
    if normalized.endswith(".ls.apple.com") and (
        normalized.startswith("gsp") or normalized.startswith("gspe")
    ):
        return True
    if normalized.startswith("gsp") and normalized.endswith("-ssl.apple.com"):
        return True
    return False


def should_dump_body(host: str, method: str, path: str, body_len: int) -> bool:
    if method.upper() != "POST":
        return False
    if body_len <= 0 or body_len > MAX_DUMP_BYTES:
        return False
    if host.lower().rstrip(".") in LOW_LEVEL_POST_DUMP_HOSTS:
        return True
    return path.startswith(("/dispatcher.arpc", "/clls/wloc", "/hvr/"))


def rewrite_wloc_response_if_configured(
    host: str,
    path: str,
    response_body: bytes,
    environ: dict[str, str] | os._Environ[str] = os.environ,
) -> tuple[bytes, int]:
    if host.lower().rstrip(".") not in {"gs-loc.apple.com", "gs-loc-cn.apple.com"}:
        return response_body, 0
    if path != "/clls/wloc":
        return response_body, 0

    coordinates = spoof_coordinates_from_env(environ)
    if coordinates is None:
        return response_body, 0

    latitude, longitude = coordinates
    return rewrite_wloc_response_body(response_body, latitude, longitude)


def spoof_coordinates_from_env(environ: dict[str, str] | os._Environ[str]) -> tuple[float, float] | None:
    target_file = environ.get(TARGET_FILE_ENV)
    if target_file:
        coordinates = load_target_coordinates(target_file)
        if coordinates is not None:
            return coordinates

    enabled = environ.get(SPOOF_ENABLED_ENV, "").strip().lower()
    if enabled not in {"1", "true", "yes", "on"}:
        return None
    try:
        return validate_coordinates(environ[SPOOF_LAT_ENV], environ[SPOOF_LON_ENV])
    except (KeyError, CoordinateValidationError):
        return None


def request(flow: http.HTTPFlow) -> None:
    host = flow.request.pretty_host
    if not is_location_candidate_host(host):
        return

    body_len = len(flow.request.raw_content or b"")
    content_type = flow.request.headers.get("content-type", "-")
    print(
        f"[{timestamp()}] LOCATION REQUEST "
        f"{flow.request.method} https://{host}{flow.request.path} "
        f"content-type={content_type} body={body_len}",
        flush=True,
    )
    dump_body("request", flow.request.method, host, flow.request.path, flow.request.raw_content or b"")


def http_connect(flow: http.HTTPFlow) -> None:
    host = flow.request.pretty_host
    if not is_location_candidate_host(host):
        return

    print(
        f"[{timestamp()}] LOCATION CONNECT "
        f"{host}:{flow.request.port}",
        flush=True,
    )


def http_connect_error(flow: http.HTTPFlow) -> None:
    host = flow.request.pretty_host
    if not is_location_candidate_host(host):
        return

    error = flow.error.msg if flow.error else "unknown error"
    print(
        f"[{timestamp()}] LOCATION CONNECT ERROR "
        f"{host}:{flow.request.port} error={error}",
        flush=True,
    )


def response(flow: http.HTTPFlow) -> None:
    host = flow.request.pretty_host
    if not is_location_candidate_host(host):
        return

    body_len = len(flow.response.raw_content or b"") if flow.response else 0
    status = flow.response.status_code if flow.response else "-"
    content_type = flow.response.headers.get("content-type", "-") if flow.response else "-"
    print(
        f"[{timestamp()}] LOCATION RESPONSE "
        f"{status} https://{host}{flow.request.path} "
        f"content-type={content_type} body={body_len}",
        flush=True,
    )
    dump_body("response", flow.request.method, host, flow.request.path, flow.response.raw_content or b"")
    rewrite_wloc_flow_response(flow, host)


def rewrite_wloc_flow_response(flow: http.HTTPFlow, host: str) -> None:
    if flow.response is None:
        return

    response_body = flow.response.get_content(strict=False) or b""
    rewritten, rewritten_count = rewrite_wloc_response_if_configured(
        host,
        flow.request.path,
        response_body,
    )
    if rewritten_count == 0:
        return

    flow.response.set_content(rewritten)
    coordinates = spoof_coordinates_from_env(os.environ)
    target = "unknown"
    if coordinates is not None:
        target = f"{coordinates[0]:.6f},{coordinates[1]:.6f}"
    print(
        f"[{timestamp()}] SPOOFED WLOC RESPONSE "
        f"https://{host}{flow.request.path} wifi_devices={rewritten_count} "
        f"target={target}",
        flush=True,
    )


def dump_body(kind: str, method: str, host: str, path: str, body: bytes) -> None:
    if not should_dump_body(host, method, path, len(body)):
        return

    BODY_DUMP_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    safe_path = quote_plus(path[:120]).replace("%", "_")
    out_path = BODY_DUMP_DIR / f"{stamp}-{kind}-{host}-{safe_path}.bin"
    out_path.write_bytes(body)
    print(f"[{timestamp()}] DUMPED {kind.upper()} BODY {out_path} bytes={len(body)}", flush=True)


def timestamp() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")
