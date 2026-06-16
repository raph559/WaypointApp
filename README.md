# Waypoint

Waypoint is a fork of `acheong08/ios-location-spoofer`, a standalone iOS app that attempts to spoof location without jailbreaks by using a local Packet Tunnel VPN extension.

> [!NOTE]
> The original app was rejected from TestFlight. For best odds, install it directly on your own device. A free Apple ID may install the app through SideStore, but the Packet Tunnel entitlement may still prevent the VPN/spoofing part from working.

https://github.com/user-attachments/assets/456d508c-2104-4d10-9458-e58e84b74788

## How it works

I did some research a few years back on how IOS location services worked: <https://github.com/acheong08/apple-corelocation-experiments>

TL;DR: iPhone scans for WIFI access points, sends the list of access points to Apple, Apple tells device where those points are, iPhone triangulates. What you can do here is have a VPN that does a Man in the Middle attack and rewrite the response with different values for where the access points are. The device then thinks that is where it is.

> MITM and processing are all done on device. No network connections are made by the app. It is safe to use...

## Building this yourself

- Go to `./GoSpoofer/` and run `make.sh`
- Open `./location-spoofer.xcodeproj/` with XCode
- Select a paid developer account (Required. PacketTunnel is a paid API)
- Run on iPhone?

## Building with Codemagic

This fork includes `codemagic.yaml` with two workflows:

- `sidestore-unsigned-ipa`: builds an unsigned `Waypoint-unsigned.ipa` for SideStore to re-sign.
- `signed-ad-hoc-ipa`: builds a signed ad hoc IPA if Codemagic has Apple profiles for `com.raph559.waypoint` and `com.raph559.waypoint.tunnel`.

For SideStore, install the unsigned IPA and keep app extensions enabled when prompted. If the app opens but the VPN profile cannot install or connect, the likely blocker is the missing `packet-tunnel-provider` entitlement on the SideStore-signed app.

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
$allow = '.*(gs-loc\.apple\.com|gs-loc-cn\.apple\.com|wps\.apple\.com|iphone-ld\.apple\.com|apple-mapkit\.com|gsp.*\.ls\.apple\.com|gspe.*\.ls\.apple\.com|gsp.*-ssl\.apple\.com).*'
& $mitm --listen-host 0.0.0.0 --listen-port 8888 --set block_global=false --set flow_detail=0 --allow-hosts $allow -s tools\mitm_location_probe.py
```

Keep the iPhone Wi-Fi proxy pointed at the computer or VPS running the proxy. When spoofing triggers, the log prints `SPOOFED WLOC RESPONSE` with the number of Wi-Fi records rewritten.

## Usage

1. Open app
2. Go to "Location"
3. Enter a GPS coordinate or choose a preset
4. Go to VPN
5. Install profile
6. Connect to VPN
7. Go to Safari
8. Go to <http://mitm.it>
9. Download profile
10. Go to settings
11. Enable profile
12. Go to General > About > Certificate Trust Settings and enable Waypoint CA
13. Turn off and on location services
14. Go to maps and see it working

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
