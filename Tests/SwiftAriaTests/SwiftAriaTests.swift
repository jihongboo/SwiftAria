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

@Test func requestRejectsUnsupportedURLSchemes() throws {
    let request = DownloadRequest(
        url: try #require(URL(string: "ftp://example.com/file.zip")),
        destination: URL(filePath: "/tmp/file.zip")
    )

    #expect(throws: DownloadError.unsupportedURLScheme("ftp")) {
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

@Test func clientDownloadsFromLocalHTTPServer() async throws {
    let payload = Data("SwiftAria local integration test".utf8)
    let server = try LocalHTTPServer(payload: payload)
    defer { server.stop() }
    try await Task.sleep(for: .milliseconds(100))

    let directory = FileManager.default.temporaryDirectory
        .appending(path: "SwiftAriaTests-")
        .appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let (serverData, _) = try await URLSession.shared.data(from: server.url)
    #expect(serverData == payload)

    let destination = directory.appending(path: "payload.txt")
    let request = DownloadRequest(
        url: server.url,
        destination: destination,
        connectionsPerServer: 1,
        splitCount: 1
    )

    let handle = try await DownloadClient().download(request)
    let fileURL = try await handle.value
    let downloaded = try Data(contentsOf: fileURL)

    #expect(downloaded == payload)
}

@Test func clientDownloadsFromPublicInternet() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "SwiftAriaInternetTests-")
        .appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let destination = directory.appending(path: "example.html")
    let request = DownloadRequest(
        url: try #require(URL(string: "https://www.example.com/")),
        destination: destination,
        connectionsPerServer: 1,
        splitCount: 1
    )

    let handle = try await DownloadClient().download(request)
    let fileURL = try await handle.value
    let downloaded = try Data(contentsOf: fileURL)
    let html = String(decoding: downloaded, as: UTF8.self)

    #expect(!downloaded.isEmpty)
    #expect(html.contains("Example Domain"))
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
            let candidate = UInt16.random(in: 40_000...60_000)
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
