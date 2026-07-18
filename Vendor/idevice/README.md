# idevice binary placeholder

Run `bash scripts/fetch-idevice.sh` before generating or building the Xcode
project. The script downloads a pinned `idevice.h` and `libidevice_ffi.a` pair
whose archive includes the otherwise optional DVT location-simulation feature.

The downloaded files are intentionally ignored by Git because the static
archive is approximately 93 MB.

