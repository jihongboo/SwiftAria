import Aria2RPC
import Foundation

/// A helper that launches the bundled `aria2c` executable with JSON-RPC enabled.
///
/// `Aria2Daemon` is the default way to run aria2 from SwiftAria. After starting
/// the daemon, pass ``endpoint`` to ``DownloadClient/init(endpoint:)`` or
/// ``Aria2RPC/Aria2RPCClient/init(endpoint:session:)``.
public actor Aria2Daemon {
    /// The JSON-RPC endpoint exposed by the daemon.
    public nonisolated let endpoint: Aria2Endpoint

    private let process: Process

    /// Creates a daemon using SwiftAria's bundled `aria2c` executable.
    ///
    /// - Parameters:
    ///   - port: The loopback TCP port aria2 should listen on.
    ///   - token: The RPC secret used to authenticate local RPC calls.
    ///   - downloadDirectory: The default directory aria2 should use for downloads.
    ///   - extraArguments: Additional command-line arguments passed to `aria2c`.
    /// - Throws: ``Aria2DaemonError/bundledExecutableNotFound`` if the package resource is missing.
    public init(
        port: UInt16 = 6800,
        token: String = UUID().uuidString,
        downloadDirectory: URL,
        extraArguments: [String] = []
    ) throws {
        try self.init(
            executableURL: Self.bundledExecutableURL(),
            port: port,
            token: token,
            downloadDirectory: downloadDirectory,
            extraArguments: extraArguments
        )
    }

    /// Creates a daemon using a caller-provided `aria2c` executable.
    ///
    /// This initializer is useful for tests, development builds, or apps that
    /// want to control exactly which aria2 binary is launched.
    ///
    /// - Parameters:
    ///   - executableURL: A local executable URL for `aria2c`.
    ///   - port: The loopback TCP port aria2 should listen on.
    ///   - token: The RPC secret used to authenticate local RPC calls.
    ///   - downloadDirectory: The default directory aria2 should use for downloads.
    ///   - extraArguments: Additional command-line arguments passed to `aria2c`.
    public init(
        executableURL: URL,
        port: UInt16 = 6800,
        token: String = UUID().uuidString,
        downloadDirectory: URL,
        extraArguments: [String] = []
    ) throws {
        let endpointURL = URL(string: "http://127.0.0.1:\(port)/jsonrpc")!
        self.endpoint = Aria2Endpoint(url: endpointURL, token: token)

        process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "--enable-rpc=true",
            "--rpc-listen-all=false",
            "--rpc-listen-port=\(port)",
            "--rpc-secret=\(token)",
            "--dir=\(downloadDirectory.path)",
            "--enable-color=false",
            "--summary-interval=0",
            "--console-log-level=warn",
        ] + extraArguments
    }

    deinit {
        process.terminate()
    }

    /// Starts the aria2 process.
    ///
    /// Calling this method more than once is harmless while the process is running.
    public func start() throws {
        guard !process.isRunning else { return }
        try process.run()
    }

    /// Stops the aria2 process if it is running.
    public func stop() {
        guard process.isRunning else { return }
        process.terminate()
    }

    private static func bundledExecutableURL() throws -> URL {
        guard let resourceURL = Bundle.module.url(forResource: "aria2c", withExtension: nil) else {
            throw Aria2DaemonError.bundledExecutableNotFound
        }

        let executableURL = FileManager.default.temporaryDirectory
            .appending(path: "SwiftAria")
            .appending(path: "aria2c")
        try FileManager.default.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if FileManager.default.fileExists(atPath: executableURL.path) {
            try FileManager.default.removeItem(at: executableURL)
        }
        try FileManager.default.copyItem(at: resourceURL, to: executableURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        return executableURL
    }
}

/// Errors thrown while preparing or launching ``Aria2Daemon``.
public enum Aria2DaemonError: Error, Sendable, Equatable {
    /// The bundled `aria2c` package resource could not be found.
    case bundledExecutableNotFound
}
