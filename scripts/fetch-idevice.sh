#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
vendor_dir="$root_dir/Vendor/idevice"
commit="c5b23e228249e384cf3e034fd379bf8b9abb76e2"
base_url="https://raw.githubusercontent.com/StephenDev0/StikDebug/$commit/StikDebug/idevice"

mkdir -p "$vendor_dir"

curl --fail --location --retry 3 \
  "$base_url/idevice.h" \
  --output "$vendor_dir/idevice.h"

curl --fail --location --retry 3 \
  "$base_url/libidevice_ffi.a" \
  --output "$vendor_dir/libidevice_ffi.a"

expected_header="864b8c5b15cce6280c7645b49980a626b3a44aeabfdaf30124881b9b2a47a5c4"
expected_library="6524066d54ef23e00d46445c04dfc694e180196d54119d718f68434fa225be35"

actual_header="$(shasum -a 256 "$vendor_dir/idevice.h" | awk '{print $1}')"
actual_library="$(shasum -a 256 "$vendor_dir/libidevice_ffi.a" | awk '{print $1}')"

if [[ "$actual_header" != "$expected_header" || "$actual_library" != "$expected_library" ]]; then
  echo "Downloaded idevice files failed checksum verification." >&2
  exit 1
fi

echo "Pinned idevice library and header are ready."

