# Waypoint Map Controller Design

## Goal

Build Waypoint as a sideloaded iPhone app that feels like a real location spoofer: open a map, move/search a pin, tap Set Location, and have other apps see that spoofed location through the VPS-based WLOC MITM path.

The app does not install or manage an iOS VPN profile. Tailscale remains the transport layer, and the VPS remains the spoofing engine.

## User Experience

### Main Screen

Waypoint opens directly to a full map.

Required controls:

- Search field for places and addresses.
- Draggable pin for the target coordinate.
- Current target coordinate display.
- Set Location button.
- Status chip showing whether the app is paired with the VPS, whether the VPS is reachable, and when the target was last applied.

Expected flow:

1. User opens Waypoint.
2. User searches for a place or drags the pin.
3. User taps Set Location.
4. App sends a signed coordinate update to the VPS over Tailscale.
5. VPS atomically updates the active spoof target.
6. mitmproxy uses the new target for subsequent Apple WLOC responses.

### Settings Screen

Settings are secondary, not the main app experience.

Required controls:

- Pair VPS.
- Show paired VPS address.
- Show paired client name/id.
- Test connection.
- Unpair.
- Manual coordinate entry as a fallback for precise numeric input.

The old VPN installation/connect controls should be removed from the primary UI because this app will not have the paid Apple Network Extension entitlement needed to install a VPN profile reliably.

## Architecture

```text
Waypoint iPhone app
  -> MapKit map/search/pin UI
  -> Keychain-held Ed25519 private key
  -> signed HTTP request over Tailscale
  -> VPS control API on Tailscale IP 100.78.165.105
  -> atomic target state file
  -> mitmproxy WLOC addon reads current target
  -> Apple WLOC response rewritten to selected coordinate
```

Tailscale must be connected on the iPhone. The app talks to the VPS at its Tailscale IP, not its public internet IP.

## VPS Components

### Control API

Add a small Python control API service on the VPS.

Recommended listener:

- Host: `100.78.165.105` if binding directly to the Tailscale address is reliable.
- Fallback host: `0.0.0.0` with firewall rules allowing the API port only from `tailscale0`.
- Port: `8765`.

Endpoints:

- `GET /v1/health`
  - Returns service status, active target, and whether at least one client is paired.
  - Does not expose private keys or pairing codes.
- `POST /v1/pair`
  - Used only during an active pairing session.
  - Registers the app public key.
- `POST /v1/target`
  - Requires a valid signed request from a paired app key.
  - Updates the active spoof target.

### Dynamic Target State

The active target should be stored outside the systemd environment so it can change without restarting mitmproxy.

Target file:

```text
/etc/waypoint/target.json
```

Shape:

```json
{
  "latitude": 48.85837,
  "longitude": 2.294481,
  "label": "Eiffel Tower",
  "updated_at": "2026-06-16T12:00:00Z",
  "updated_by": "iphone171"
}
```

Writes must be atomic:

1. Write a temporary file in the same directory.
2. Flush and close.
3. Rename over `target.json`.

The mitmproxy addon should read `WAYPOINT_TARGET_FILE=/etc/waypoint/target.json`. It should keep the existing environment-coordinate behavior as a fallback for local laptop testing.

### Client Registry

Paired clients should be stored on the VPS:

```text
/etc/waypoint/clients.json
```

Shape:

```json
{
  "clients": [
    {
      "id": "iphone171",
      "name": "Raph iPhone",
      "public_key": "base64url-ed25519-public-key",
      "created_at": "2026-06-16T12:00:00Z"
    }
  ]
}
```

The VPS never stores the app private key.

## Pairing

Pairing is QR-first with code fallback.

### VPS Pairing Command

Add a VPS command:

```bash
waypoint-pair
```

Behavior:

1. Creates a one-time pairing session.
2. Generates a random 10-character Crockford base32 pairing code from at least 64 bits of randomness.
3. Expires after 5 minutes.
4. Prints a QR code and a manual fallback code.
5. Shows the VPS Tailscale address and API port.

QR payload:

```json
{
  "type": "waypoint-pair-v1",
  "server": "http://100.78.165.105:8765",
  "code": "7K4M9Q2XPA",
  "expires_at": "2026-06-16T12:05:00Z"
}
```

Manual fallback:

- VPS address: `http://100.78.165.105:8765`
- Pairing code: same code shown in the QR payload

### App Pairing Flow

1. User opens Settings -> Pair VPS.
2. App scans the QR code with the camera.
3. If camera scanning fails, user can enter VPS address and pairing code.
4. App generates an Ed25519 keypair on-device.
5. App stores the private key in the iOS Keychain.
6. App sends the public key, a generated client id, and pairing code to `POST /v1/pair`.
7. VPS verifies the active code and stores the public key.
8. App stores the server URL and paired client id.

Pairing should be one-time. Re-running `waypoint-pair` creates a fresh temporary session.

Active pairing sessions may live in memory when `waypoint-pair` talks to a running API service, or in a root-owned runtime file:

```text
/run/waypoint/pairing.json
```

The implementation should choose the simpler path that fits the final API process model.

## Signed Requests

All target updates must be signed with Ed25519.

The app sends:

- `X-Waypoint-Client`: paired client id.
- `X-Waypoint-Timestamp`: Unix timestamp in seconds.
- `X-Waypoint-Nonce`: random 128-bit nonce encoded base64url.
- `X-Waypoint-Signature`: base64url Ed25519 signature.

Canonical string:

```text
WAYPOINT-V1
POST
/v1/target
<unix_timestamp>
<base64url_nonce>
<sha256_hex_of_request_body>
```

The VPS must reject:

- Unknown client ids.
- Invalid signatures.
- Timestamps outside a 120-second skew window.
- Reused nonces within the replay window.
- Invalid latitude/longitude ranges.
- Request bodies larger than the small expected JSON payload.

Target update body:

```json
{
  "latitude": 48.85837,
  "longitude": 2.294481,
  "label": "Eiffel Tower"
}
```

## iOS Implementation

### Map UI

Use SwiftUI with MapKit.

Use CryptoKit's `Curve25519.Signing.PrivateKey` and `Curve25519.Signing.PublicKey` APIs for Ed25519 signing on iOS.

Main pieces:

- `WaypointMapView`
  - Owns map camera position, selected coordinate, and pin interactions.
- `PlaceSearchViewModel`
  - Uses MapKit search/completion APIs.
- `WaypointControlClient`
  - Talks to the VPS API.
- `WaypointSigner`
  - Builds canonical strings and signs requests.
- `WaypointKeychain`
  - Stores private key material, server URL, and paired client id.
- `PairingView`
  - QR scanner and manual fallback form.

### Key Storage

Use iOS Keychain for the private signing key. UserDefaults is acceptable for non-secret values such as the last selected coordinate, server URL, and paired client id.

### Networking

The app should use the paired server URL, initially:

```text
http://100.78.165.105:8765
```

This is acceptable for V1 because the traffic runs inside Tailscale's encrypted tunnel and the update request is signed. The API must not be exposed on the public internet.

## Error Handling

Map screen errors:

- Not paired: Set Location is disabled and opens Pair VPS.
- Tailscale disconnected or VPS unreachable: show VPS Offline and keep selected coordinate locally.
- Signature rejected: show Pairing Invalid and require re-pairing.
- Coordinate rejected: keep pin, show validation message.

VPS errors:

- Missing target file: mitmproxy keeps env fallback or default Eiffel Tower target.
- Corrupt target file: ignore the corrupt file, log the error, keep last valid target in memory if present.
- API restart: target persists because it is stored in `/etc/waypoint/target.json`.

## Testing

Python tests:

- Pairing code creation, expiration, and one-time use.
- Client registry persistence.
- Ed25519 signature verification.
- Timestamp skew rejection.
- Nonce replay rejection.
- Coordinate validation.
- Atomic target file update.
- mitmproxy target file fallback behavior.

Swift tests where feasible:

- Canonical request string construction.
- Signature header creation.
- Coordinate validation.
- Pairing payload parsing.

Manual validation:

1. Start Tailscale on iPhone.
2. Run `waypoint-pair` on VPS.
3. Pair app by scanning QR.
4. Pick Eiffel Tower on map and tap Set Location.
5. Confirm VPS `target.json` updates.
6. Trigger Maps/Compass location refresh.
7. Confirm VPS logs show `SPOOFED WLOC RESPONSE`.
8. Confirm iPhone appears at the selected coordinate.
9. Pick a different city in Waypoint and confirm subsequent WLOC responses use the new coordinate without restarting mitmproxy.

## Out Of Scope For V1

- Route management from the iPhone app.
- Installing or managing a VPN profile from the iPhone app.
- Public internet API access.
- Multi-user account management.
- Routes or GPX playback.
- Background continuous location movement.
- App Store distribution.

## Implementation Order

1. Add VPS dynamic target loading to the existing mitmproxy addon.
2. Add Python control API with pairing and signed target updates.
3. Add VPS deploy assets for the API service and pairing command.
4. Replace primary iOS UI with map-first controller.
5. Add iOS keychain/signing/API client.
6. Add pairing UI with QR scanner and manual fallback.
7. Update runbook and Codemagic build notes.
