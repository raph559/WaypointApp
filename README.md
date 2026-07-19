<div align="center">
  <img
    src="Waypoint/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
    width="140"
    alt="Waypoint app icon"
  >

  <h1>Waypoint</h1>

  <p><strong>Pick a place. Drop the pin. Move your iPhone's simulated location.</strong></p>

  <p>
    An open-source, map-first location simulator for iOS 26 that runs directly
    on your device. No Mac, VPS, or always-on computer is required during normal
    use.
  </p>

  <p>
    <a href="https://github.com/raph559/WaypointApp/actions/workflows/build-ipa.yml">
      <img
        src="https://github.com/raph559/WaypointApp/actions/workflows/build-ipa.yml/badge.svg?branch=main"
        alt="Build unsigned IPA"
      >
    </a>
    <img
      src="https://img.shields.io/badge/tested-iOS%2026-black?logo=apple"
      alt="Tested on iOS 26"
    >
    <img
      src="https://img.shields.io/badge/UI-SwiftUI-F05138?logo=swift&logoColor=white"
      alt="SwiftUI"
    >
    <img
      src="https://img.shields.io/badge/version-0.2.0-00B7C7"
      alt="Version 0.2.0"
    >
    <a href="LICENSE">
      <img
        src="https://img.shields.io/badge/license-MIT-blue"
        alt="MIT License"
      >
    </a>
  </p>

  <p>
    <a href="https://github.com/raph559/WaypointApp/actions/workflows/build-ipa.yml?query=branch%3Amain+is%3Asuccess">
      <img
        src="https://img.shields.io/badge/Get%20the%20IPA-GitHub%20Actions-2088FF?style=for-the-badge&logo=githubactions&logoColor=white"
        alt="Get the unsigned IPA from GitHub Actions"
      >
    </a>
  </p>

  <p>
    <a href="#download-and-install">Install</a> ·
    <a href="#first-time-setup">Set up</a> ·
    <a href="#how-it-works">How it works</a> ·
    <a href="#build-from-source">Build</a> ·
    <a href="#compatibility-and-limitations">Limitations</a>
  </p>
</div>

Waypoint gives you a clean SwiftUI map for controlling Apple's developer
location-simulation service. Search for an address or point of interest, tap the
map or drag the pin, then start or move the simulated location without returning
to a computer.

After the initial SideStore, pairing-record, and LocalDevVPN setup, routine use
happens entirely on the iPhone.

## Highlights

| | Feature | What it does |
|---|---|---|
| 🔎 | **Live place search** | Suggests addresses and points of interest with MapKit |
| 📍 | **Natural map controls** | Selects a location by search, tap, or draggable pin |
| ⚡ | **Instant moves** | Moves an active simulation without stopping it first |
| ✅ | **Clear status feedback** | Shows animated Start, Move, Stop, and connection-loss states with haptics |
| 🔔 | **Connection warnings** | Warns when Waypoint can no longer confirm the simulation heartbeat |
| 🌙 | **Optional background keepalive** | Improves reliability while switching between apps |
| 🔐 | **Protected local pairing data** | Stores the pairing record on-device and excludes it from backups |

> [!IMPORTANT]
> Waypoint uses Apple's software-simulated developer location. Apps can detect
> or reject simulated locations, so compatibility depends on the destination
> app. Waypoint does not attempt to conceal simulation.

## Requirements

The currently validated setup requires:

- An iPhone running **iOS 26** with **Developer Mode** enabled
- [SideStore](https://sidestore.io/) installed and able to refresh apps
- LocalDevVPN installed and connected
- A valid <code>.mobiledevicepairing</code> file for the iPhone
- Internet access during the first developer-image download and for MapKit
  search

The app target also includes arm64 iPhone and iPad devices from iOS/iPadOS 17.4,
but physical validation has only been completed on an iPhone running iOS 26.

The personalized developer-image files are downloaded once, cached locally, and
normally only need to be mounted again after restarting the iPhone.

## Download and install

Waypoint is distributed as an unsigned IPA. SideStore signs it with your Apple
ID during installation.

1. Open the
   [latest successful build on main](https://github.com/raph559/WaypointApp/actions/workflows/build-ipa.yml?query=branch%3Amain+is%3Asuccess).
2. Select the newest successful **Build unsigned IPA** run.
3. Download the **Waypoint-unsigned-ipa** artifact.
4. Extract the downloaded ZIP.
5. Import <code>Waypoint-unsigned.ipa</code> into SideStore.

GitHub may require you to sign in before downloading workflow artifacts.
Artifacts are retained for 30 days; if none is available, run the included
workflow from a fork or use one of the build methods below.

## First-time setup

1. Enable **Developer Mode** in iOS Settings and restart when prompted.
2. Connect LocalDevVPN.
3. Open Waypoint.
4. Import the <code>.mobiledevicepairing</code> file with
   **Choose pairing file**.
5. Tap **Prepare device** and wait for the developer-image files to download and
   mount.
6. Search for a place, tap the map, or drag the pin.
7. Tap **Start spoofing**.
8. Allow notifications when prompted to receive connection-loss warnings.

When finished, press **Stop** before disconnecting LocalDevVPN so Waypoint can
clear the simulated location. If the stop cannot be confirmed, reconnect
LocalDevVPN, prepare the device, and try **Stop** again; otherwise reboot and
verify the reported location.

## Everyday use

While the simulation is active, choose another place and tap **Move spoof here**
to update it immediately. Waypoint shows a banner and triggers a haptic response
whenever the simulation starts, moves, stops, or loses its connection.

The background keepalive is enabled by default and can be disabled in setup. It
uses low-accuracy Core Location activity and silent audio mixed with other
playback, may request Always location access, can show iOS location activity,
and uses additional battery. Location permission is not required for foreground
spoofing.

The keepalive improves reliability while switching apps, but cannot prevent
every iOS suspension or termination.

If Waypoint goes roughly 30 seconds without a successful heartbeat, its
watchdog can notify you that the simulated location can no longer be confirmed.
Notifications are optional but required for these alerts. The wording is
intentionally cautious: after iOS suspends or terminates the app, Waypoint
cannot directly verify the current GPS state.

## Privacy and pairing-file safety

A pairing record contains trusted device credentials. Treat it like a secret
and never share it.

Waypoint:

- Stores the imported record under Application Support
- Uses iOS file protection and file mode <code>0600</code>
- Excludes the record from device backups
- Does not log the record in Waypoint's own code

Importing through Files is the recommended option. The direct SideStore callback
is more convenient, but it places the pairing data in a custom URL that may be
exposed by URL or debug logging.

## How it works

~~~mermaid
flowchart LR
    A["Waypoint map"] --> B["idevice FFI"]
    B --> C["LocalDevVPN loopback"]
    C --> D["Apple DVT LocationSimulation"]
    D --> E["Core Location apps"]
~~~

<details>
<summary><strong>Technical overview</strong></summary>

1. Waypoint imports this iPhone's pairing record from Files or through the
   explicit SideStore callback.
2. LocalDevVPN exposes the remote-pairing service locally at
   <code>10.7.0.1:49152</code>.
3. Waypoint uses the MIT-licensed <code>idevice</code> FFI to establish remote
   pairing and Remote Service Discovery.
4. It checks or mounts the personalized Developer Disk Image.
5. It opens Apple's DVT LocationSimulation channel and sends the selected
   coordinates.
6. While active, it keeps the DVT client alive and resends the point every four
   seconds.

Waypoint does not require JIT, a jailbreak, private entitlements, a bundled
Network Extension, patches to <code>locationd</code>, or an external spoofing
server.

</details>

## Compatibility and limitations

- iOS marks the location as software-simulated. Apps can inspect
  <code>CLLocationSourceInformation.isSimulatedBySoftware</code>.
- Destination apps may reject simulated locations or compare them with IP
  address, time zone, Wi-Fi, cellular, or motion data.
- Force-quitting Waypoint ends its keepalive.
- VPN interruption, memory pressure, background suspension, or SideStore
  profile expiry can stop the DVT connection.
- A watchdog notification means Waypoint lost confirmation; it does not prove
  exactly when iOS restored the real location.
- The developer image generally needs to be prepared again after an iPhone
  reboot, but cached files normally do not need to be downloaded again.
- Use Waypoint for development and testing, and follow the rules of the apps and
  services you test.

## Build from source

<details>
<summary><strong>GitHub Actions</strong></summary>

The included **Build unsigned IPA** workflow:

- Uses Xcode 26.0.1
- Downloads and checksum-verifies the location-enabled
  <code>idevice</code> archive
- Verifies the required location-simulation symbols
- Generates the Xcode project with XcodeGen
- Archives without code signing
- Packages <code>Waypoint.app</code> as
  <code>Waypoint-unsigned.ipa</code>

Run it from **Actions → Build unsigned IPA → Run workflow**. It also runs
automatically for pushes to <code>main</code> and pull requests targeting
<code>main</code>.

</details>

<details>
<summary><strong>Codemagic</strong></summary>

Import the repository into Codemagic, select the
<code>waypoint-unsigned</code> workflow, and build the
<code>main</code> branch with Xcode 26.0. The unsigned IPA is published as a
build artifact for SideStore.

</details>

<details>
<summary><strong>Local Mac</strong></summary>

Install Xcode 26 and XcodeGen, then run:

~~~sh
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
~~~

Place the archived <code>Waypoint.app</code> inside a top-level
<code>Payload</code> directory and package it with an
<code>.ipa</code> extension.

</details>

## Project status

Waypoint **0.2.0** has been:

- Archived successfully with Xcode 26.0.1
- Packaged as an unsigned arm64 IPA
- Installed through SideStore
- Validated on a physical iPhone running iOS 26

For a new iOS release or destination app, test pairing import, device
preparation, Start/Move/Stop, backgrounding, lock/unlock, VPN interruption,
SideStore refresh, and developer-image remount after reboot.

## Contributing

Bug reports, compatibility results, feature ideas, and pull requests are
welcome. Please open a
[GitHub issue](https://github.com/raph559/WaypointApp/issues) with the iOS
version, installation method, and reproducible steps when reporting a problem.

## Credits

- [<code>jkcoxson/idevice</code>](https://github.com/jkcoxson/idevice)
  provides the MIT-licensed device-service FFI.
- [<code>StephenDev0/StikDebug</code>](https://github.com/StephenDev0/StikDebug)
  provided a functional reference for the on-device iOS 26 workflow. StikDebug
  is not required to use Waypoint.
- [<code>doronz88/DeveloperDiskImage</code>](https://github.com/doronz88/DeveloperDiskImage)
  provides the personalized developer-image files downloaded during setup.

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for details.

## License

Waypoint is open source under the [MIT License](LICENSE).
