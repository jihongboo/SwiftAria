# SwiftAria

SwiftAria is a macOS 15+ Swift package that exposes aria2 through Swift async/await APIs.

The first supported platform target is Apple Silicon macOS (`arm64`) only.

## Products

SwiftAria ships two library products:

- `Aria2RPC`: a lightweight pure Swift JSON-RPC client for an existing aria2 daemon. It does not bundle or launch `aria2c`.
- `SwiftAria`: the complete local daemon package. It depends on `Aria2RPC`, bundles `aria2c`, launches it through `Aria2Daemon`, and provides the high-level `DownloadClient` API.

Use `Aria2RPC` when your app talks to a remote aria2 service, a user-installed local aria2 daemon, or another process that owns aria2. Use `SwiftAria` when your app should work out of the box with the bundled aria2 executable.

## Current Status

SwiftAria uses a pure Swift RPC integration path:

- `Aria2Daemon` launches the bundled `aria2c` executable as a local RPC server.
- `Aria2RPCClient` uses system `URLSession` and `JSONSerialization` to call aria2 JSON-RPC.
- `DownloadClient(endpoint:)` provides the high-level async/await download API.

The native C bridge has been removed. The package no longer builds, links, or ships an `Aria2.xcframework`; the full `SwiftAria` product only needs the bundled `aria2c` executable.

The current working download scope is HTTP, HTTPS, and FTP downloads with progress, wait-for-completion, pause, resume, and cancel entry points.

## SwiftAria Usage

```swift
import Foundation
import SwiftAria

let daemon = try Aria2Daemon(
    downloadDirectory: URL(filePath: "/tmp")
)
try await daemon.start()

let client = DownloadClient(endpoint: daemon.endpoint)
let handle = try await client.download(
    DownloadRequest(
        url: URL(string: "https://example.com/archive.zip")!,
        destination: URL(filePath: "/tmp/archive.zip")
    )
)

let fileURL = try await handle.value
print(fileURL)
```

## Aria2RPC Usage

```swift
import Aria2RPC
import Foundation

let endpoint = Aria2Endpoint(
    url: URL(string: "http://127.0.0.1:6800/jsonrpc")!,
    token: "secret"
)
let client = Aria2RPCClient(endpoint: endpoint)
let gid = try await client.addURI(["https://example.com/archive.zip"])
let status = try await client.tellStatus(gid: gid)
print(status.status)
```

## aria2 Build Strategy

SwiftAria builds aria2 from the official aria2 source release instead of consuming third-party binaries. The package pins an aria2 release tag and copies the stripped `aria2c` executable into `Sources/SwiftAria/Resources/aria2c` for daemon usage.

See `BUILDING.md` and `Scripts/build-libaria2-xcframework.sh` for the reproducible build flow.

## Documentation

This package includes DocC catalogs for both products:

- `Sources/Aria2RPC/Aria2RPC.docc`
- `Sources/SwiftAria/SwiftAria.docc`

The repository includes a GitHub Actions workflow at `.github/workflows/docs.yml` that builds DocC with `swift-docc-plugin` and deploys the generated static site to GitHub Pages on pushes to `main`.

After enabling GitHub Pages with GitHub Actions as the source, the documentation is published at:

```text
https://<owner>.github.io/<repository>/
```

## License Notice

aria2 is distributed under GPL-2.0-or-later. Distributing the `SwiftAria` product with aria2 binaries means downstream users need to evaluate GPL compliance for their applications. The `Aria2RPC` product is only the Swift RPC interface and does not include the aria2 binary.
