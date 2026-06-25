import Foundation

/// The JSON-RPC endpoint for an aria2 daemon.
public struct Aria2Endpoint: Sendable, Equatable {
    /// The full JSON-RPC URL, usually ending in `/jsonrpc`.
    public var url: URL

    /// The optional aria2 RPC secret.
    public var token: String?

    /// Creates an aria2 RPC endpoint.
    ///
    /// - Parameters:
    ///   - url: The full JSON-RPC URL.
    ///   - token: The optional RPC secret. When set, Aria2RPC sends it as `token:<secret>`.
    public init(url: URL, token: String? = nil) {
        self.url = url
        self.token = token
    }
}

/// A low-level aria2 JSON-RPC client.
///
/// Use this type when you need direct access to aria2 RPC methods. Apps that
/// want the bundled local daemon and a higher-level download API can use the
/// `SwiftAria` product instead.
public final class Aria2RPCClient: @unchecked Sendable {
    private let endpoint: Aria2Endpoint
    private let session: URLSession

    /// Creates a JSON-RPC client.
    ///
    /// - Parameters:
    ///   - endpoint: The aria2 JSON-RPC endpoint.
    ///   - session: The URL session used to send RPC requests.
    public init(endpoint: Aria2Endpoint, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    /// Calls `aria2.addUri` and returns the new GID.
    ///
    /// - Parameters:
    ///   - uris: One or more source URIs for the same download.
    ///   - options: aria2 options for the download.
    /// - Returns: The aria2 GID for the created download.
    public func addURI(_ uris: [String], options: [String: String] = [:]) async throws -> String {
        let result = try await call(method: "aria2.addUri", params: [uris, options])
        guard let gid = result as? String else {
            throw Aria2RPCError.invalidResult
        }

        return gid
    }

    /// Calls `aria2.pause` for a GID.
    ///
    /// - Parameter gid: The aria2 GID to pause.
    public func pause(gid: String) async throws {
        _ = try await call(method: "aria2.pause", params: [gid])
    }

    /// Calls `aria2.unpause` for a GID.
    ///
    /// - Parameter gid: The aria2 GID to resume.
    public func resume(gid: String) async throws {
        _ = try await call(method: "aria2.unpause", params: [gid])
    }

    /// Calls `aria2.remove` for a GID.
    ///
    /// - Parameter gid: The aria2 GID to remove.
    public func remove(gid: String) async throws {
        _ = try await call(method: "aria2.remove", params: [gid])
    }

    /// Calls `aria2.tellStatus` for a GID.
    ///
    /// - Parameters:
    ///   - gid: The aria2 GID to inspect.
    ///   - keys: Optional aria2 status keys to request.
    /// - Returns: A typed subset of aria2's status payload.
    public func tellStatus(gid: String, keys: [String] = []) async throws -> Aria2Status {
        let params: [Any]
        if keys.isEmpty {
            params = [gid]
        } else {
            params = [gid, keys]
        }

        let result = try await call(method: "aria2.tellStatus", params: params)
        guard let status = result as? [String: Any] else {
            throw Aria2RPCError.invalidResult
        }

        return Aria2Status(payload: status)
    }

    /// Calls `aria2.getVersion`.
    ///
    /// - Returns: The raw JSON object returned by aria2.
    public func getVersion() async throws -> [String: Any] {
        let result = try await call(method: "aria2.getVersion", params: [])
        guard let version = result as? [String: Any] else {
            throw Aria2RPCError.invalidResult
        }

        return version
    }

    /// Calls an arbitrary aria2 JSON-RPC method.
    ///
    /// The RPC secret from ``Aria2Endpoint/token`` is inserted automatically when present.
    ///
    /// - Parameters:
    ///   - method: The aria2 RPC method name, such as `aria2.tellStatus`.
    ///   - params: The method parameters without the RPC token.
    /// - Returns: The raw `result` value from aria2's JSON-RPC response.
    public func call(method: String, params: [Any]) async throws -> Any {
        var request = URLRequest(url: endpoint.url)
        request.httpMethod = "POST"
        request.setValue("application/json-rpc", forHTTPHeaderField: "Content-Type")

        var rpcParams = params
        if let token = endpoint.token {
            rpcParams.insert("token:\(token)", at: 0)
        }

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": UUID().uuidString,
            "method": method,
            "params": rpcParams,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw Aria2RPCError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw Aria2RPCError.httpStatus(httpResponse.statusCode)
        }

        let object = try JSONSerialization.jsonObject(with: data)
        guard let payload = object as? [String: Any] else {
            throw Aria2RPCError.invalidResponse
        }

        if let error = payload["error"] as? [String: Any] {
            let code = error["code"] as? Int ?? -1
            let message = error["message"] as? String ?? "Unknown aria2 RPC error"
            throw Aria2RPCError.rpc(code: code, message: message)
        }

        guard let result = payload["result"] else {
            throw Aria2RPCError.invalidResult
        }

        return result
    }
}

/// A typed subset of an aria2 `tellStatus` response.
public struct Aria2Status: Sendable, Equatable {
    /// The aria2 GID.
    public var gid: String

    /// The raw aria2 status string.
    public var status: String

    /// The total download size in bytes, or `0` when aria2 does not know it yet.
    public var totalLength: Int64

    /// The number of completed bytes.
    public var completedLength: Int64

    /// The current download speed in bytes per second.
    public var downloadSpeed: Int64

    /// The aria2 error code, or `0` when there is no error.
    public var errorCode: Int

    init(payload: [String: Any]) {
        gid = payload["gid"] as? String ?? ""
        status = payload["status"] as? String ?? ""
        totalLength = Int64(payload["totalLength"] as? String ?? "0") ?? 0
        completedLength = Int64(payload["completedLength"] as? String ?? "0") ?? 0
        downloadSpeed = Int64(payload["downloadSpeed"] as? String ?? "0") ?? 0
        errorCode = Int(payload["errorCode"] as? String ?? "0") ?? 0
    }
}

/// Errors thrown by ``Aria2RPCClient``.
public enum Aria2RPCError: Error, Sendable, Equatable {
    /// The HTTP response or JSON-RPC envelope had an unexpected shape.
    case invalidResponse

    /// The JSON-RPC result was missing or had an unexpected type.
    case invalidResult

    /// The RPC endpoint returned a non-success HTTP status code.
    case httpStatus(Int)

    /// aria2 returned a JSON-RPC error object.
    case rpc(code: Int, message: String)
}
