# Building the Native aria2 Backend

SwiftAria distributes a macOS Apple Silicon `Vendor/Aria2.xcframework` built from official aria2 source releases.

## Target

- aria2 version: 1.37.0
- Platform: macOS 15+
- Architecture: arm64 only
- License: GPL-2.0-or-later
- First feature scope: HTTP/HTTPS downloads

## Verified Build Shape

The current minimal build uses macOS AppleTLS and system zlib. It disables protocols and dependencies that are outside SwiftAria's first HTTP/HTTPS scope:

- BitTorrent: disabled
- Metalink: disabled
- WebSocket: disabled
- GnuTLS/OpenSSL: disabled in favor of AppleTLS
- SQLite, libxml2, c-ares, libssh2: disabled

This keeps the first binary smaller and avoids shipping third-party crypto/network libraries for v1.

## Build Command

Run the reproducible build script from the package root:

```sh
sh Scripts/build-libaria2-xcframework.sh
```

By default it downloads the official aria2 1.37.0 source release, builds static `libaria2` with `--enable-libaria2`, uses size-oriented release flags (`-Os -DNDEBUG`), strips debug symbols from the static archive, and writes:

```text
Vendor/Aria2.xcframework
```

You can override locations and compiler flags when needed:

```sh
ARIA2_VERSION=1.37.0 \
WORK_DIR=/tmp/swiftaria-aria2-build \
INSTALL_DIR=/tmp/swiftaria-aria2-install \
OUTPUT_DIR=/tmp/Aria2.xcframework \
CFLAGS="-Oz -DNDEBUG" \
CXXFLAGS="-Oz -DNDEBUG" \
sh Scripts/build-libaria2-xcframework.sh
```

## Package Integration

`Package.swift` already declares:

```swift
.target(
    name: "CAria2Bridge",
    dependencies: ["Aria2Binary"],
    publicHeadersPath: "include",
    linkerSettings: [
        .linkedLibrary("z"),
        .linkedFramework("CoreFoundation"),
        .linkedFramework("Security"),
    ]
),
.binaryTarget(
    name: "Aria2Binary",
    path: "Vendor/Aria2.xcframework"
)
```

`Sources/CAria2Bridge/CAria2Bridge.cpp` calls `libaria2` through `aria2/aria2.h` while preserving the C ABI declared in `Sources/CAria2Bridge/include/CAria2Bridge.h`.

## Current Local Verification

The package builds and links against `Vendor/Aria2.xcframework`. The test suite includes a local loopback HTTP integration test that downloads a small file through the public `DownloadClient` API and verifies the downloaded bytes.
