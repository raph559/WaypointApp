# Waypoint Map Controller Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Waypoint as a sideloaded map-first iPhone controller that sets the active spoof coordinate on the VPS over Tailscale using QR/code pairing and Ed25519 signed requests.

**Architecture:** The VPS runs a small Python control API on the Tailscale interface, stores paired public keys in `/etc/waypoint/clients.json`, and atomically writes the active target to `/etc/waypoint/target.json`. The existing mitmproxy addon reads that target file on each WLOC rewrite, while the iOS app uses SwiftUI MapKit, CryptoKit, and Keychain to pair with the VPS and sign coordinate updates.

**Tech Stack:** Python 3 standard library, `cryptography`, `qrcode`, `unittest`, mitmproxy addon hooks, SwiftUI, MapKit, CryptoKit, Security/Keychain, AVFoundation QR scanning, XcodeGen, Codemagic.

---

## Spec And Existing Context

- Approved design: `docs/superpowers/specs/2026-06-16-waypoint-map-controller-design.md`
- Existing WLOC rewrite code: `tools/apple_wloc.py`
- Existing mitmproxy addon: `tools/mitm_location_probe.py`
- Existing app entry point: `App/ContentView.swift`
- Existing coordinate storage: `App/LocationConfiguration.swift`
- Current build source of truth should become `project.yml`; Codemagic must generate `location-spoofer.xcodeproj` before building.
- The old Packet Tunnel extension files may remain in the repo, but the V1 map-controller app must not depend on or build the extension for the SideStore unsigned IPA workflow.

## File Structure

- Create: `tools/waypoint_state.py`
  - Coordinate validation, atomic JSON target writes, client registry persistence, dynamic target loading.
- Create: `tools/waypoint_security.py`
  - Base64url helpers, canonical request string, Ed25519 verification, nonce replay cache, pairing code generation.
- Create: `tools/waypoint_control_api.py`
  - HTTP server with `/v1/health`, `/v1/pair`, and `/v1/target`.
- Create: `tools/waypoint_pair.py`
  - CLI that creates a short-lived pairing session and prints QR plus manual fallback.
- Create: `tools/test_waypoint_state.py`
  - Unit tests for target file and registry behavior.
- Create: `tools/test_waypoint_security.py`
  - Unit tests for signed request verification, timestamp skew, nonce replay, and pairing codes.
- Create: `tools/test_waypoint_control_api.py`
  - Unit tests for HTTP endpoints.
- Modify: `tools/mitm_location_probe.py`
  - Load target coordinates from `WAYPOINT_TARGET_FILE` with environment-coordinate fallback.
- Modify: `tools/test_proxy_probe.py`
  - Add tests for target-file based WLOC rewrite configuration.
- Create: `deploy/waypoint-vps/waypoint-spoof.env.example`
  - MITM service environment with dynamic target file path.
- Create: `deploy/waypoint-vps/waypoint-mitm.service`
  - systemd unit for the transparent MITM proxy.
- Create: `deploy/waypoint-vps/waypoint-transparent-iptables.sh`
  - Firewall/NAT helper for Tailscale-only transparent MITM and control API access.
- Create: `deploy/waypoint-vps/verify-vps.sh`
  - VPS verification helper for Tailscale, firewall, control API, and MITM logs.
- Create: `deploy/waypoint-vps/waypoint-control.env.example`
  - API service environment.
- Create: `deploy/waypoint-vps/waypoint-control.service`
  - systemd unit for the control API.
- Create: `App/WaypointModels.swift`
  - Coordinates, health response, pairing payload, API errors.
- Create: `App/WaypointSigner.swift`
  - CryptoKit key generation, canonical string, request signing.
- Create: `App/WaypointKeychain.swift`
  - Store/load/delete private signing key.
- Create: `App/WaypointSettingsStore.swift`
  - Store non-secret pairing settings and last selected coordinate.
- Create: `App/WaypointControlClient.swift`
  - Health, pair, and signed target update requests.
- Create: `App/WaypointMapView.swift`
  - Map-first UI and selected pin state.
- Create: `App/PlaceSearchViewModel.swift`
  - MapKit search and completion behavior.
- Create: `App/PairingView.swift`
  - QR scanner entry and manual fallback pairing form.
- Create: `App/QRCodeScannerView.swift`
  - AVFoundation-backed QR scanner.
- Create: `App/SettingsView.swift`
  - Paired server, test connection, unpair, manual coordinate input.
- Modify: `App/ContentView.swift`
  - Replace VPN tabs with map-first navigation.
- Modify: `App/LocationConfiguration.swift`
  - Keep or replace as non-secret coordinate persistence used by the new app.
- Modify: `Resources/Info.plist`
  - Add camera usage text for QR scanning.
- Modify: `project.yml`
  - Make `location-spoofer` an app-only map controller target; stop embedding/building `location-spoofer-tunnel` for V1.
- Modify: `codemagic.yaml`
  - Install/use XcodeGen, remove Go tunnel build from the unsigned workflow, build the generated app-only project.
- Modify: `README.md`
  - Document the new Tailscale/VPS controller architecture and pairing flow.
- Create: `docs/tailscale-cellular.md`
  - Add control API, pairing, and map app validation steps.

## Task 1: Dynamic Target State And MITM Integration

**Files:**
- Create: `tools/waypoint_state.py`
- Create: `tools/test_waypoint_state.py`
- Modify: `tools/mitm_location_probe.py`
- Modify: `tools/test_proxy_probe.py`

- [ ] **Step 1: Write target-state unit tests**

Create `tools/test_waypoint_state.py` with tests named exactly:

```python
import json
import tempfile
import unittest
from pathlib import Path

from tools.waypoint_state import (
    CoordinateValidationError,
    TargetStore,
    load_target_coordinates,
    validate_coordinates,
)


class WaypointStateTests(unittest.TestCase):
    def test_validate_coordinates_accepts_valid_values(self):
        self.assertEqual(validate_coordinates(48.85837, 2.294481), (48.85837, 2.294481))

    def test_validate_coordinates_rejects_out_of_range_values(self):
        with self.assertRaises(CoordinateValidationError):
            validate_coordinates(91.0, 2.0)
        with self.assertRaises(CoordinateValidationError):
            validate_coordinates(48.0, 181.0)

    def test_target_store_writes_and_reads_target(self):
        with tempfile.TemporaryDirectory() as tmp:
            store = TargetStore(Path(tmp) / "target.json")
            store.write_target(48.85837, 2.294481, label="Eiffel Tower", updated_by="test-phone")

            data = json.loads((Path(tmp) / "target.json").read_text(encoding="utf-8"))
            self.assertEqual(data["latitude"], 48.85837)
            self.assertEqual(data["longitude"], 2.294481)
            self.assertEqual(data["label"], "Eiffel Tower")
            self.assertEqual(data["updated_by"], "test-phone")

            loaded = store.read_target()
            self.assertEqual(loaded.latitude, 48.85837)
            self.assertEqual(loaded.longitude, 2.294481)

    def test_load_target_coordinates_returns_none_for_missing_or_corrupt_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "target.json"
            self.assertIsNone(load_target_coordinates(path))
            path.write_text("{broken", encoding="utf-8")
            self.assertIsNone(load_target_coordinates(path))
```

- [ ] **Step 2: Write MITM target-file tests**

Add this test to `tools/test_proxy_probe.py`:

```python
    def test_rewrites_wloc_response_from_target_file(self):
        body = self.build_wloc_response_body("aa:bb:cc:dd:ee:ff", 50.1, 2.1)
        with tempfile.TemporaryDirectory() as tmp:
            target_file = Path(tmp) / "target.json"
            target_file.write_text(
                '{"latitude":48.85837,"longitude":2.294481,"label":"Eiffel Tower"}',
                encoding="utf-8",
            )

            rewritten, rewritten_count = rewrite_wloc_response_if_configured(
                "gs-loc.apple.com",
                "/clls/wloc",
                body,
                {"WAYPOINT_TARGET_FILE": str(target_file)},
            )

        self.assertEqual(rewritten_count, 1)
        [location] = extract_wifi_locations_from_response_body(rewritten)
        self.assertEqual(round(location["latitude"], 6), 48.85837)
        self.assertEqual(round(location["longitude"], 6), 2.294481)
```

Also import `Path` and `tempfile` at the top of `tools/test_proxy_probe.py`.

- [ ] **Step 3: Verify RED**

Run:

```powershell
python -m unittest tools.test_waypoint_state tools.test_proxy_probe
```

Expected: failures importing `tools.waypoint_state` or missing target-file behavior.

- [ ] **Step 4: Implement target state module**

Create `tools/waypoint_state.py` with:

- `CoordinateValidationError(ValueError)`.
- Frozen dataclass `WaypointTarget(latitude: float, longitude: float, label: str | None, updated_at: str | None, updated_by: str | None)`.
- `validate_coordinates(latitude, longitude) -> tuple[float, float]`.
- `load_target_coordinates(path: str | Path) -> tuple[float, float] | None`.
- `TargetStore(path).read_target() -> WaypointTarget | None`.
- `TargetStore(path).write_target(latitude, longitude, label=None, updated_by=None) -> WaypointTarget`.
- Atomic writes using `tempfile.NamedTemporaryFile(delete=False, dir=path.parent)` and `os.replace`.
- UTC timestamps using `datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")`.

- [ ] **Step 5: Wire mitmproxy addon to target file**

Modify `tools/mitm_location_probe.py`:

- Add `TARGET_FILE_ENV = "WAYPOINT_TARGET_FILE"`.
- Update `spoof_coordinates_from_env` to first read `WAYPOINT_TARGET_FILE` via `load_target_coordinates`.
- Preserve existing `WAYPOINT_SPOOF_ENABLED`, `WAYPOINT_SPOOF_LAT`, and `WAYPOINT_SPOOF_LON` fallback behavior.
- If target file is missing or corrupt, return the env fallback instead of raising.

- [ ] **Step 6: Verify GREEN**

Run:

```powershell
python -m unittest tools.test_waypoint_state tools.test_proxy_probe tools.test_apple_wloc
```

Expected: all tests pass.

- [ ] **Step 7: Commit Task 1**

Run:

```powershell
git add tools/waypoint_state.py tools/test_waypoint_state.py tools/mitm_location_probe.py tools/test_proxy_probe.py
git commit -m "Add dynamic Waypoint target state"
```

## Task 2: Signed Request Security And Pairing State

**Files:**
- Create: `tools/waypoint_security.py`
- Create: `tools/test_waypoint_security.py`
- Modify: `tools/waypoint_state.py`
- Modify: `tools/test_waypoint_state.py`

- [ ] **Step 1: Write security tests**

Create `tools/test_waypoint_security.py` with tests for:

```python
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat
```

Test names:

- `test_base64url_round_trips_without_padding`
- `test_canonical_request_includes_body_hash`
- `test_verify_signed_request_accepts_valid_signature`
- `test_verify_signed_request_rejects_bad_signature`
- `test_verify_signed_request_rejects_old_timestamp`
- `test_verify_signed_request_rejects_reused_nonce`
- `test_pairing_code_is_crockford_base32_and_ten_characters`

Use a fixed body `b'{"latitude":48.85837,"longitude":2.294481,"label":"Eiffel Tower"}'`, method `POST`, path `/v1/target`, timestamp `1_781_607_200`, and nonce text `abc123nonce`.

- [ ] **Step 2: Write client registry tests**

Extend `tools/test_waypoint_state.py` with tests named:

- `test_client_registry_adds_and_loads_client`
- `test_client_registry_rejects_duplicate_client_id`
- `test_pairing_session_store_accepts_active_code_once`
- `test_pairing_session_store_rejects_expired_code`

The tests should use temporary directories and assert JSON files are written under the requested paths.

- [ ] **Step 3: Verify RED**

Run:

```powershell
python -m unittest tools.test_waypoint_security tools.test_waypoint_state
```

Expected: failures importing missing security and registry classes.

- [ ] **Step 4: Implement `tools/waypoint_security.py`**

Implement:

- `b64url_encode(data: bytes) -> str`.
- `b64url_decode(text: str) -> bytes`.
- `sha256_hex(data: bytes) -> str`.
- `canonical_request(method, path, timestamp, nonce, body) -> str` using the exact format from the design spec.
- `generate_pairing_code() -> str` using Crockford alphabet `0123456789ABCDEFGHJKMNPQRSTVWXYZ`, length 10, from `secrets.randbits(64)`.
- `NonceReplayCache(window_seconds=120)` with `check_and_store(client_id, nonce, now) -> bool`.
- `SignedRequestVerifier(allowed_skew_seconds=120)` with `verify(public_key_b64, method, path, body, headers, now=None) -> bool`.

Use `cryptography.hazmat.primitives.asymmetric.ed25519.Ed25519PublicKey`.

- [ ] **Step 5: Extend `tools/waypoint_state.py`**

Add:

- Frozen dataclass `WaypointClient(id: str, name: str, public_key: str, created_at: str)`.
- `ClientRegistry(path)` with `add_client`, `get_client`, `has_clients`, and `list_clients`.
- `PairingSessionStore(path)` with `create_session(server_url, code, expires_at)`, `load_session`, `consume_code(code, now=None)`.

Use atomic writes for registry and pairing session files.

- [ ] **Step 6: Verify GREEN**

Run:

```powershell
python -m unittest tools.test_waypoint_security tools.test_waypoint_state
```

Expected: all tests pass.

- [ ] **Step 7: Commit Task 2**

Run:

```powershell
git add tools/waypoint_security.py tools/test_waypoint_security.py tools/waypoint_state.py tools/test_waypoint_state.py
git commit -m "Add Waypoint signed request security"
```

## Task 3: VPS Control API And Pairing CLI

**Files:**
- Create: `tools/waypoint_control_api.py`
- Create: `tools/waypoint_pair.py`
- Create: `tools/test_waypoint_control_api.py`

- [ ] **Step 1: Write control API tests**

Create `tools/test_waypoint_control_api.py` using `unittest` and direct handler/service helpers instead of binding a real network port.

Required tests:

- `test_health_reports_target_and_pairing_state`
- `test_pair_registers_client_with_active_code`
- `test_pair_rejects_invalid_code`
- `test_target_update_requires_known_client`
- `test_target_update_accepts_valid_signature_and_writes_target`
- `test_target_update_rejects_invalid_coordinates`
- `test_target_update_rejects_replayed_nonce`

The tests should create a temporary state directory with:

- `target.json`
- `clients.json`
- `pairing.json`

Use `Ed25519PrivateKey.generate()` to sign target update requests.

- [ ] **Step 2: Verify RED**

Run:

```powershell
python -m unittest tools.test_waypoint_control_api
```

Expected: import failure for `tools.waypoint_control_api`.

- [ ] **Step 3: Implement the API service**

Create `tools/waypoint_control_api.py` with:

- `WaypointControlService(target_store, client_registry, pairing_store, nonce_cache)`.
- `health() -> tuple[int, dict]`.
- `pair(body: bytes) -> tuple[int, dict]`.
- `update_target(body: bytes, headers: Mapping[str, str]) -> tuple[int, dict]`.
- `WaypointRequestHandler(BaseHTTPRequestHandler)` that maps:
  - `GET /v1/health`
  - `POST /v1/pair`
  - `POST /v1/target`
- `main(argv=None)` with args:
  - `--host`, default `100.78.165.105`
  - `--port`, default `8765`
  - `--state-dir`, default `/etc/waypoint`
  - `--runtime-dir`, default `/run/waypoint`

Response JSON should include `{"ok": true}` or `{"ok": false, "error": "message"}`.

- [ ] **Step 4: Implement the pairing CLI**

Create `tools/waypoint_pair.py` with:

- `main(argv=None)`.
- Args:
  - `--server`, default `http://100.78.165.105:8765`
  - `--runtime-dir`, default `/run/waypoint`
  - `--ttl-seconds`, default `300`
- It creates the runtime directory, writes the pairing session, prints:
  - `Waypoint pairing`
  - `Server: ...`
  - `Code: ...`
  - `Expires: ...`
  - QR payload JSON
- If `qrcode` is installed, print an ASCII QR using `qrcode.QRCode().print_ascii(invert=True)`.
- If `qrcode` is not installed, print `QR unavailable; use manual code`.

- [ ] **Step 5: Verify GREEN**

Run:

```powershell
python -m unittest tools.test_waypoint_control_api tools.test_waypoint_security tools.test_waypoint_state
python tools/waypoint_pair.py --runtime-dir .\tmp\waypoint-runtime --server http://100.78.165.105:8765
```

Expected: tests pass and the pairing command prints a server, code, expiration, and QR payload.

- [ ] **Step 6: Commit Task 3**

Run:

```powershell
git add tools/waypoint_control_api.py tools/waypoint_pair.py tools/test_waypoint_control_api.py
git commit -m "Add Waypoint VPS control API"
```

## Task 4: VPS Deploy Assets And Runbook

**Files:**
- Create: `deploy/waypoint-vps/waypoint-spoof.env.example`
- Create: `deploy/waypoint-vps/waypoint-mitm.service`
- Create: `deploy/waypoint-vps/waypoint-transparent-iptables.sh`
- Create: `deploy/waypoint-vps/verify-vps.sh`
- Create: `deploy/waypoint-vps/waypoint-control.env.example`
- Create: `deploy/waypoint-vps/waypoint-control.service`
- Create: `docs/tailscale-cellular.md`
- Modify: `README.md`

- [ ] **Step 1: Add MITM deploy assets**

Create directory `deploy/waypoint-vps`.

Create `deploy/waypoint-vps/waypoint-spoof.env.example`:

```env
WAYPOINT_TARGET_FILE=/etc/waypoint/target.json
WAYPOINT_SPOOF_ENABLED=1
WAYPOINT_SPOOF_LAT=48.858370
WAYPOINT_SPOOF_LON=2.294481
PYTHONUNBUFFERED=1
```

Create `deploy/waypoint-vps/waypoint-mitm.service`:

```ini
[Unit]
Description=Waypoint gs-loc transparent MITM
After=network-online.target tailscaled.service
Wants=network-online.target
Requires=tailscaled.service

[Service]
Type=simple
User=waypoint-mitm
Group=waypoint-mitm
WorkingDirectory=/opt/waypoint
EnvironmentFile=/etc/waypoint/waypoint-spoof.env
Environment=HOME=/opt/waypoint
Environment=PYTHONUNBUFFERED=1
ExecStart=/opt/waypoint/.venv/bin/mitmdump --mode transparent --listen-port 8080 --showhost --set block_global=false --set flow_detail=0 --allow-hosts=^gs-loc(-cn)?[.]apple[.]com(:443)?$ -s /opt/waypoint/tools/mitm_location_probe.py
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
```

Create `deploy/waypoint-vps/waypoint-transparent-iptables.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

TAILSCALE_IF="tailscale0"
MITM_PORT="8080"
API_PORT="8765"
CHAIN="WAYPOINT_GSLOC"

if ! ip link show "$TAILSCALE_IF" >/dev/null 2>&1; then
  echo "Missing interface: $TAILSCALE_IF" >&2
  exit 1
fi

sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv4.conf.all.send_redirects=0

iptables -t nat -N "$CHAIN" 2>/dev/null || true
iptables -t nat -F "$CHAIN"
iptables -t nat -A "$CHAIN" -p tcp --dport 443 -j REDIRECT --to-ports "$MITM_PORT"

if ! iptables -t nat -C PREROUTING -i "$TAILSCALE_IF" -p tcp --dport 443 -j "$CHAIN" 2>/dev/null; then
  iptables -t nat -A PREROUTING -i "$TAILSCALE_IF" -p tcp --dport 443 -j "$CHAIN"
fi

if ! iptables -C INPUT -i "$TAILSCALE_IF" -p tcp --dport "$MITM_PORT" -j ACCEPT 2>/dev/null; then
  iptables -I INPUT 1 -i "$TAILSCALE_IF" -p tcp --dport "$MITM_PORT" -j ACCEPT
fi

if ! iptables -C INPUT -i "$TAILSCALE_IF" -p tcp --dport "$API_PORT" -j ACCEPT 2>/dev/null; then
  iptables -I INPUT 1 -i "$TAILSCALE_IF" -p tcp --dport "$API_PORT" -j ACCEPT
fi

if ! iptables -C INPUT -p tcp --dport "$MITM_PORT" -j DROP 2>/dev/null; then
  iptables -A INPUT -p tcp --dport "$MITM_PORT" -j DROP
fi

if ! iptables -C INPUT -p tcp --dport "$API_PORT" -j DROP 2>/dev/null; then
  iptables -A INPUT -p tcp --dport "$API_PORT" -j DROP
fi

iptables -t nat -S | grep "$CHAIN"
```

Create `deploy/waypoint-vps/verify-vps.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "== tailscaled =="
systemctl is-active --quiet tailscaled
systemctl status tailscaled --no-pager --lines=5

echo
echo "== tailscale0 =="
ip link show tailscale0

echo
echo "== IPv4 forwarding =="
sysctl net.ipv4.ip_forward

echo
echo "== NAT rules =="
iptables -t nat -S | grep WAYPOINT_GSLOC

echo
echo "== control API health =="
curl -s http://100.78.165.105:8765/v1/health || true

echo
echo "== waypoint-control =="
systemctl status waypoint-control.service --no-pager --lines=20

echo
echo "== waypoint-mitm =="
systemctl status waypoint-mitm.service --no-pager --lines=20

echo
echo "== recent control logs =="
journalctl -u waypoint-control.service -n 80 --no-pager

echo
echo "== recent mitm logs =="
journalctl -u waypoint-mitm.service -n 80 --no-pager
```

- [ ] **Step 2: Add control API deploy assets**

Create `deploy/waypoint-vps/waypoint-control.env.example`:

```env
WAYPOINT_STATE_DIR=/etc/waypoint
WAYPOINT_RUNTIME_DIR=/run/waypoint
WAYPOINT_CONTROL_HOST=100.78.165.105
WAYPOINT_CONTROL_PORT=8765
PYTHONUNBUFFERED=1
```

Create `deploy/waypoint-vps/waypoint-control.service`:

```ini
[Unit]
Description=Waypoint control API
After=network-online.target tailscaled.service
Wants=network-online.target
Requires=tailscaled.service

[Service]
Type=simple
User=waypoint-mitm
Group=waypoint-mitm
WorkingDirectory=/opt/waypoint
EnvironmentFile=/etc/waypoint/waypoint-control.env
ExecStart=/opt/waypoint/.venv/bin/python /opt/waypoint/tools/waypoint_control_api.py --host ${WAYPOINT_CONTROL_HOST} --port ${WAYPOINT_CONTROL_PORT} --state-dir ${WAYPOINT_STATE_DIR} --runtime-dir ${WAYPOINT_RUNTIME_DIR}
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 3: Update docs**

Create `docs/tailscale-cellular.md` with:

- `pip install mitmproxy cryptography qrcode`.
- Installing `waypoint-control.service`.
- Starting `waypoint-control.service`.
- Running `sudo -u waypoint-mitm /opt/waypoint/.venv/bin/python /opt/waypoint/tools/waypoint_pair.py --runtime-dir /run/waypoint --server http://100.78.165.105:8765`.
- Pairing from the app.
- Validating `cat /etc/waypoint/target.json`.

Update `README.md` to say Waypoint is now a map-first controller for a VPS spoofing engine, not an on-device VPN spoofer.

- [ ] **Step 4: Verify deploy asset text**

Run:

```powershell
Select-String -Path deploy\waypoint-vps\*.service,deploy\waypoint-vps\*.sh,docs\tailscale-cellular.md,README.md -Pattern 'waypoint-control','8765','target.json','waypoint_pair.py' -SimpleMatch
python -m unittest tools.test_waypoint_state tools.test_waypoint_security tools.test_waypoint_control_api tools.test_proxy_probe tools.test_apple_wloc
```

Expected: patterns are present and tests pass.

- [ ] **Step 5: Commit Task 4**

Run:

```powershell
git add deploy/waypoint-vps docs/tailscale-cellular.md README.md
git commit -m "Add Waypoint VPS controller deploy docs"
```

## Task 5: iOS Signing, Storage, And API Client

**Files:**
- Create: `App/WaypointModels.swift`
- Create: `App/WaypointSigner.swift`
- Create: `App/WaypointKeychain.swift`
- Create: `App/WaypointSettingsStore.swift`
- Create: `App/WaypointControlClient.swift`

- [ ] **Step 1: Add models**

Create `WaypointModels.swift` with:

- `struct WaypointCoordinate: Codable, Equatable`
- `struct WaypointTargetRequest: Codable`
- `struct WaypointHealthResponse: Codable`
- `struct WaypointPairingPayload: Codable`
- `struct WaypointPairRequest: Codable`
- `enum WaypointAPIError: LocalizedError`

Use `Double` latitude/longitude and optional `String` label.

- [ ] **Step 2: Add signer**

Create `WaypointSigner.swift` using `CryptoKit`.

Required APIs:

- `static func generatePrivateKey() -> Curve25519.Signing.PrivateKey`
- `static func publicKeyBase64URL(from privateKey: Curve25519.Signing.PrivateKey) -> String`
- `static func canonicalRequest(method:path:timestamp:nonce:body:) -> String`
- `static func signedHeaders(privateKey:clientID:method:path:body:date:) throws -> [String: String]`

The canonical string must exactly match the Python contract:

```text
WAYPOINT-V1
POST
/v1/target
<unix_timestamp>
<base64url_nonce>
<sha256_hex_of_request_body>
```

- [ ] **Step 3: Add Keychain storage**

Create `WaypointKeychain.swift`.

Required APIs:

- `savePrivateKey(_ key: Curve25519.Signing.PrivateKey) throws`
- `loadPrivateKey() throws -> Curve25519.Signing.PrivateKey?`
- `deletePrivateKey() throws`

Use service `com.raph559.waypoint.signing-key` and account `default`.

- [ ] **Step 4: Add settings store**

Create `WaypointSettingsStore.swift` as an `ObservableObject`.

Persist in standard `UserDefaults`:

- `serverURL`
- `clientID`
- `clientName`
- `lastLatitude`
- `lastLongitude`
- `lastLabel`
- `lastAppliedAt`

Expose:

- `var isPaired: Bool`
- `func savePairing(serverURL: String, clientID: String, clientName: String)`
- `func clearPairing()`
- `func saveLastCoordinate(_ coordinate: WaypointCoordinate)`

- [ ] **Step 5: Add API client**

Create `WaypointControlClient.swift`.

Required APIs:

- `init(settings: WaypointSettingsStore, keychain: WaypointKeychain = WaypointKeychain())`
- `func health() async throws -> WaypointHealthResponse`
- `func pair(serverURL: URL, code: String, clientName: String) async throws`
- `func setTarget(_ coordinate: WaypointCoordinate) async throws`

Pairing should generate a key if no key exists, send public key to `/v1/pair`, and save pairing on success.

- [ ] **Step 6: Commit Task 5**

Run:

```powershell
git add App/WaypointModels.swift App/WaypointSigner.swift App/WaypointKeychain.swift App/WaypointSettingsStore.swift App/WaypointControlClient.swift
git commit -m "Add Waypoint iOS control client"
```

## Task 6: Map-First iOS UI And Pairing UI

**Files:**
- Create: `App/WaypointMapView.swift`
- Create: `App/PlaceSearchViewModel.swift`
- Create: `App/PairingView.swift`
- Create: `App/QRCodeScannerView.swift`
- Create: `App/SettingsView.swift`
- Modify: `App/ContentView.swift`
- Modify: `Resources/Info.plist`

- [ ] **Step 1: Add place search model**

Create `PlaceSearchViewModel.swift` using `MapKit`.

It should:

- Publish search text.
- Publish completion results.
- Use `MKLocalSearchCompleter`.
- Convert selected completion into `WaypointCoordinate` using `MKLocalSearch`.

- [ ] **Step 2: Add map view**

Create `WaypointMapView.swift` with:

- `Map` as the primary screen.
- Search field overlay.
- Draggable or tap-to-move pin behavior. If draggable annotation is awkward in SwiftUI Map, use tap-to-place and document it in UI text.
- Coordinate display.
- `Set Location` button that calls `WaypointControlClient.setTarget`.
- Status chip with Paired/Offline/Applied states.
- Toolbar button opening Settings.

- [ ] **Step 3: Add QR scanner**

Create `QRCodeScannerView.swift` using `AVFoundation`.

It should:

- Request camera permission.
- Scan QR metadata objects.
- Return the scanned string to `PairingView`.
- Show manual fallback if permission is denied.

- [ ] **Step 4: Add pairing view**

Create `PairingView.swift`.

It should:

- Parse QR JSON into `WaypointPairingPayload`.
- Offer manual server URL and pairing code fields.
- Call `WaypointControlClient.pair`.
- Show errors and success.

- [ ] **Step 5: Add settings view**

Create `SettingsView.swift`.

It should:

- Show paired server/client.
- Open pairing flow.
- Test connection with `/v1/health`.
- Unpair by clearing Keychain and settings.
- Offer manual coordinate entry that can call `setTarget`.

- [ ] **Step 6: Replace ContentView**

Modify `ContentView.swift`:

- Remove `NetworkExtension` import.
- Remove VPN installation and `NETunnelProviderManager` logic.
- Show `WaypointMapView()` as the root experience.

- [ ] **Step 7: Add camera usage description**

Add to `Resources/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Waypoint uses the camera to scan the VPS pairing QR code.</string>
```

- [ ] **Step 8: Commit Task 6**

Run:

```powershell
git add App/WaypointMapView.swift App/PlaceSearchViewModel.swift App/PairingView.swift App/QRCodeScannerView.swift App/SettingsView.swift App/ContentView.swift Resources/Info.plist
git commit -m "Add Waypoint map-first iOS UI"
```

## Task 7: Build Configuration For App-Only SideStore IPA

**Files:**
- Modify: `project.yml`
- Modify: `codemagic.yaml`
- Modify: `README.md`

- [ ] **Step 1: Update XcodeGen project**

Modify `project.yml`:

- Keep `location-spoofer` application target.
- Remove the `location-spoofer` dependency on `location-spoofer-tunnel`.
- Remove `CODE_SIGN_ENTITLEMENTS: Resources/location-spoofer.entitlements` from the app target.
- Remove `location-spoofer-tunnel` from the `location-spoofer` scheme build targets.
- Keep the old tunnel target definition only for a separate `location-spoofer-tunnel` debug scheme; it must not be part of the `location-spoofer` app scheme or unsigned SideStore workflow.

- [ ] **Step 2: Update Codemagic unsigned workflow**

Modify `codemagic.yaml` unsigned workflow:

- Remove `Ensure Go is available`.
- Remove `Build Go location spoofer library`.
- Add script before package resolution:

```yaml
      - name: Generate Xcode project
        script: |
          if ! command -v xcodegen >/dev/null 2>&1; then
            brew install xcodegen
          fi
          cd "$CM_BUILD_DIR"
          xcodegen generate
```

Keep `xcodebuild build` and IPA packaging.

- [ ] **Step 3: Update README build and usage docs**

README must say:

- SideStore app is a controller.
- It requires the official Tailscale app connected to the tailnet.
- It does not install a VPN profile.
- Run the VPS setup first, then pair with QR/code, then use the map.

- [ ] **Step 4: Verify text and project references**

Run:

```powershell
Select-String -Path project.yml,codemagic.yaml,README.md -Pattern 'xcodegen','location-spoofer-tunnel','NetworkExtension','Pair VPS','Tailscale' -SimpleMatch
python -m unittest tools.test_waypoint_state tools.test_waypoint_security tools.test_waypoint_control_api tools.test_proxy_probe tools.test_apple_wloc
```

Expected:

- `xcodegen` appears in Codemagic.
- `location-spoofer-tunnel` does not appear in the `location-spoofer` scheme build target list.
- Python tests pass.

- [ ] **Step 5: Commit Task 7**

Run:

```powershell
git add project.yml codemagic.yaml README.md
git commit -m "Configure app-only Waypoint build"
```

## Task 8: Final Verification And Handoff

**Files:**
- No planned source changes unless verification reveals a defect.

- [ ] **Step 1: Run full Python tests**

Run:

```powershell
python -m unittest tools.test_waypoint_state tools.test_waypoint_security tools.test_waypoint_control_api tools.test_proxy_probe tools.test_apple_wloc
```

Expected: all tests pass.

- [ ] **Step 2: Run Python compile check**

Run:

```powershell
python -m py_compile tools/waypoint_state.py tools/waypoint_security.py tools/waypoint_control_api.py tools/waypoint_pair.py tools/mitm_location_probe.py tools/apple_wloc.py
```

Expected: no output and exit code `0`.

- [ ] **Step 3: Run local API smoke test**

Run:

```powershell
python tools/waypoint_control_api.py --host 127.0.0.1 --port 8765 --state-dir .\tmp\waypoint-state --runtime-dir .\tmp\waypoint-runtime
```

In another shell:

```powershell
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:8765/v1/health
```

Expected: JSON response with `"ok": true`.

- [ ] **Step 4: Verify git state**

Run:

```powershell
git status --short
git log --oneline -8
```

Expected: no uncommitted files except ignored runtime `tmp/` logs.

- [ ] **Step 5: Push**

Run:

```powershell
git push
```

Expected: `main -> main`.
