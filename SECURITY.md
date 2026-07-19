# Security Policy

Waypoint handles sensitive iPhone pairing credentials and communicates with
developer services through LocalDevVPN. Please report security concerns
privately and handle diagnostic material carefully.

## Supported versions

Security fixes are provided on a best-effort basis for the latest release and
the current `main` branch. Older releases may not receive separate patches.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting flow:

[Report a vulnerability privately](https://github.com/raph559/WaypointApp/security/advisories/new)

If GitHub reports that private vulnerability reporting is unavailable, use a
private contact method listed on the
[maintainer's GitHub profile](https://github.com/raph559) and include only
sanitized information in the first message.

Do not open a public issue for a suspected vulnerability. Include:

- The affected Waypoint and iOS versions
- A concise description of the impact
- Reproduction steps or a minimal proof of concept
- Suggested remediation, if known

> [!CAUTION]
> Never submit a `.mobiledevicepairing` file or its contents, Apple credentials,
> signing credentials, private keys, device tokens, or secrets embedded in URLs.
> Redact personal data, UDIDs, IP addresses, and unrelated log content. If a
> pairing record is required to explain a finding, describe its structure using
> fabricated values.

Reports are acknowledged and investigated on a best-effort basis. Please allow
the maintainer time to reproduce and address the issue before public disclosure.
Submitting a report does not guarantee a fix or a specific response timeline.

For ordinary setup problems and non-sensitive bugs, use [SUPPORT.md](SUPPORT.md)
and the public issue forms instead.
