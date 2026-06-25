import Aria2RPC
import Foundation

/// A high-level async download client backed by an aria2 JSON-RPC endpoint.
///
/// Create a client with an ``Aria2RPC/Aria2Endpoint`` from ``Aria2Daemon`` when
/// you want SwiftAria to launch and manage the bundled `aria2c` executable for
/// the app. Use ``download(_:)`` to start a transfer and receive a
/// ``DownloadHandle`` for progress, cancellation, pausing, resuming, and waiting
/// for completion.
public actor DownloadClient {
    private let backend: DownloadBackend

    /// Unavailable. Create a client with ``init(endpoint:)``.
    @available(*, unavailable, message: "Use init(endpoint:) or start Aria2Daemon and pass daemon.endpoint.")
    public init() {
        fatalError("Use init(endpoint:) or start Aria2Daemon and pass daemon.endpoint.")
    }

    /// Creates a download client that talks to an aria2 JSON-RPC endpoint.
    ///
    /// - Parameter endpoint: The RPC endpoint exposed by an aria2 daemon.
    public init(endpoint: Aria2Endpoint) {
        self.backend = RPCAria2Backend(endpoint: endpoint)
    }

    init(backend: DownloadBackend) {
        self.backend = backend
    }

    /// Starts a download and returns a handle for observing and controlling it.
    ///
    /// The request is validated before it is sent to aria2. The current public
    /// API supports HTTP, HTTPS, and FTP URLs with file URL destinations.
    ///
    /// - Parameter request: The download request to start.
    /// - Returns: A handle that exposes progress updates and control operations.
    /// - Throws: ``DownloadError`` when the request is invalid or aria2 rejects the download.
    public func download(_ request: DownloadRequest) async throws -> DownloadHandle {
        try request.validate()
        let session = try await backend.start(request)

        return DownloadHandle(
            id: session.id,
            progressUpdates: session.progressUpdates,
            pauseAction: {
                try await self.pause(session.id)
            },
            resumeAction: {
                try await self.resume(session.id)
            },
            cancelAction: {
                try await self.cancel(session.id)
            },
            valueAction: {
                try await self.wait(for: session.id)
            }
        )
    }

    /// Pauses an active download.
    ///
    /// - Parameter id: The aria2 download identifier.
    public func pause(_ id: DownloadID) async throws {
        try await backend.pause(id)
    }

    /// Resumes a paused download.
    ///
    /// - Parameter id: The aria2 download identifier.
    public func resume(_ id: DownloadID) async throws {
        try await backend.resume(id)
    }

    /// Cancels a download.
    ///
    /// - Parameter id: The aria2 download identifier.
    public func cancel(_ id: DownloadID) async throws {
        try await backend.cancel(id)
    }

    /// Waits until a download reaches a terminal state.
    ///
    /// - Parameter id: The aria2 download identifier.
    /// - Returns: The requested destination URL when the download completes.
    /// - Throws: ``DownloadError/downloadFailed(id:message:)`` if the download fails or is cancelled.
    public func wait(for id: DownloadID) async throws -> URL {
        try await backend.wait(for: id)
    }
}

/// A stable identifier for an aria2 download.
public struct DownloadID: Hashable, Sendable, RawRepresentable, CustomStringConvertible {
    /// The raw aria2 GID string.
    public let rawValue: String

    /// Creates a download identifier from an aria2 GID string.
    ///
    /// - Parameter rawValue: The raw aria2 GID string.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// The raw aria2 GID string.
    public var description: String {
        rawValue
    }
}

/// A request describing a single-output download.
public struct DownloadRequest: Sendable, Equatable {
    /// The remote resource URL.
    public var url: URL

    /// The local file URL where aria2 should write the completed download.
    public var destination: URL

    /// HTTP headers to pass to aria2.
    public var headers: [String: String]

    /// The maximum number of connections to a single server.
    public var connectionsPerServer: Int

    /// The number of pieces aria2 should split the download into.
    public var splitCount: Int

    /// Creates a download request.
    ///
    /// - Parameters:
    ///   - url: The remote HTTP, HTTPS, or FTP URL.
    ///   - destination: The local file URL for the completed download.
    ///   - headers: HTTP headers to pass to aria2.
    ///   - connectionsPerServer: The maximum number of connections to a single server.
    ///   - splitCount: The number of pieces aria2 should split the download into.
    public init(
        url: URL,
        destination: URL,
        headers: [String: String] = [:],
        connectionsPerServer: Int = 4,
        splitCount: Int = 4
    ) {
        self.url = url
        self.destination = destination
        self.headers = headers
        self.connectionsPerServer = connectionsPerServer
        self.splitCount = splitCount
    }

    func validate() throws {
        guard url.scheme == "http" || url.scheme == "https" || url.scheme == "ftp" else {
            throw DownloadError.unsupportedURLScheme(url.scheme)
        }

        guard destination.isFileURL else {
            throw DownloadError.destinationMustBeFileURL(destination)
        }

        guard connectionsPerServer > 0 else {
            throw DownloadError.invalidOption("connectionsPerServer must be greater than zero")
        }

        guard splitCount > 0 else {
            throw DownloadError.invalidOption("splitCount must be greater than zero")
        }
    }
}

/// A point-in-time progress snapshot for a download.
public struct DownloadProgress: Sendable, Equatable {
    /// The download identifier.
    public var id: DownloadID

    /// The number of bytes written so far.
    public var completedBytes: Int64

    /// The expected total byte count, when aria2 knows it.
    public var totalBytes: Int64?

    /// The current transfer speed in bytes per second.
    public var bytesPerSecond: Int64

    /// The current download state.
    public var state: DownloadState

    /// Creates a progress snapshot.
    public init(
        id: DownloadID,
        completedBytes: Int64,
        totalBytes: Int64?,
        bytesPerSecond: Int64,
        state: DownloadState
    ) {
        self.id = id
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.bytesPerSecond = bytesPerSecond
        self.state = state
    }
}

/// The high-level state of a download.
public enum DownloadState: String, Sendable, Equatable {
    /// The download is waiting to start.
    case queued

    /// The download is actively transferring data.
    case active

    /// The download is paused.
    case paused

    /// The download completed successfully.
    case completed

    /// The download failed.
    case failed

    /// The download was cancelled or removed.
    case cancelled
}

/// A handle returned by ``DownloadClient`` for a running download.
public struct DownloadHandle: Sendable {
    /// The aria2 download identifier.
    public let id: DownloadID

    /// A stream of progress snapshots for the download.
    public let progressUpdates: AsyncStream<DownloadProgress>

    private let pauseAction: @Sendable () async throws -> Void
    private let resumeAction: @Sendable () async throws -> Void
    private let cancelAction: @Sendable () async throws -> Void
    private let valueAction: @Sendable () async throws -> URL

    init(
        id: DownloadID,
        progressUpdates: AsyncStream<DownloadProgress>,
        pauseAction: @escaping @Sendable () async throws -> Void,
        resumeAction: @escaping @Sendable () async throws -> Void,
        cancelAction: @escaping @Sendable () async throws -> Void,
        valueAction: @escaping @Sendable () async throws -> URL
    ) {
        self.id = id
        self.progressUpdates = progressUpdates
        self.pauseAction = pauseAction
        self.resumeAction = resumeAction
        self.cancelAction = cancelAction
        self.valueAction = valueAction
    }

    /// Pauses the download represented by this handle.
    public func pause() async throws {
        try await pauseAction()
    }

    /// Resumes the download represented by this handle.
    public func resume() async throws {
        try await resumeAction()
    }

    /// Cancels the download represented by this handle.
    public func cancel() async throws {
        try await cancelAction()
    }

    /// Waits for the download to finish and returns its destination URL.
    public var value: URL {
        get async throws {
            try await valueAction()
        }
    }
}

/// Errors produced by the high-level download API.
public enum DownloadError: Error, Sendable, Equatable {
    /// The request URL scheme is not supported by the public API.
    case unsupportedURLScheme(String?)

    /// The destination URL is not a file URL.
    case destinationMustBeFileURL(URL)

    /// A request option is invalid.
    case invalidOption(String)

    /// The configured backend is not available.
    case backendUnavailable(String)

    /// aria2 reported a terminal failure for the download.
    case downloadFailed(id: DownloadID, message: String)
}

struct DownloadSession: Sendable {
    var id: DownloadID
    var progressUpdates: AsyncStream<DownloadProgress>
}

protocol DownloadBackend: Sendable {
    func start(_ request: DownloadRequest) async throws -> DownloadSession
    func pause(_ id: DownloadID) async throws
    func resume(_ id: DownloadID) async throws
    func cancel(_ id: DownloadID) async throws
    func wait(for id: DownloadID) async throws -> URL
}
