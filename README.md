# Waypoint

Waypoint is now a map-first iPhone controller for a VPS-hosted location spoofing engine. The app selects target coordinates and sends them over Tailscale to the VPS; spoofing happens on the server-side MITM path, not in an on-device Packet Tunnel VPN.

> [!NOTE]
> The original fork attempted on-device VPN spoofing and was rejected from TestFlight. Waypoint's current direction avoids relying on a local Packet Tunnel entitlement by moving spoofing to the VPS.

https://github.com/user-attachments/assets/456d508c-2104-4d10-9458-e58e84b74788

## How it works

I did some research a few years back on how IOS location services worked: <https://github.com/acheong08/apple-corelocation-experiments>

TL;DR: iPhone scans for WIFI access points, sends the list of access points to Apple, Apple tells device where those points are, iPhone triangulates. Waypoint's app is the map controller for the target coordinate, and the VPS/Tailscale spoofing engine runs the Man in the Middle path that rewrites the response with different values for where the access points are. The device then thinks that is where it is.

For cellular use through Tailscale, see [docs/tailscale-cellular.md](docs/tailscale-cellular.md).

## Building this yourself

Waypoint's SideStore app is a controller. It selects coordinates on the map and talks to the VPS control API over the official Tailscale app; the SideStore build does not install a VPN profile or package the old tunnel extension.

1. Install XcodeGen if needed: `brew install xcodegen`.
2. Generate the Xcode project: `xcodegen generate`.
3. Open `./location-spoofer.xcodeproj/` with Xcode.
4. Select the `location-spoofer` scheme.
5. Build and run the app on iPhone.

Before using the app, run the VPS setup first, connect the official Tailscale app to the same tailnet, pair Waypoint with the VPS by QR/code, then use the map to send target coordinates.

## Building with Codemagic

This fork includes `codemagic.yaml` with two workflows:

- `sidestore-unsigned-ipa`: generates the Xcode project with XcodeGen, builds the app-only controller, and packages an unsigned `Waypoint-unsigned.ipa` for SideStore to re-sign.
- `signed-ad-hoc-ipa`: generates the Xcode project with XcodeGen, builds the signed app-only controller, and requires Apple signing profiles for the app bundle only.

For SideStore, install the unsigned IPA as the controller app. Waypoint does not install a VPN profile; keep the official Tailscale app installed, signed in, and connected to the tailnet before opening Waypoint.

## Free Wi-Fi proxy experiment

The SideStore/free-signing path cannot install the Packet Tunnel VPN profile. Before paying for Apple signing, you can test a different route: check whether iOS sends Apple location lookup traffic through the manual Wi-Fi HTTP proxy setting.

Run the probe on a laptop on the same Wi-Fi network as your iPhone:

```bash
python tools/proxy_probe.py --host 0.0.0.0 --port 8888
```

Find the laptop LAN IP, then on iPhone go to:

`Settings > Wi-Fi > your network > Configure Proxy > Manual`

Set:

- Server: your laptop LAN IP
- Port: `8888`
- Authentication: Off

Open Safari on the iPhone and visit any website to confirm traffic appears in the terminal. Then open Maps or another app that triggers a fresh location lookup.

If the terminal logs a line containing `*** LOCATION CANDIDATE ***`, iOS is sending the location lookup through the proxy and a standalone MITM/rewrite proxy is worth building next. If you never see `gs-loc.apple.com`, this free route is probably blocked on your iOS/network setup.

You can also run the probe on a VPS, but do not leave it exposed as a public open proxy. Restrict inbound traffic to your current public IP while testing.

### Standalone MITM rewrite test

After installing and trusting the mitmproxy CA on the iPhone, `tools/mitm_location_probe.py` can rewrite Apple Wi-Fi location responses from `gs-loc.apple.com/clls/wloc`.

PowerShell example:

```powershell
$env:WAYPOINT_SPOOF_ENABLED='1'
$env:WAYPOINT_SPOOF_LAT='48.858370'
$env:WAYPOINT_SPOOF_LON='2.294481'
$mitm = Join-Path $env:APPDATA 'Python\Python314\Scripts\mitmdump.exe'
$allow = '^gs-loc(-cn)?\.apple\.com(:443)?$'
& $mitm --listen-host 0.0.0.0 --listen-port 8888 --set block_global=false --set flow_detail=0 --set connection_strategy=lazy --allow-hosts $allow -s tools\mitm_location_probe.py
```

Keep the iPhone Wi-Fi proxy pointed at the computer or VPS running the proxy. When spoofing triggers, the log prints `SPOOFED WLOC RESPONSE` with the number of Wi-Fi records rewritten.

Keep the allow-list narrow. Apps such as Snapchat and TikTok may pin their TLS certificates; if mitmproxy tries to decrypt their traffic, they can stop loading. The command above tunnels non-Apple-location traffic without rewriting it.

## Usage

Waypoint's active usage flow is the VPS/Tailscale controller path. Follow the VPS setup and pairing runbook in [docs/tailscale-cellular.md](docs/tailscale-cellular.md), then use the SideStore app as the map controller.

1. Run the VPS setup and start `waypoint-control.service` on the Tailscale address, for example `http://100.78.165.105:8765`.
2. Install and connect the official Tailscale app on the iPhone to the same tailnet.
3. Pair VPS: pair the iPhone app with the VPS control API using the QR code or pairing code from `tools/waypoint_pair.py` as described in the runbook.
4. Open Waypoint from SideStore while Tailscale is connected.
5. Choose the target coordinate on the map.
6. Send the selected coordinate to the VPS control API.
7. Validate the VPS target state with `cat /etc/waypoint/target.json`.
8. Keep the VPS MITM path running while testing location updates on the phone.

The old on-device PacketTunnel/VPN profile flow is retired for current Waypoint usage. Do not use the previous steps that installed a VPN profile, visited `mitm.it`, or trusted a local on-device CA as the active setup path.

## Some annoying notes encountered along the way

- To do MITM on IOS, you need to do a weird song and dance. PacketTunnel -> Proxy -> Socks Server.
- See [HACKS.md](./HACKS.md). Apple won't let you upload if you have a `.a` in your bundle
- When you run out of memory in a service, you get SIGKILLED without notice or logs. I spent forever figuring out why I was randomly getting SIGKILLED. Answer is look at the Console app (wayyy to verbose)

## Additional notes

This was partially vibe-coded, kinda, sorta. I wrote [apple-corelocation-experiments](https://github.com/acheong08/apple-corelocation-experiments) and [ios-mitm-demo](https://github.com/acheong08/ios-mitm-demo) by hand and told AI to combine them into 1. I'd say a solid 70% of code is reused and the AI didn't have to do any of the hard parts like reverse engineering. The objective was to test open source models (GLM-4.7 and MiniMax-M2.1) and how far they can go while also getting something useful out of it.

Results were mixed. AI can definitely do UI, but whenever it hit a real roadblock, it'll hullucinate, delete all tests, and try to cheat its way to success. For example, it failed to re-implement my ARPC parsing correctly, and instead of referencing the correct implementation and fixing its own, it tried to delete everything in Go and try to rewrite in Swift. A lot of times, I had to step in and fix whatever it was stuck on before proceeding.

IOS development is hell though and I can see how the lack of proper feedback for runtime issues can cause it to go crazy.

~There are some **known bugs** even I can't figure out how to fix. For some reason, if you connect to another VPN, and try to connect to the location spoofer again, it will fail. You have to go to Settings > VPN and manually select the right profile before turning it on. Not enough references online for me to figure out. I am not an IOS developer and I do not have the time and energy to fix this. Workaround works well enough for my use case.~

Update: Claude Opus 4.5 was able to figure it out in 2 tries after giving it a reference implementation by [Kean](https://github.com/kean/VPN/).
