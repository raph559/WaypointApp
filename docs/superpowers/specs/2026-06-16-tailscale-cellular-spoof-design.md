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

Use the VPS as a Tailscale subnet router for only the current IP routes behind Apple location lookup hosts.

```text
iPhone on cellular
  -> Tailscale route for gs-loc IP only
  -> VPS tailscale0
  -> transparent redirect for routed gs-loc:443 packets
  -> mitmproxy transparent listener
  -> Waypoint WLOC rewriter
  -> real Apple gs-loc server
```

Traffic that does not match the advertised Apple location routes does not enter the VPS and continues through normal cellular networking.

## VPS Components

### Tailscale Subnet Router

The VPS advertises narrow `/32` routes for IPv4 addresses currently returned by:

- `gs-loc.apple.com`
- `gs-loc-cn.apple.com`

IPv6 is disabled for this first version unless testing shows iOS prefers IPv6 for `gs-loc`. Starting with IPv4 only keeps the firewall rules and route updates easier to reason about.

### Route Updater

A small updater service runs on the VPS and periodically:

1. Resolves `gs-loc.apple.com` and `gs-loc-cn.apple.com`.
2. Filters results to public IPv4 addresses.
3. Updates a local ipset/nft set containing those destination IPs.
4. Updates Tailscale advertised routes to the same `/32` list.
5. Restarts or reapplies Tailscale routing only when the route set changes.

The updater should keep the previous route set if DNS resolution fails, to avoid breaking spoofing during temporary DNS issues.

### Transparent MITM Proxy

mitmproxy runs on the VPS in transparent mode with:

- The existing `tools/mitm_location_probe.py` addon.
- `WAYPOINT_SPOOF_ENABLED=1`.
- `WAYPOINT_SPOOF_LAT` and `WAYPOINT_SPOOF_LON` set to the active target.
- An allow-list restricted to `gs-loc.apple.com` and `gs-loc-cn.apple.com`.

The VPS firewall redirects only destination port `443` traffic whose destination IP is in the Apple-location ipset/nft set to mitmproxy's transparent listener.

### Certificate Trust

The iPhone must trust the mitmproxy CA used by the VPS.

Preferred path:

- Copy the laptop's existing mitmproxy CA to the VPS, so the already-installed iPhone trust profile continues to work.

Fallback path:

- Install and trust the VPS mitmproxy CA on the iPhone.

## iPhone Configuration

The iPhone stays connected to Tailscale, but does not use the VPS as an exit node.

Required tailnet behavior:

- iPhone accepts subnet routes from the VPS.
- iPhone routes only advertised Apple location `/32` destinations through Tailscale.
- Normal internet traffic remains direct over cellular.

If Tailscale iOS refuses or inconsistently applies these narrow routes, implementation stops and reports that the preferred design is blocked. Exit-node mode remains a manual fallback choice, not automatic behavior.

## Security And Reliability

- Do not expose mitmproxy on the public internet.
- Bind mitmproxy locally or to the VPS network namespace used for transparent interception.
- Keep the Tailscale ACL limited so only the iPhone can reach the spoofing path.
- Keep the MITM allow-list narrow to avoid breaking apps with certificate pinning.
- Log spoof events, route updates, and DNS failures.
- Avoid dumping large unrelated traffic bodies; only WLOC request/response bodies should be logged.

## Failure Modes

- Apple changes `gs-loc` IPs: the updater refreshes advertised routes and firewall sets.
- iPhone uses IPv6 for `gs-loc`: initial implementation will miss the traffic; add IPv6 route/firewall support if observed.
- Tailscale iOS does not use subnet routes for internet destinations: stop and ask whether to use exit-node mode despite routing all phone traffic through the VPS.
- mitmproxy CA mismatch: WLOC TLS fails until the iPhone trusts the correct CA.
- Apple validates additional location channels: spoofing may still work partially; inspect VPS logs for non-WLOC location traffic.

## Testing Plan

1. Confirm Tailscale device connectivity between iPhone and VPS.
2. Advertise one temporary test `/32` route from the VPS and verify the iPhone routes only that IP through Tailscale.
3. Start mitmproxy transparent mode on the VPS and confirm it receives only `gs-loc` traffic.
4. Trigger location refresh on cellular with Wi-Fi off.
5. Confirm VPS logs show `SPOOFED WLOC RESPONSE`.
6. Confirm Maps/Compass moves to the target coordinate.
7. Confirm Snapchat/TikTok continue loading while spoofing is active.
8. Confirm disabling the route updater or Tailscale restores normal direct behavior.

## Fallback Criterion

The implementation should first attempt the subnet-route design. If iPhone Tailscale does not honor public `/32` subnet routes reliably, do not keep iterating blindly. Report the evidence and ask before switching to an exit-node design.
