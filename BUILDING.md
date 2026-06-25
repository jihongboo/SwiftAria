# Building aria2 for SwiftAria

The package has two products: `Aria2RPC` is a pure Swift RPC interface and does not need an aria2 binary; `SwiftAria` bundles a macOS Apple Silicon `aria2c` executable for its local daemon path. The current package does not link `libaria2` or ship an `XCFramework`.

## Target

- aria2 version: 1.37.0
- Platform: macOS 15+
- Architecture: arm64 only
- License: GPL-2.0-or-later
- Default feature scope: HTTP/HTTPS/FTP downloads

## Protocol Profiles

The build script supports three protocol profiles:

| Profile | Command | Intended support |
| --- | --- | --- |
| `minimal` | `sh Scripts/build-libaria2-xcframework.sh` | HTTP, HTTPS, FTP. Smallest default binary. |
| `magnet` | `PROTOCOL_PROFILE=magnet sh Scripts/build-libaria2-xcframework.sh` | Enables aria2 BitTorrent/Magnet internals while keeping Metalink, WebSocket, SFTP, and external resolver libraries disabled. |
| `full` | `PROTOCOL_PROFILE=full sh Scripts/build-libaria2-xcframework.sh` | Attempts to enable aria2's broader protocol set, including BitTorrent, Metalink, WebSocket, c-ares, libssh2, OpenSSL, SQLite, and libxml2 when available through Homebrew. |

The current public Swift `DownloadRequest` API is designed for single-output URI downloads. HTTP, HTTPS, and FTP use that model directly. Magnet, torrent, Metalink, and SFTP need dedicated API shapes before they should be advertised as public Swift support.

## Verified Build Shape

The default `minimal` build uses macOS AppleTLS and system zlib. It keeps aria2's HTTP/HTTPS/FTP path and disables protocols and dependencies that are outside SwiftAria's first scope:

- BitTorrent: disabled
- Metalink: disabled
- WebSocket: disabled
- GnuTLS/OpenSSL: disabled in favor of AppleTLS
- SQLite, libxml2, c-ares, libssh2: disabled

This keeps the default daemon binary small and avoids shipping third-party crypto/network libraries for v1.

## Build Command

Run the reproducible default build script from the package root:

```sh
sh Scripts/build-libaria2-xcframework.sh
```

By default it downloads the official aria2 1.37.0 source release, builds `aria2c`, uses size-oriented release flags (`-Os -DNDEBUG`), strips debug symbols, and writes:

```text
Sources/SwiftAria/Resources/aria2c
```

The `SwiftAria` target packages `Sources/SwiftAria/Resources/aria2c` as a copied resource. The `Aria2RPC` target has no resources. `Aria2.xcframework` is no longer produced or linked by the package.

You can override locations and compiler flags when needed:

```sh
ARIA2_VERSION=1.37.0 \
WORK_DIR=/tmp/swiftaria-aria2-build \
INSTALL_DIR=/tmp/swiftaria-aria2-install \
DAEMON_OUTPUT=/tmp/aria2c \
CFLAGS="-Oz -DNDEBUG" \
CXXFLAGS="-Oz -DNDEBUG" \
sh Scripts/build-libaria2-xcframework.sh
```

## Full Profile Dependencies

The `full` profile uses Homebrew prefixes when available for:

- c-ares
- libssh2
- openssl@3
- sqlite
- libxml2

The script does not install dependencies. It only uses them if they are already installed.

## Package Integration

`Package.swift` exposes two products:

```swift
.library(name: "Aria2RPC", targets: ["Aria2RPC"])
.library(name: "SwiftAria", targets: ["SwiftAria"])
```

`SwiftAria` packages the daemon executable as a copied resource:

```swift
.target(
    name: "SwiftAria",
    dependencies: ["Aria2RPC"],
    resources: [
        .copy("Resources/aria2c"),
    ]
)
```

`Aria2Daemon` copies that bundled resource to a temporary executable path and launches it with RPC enabled. `DownloadClient(endpoint:)` then talks to the daemon through `Aria2RPCClient`.

## Current Local Verification

The package builds and packages the bundled `aria2c` resource. The test suite includes a local loopback HTTP integration test that starts `Aria2Daemon`, downloads a small file through `DownloadClient(endpoint:)`, and verifies the downloaded bytes.
