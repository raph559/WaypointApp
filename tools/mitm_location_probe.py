"""mitmproxy addon for logging Apple location/map probe requests.

Run with:
  mitmdump -p 8888 -s tools/mitm_location_probe.py --set flow_detail=0
"""

from __future__ import annotations

from datetime import datetime
from pathlib import Path
from urllib.parse import quote_plus

from mitmproxy import http


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
    return False


def should_dump_body(host: str, method: str, path: str, body_len: int) -> bool:
    if method.upper() != "POST":
        return False
    if body_len <= 0 or body_len > MAX_DUMP_BYTES:
        return False
    if host.lower().rstrip(".") in LOW_LEVEL_POST_DUMP_HOSTS:
        return True
    return path.startswith(("/dispatcher.arpc", "/clls/wloc", "/hvr/"))


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
