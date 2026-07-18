# Third-party notices

## idevice

Waypoint links a static library built from
[`jkcoxson/idevice`](https://github.com/jkcoxson/idevice). The checksum-pinned
binary/header pair is fetched from the StikDebug repository at commit
`c5b23e228249e384cf3e034fd379bf8b9abb76e2` because that build explicitly
includes the optional DVT location-simulation FFI symbols.

`idevice` is distributed under the MIT License. Its copyright and license are
available in the upstream repository.

## Personalized Developer Disk Image files

At setup time, Waypoint downloads the current personalized developer image,
trust cache, and build manifest from
[`doronz88/DeveloperDiskImage`](https://github.com/doronz88/DeveloperDiskImage).
Those files originate from Apple's Xcode distribution and are not included in
this source archive.

## Functional reference

[`StephenDev0/StikDebug`](https://github.com/StephenDev0/StikDebug) provided
release-level proof that the on-device DVT location-simulation mechanism works
on iOS 26. Waypoint does not include StikDebug source code. StikDebug is
AGPL-3.0; `idevice`, the lower-level library used here, is MIT-licensed.
