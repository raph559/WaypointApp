# Waypoint

Waypoint is an iPhone map controller for a VPS-hosted location spoofing setup. The iOS app lets you choose a target coordinate, pairs with your VPS over Tailscale, and sends signed coordinate updates to the server. The VPS is responsible for the spoofing path.

The SideStore build is app-only. It does not install a VPN profile and does not require a paid Network Extension entitlement.

## Status

- iOS controller app: map search, draggable/tappable target pin, QR/code pairing, manual coordinate entry
- VPS control API: pairing sessions, signed target updates, replay protection, target state file
- Spoofing engine: mitmproxy-based Apple Wi-Fi location response rewriting
- Deployment: systemd services and helper scripts for a Tailscale-connected VPS
- Build: Codemagic workflows for unsigned SideStore IPA and signed ad hoc IPA

## Architecture

```text
iPhone
  Waypoint app
    |
    | signed HTTPS/HTTP request over Tailscale
    v
VPS
  waypoint-control.service
    |
    | writes /etc/waypoint/target.json
    v
  waypoint-mitm.service
    |
    | rewrites Apple Wi-Fi location responses toward target coordinate
    v
iOS Location Services
```

Waypoint is split intentionally:

- The iPhone app is only the controller UI.
- Tailscale provides the private network path between iPhone and VPS.
- The VPS stores the selected coordinate and runs the MITM/rewrite logic.
- The control API accepts coordinate changes only from paired clients with signed requests.

## Repository Layout

```text
App/                         SwiftUI iPhone controller
Resources/                   App Info.plist and assets wiring
deploy/waypoint-vps/         systemd units, env examples, VPS helper scripts
docs/tailscale-cellular.md   end-to-end VPS and cellular runbook
tools/                       control API, pairing CLI, MITM/proxy tooling, tests
codemagic.yaml               Codemagic iOS build workflows
project.yml                  XcodeGen project definition
```

## Build the iOS App

### Codemagic

Use the standalone repository:

- Repository: `raph559/Waypoint-iOS`
- Branch: `main`
- Workflow: `SideStore Unsigned IPA`

The workflow generates the Xcode project with XcodeGen, builds the app-only controller target, and exports `Waypoint-unsigned.ipa`.

Install the generated IPA with SideStore. Keep the official Tailscale app installed and connected before using Waypoint.

### Local Mac Build

```bash
brew install xcodegen
xcodegen generate
open location-spoofer.xcodeproj
```

In Xcode, select the `location-spoofer` scheme and build for your iPhone.

## Deploy the VPS

Follow the full runbook:

[docs/tailscale-cellular.md](docs/tailscale-cellular.md)

Minimum flow:

```bash
cd /opt/waypoint
sudo systemctl start waypoint-control.service
curl -s http://100.78.165.105:8765/v1/health
```

Expected health response:

```json
{"ok": true}
```

Then start the MITM service after the VPS environment and routing are configured:

```bash
sudo systemctl start waypoint-mitm.service
```

## Pair the App

Generate a pairing QR/code on the VPS:

```bash
sudo -u waypoint-mitm /opt/waypoint/.venv/bin/python /opt/waypoint/tools/waypoint_pair.py --runtime-dir /run/waypoint --server http://100.78.165.105:8765
```

On the iPhone:

1. Connect Tailscale.
2. Open Waypoint.
3. Tap the gear icon.
4. Tap `Pair Device`.
5. Scan the QR code or enter the server URL and pairing code manually.

After pairing, choose a location on the map and tap `Set Location`.

Validate on the VPS:

```bash
cat /etc/waypoint/target.json
```

## Security Model

Pairing is temporary and explicit:

- `tools/waypoint_pair.py` creates a short-lived pairing session.
- The app generates a client key and registers its public key during pairing.
- Coordinate updates are signed by the app.
- The control API verifies client ID, timestamp, nonce, and signature.
- Replayed update requests are rejected.

Unauthenticated `/v1/health` is intentionally liveness-only and returns no pairing or target state.

## Testing

Python tests cover the control API, request signing, target state, and Apple location response rewriting:

```bash
python -m unittest tools.test_waypoint_state tools.test_waypoint_security tools.test_waypoint_control_api tools.test_proxy_probe tools.test_apple_wloc
```

Compile-check the Python tools:

```bash
python -m py_compile tools/waypoint_state.py tools/waypoint_security.py tools/waypoint_control_api.py tools/waypoint_pair.py tools/mitm_location_probe.py tools/apple_wloc.py
```

## Notes

Waypoint is intended for personal testing on devices and networks you control. Location spoofing can violate app terms or local rules depending on how it is used.

## License

This project is licensed under the GNU Affero General Public License v3.0. See [LICENSE](LICENSE).
