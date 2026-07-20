# Contributing to Waypoint

Thanks for helping improve Waypoint. Bug reports, device compatibility results,
documentation fixes, and focused pull requests are welcome.

By participating, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Before opening an issue

- Read the [README](README.md), [support guide](SUPPORT.md), and existing issues.
- Use the private process in [SECURITY.md](SECURITY.md) for vulnerabilities.
- Use the appropriate issue form for bugs, compatibility results, or features.

> [!CAUTION]
> Never upload or paste a `.mobiledevicepairing` file, pairing-record contents,
> Apple credentials, signing credentials, device tokens, or unredacted logs.
> Pairing records are trusted device credentials, not ordinary diagnostics.

## Development setup

Waypoint requires a Mac with Xcode 26 and
[XcodeGen](https://github.com/yonaskolb/XcodeGen). The Xcode project and the
location-enabled `idevice` binary are generated or fetched locally:

```sh
bash scripts/fetch-idevice.sh
xcodegen generate
open Waypoint.xcodeproj
```

Do not commit the generated `Waypoint.xcodeproj`, build output, IPA files,
downloaded vendor binaries, or any device-specific pairing material.

## Making a change

1. Create a branch from the current `main` branch.
2. Keep the change focused and follow the existing Swift and SwiftUI style.
3. Preserve the app's clear disclosure that locations are software-simulated;
   Waypoint does not attempt to hide simulation from other apps.
4. Update documentation when behavior, requirements, or setup changes.
5. Open a pull request using the repository template.

## Commit messages

Waypoint uses [Conventional Commits](https://www.conventionalcommits.org/) with
a required scope:

```text
<type>(<scope>): <description>
```

Use `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `build`, `ci`, `chore`,
or `revert` as the type. Choose a concise lowercase scope that identifies the
affected area, such as `map`, `spoofing`, `cellular`, `notifications`,
`onboarding`, `codemagic`, `release`, or `readme`. Keep the description
lowercase, imperative, and without a trailing period.

Examples:

```text
feat(map): add search result previews
fix(cellular): restore spoofing after reconnect
ci(codemagic): trigger builds from a release tag
docs(readme): clarify first-run setup
```

Mark breaking changes with `!` before the colon and explain them in a
`BREAKING CHANGE:` footer.

## Validation

At minimum, ensure the unsigned archive builds with Xcode 26. GitHub Actions
runs this check for every pull request.

For changes that affect device behavior, report which of these you tested:

- Start, move, and stop on Wi-Fi
- Guided start on cellular data with Wi-Fi off
- First-run pairing and LocalDevVPN setup
- Backgrounding, notification permission, and connection interruption
- Relaunch or remount behavior after an iPhone restart

Physical-device testing is valuable but not required to propose a change. If it
was not available, say so clearly in the pull request.

## Licensing

Contributions are submitted under the repository's
[GNU Affero General Public License v3.0](LICENSE).
Identify any third-party code or assets and include all required attribution and
license notices.
