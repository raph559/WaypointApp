# Third-party notices

## idevice

Waypoint links a static library built from
[`jkcoxson/idevice`](https://github.com/jkcoxson/idevice). The checksum-pinned
binary/header pair is fetched from the StikDebug repository at commit
`c5b23e228249e384cf3e034fd379bf8b9abb76e2` because that build explicitly
includes the optional DVT location-simulation FFI symbols.

The build verifies these SHA-256 values before linking:

- `idevice.h`: `864b8c5b15cce6280c7645b49980a626b3a44aeabfdaf30124881b9b2a47a5c4`
- `libidevice_ffi.a`: `6524066d54ef23e00d46445c04dfc694e180196d54119d718f68434fa225be35`

`idevice` is distributed under the MIT License. Its upstream notice is
reproduced here:

> Copyright 2026 Jackson Coxson
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the “Software”), to
> deal in the Software without restriction, including without limitation the
> rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
> sell copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in
> all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.

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
AGPL-3.0; `idevice`, the lower-level library used here, is MIT-licensed. The
exact StikDebug commit above is also the distribution location for the pinned
`idevice` binary/header pair.
