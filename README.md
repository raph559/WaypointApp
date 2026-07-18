# Waypoint

Waypoint is a focused SwiftUI proof of concept for selecting a point on a map
and asking iOS's developer location-simulation service to report that point to
Core Location clients. It is designed for an iOS 26 device and an unsigned IPA
that SideStore re-signs during sideloading.

## Status

The mechanism is proven on iOS 26 by StikDebug 3.1.6. This repository is a new,
smaller implementation over the MIT-licensed `idevice` FFI. It still needs a
real Xcode 26 archive build and device validation before being treated as a
release. The Linux development environment used to create this source cannot
compile an iPhone app.

Test unmodified
[`StikDebug 3.1.6`](https://github.com/StephenDev0/StikDebug/releases/tag/3.1.6)
on the exact iPhone and destination apps first. If a destination app rejects
Apple's software-simulated locations, a different map UI will not change that.

## How it works

1. SideStore provides this device's pairing record.
2. LocalDevVPN exposes the iPhone's remote-pairing service to the same phone at
   `10.7.0.1:49152`.
3. Waypoint uses `idevice` to establish remote pairing and a Remote Service
   Discovery connection.
4. Waypoint checks or mounts the personalized Developer Disk Image.
5. It opens Apple's DVT LocationSimulation channel and sends latitude and
   longitude.
6. It keeps the DVT client alive, resends the selected point every four
   seconds, and optionally runs a transparent audio/location background
   keepalive until Stop is pressed.

This does not add private entitlements, patch `locationd`, use JIT, or bundle a
Network Extension. SideStore's normal personal-team signing can therefore sign
the IPA.

## Prerequisites

- iPhone with iOS 26 and Developer Mode enabled.
- SideStore installed and able to refresh apps.
- LocalDevVPN installed and connected.
- A valid `.mobiledevicepairing` record. Files import is the safer default.
  Waypoint also supports SideStore's current custom-URL callback as an explicitly
  sensitive convenience option.
- Wi-Fi/internet for the first developer-image download. The image normally
  needs to be remounted after every device reboot.

The pairing record contains device trust credentials. Do not share it. Waypoint
stores it under Application Support with file protection and mode `0600`,
excludes it from backups, and does not log it. Current SideStore code may log
the direct callback URL (which contains the record), so prefer Files import.

## Build the unsigned IPA

### Codemagic

Add the repository in Codemagic, select the `waypoint-unsigned` workflow, and
build this branch. `codemagic.yaml` pins the Xcode 26 image, fetches and verifies
the location-enabled `idevice` archive, then publishes `Waypoint-unsigned.ipa`
as a build artifact for SideStore to re-sign.

### GitHub Actions

1. Put this directory in a GitHub repository.
2. Open **Actions → Build unsigned IPA → Run workflow**.
3. Download the `Waypoint-unsigned-ipa` artifact.
4. Extract the workflow artifact ZIP, then import `Waypoint-unsigned.ipa` into
   SideStore.

The workflow uses Xcode 26, downloads a checksum-pinned `idevice` archive with
the optional location-simulation feature enabled, verifies the required
symbols, generates the project with XcodeGen, builds without signing, and wraps
`Waypoint.app` in an IPA. SideStore supplies the development signature later.

### Local Mac

Install Xcode 26 and XcodeGen, then run:

```sh
bash scripts/fetch-idevice.sh
xcodegen generate
xcodebuild archive \
  -project Waypoint.xcodeproj \
  -scheme Waypoint \
  -configuration Release \
  -archivePath build/Waypoint.xcarchive \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO
```

Package `build/Waypoint.xcarchive/Products/Applications/Waypoint.app` inside a
top-level `Payload` directory and zip it with an `.ipa` suffix.

## First run

1. Enable Developer Mode and reboot when iOS asks.
2. Connect LocalDevVPN.
3. Open Waypoint and use **Choose pairing file**. The direct SideStore callback
   is more convenient, but its screen explains why it is the less private path.
4. Return to Waypoint and tap **Prepare device**. Let the DDI files download and
   mount.
5. Search, tap the map, or drag the red pin.
6. Tap **Start spoofing**. The default keepalive uses low-accuracy background
   location activity plus silent audio mixed with other playback; it is visible
   as a toggle in setup and uses extra battery.
7. Tap **Stop** before disconnecting the VPN to restore real GPS.

## Important limitations

- Location is marked as software-simulated. Apps can inspect
  `CLLocationSourceInformation.isSimulatedBySoftware` and reject it.
- Apps may cross-check IP address, time zone, Wi-Fi, cellular, or motion data.
- The DVT connection must stay alive. Backgrounding, force-quitting, SideStore
  profile expiry, VPN interruption, or iOS memory pressure can end the spoof.
- The keepalive improves app-switching reliability but is not a guarantee. iOS
  can still suspend or terminate the process, and a force-quit ends it.
- Use it for development and testing, and follow the rules of destination apps
  and services. Waypoint does not attempt to hide simulation.

## Before calling it release-ready

Validate pairing import, first DDI mount, remount after reboot, drag/tap/search,
Start/Move/Stop, VPN interruption, lock/unlock, app backgrounding, SideStore
refresh, and every intended destination app on the exact iOS 26 point release.
