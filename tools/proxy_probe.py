#!/usr/bin/env python3
"""Small HTTP proxy probe for checking whether iOS routes location traffic.

This is intentionally not a MITM proxy. It logs proxy targets and tunnels
CONNECT traffic so you can see whether hosts such as gs-loc.apple.com reach the
configured Wi-Fi HTTP proxy at all.
"""

from __future__ import annotations

import argparse
import select
import socket
import socketserver
import sys
import time
from dataclasses import dataclass
from typing import Iterable
from urllib.parse import urlsplit, urlunsplit


LOCATION_HOST_MARKERS = ("gs-loc.apple.com", "gs-loc-cn.apple.com")
MAX_HEADER_BYTES = 65536
SOCKET_TIMEOUT_SECONDS = 20


@dataclass(frozen=True)
class ProxyTarget:
    method: str
    host: str
    port: int


def parse_proxy_target(data: bytes) -> tuple[str, str, int] | None:
    """Parse the target host/port from an HTTP proxy request header."""
    header = data.split(b"\r\n\r\n", 1)[0].decode("iso-8859-1", errors="replace")
    lines = header.split("\r\n")
    if not lines:
        return None

    parts = lines[0].split()
    if len(parts) != 3:
        return None

    method, target, _version = parts
    method = method.upper()

    if method == "CONNECT":
        authority = _parse_authority(target, default_port=443)
        if authority is None:
            return None
        host, port = authority
        return method, host, port

    if target.startswith(("http://", "https://")):
        parsed = urlsplit(target)
        if not parsed.hostname:
            return None
        port = parsed.port or (443 if parsed.scheme == "https" else 80)
        return method, parsed.hostname, port

    host_header = _find_header(lines[1:], "host")
    if not host_header:
        return None
    authority = _parse_authority(host_header, default_port=80)
    if authority is None:
        return None
    host, port = authority
    return method, host, port


def _find_header(lines: Iterable[str], name: str) -> str | None:
    prefix = f"{name.lower()}:"
    for line in lines:
        if line.lower().startswith(prefix):
            return line.split(":", 1)[1].strip()
    return None


def _parse_authority(authority: str, default_port: int) -> tuple[str, int] | None:
    authority = authority.strip()
    if not authority:
        return None

    if authority.startswith("["):
        end = authority.find("]")
        if end == -1:
            return None
        host = authority[1:end]
        rest = authority[end + 1 :]
        if rest.startswith(":"):
            try:
                return host, int(rest[1:])
            except ValueError:
                return None
        return host, default_port

    if ":" in authority:
        host, port_text = authority.rsplit(":", 1)
        try:
            return host, int(port_text)
        except ValueError:
            return None
    return authority, default_port


def read_http_header(conn: socket.socket) -> bytes:
    data = bytearray()
    while b"\r\n\r\n" not in data:
        chunk = conn.recv(4096)
        if not chunk:
            break
        data.extend(chunk)
        if len(data) > MAX_HEADER_BYTES:
            raise ValueError("HTTP header too large")
    return bytes(data)


def is_location_candidate(host: str) -> bool:
    normalized = host.lower().rstrip(".")
    return any(normalized == marker or normalized.endswith("." + marker) for marker in LOCATION_HOST_MARKERS)


def rewrite_absolute_form_request(data: bytes) -> bytes:
    header, separator, body = data.partition(b"\r\n\r\n")
    lines = header.split(b"\r\n")
    if not lines:
        return data

    try:
        request_line = lines[0].decode("iso-8859-1")
        method, target, version = request_line.split()
    except ValueError:
        return data

    if not target.startswith(("http://", "https://")):
        return data

    parsed = urlsplit(target)
    path = urlunsplit(("", "", parsed.path or "/", parsed.query, ""))
    lines[0] = f"{method} {path} {version}".encode("iso-8859-1")
    return b"\r\n".join(lines) + separator + body


class ProxyProbeHandler(socketserver.BaseRequestHandler):
    def handle(self) -> None:
        client = self.request
        client.settimeout(SOCKET_TIMEOUT_SECONDS)

        try:
            initial_data = read_http_header(client)
            parsed = parse_proxy_target(initial_data)
            if parsed is None:
                client.sendall(b"HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n")
                return

            method, host, port = parsed
            log_target(method, host, port, self.client_address)

            with socket.create_connection((host, port), timeout=SOCKET_TIMEOUT_SECONDS) as upstream:
                if method == "CONNECT":
                    client.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
                else:
                    upstream.sendall(rewrite_absolute_form_request(initial_data))
                relay(client, upstream)
        except Exception as exc:
            print(f"[{timestamp()}] error from {self.client_address[0]}: {exc}", flush=True)


def log_target(method: str, host: str, port: int, client_address: tuple[str, int]) -> None:
    marker = " *** LOCATION CANDIDATE ***" if is_location_candidate(host) else ""
    print(f"[{timestamp()}] {client_address[0]} {method} {host}:{port}{marker}", flush=True)


def relay(left: socket.socket, right: socket.socket) -> None:
    sockets = [left, right]
    for sock in sockets:
        sock.setblocking(False)

    while True:
        readable, _, errored = select.select(sockets, [], sockets, SOCKET_TIMEOUT_SECONDS)
        if errored or not readable:
            return

        for source in readable:
            target = right if source is left else left
            try:
                chunk = source.recv(16384)
            except BlockingIOError:
                continue
            if not chunk:
                return
            target.sendall(chunk)


class ThreadingTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True


def timestamp() -> str:
    return time.strftime("%Y-%m-%d %H:%M:%S")


def run_server(host: str, port: int) -> None:
    with ThreadingTCPServer((host, port), ProxyProbeHandler) as server:
        print(f"Waypoint proxy probe listening on {host}:{port}", flush=True)
        print("Set your iPhone Wi-Fi HTTP proxy to this host and port.", flush=True)
        print("Watch for lines containing: *** LOCATION CANDIDATE ***", flush=True)
        print("Press Ctrl+C to stop.", flush=True)
        server.serve_forever()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Log iOS Wi-Fi proxy targets for the Waypoint location test.")
    parser.add_argument("--host", default="0.0.0.0", help="Host/interface to bind. Default: 0.0.0.0")
    parser.add_argument("--port", default=8888, type=int, help="Port to listen on. Default: 8888")
    args = parser.parse_args(argv)

    try:
        run_server(args.host, args.port)
    except KeyboardInterrupt:
        print("\nStopped.", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
