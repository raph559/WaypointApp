<div align="center">
  <img
    src="Waypoint/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
    width="140"
    alt="Waypoint app icon"
  >

  <h1>Waypoint</h1>

  <p><strong>Pick a place. Tap Start. Waypoint handles the connection.</strong></p>

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
      src="https://img.shields.io/badge/target-iOS%2026-black?logo=apple"
      alt="Target iOS 26"
    >
    <img
      src="https://img.shields.io/badge/UI-SwiftUI-F05138?logo=swift&logoColor=white"
      alt="SwiftUI"
    >
    <a href="https://github.com/raph559/WaypointApp/releases/latest">
      <img
        src="https://img.shields.io/github/v/release/raph559/WaypointApp?label=version&color=00B7C7"
        alt="Latest Waypoint release"
      >
    </a>
    <a href="LICENSE">
      <img
        src="https://img.shields.io/badge/license-AGPL--3.0-blue"
        alt="GNU AGPL v3 License"
      >
    </a>
  </p>

  <p>
    <a href="https://github.com/raph559/WaypointApp/releases/latest">
      <img
        src="https://img.shields.io/badge/Download-Waypoint%20IPA-2088FF?style=for-the-badge&logo=apple&logoColor=white"
        alt="Open the latest Waypoint release"
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

After one-time Developer Mode and pairing setup, Waypoint adapts to the current
connection. On Wi-Fi, tap **Start spoofing**. On 4G/5G, tap **Start on mobile
data** and follow the two Airplane Mode prompts. Waypoint handles the remaining
preparation automatically.

## Highlights

| | Feature | What it does |
|---|---|---|
| 🔎 | **Live place search** | Suggests addresses and points of interest with MapKit |
| 📍 | **Natural map controls** | Selects a location by search, tap, or draggable pin |
| ⚡ | **Instant moves** | Moves an active simulation without stopping it first |
| ✅ | **Clear status feedback** | Shows animated Start, Move, Stop, and connection-loss states with haptics |
| 🔔 | **Connection warnings** | Warns when Waypoint can no longer confirm the simulation heartbeat |
| 🌙 | **Optional background keepalive** | Improves reliability while switching between apps |
| 🔄 | **Connection-aware start** | Uses a normal start on Wi-Fi and shows the guided cellular flow only on mobile data |
| 🧩 | **Guided dependency setup** | Detects a missing LocalDevVPN, links to the App Store, and continues automatically after installation |
| 📡 | **Guided mobile-data start (experimental)** | Opens LocalDevVPN, prepares the session, and guides the two Airplane Mode changes while Wi-Fi stays off |
| 🔐 | **Protected local pairing data** | Stores the pairing record on-device and excludes it from backups |

> [!IMPORTANT]
> Waypoint uses Apple's software-simulated developer location. Apps can detect
> or reject simulated locations, so compatibility depends on the destination
> app. Waypoint does not attempt to conceal simulation.

## Requirements

You'll need:

- An iPhone running **iOS 26** with **Developer Mode** enabled
- [SideStore](https://sidestore.io/) installed and able to refresh apps
- [LocalDevVPN](https://apps.apple.com/app/id6755608044) installed, with its
  one-time VPN permission accepted
- A valid <code>.mobiledevicepairing</code> file for the iPhone
- Internet access for the one-time developer-image download and MapKit search

For the experimental cellular-only start, mobile data must be working before
you begin and Wi-Fi must remain off during the handoff.

The personalized developer-image files are downloaded once, cached locally, and
normally only need to be mounted again after restarting the iPhone.

## Download and install

Waypoint is distributed as an unsigned IPA. SideStore signs it with your Apple
ID during installation.

1. Open the [latest Waypoint release](https://github.com/raph559/WaypointApp/releases/latest)
   and download its <code>.ipa</code> asset.
2. Open or share the IPA with SideStore.
3. Install it as a normal SideStore app.

The same release page contains the release notes and SHA-256 checksum.

## First-time setup

### Recommended: start on Wi-Fi

1. Enable **Developer Mode** in iOS Settings and restart when prompted.
2. Install Waypoint through SideStore. If LocalDevVPN is missing, Waypoint links
   directly to its App Store page and continues setup when you return. Complete
   LocalDevVPN's one-time VPN permission if iOS asks.
3. Keep Wi-Fi connected, choose a location, and tap **Start spoofing**.
4. If prompted, import this iPhone's pairing record. Waypoint downloads about
   17 MB of developer-support files once, opens LocalDevVPN, and prepares the
   device automatically.
5. Leave Waypoint open until it confirms that the spoof is active.

Airplane Mode is not needed when starting on Wi-Fi.

### Importing the pairing record

SideStore maintains the pairing record it uses for this iPhone. When Waypoint
asks for it, choose one of these options:

- **Import from SideStore** asks SideStore to return the record directly to
  Waypoint.
- **Choose from Files** imports a <code>.mobiledevicepairing</code> file that you
  previously exported from SideStore. This is the more private option.

The same controls remain available under **Settings → Device Setup** if the
record needs to be replaced.

> [!CAUTION]
> A pairing record contains trusted device credentials. Use only the record for
> your own iPhone. Never share it, post it in an issue, or include it in logs or
> screenshots.

### Without Wi-Fi: cellular-only start — experimental

1. Turn Wi-Fi off, confirm that mobile data is working, and choose a location.
2. Tap **Start on mobile data**.
3. Complete pairing and the one-time support download if Waypoint asks.
4. When prompted, turn **Airplane Mode on** and keep Wi-Fi off.
5. When prompted again, turn **Airplane Mode off** and still keep Wi-Fi off.
6. Leave Waypoint open until it confirms **Spoof Active on Mobile Data**.

Later cellular-only starts use the same two Airplane Mode prompts. Waypoint
handles LocalDevVPN, device preparation, and session verification around them.

When finished, press **Stop** before disconnecting LocalDevVPN so Waypoint can
clear the simulated location. If Waypoint cannot confirm the stop, disconnect
LocalDevVPN or restart the iPhone, then verify the reported location before
relying on it.

## Everyday use

While the simulation is active, choose another place and tap **Move spoof here**
to update it immediately. Tap **Stop** before disconnecting LocalDevVPN so
Waypoint can restore the real location cleanly. Waypoint shows a banner and
triggers a haptic response whenever the simulation starts, moves, stops, or
loses its connection.

The background keepalive is enabled by default and can be disabled in Settings.
It uses low-accuracy Core Location activity and silent audio mixed with other
playback, may request Always location access, can show iOS location activity,
and uses additional battery. Location permission is not required for foreground
spoofing.

The keepalive improves reliability while switching apps, but cannot prevent
every iOS suspension or termination.

If Waypoint goes roughly 30 seconds without a successful heartbeat, its
watchdog can notify you that the simulated location can no longer be confirmed.
Enable **Notify If Spoof Stops** under **Settings** to receive
these alerts, including without Wi-Fi or mobile data. If permission was denied,
Waypoint provides a direct shortcut to iOS notification settings. The wording
is intentionally cautious: after iOS suspends or terminates the app, Waypoint
cannot directly verify the current GPS state.

### Mobile data with no Wi-Fi — experimental

On the tested iOS 26 device, a **new** developer-service connection failed while
cellular was the only active physical interface. Waypoint's guide creates the
simulation while the phone is temporarily offline, retains that same session,
and verifies that it still responds after 4G/5G returns. It never claims success
merely because mobile data reappeared.

The retained-session mechanism and guided workflow have been confirmed through
SideStore on a physical iPhone running iOS 26. Results can still vary with the
device and current iOS network state.

> [!WARNING]
> Cellular operation remains device-dependent. An app termination, VPN restart,
> iPhone reboot, or iOS closing the retained session requires running the guided
> start again.

## Troubleshooting

| Problem | What to try |
|---|---|
| **Waypoint asks for LocalDevVPN** | Install it from the offered App Store link, open it once, accept the VPN permission, and return to Waypoint. If iOS closed Waypoint, tap Start again. |
| **Pairing is missing or rejected** | Confirm Developer Mode is enabled, then replace the record under **Settings → Device Setup** with a fresh record for this same iPhone. |
| **Developer support will not download or mount** | Check the internet connection, choose **Settings → Reset Support Files**, and start again. |
| **The cellular guide times out** | Restore mobile data, keep Wi-Fi off, confirm 4G/5G works, and retry the guide from the beginning. Follow each Airplane Mode prompt only when it appears. |
| **Disconnect alerts cannot be enabled** | Allow notifications in iOS Settings. The shortcut under **Settings → Alerts** opens the correct page after permission is denied. |
| **Another app still shows the simulated location after Stop** | Disconnect LocalDevVPN or restart the iPhone, then verify the location again before relying on it. |

When reporting a problem, include the iOS version, Waypoint version,
installation method, connection type, and reproducible steps—but never attach a
pairing record or a callback URL containing one.

For more help, read the [support guide](SUPPORT.md). Report suspected security
issues through the private process in [SECURITY.md](SECURITY.md), not a public
issue.

## Privacy and data flow

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

Waypoint has no account system, analytics, or Waypoint-operated server. The app
does use these external services during normal operation:

- Apple's MapKit services provide map content and place search.
- Developer-image files are downloaded from the
  [DeveloperDiskImage](https://github.com/doronz88/DeveloperDiskImage)
  repository and cached on-device.
- SideStore supplies the pairing record when direct import is selected.
- LocalDevVPN exposes the iPhone's developer service through an on-device VPN.
- Disconnect warnings are local iOS notifications and do not require an
  internet connection.

The pairing record is used for the local developer connection and is never sent
to a Waypoint-operated service.

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

| Environment | Status |
|---|---|
| iPhone on iOS 26, Wi-Fi start | Primary supported and physically tested configuration |
| iPhone on iOS 26, cellular-only start | Physically tested, but still experimental and device-dependent |
| iPhone on iOS 17.4–25 | Included by the build target, but not physically validated |
| iPad on iPadOS 17.4 or later | Included by the build target, but not physically validated |

- iOS marks the location as software-simulated. Apps can inspect
  <code>CLLocationSourceInformation.isSimulatedBySoftware</code>.
- Destination apps may reject simulated locations or compare them with IP
  address, time zone, Wi-Fi, cellular, or motion data.
- Force-quitting Waypoint ends its keepalive.
- VPN interruption, memory pressure, background suspension, or SideStore
  profile expiry can stop the DVT connection.
- On the tested iOS 26 device, fresh DVT connections failed on cellular-only
  paths. The no-Wi-Fi handoff is experimental and may fail if iOS closes the
  already-open session when cellular returns.
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
- Downloads and checksum-verifies the location-enabled <code>idevice</code>
  binary/header pair
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
xcodebuild clean archive \
  -project Waypoint.xcodeproj \
  -scheme Waypoint \
  -configuration Release \
  -archivePath build/Waypoint.xcarchive \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  CODE_SIGN_IDENTITY='' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  ONLY_ACTIVE_ARCH=NO
~~~

Place the archived <code>Waypoint.app</code> inside a top-level
<code>Payload</code> directory and package it with an
<code>.ipa</code> extension.

</details>

## Project status

Waypoint's core map, pairing, preparation, and Wi-Fi Start/Move/Stop flow is the
stable V1 experience. The guided no-Wi-Fi cellular workflow has also been
confirmed on a physical iPhone running iOS 26, but remains experimental across
devices and iOS network states.

- Automatic preparation stays inside the Start flow; there is no separate
  Prepare button.
- Every release is archived with Xcode 26 and packaged as an unsigned arm64 IPA
  by GitHub Actions.

For a new iOS release or destination app, test pairing import, device
preparation, Start/Move/Stop, backgrounding, lock/unlock, VPN interruption,
SideStore refresh, and developer-image remount after reboot.

## Contributing

Bug reports, compatibility results, feature ideas, and pull requests are
welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md), then open a
[GitHub issue](https://github.com/raph559/WaypointApp/issues) with the iOS
version, installation method, and reproducible steps when reporting a problem.
Never attach a pairing record or an unredacted SideStore callback URL.

Before submitting a pull request, keep the change focused and confirm that the
unsigned IPA workflow builds successfully. The Xcode project is generated from
<code>project.yml</code> and should not be committed.

Community participation follows the [Code of Conduct](CODE_OF_CONDUCT.md).

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

Waypoint is open source under the [GNU Affero General Public License v3.0](LICENSE).
