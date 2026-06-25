# ``SwiftAria``

Launch bundled aria2 and manage downloads with async/await APIs.

## Overview

The `SwiftAria` product is the complete local daemon layer. It depends on the lightweight `Aria2RPC` product, bundles an `aria2c` executable, starts it with JSON-RPC enabled, and exposes a high-level download API.

Use `SwiftAria` when your app should include aria2 itself. Use the `Aria2RPC` product directly when your app only needs to control an existing aria2 daemon.

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

for await progress in handle.progressUpdates {
    print(progress.completedBytes)
}

let fileURL = try await handle.value
print(fileURL)
```

The current public download API supports HTTP, HTTPS, and FTP URLs with local file destinations.

## Topics

### Starting aria2

- ``Aria2Daemon``
- ``Aria2DaemonError``

### Downloading Files

- ``DownloadClient``
- ``DownloadRequest``
- ``DownloadHandle``
- ``DownloadID``
- ``DownloadProgress``
- ``DownloadState``
- ``DownloadError``
