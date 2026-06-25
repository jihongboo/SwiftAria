import Foundation
import Testing
@testable import Aria2RPC

@Test func endpointStoresURLAndToken() throws {
    let url = try #require(URL(string: "http://127.0.0.1:6800/jsonrpc"))
    let endpoint = Aria2Endpoint(url: url, token: "secret")

    #expect(endpoint.url == url)
    #expect(endpoint.token == "secret")
}

@Test func addURISendsTokenAndParsesGID() async throws {
    let capturedBody = LockedValue<Data?>(nil)
    let url = mockRPCURL()
    let session = makeMockSession(for: url) { request in
        capturedBody.set(try requestBodyData(from: request))
        return try rpcResponse(for: url, result: "gid-123")
    }
    let endpoint = Aria2Endpoint(url: url, token: "secret")
    let client = Aria2RPCClient(endpoint: endpoint, session: session)

    let gid = try await client.addURI(
        ["https://example.com/file.zip"],
        options: ["dir": "/tmp", "out": "file.zip"]
    )

    #expect(gid == "gid-123")

    let body = try #require(capturedBody.value())
    let payload = try jsonObject(from: body)
    #expect(payload["method"] as? String == "aria2.addUri")

    let params = try #require(payload["params"] as? [Any])
    #expect(params.count == 3)
    #expect(params[0] as? String == "token:secret")
    #expect(params[1] as? [String] == ["https://example.com/file.zip"])

    let options = try #require(params[2] as? [String: String])
    #expect(options["dir"] == "/tmp")
    #expect(options["out"] == "file.zip")
}

@Test func tellStatusParsesStringBackedStatusPayload() async throws {
    let url = mockRPCURL()
    let session = makeMockSession(for: url) { _ in
        try rpcResponse(
            for: url,
            result: [
                "gid": "gid-123",
                "status": "active",
                "totalLength": "100",
                "completedLength": "40",
                "downloadSpeed": "20",
                "errorCode": "0",
            ]
        )
    }
    let endpoint = Aria2Endpoint(url: url)
    let client = Aria2RPCClient(endpoint: endpoint, session: session)

    let status = try await client.tellStatus(gid: "gid-123")

    #expect(status.gid == "gid-123")
    #expect(status.status == "active")
    #expect(status.totalLength == 100)
    #expect(status.completedLength == 40)
    #expect(status.downloadSpeed == 20)
    #expect(status.errorCode == 0)
}

@Test func rpcErrorResponseThrowsTypedError() async throws {
    let url = mockRPCURL()
    let session = makeMockSession(for: url) { _ in
        try rpcResponse(
            for: url,
            error: [
                "code": 1,
                "message": "Unauthorized",
            ]
        )
    }
    let endpoint = Aria2Endpoint(url: url)
    let client = Aria2RPCClient(endpoint: endpoint, session: session)

    await #expect(throws: Aria2RPCError.rpc(code: 1, message: "Unauthorized")) {
        _ = try await client.getVersion()
    }
}

private func mockRPCURL() -> URL {
    URL(string: "http://aria2.test/\(UUID().uuidString)/jsonrpc")!
}

private func makeMockSession(
    for url: URL,
    handler: @escaping MockURLProtocol.Handler
) -> URLSession {
    MockURLProtocol.register(handler, for: url)

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func rpcResponse(for url: URL, result: Any) throws -> (HTTPURLResponse, Data) {
    try httpResponse(
        for: url,
        payload: [
            "jsonrpc": "2.0",
            "id": "test",
            "result": result,
        ]
    )
}

private func rpcResponse(for url: URL, error: [String: Any]) throws -> (HTTPURLResponse, Data) {
    try httpResponse(
        for: url,
        payload: [
            "jsonrpc": "2.0",
            "id": "test",
            "error": error,
        ]
    )
}

private func httpResponse(for url: URL, payload: [String: Any]) throws -> (HTTPURLResponse, Data) {
    let response = try #require(
        HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )
    )
    let data = try JSONSerialization.data(withJSONObject: payload)
    return (response, data)
}

private func jsonObject(from data: Data) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: data)
    return try #require(object as? [String: Any])
}

private func requestBodyData(from request: URLRequest) throws -> Data {
    if let httpBody = request.httpBody {
        return httpBody
    }

    let stream = try #require(request.httpBodyStream)
    stream.open()
    defer { stream.close() }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count < 0 {
            throw MockURLProtocolError.unreadableBody
        }
        if count == 0 {
            break
        }
        data.append(buffer, count: count)
    }
    return data
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let handlers = LockedValue<[URL: Handler]>([:])

    static func register(_ handler: @escaping Handler, for url: URL) {
        handlers.withValue { values in
            values[url] = handler
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let handler = Self.handlers.value()[url] else {
            client?.urlProtocol(self, didFailWithError: MockURLProtocolError.missingHandler)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private enum MockURLProtocolError: Error {
    case missingHandler
    case unreadableBody
}

private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        self.storedValue = value
    }

    func value() -> Value {
        lock.withLock { storedValue }
    }

    func set(_ value: Value) {
        lock.withLock {
            storedValue = value
        }
    }

    func withValue(_ body: (inout Value) -> Void) {
        lock.withLock {
            body(&storedValue)
        }
    }
}
