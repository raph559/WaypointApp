# Tailscale Cellular Location Spoof Design

## Goal

Make Waypoint work on iPhone cellular data without keeping the laptop on, while avoiding a full-device exit-node VPN through the VPS.

The target behavior is:

- Only Apple CoreLocation lookup traffic for `gs-loc.apple.com` and `gs-loc-cn.apple.com` is routed to the VPS.
- Snapchat, TikTok, Google, and other normal traffic stay direct over cellular.
- The VPS rewrites Apple WLOC responses using the existing `tools/mitm_location_probe.py` and `tools/apple_wloc.py` logic.
- The iPhone continues to trust the mitmproxy CA used by the spoofing proxy.

## Current Baseline

The laptop proof of concept works with:

- iPhone Wi-Fi manual proxy pointed at the laptop.
- mitmproxy using a narrow allow-list for `gs-loc.apple.com` and `gs-loc-cn.apple.com`.
- WLOC response rewriting for gzip bodies, Wi-Fi records, auxiliary field `22` records, and horizontal accuracy normalization.

This does not work on cellular directly because iOS does not provide a manual HTTP proxy setting for cellular data. Tailscale can provide the transport path, but should not be used as a full exit node for all phone traffic unless necessary.

## Recommended Architecture

Use the VPS as a Tailscale app connector for only Apple location lookup hosts.

```text
iPhone on cellular
  -> Tailscale app connector route for gs-loc domains only
  -> VPS tailscale0
  -> transparent redirect for routed gs-loc:443 packets
  -> mitmproxy transparent listener
  -> Waypoint WLOC rewriter
  -> real Apple gs-loc server
```

Traffic that does not match the Apple location app connector domains does not enter the VPS and continues through normal cellular networking.

## VPS Components

### Tailscale App Connector

The VPS is configured as a Tailscale app connector for:

- `gs-loc.apple.com`
- `gs-loc-cn.apple.com`

The app connector discovers current destination IPs for these domains and advertises matching routes to the tailnet. This replaces a custom DNS-to-route updater for the first implementation.

### Manual Subnet Route Fallback

If app connectors are unavailable or do not route these domains from iOS as expected, fall back to a small updater service that runs on the VPS and periodically:

1. Resolves `gs-loc.apple.com` and `gs-loc-cn.apple.com`.
2. Filters results to public IPv4 addresses.
3. Updates a local ipset/nft set containing those destination IPs.
4. Updates Tailscale advertised routes to the same `/32` list.
5. Restarts or reapplies Tailscale routing only when the route set changes.

The fallback updater should keep the previous route set if DNS resolution fails, to avoid breaking spoofing during temporary DNS issues.

### Transparent MITM Proxy

mitmproxy runs on the VPS in transparent mode with:

- The existing `tools/mitm_location_probe.py` addon.
- `WAYPOINT_SPOOF_ENABLED=1`.
- `WAYPOINT_SPOOF_LAT` and `WAYPOINT_SPOOF_LON` set to the active target.
- An allow-list restricted to `gs-loc.apple.com` and `gs-loc-cn.apple.com`.

For the Tailscale app connector implementation, the VPS firewall redirects TCP port `443` traffic arriving on `tailscale0` to mitmproxy's transparent listener, because only the configured app connector domains should be routed to the VPS on that path. If logs show unrelated HTTPS traffic arriving on `tailscale0`, tighten this with an explicit ipset/nft destination set or stop and switch to the manual subnet-route fallback.

### Certificate Trust

The iPhone must trust the mitmproxy CA used by the VPS.

Preferred path:

- Copy the laptop's existing mitmproxy CA to the VPS, so the already-installed iPhone trust profile continues to work.

Fallback path:

- Install and trust the VPS mitmproxy CA on the iPhone.

## iPhone Configuration

The iPhone stays connected to Tailscale, but does not use the VPS as an exit node.

Required tailnet behavior:

- iPhone accepts app connector routes from the VPS.
- iPhone routes only Apple location app connector destinations through Tailscale.
- Normal internet traffic remains direct over cellular.

If Tailscale iOS refuses or inconsistently applies these narrow routes, implementation stops and reports that the preferred design is blocked. Manual subnet routes and exit-node mode remain fallback choices, not automatic behavior.

## Security And Reliability

- Do not expose mitmproxy on the public internet.
- Bind mitmproxy locally or to the VPS network namespace used for transparent interception.
- Keep the Tailscale ACL limited so only the iPhone can reach the spoofing path.
- Keep the MITM allow-list narrow to avoid breaking apps with certificate pinning.
- Log spoof events, route updates, and DNS failures.
- Avoid dumping large unrelated traffic bodies; only WLOC request/response bodies should be logged.

## Failure Modes

- Apple changes `gs-loc` IPs: the app connector discovers new routes; manual fallback uses the updater to refresh advertised routes and firewall sets.
- iPhone uses IPv6 for `gs-loc`: initial implementation will miss the traffic; add IPv6 route/firewall support if observed.
- Tailscale iOS does not use app connector routes for internet destinations: stop and ask whether to try manual subnet routes or exit-node mode.
- mitmproxy CA mismatch: WLOC TLS fails until the iPhone trusts the correct CA.
- Apple validates additional location channels: spoofing may still work partially; inspect VPS logs for non-WLOC location traffic.

## Testing Plan

1. Confirm Tailscale device connectivity between iPhone and VPS.
2. Configure a custom Tailscale app connector for `gs-loc.apple.com` and `gs-loc-cn.apple.com`.
3. Confirm app connector route discovery advertises only Apple location destinations.
4. Start mitmproxy transparent mode on the VPS and confirm it receives only `gs-loc` traffic.
5. Trigger location refresh on cellular with Wi-Fi off.
6. Confirm VPS logs show `SPOOFED WLOC RESPONSE`.
7. Confirm Maps/Compass moves to the target coordinate.
8. Confirm Snapchat/TikTok continue loading while spoofing is active.
9. Confirm disabling the app connector or Tailscale restores normal direct behavior.

## Fallback Criterion

The implementation should first attempt the Tailscale app connector design. If iPhone Tailscale does not honor app connector routes reliably, do not keep iterating blindly. Report the evidence and ask before switching to manual subnet routes or an exit-node design.
