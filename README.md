# SwiftAria

SwiftAria is a macOS 15+ Swift package that exposes aria2 through a Swifty async/await download API.

The first supported platform target is Apple Silicon macOS (`arm64`) only.

## Current Status

SwiftAria now links the native `libaria2` backend through `Vendor/Aria2.xcframework` and `CAria2Bridge`. The first working scope is HTTP/HTTPS downloads with progress, wait-for-completion, pause, resume, and cancel entry points.

## Usage

```swift
import Foundation
import SwiftAria

let client = DownloadClient()
let request = DownloadRequest(
    url: URL(string: "https://example.com/archive.zip")!,
    destination: URL(filePath: "/tmp/archive.zip")
)

let handle = try await client.download(request)

for await progress in handle.progressUpdates {
    print(progress.completedBytes, progress.totalBytes as Any)
}

let fileURL = try await handle.value
print(fileURL)
```

## Native aria2 Build Strategy

SwiftAria builds `libaria2` from the official aria2 source release instead of consuming third-party binaries. The package pins an aria2 release tag, builds macOS `arm64` with `--enable-libaria2`, wraps the output as `Vendor/Aria2.xcframework`, and commits that framework so downstream SwiftPM users can import SwiftAria directly.

See `BUILDING.md` and `Scripts/build-libaria2-xcframework.sh` for the reproducible build flow.

## License Notice

aria2 is distributed under GPL-2.0-or-later. Linking and distributing SwiftAria with `libaria2` means downstream users need to evaluate GPL compliance for their applications.
