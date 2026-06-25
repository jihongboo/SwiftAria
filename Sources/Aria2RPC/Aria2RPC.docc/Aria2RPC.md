# ``Aria2RPC``

Call aria2 JSON-RPC from Swift.

## Overview

Aria2RPC is the lightweight interface layer for aria2. It does not bundle or launch `aria2c`; it only talks to an existing aria2 JSON-RPC endpoint using Foundation networking.

Use this product when your app controls a remote aria2 service, a user-installed local aria2 daemon, or a daemon started by another process.

```swift
import Aria2RPC
import Foundation

let endpoint = Aria2Endpoint(
    url: URL(string: "http://127.0.0.1:6800/jsonrpc")!,
    token: "secret"
)
let client = Aria2RPCClient(endpoint: endpoint)
let gid = try await client.addURI([
    "https://example.com/archive.zip"
])
let status = try await client.tellStatus(gid: gid)
print(status.status)
```

Apps that want SwiftAria to launch the bundled `aria2c` executable should use the `SwiftAria` product.

## Topics

### Connecting

- ``Aria2Endpoint``
- ``Aria2RPCClient``

### Status

- ``Aria2Status``

### Errors

- ``Aria2RPCError``
