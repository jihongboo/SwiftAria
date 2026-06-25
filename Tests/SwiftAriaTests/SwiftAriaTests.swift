import Aria2RPC
import Foundation
import Network
import Testing
@testable import SwiftAria

@Test func requestAcceptsHTTPURLsAndFileDestinations() throws {
    let request = DownloadRequest(
        url: try #require(URL(string: "https://example.com/file.zip")),
        destination: URL(filePath: "/tmp/file.zip")
    )

    #expect(throws: Never.self) {
        try request.validate()
    }
}

@Test func requestAcceptsFTPURLs() throws {
    let request = DownloadRequest(
        url: try #require(URL(string: "ftp://example.com/file.zip")),
        destination: URL(filePath: "/tmp/file.zip")
    )

    #expect(throws: Never.self) {
        try request.validate()
    }
}

@Test func requestRejectsUnsupportedURLSchemes() throws {
    let request = DownloadRequest(
        url: try #require(URL(string: "sftp://example.com/file.zip")),
        destination: URL(filePath: "/tmp/file.zip")
    )

    #expect(throws: DownloadError.unsupportedURLScheme("sftp")) {
        try request.validate()
    }
}

@Test func requestRejectsNonFileDestinations() throws {
    let request = DownloadRequest(
        url: try #require(URL(string: "https://example.com/file.zip")),
        destination: try #require(URL(string: "https://example.com/output.zip"))
    )

    #expect(throws: DownloadError.destinationMustBeFileURL(request.destination)) {
        try request.validate()
    }
}

@Test func requestRejectsInvalidConnectionCounts() throws {
    let request = DownloadRequest(
        url: try #require(URL(string: "https://example.com/file.zip")),
        destination: URL(filePath: "/tmp/file.zip"),
        connectionsPerServer: 0
    )

    #expect(throws: DownloadError.invalidOption("connectionsPerServer must be greater than zero")) {
        try request.validate()
    }
}

@Test func downloadIDDescriptionUsesRawValue() {
    let id = DownloadID(rawValue: "42")

    #expect(id.description == "42")
}

@Test func downloadClientUsesInjectedBackend() async throws {
    let destination = URL(filePath: "/tmp/swiftaria-test.bin")
    let request = DownloadRequest(
        url: try #require(URL(string: "https://example.com/file.bin")),
        destination: destination
    )
    let backend = FakeDownloadBackend(destination: destination)
    let client = DownloadClient(backend: backend)

    let handle = try await client.download(request)
    let fileURL = try await handle.value

    #expect(handle.id == DownloadID(rawValue: "fake-gid"))
    #expect(fileURL == destination)
    #expect(await backend.startedRequests == [request])
}

@Test func rpcDaemonDownloadsFromLocalHTTPServer() async throws {
    let payload = Data("SwiftAria RPC integration test".utf8)
    let server = try LocalHTTPServer(payload: payload)
    defer { server.stop() }
    try await Task.sleep(for: .milliseconds(100))

    let directory = FileManager.default.temporaryDirectory
        .appending(path: "SwiftAriaRPCTests-")
        .appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let daemon = try Aria2Daemon(
        port: randomPort(),
        downloadDirectory: directory
    )
    try await daemon.start()
    defer { Task { await daemon.stop() } }

    let rpcClient = Aria2RPCClient(endpoint: daemon.endpoint)
    try await waitForRPCServer(rpcClient)

    let destination = directory.appending(path: "payload.txt")
    let request = DownloadRequest(
        url: server.url,
        destination: destination,
        connectionsPerServer: 1,
        splitCount: 1
    )

    let client = DownloadClient(endpoint: daemon.endpoint)
    let handle = try await client.download(request)
    let fileURL = try await handle.value
    let downloaded = try Data(contentsOf: fileURL)

    #expect(downloaded == payload)
}

actor FakeDownloadBackend: DownloadBackend {
    private let destination: URL
    private(set) var startedRequests: [DownloadRequest] = []

    init(destination: URL) {
        self.destination = destination
    }

    func start(_ request: DownloadRequest) async throws -> DownloadSession {
        startedRequests.append(request)
        let id = DownloadID(rawValue: "fake-gid")
        let stream = AsyncStream<DownloadProgress> { continuation in
            continuation.yield(
                DownloadProgress(
                    id: id,
                    completedBytes: 1,
                    totalBytes: 1,
                    bytesPerSecond: 0,
                    state: .completed
                )
            )
            continuation.finish()
        }

        return DownloadSession(id: id, progressUpdates: stream)
    }

    func pause(_ id: DownloadID) async throws {}
    func resume(_ id: DownloadID) async throws {}
    func cancel(_ id: DownloadID) async throws {}

    func wait(for id: DownloadID) async throws -> URL {
        destination
    }
}

private final class LocalHTTPServer: @unchecked Sendable {
    let url: URL

    private let listener: NWListener
    private let queue = DispatchQueue(label: "SwiftAriaTests.LocalHTTPServer")
    private let payload: Data

    init(payload: Data) throws {
        self.payload = payload

        var selectedListener: NWListener?
        var selectedPort: UInt16?
        for _ in 0..<20 {
            let candidate = randomPort()
            guard let port = NWEndpoint.Port(rawValue: candidate) else { continue }

            do {
                selectedListener = try NWListener(using: .tcp, on: port)
                selectedPort = candidate
                break
            } catch {
                continue
            }
        }

        listener = try #require(selectedListener)
        let port = try #require(selectedPort)
        url = try #require(URL(string: "http://127.0.0.1:\(port)/payload.txt"))

        listener.newConnectionHandler = { [payload, queue] connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { _, _, _, _ in
                let header = "HTTP/1.1 200 OK\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
                var response = Data(header.utf8)
                response.append(payload)
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener.cancel()
    }
}

private func randomPort() -> UInt16 {
    UInt16.random(in: 40_000...60_000)
}

private func waitForRPCServer(_ client: Aria2RPCClient) async throws {
    var lastError: Error?
    for _ in 0..<20 {
        do {
            _ = try await client.getVersion()
            return
        } catch {
            lastError = error
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    if let lastError {
        throw lastError
    }
}
