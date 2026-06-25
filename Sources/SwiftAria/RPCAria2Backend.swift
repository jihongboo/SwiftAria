import Aria2RPC
import Foundation

actor RPCAria2Backend: DownloadBackend {
    private let client: Aria2RPCClient
    private var destinations: [DownloadID: URL] = [:]

    init(endpoint: Aria2Endpoint) {
        self.client = Aria2RPCClient(endpoint: endpoint)
    }

    func start(_ request: DownloadRequest) async throws -> DownloadSession {
        let options = rpcOptions(for: request)
        let gid = try await client.addURI([request.url.absoluteString], options: options)
        let id = DownloadID(rawValue: gid)
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
        try await client.pause(gid: id.rawValue)
    }

    func resume(_ id: DownloadID) async throws {
        try await client.resume(gid: id.rawValue)
    }

    func cancel(_ id: DownloadID) async throws {
        try await client.remove(gid: id.rawValue)
    }

    func wait(for id: DownloadID) async throws -> URL {
        while !Task.isCancelled {
            let progress = try await poll(id: id)
            switch progress.state {
            case .completed:
                guard let destination = destinations[id] else {
                    throw DownloadError.downloadFailed(id: id, message: "Missing destination for completed download")
                }
                return destination
            case .failed, .cancelled:
                throw DownloadError.downloadFailed(id: id, message: "Download ended with state \(progress.state.rawValue)")
            case .queued, .active, .paused:
                try await Task.sleep(for: .milliseconds(250))
            }
        }

        throw DownloadError.downloadFailed(id: id, message: "Download wait was cancelled")
    }

    private func monitor(id: DownloadID, continuation: AsyncStream<DownloadProgress>.Continuation) async {
        while !Task.isCancelled {
            do {
                let progress = try await poll(id: id)
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

    private func poll(id: DownloadID) async throws -> DownloadProgress {
        let status = try await client.tellStatus(
            gid: id.rawValue,
            keys: ["gid", "status", "totalLength", "completedLength", "downloadSpeed", "errorCode"]
        )

        return DownloadProgress(
            id: id,
            completedBytes: status.completedLength,
            totalBytes: status.totalLength,
            bytesPerSecond: status.downloadSpeed,
            state: DownloadState(rpcStatus: status.status)
        )
    }

    private func rpcOptions(for request: DownloadRequest) -> [String: String] {
        [
            "dir": request.destination.deletingLastPathComponent().path,
            "out": request.destination.lastPathComponent,
            "max-connection-per-server": String(request.connectionsPerServer),
            "split": String(request.splitCount),
        ]
    }
}

extension DownloadState {
    init(rpcStatus: String?) {
        switch rpcStatus {
        case "active":
            self = .active
        case "waiting":
            self = .queued
        case "paused":
            self = .paused
        case "complete":
            self = .completed
        case "removed":
            self = .cancelled
        case "error":
            self = .failed
        default:
            self = .failed
        }
    }
}
