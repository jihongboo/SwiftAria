import Foundation
import CAria2Bridge

public actor DownloadClient {
    private let backend: DownloadBackend

    public init() {
        self.backend = NativeAria2Backend.shared
    }

    init(backend: DownloadBackend) {
        self.backend = backend
    }

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

    public func pause(_ id: DownloadID) async throws {
        try await backend.pause(id)
    }

    public func resume(_ id: DownloadID) async throws {
        try await backend.resume(id)
    }

    public func cancel(_ id: DownloadID) async throws {
        try await backend.cancel(id)
    }

    public func wait(for id: DownloadID) async throws -> URL {
        try await backend.wait(for: id)
    }
}

public struct DownloadID: Hashable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }
}

public struct DownloadRequest: Sendable, Equatable {
    public var url: URL
    public var destination: URL
    public var headers: [String: String]
    public var connectionsPerServer: Int
    public var splitCount: Int

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
        guard url.scheme == "http" || url.scheme == "https" else {
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

public struct DownloadProgress: Sendable, Equatable {
    public var id: DownloadID
    public var completedBytes: Int64
    public var totalBytes: Int64?
    public var bytesPerSecond: Int64
    public var state: DownloadState

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

public enum DownloadState: String, Sendable, Equatable {
    case queued
    case active
    case paused
    case completed
    case failed
    case cancelled
}

public struct DownloadHandle: Sendable {
    public let id: DownloadID
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

    public func pause() async throws {
        try await pauseAction()
    }

    public func resume() async throws {
        try await resumeAction()
    }

    public func cancel() async throws {
        try await cancelAction()
    }

    public var value: URL {
        get async throws {
            try await valueAction()
        }
    }
}

public enum DownloadError: Error, Sendable, Equatable {
    case unsupportedURLScheme(String?)
    case destinationMustBeFileURL(URL)
    case invalidOption(String)
    case backendUnavailable(String)
    case clientDeallocated
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

final class Aria2SessionBox: @unchecked Sendable {
    let raw: OpaquePointer

    init(raw: OpaquePointer) {
        self.raw = raw
    }

    deinit {
        swift_aria2_session_destroy(raw)
    }
}

actor NativeAria2Backend: DownloadBackend {
    static let shared = NativeAria2Backend()

    private var sessionBox: Aria2SessionBox?
    private var destinations: [DownloadID: URL] = [:]

    func start(_ request: DownloadRequest) async throws -> DownloadSession {
        guard swift_aria2_backend_available() != 0 else {
            throw DownloadError.backendUnavailable(statusMessage)
        }

        let session = try sessionHandle()
        let directory = request.destination.deletingLastPathComponent().path
        let fileName = request.destination.lastPathComponent
        let urlString = request.url.absoluteString
        var rawGID: UInt64 = 0

        let result = urlString.withCString { urlPointer in
            directory.withCString { directoryPointer in
                fileName.withCString { fileNamePointer in
                    swift_aria2_add_uri(
                        session,
                        urlPointer,
                        directoryPointer,
                        fileNamePointer,
                        CInt(request.connectionsPerServer),
                        CInt(request.splitCount),
                        &rawGID
                    )
                }
            }
        }

        guard result == 0 else {
            throw DownloadError.downloadFailed(
                id: DownloadID(rawValue: String(rawGID)),
                message: "aria2 addUri failed with code \(result)"
            )
        }

        let id = DownloadID(rawValue: String(rawGID))
        destinations[id] = request.destination

        let stream = AsyncStream<DownloadProgress> { continuation in
            let task = Task {
                await self.monitor(id: id, continuation: continuation)
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }

        return DownloadSession(id: id, progressUpdates: stream)
    }

    func pause(_ id: DownloadID) async throws {
        let result = swift_aria2_pause(try sessionHandle(), try rawGID(for: id))
        try throwIfNeeded(result, id: id, action: "pause")
    }

    func resume(_ id: DownloadID) async throws {
        let result = swift_aria2_resume(try sessionHandle(), try rawGID(for: id))
        try throwIfNeeded(result, id: id, action: "resume")
    }

    func cancel(_ id: DownloadID) async throws {
        let result = swift_aria2_cancel(try sessionHandle(), try rawGID(for: id))
        try throwIfNeeded(result, id: id, action: "cancel")
    }

    func wait(for id: DownloadID) async throws -> URL {
        while !Task.isCancelled {
            let progress = try poll(id: id)
            switch progress.state {
            case .completed:
                guard let destination = destinations[id] else {
                    throw DownloadError.downloadFailed(id: id, message: "Missing destination for completed download")
                }
                return destination
            case .failed, .cancelled:
                let status = try status(for: id)
                throw DownloadError.downloadFailed(
                    id: id,
                    message: "Download ended with state \(progress.state.rawValue), aria2 error code \(status.error_code)"
                )
            case .queued, .active, .paused:
                try await Task.sleep(for: .milliseconds(250))
            }
        }

        throw DownloadError.downloadFailed(id: id, message: "Download wait was cancelled")
    }

    private func monitor(id: DownloadID, continuation: AsyncStream<DownloadProgress>.Continuation) async {
        while !Task.isCancelled {
            do {
                let progress = try poll(id: id)
                continuation.yield(progress)

                if progress.state == .completed || progress.state == .failed || progress.state == .cancelled {
                    continuation.finish()
                    return
                }

                try await Task.sleep(for: .milliseconds(250))
            } catch {
                continuation.finish()
                return
            }
        }

        continuation.finish()
    }

    private func poll(id: DownloadID) throws -> DownloadProgress {
        let session = try sessionHandle()
        _ = swift_aria2_session_run_once(session)

        let status = try status(for: id)

        return DownloadProgress(
            id: id,
            completedBytes: status.completed_length,
            totalBytes: status.total_length >= 0 ? status.total_length : nil,
            bytesPerSecond: status.download_speed,
            state: DownloadState(status.state)
        )
    }

    private func status(for id: DownloadID) throws -> swift_aria2_download_status_t {
        var status = swift_aria2_download_status_t()
        let result = swift_aria2_get_status(try sessionHandle(), try rawGID(for: id), &status)
        guard result == 0 else {
            throw DownloadError.downloadFailed(id: id, message: "aria2 getStatus failed with code \(result)")
        }

        return status
    }

    private func sessionHandle() throws -> OpaquePointer {
        if let sessionBox {
            return sessionBox.raw
        }

        guard let created = swift_aria2_session_create() else {
            throw DownloadError.backendUnavailable("Failed to create aria2 session. \(statusMessage)")
        }

        let box = Aria2SessionBox(raw: created)
        sessionBox = box
        return box.raw
    }

    private func rawGID(for id: DownloadID) throws -> UInt64 {
        guard let gid = UInt64(id.rawValue) else {
            throw DownloadError.downloadFailed(id: id, message: "Invalid aria2 gid")
        }

        return gid
    }

    private func throwIfNeeded(_ result: CInt, id: DownloadID, action: String) throws {
        guard result == 0 else {
            throw DownloadError.downloadFailed(id: id, message: "aria2 \(action) failed with code \(result)")
        }
    }

    private var statusMessage: String {
        guard let message = swift_aria2_backend_status_message() else {
            return "SwiftAria native libaria2 backend is not linked yet."
        }

        return String(cString: message)
    }
}

extension DownloadState {
    init(_ state: swift_aria2_download_state_t) {
        switch state {
        case SWIFT_ARIA2_DOWNLOAD_STATE_ACTIVE:
            self = .active
        case SWIFT_ARIA2_DOWNLOAD_STATE_WAITING:
            self = .queued
        case SWIFT_ARIA2_DOWNLOAD_STATE_PAUSED:
            self = .paused
        case SWIFT_ARIA2_DOWNLOAD_STATE_COMPLETE:
            self = .completed
        case SWIFT_ARIA2_DOWNLOAD_STATE_ERROR:
            self = .failed
        case SWIFT_ARIA2_DOWNLOAD_STATE_REMOVED:
            self = .cancelled
        default:
            self = .failed
        }
    }
}
