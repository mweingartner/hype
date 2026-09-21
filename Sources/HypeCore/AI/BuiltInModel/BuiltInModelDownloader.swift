import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Progress of a Built-in model installation.
public struct BuiltInDownloadProgress: Sendable, Equatable {
    public enum Phase: String, Sendable, Equatable {
        case downloading
        case verifying
        case finished
    }

    public var phase: Phase
    public var completedBytes: Int64
    public var totalBytes: Int64
    public var currentFile: String?

    public init(phase: Phase, completedBytes: Int64, totalBytes: Int64, currentFile: String?) {
        self.phase = phase
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.currentFile = currentFile
    }

    public var fraction: Double {
        totalBytes > 0 ? min(1, Double(completedBytes) / Double(totalBytes)) : 0
    }
}

public enum BuiltInModelDownloadError: Error, LocalizedError, Equatable {
    case invalidManifestPath(String)
    case insufficientDiskSpace(requiredBytes: Int64, availableBytes: Int64)
    case disallowedHost(String)
    case unexpectedStatus(path: String, status: Int)
    case sizeMismatch(path: String)
    case checksumMismatch(path: String)
    case hashingUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidManifestPath(let path):
            return "The model manifest contains an unsafe file path (\(path))."
        case .insufficientDiskSpace(let required, let available):
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return "Not enough disk space: \(formatter.string(fromByteCount: required)) needed, \(formatter.string(fromByteCount: available)) available."
        case .disallowedHost(let host):
            return "The model download was redirected to an unexpected host (\(host)) and was stopped."
        case .unexpectedStatus(let path, let status):
            return "Downloading \(path) failed (HTTP \(status))."
        case .sizeMismatch(let path):
            return "\(path) did not have the expected size. The partial file was discarded; try again."
        case .checksumMismatch(let path):
            return "\(path) failed its integrity check. The file was discarded; try again."
        case .hashingUnavailable:
            return "This platform cannot verify model downloads."
        }
    }
}

/// Downloads a Built-in model variant, resumably, and verifies every file
/// against the SHA-256 pinned in Hype's catalog before activating it.
///
/// Guardrails:
/// - only ever started by an explicit user action (never a silent multi-GB fetch);
/// - HTTPS only, hosts restricted to Hugging Face and its LFS CDNs — redirects
///   included;
/// - a file that is too large, too small or has the wrong hash is deleted;
/// - the variant becomes visible to the rest of Hype only after *all* files
///   verified (staging directory → atomic move).
public final class BuiltInModelDownloader: Sendable {
    public static let allowedHostSuffixes = ["huggingface.co", "hf.co"]
    /// Free space required beyond the bytes still to download.
    static let diskSafetyMarginBytes: Int64 = 2 << 30

    private let store: BuiltInModelStore
    private let sessionConfiguration: URLSessionConfiguration

    public init(
        store: BuiltInModelStore = BuiltInModelStore(),
        sessionConfiguration: URLSessionConfiguration = BuiltInModelDownloader.defaultSessionConfiguration()
    ) {
        self.store = store
        self.sessionConfiguration = sessionConfiguration
    }

    public static func defaultSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 60 * 60 * 24
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return configuration
    }

    static func isAllowed(host: String?) -> Bool {
        guard let host = host?.lowercased(), !host.isEmpty else { return false }
        return allowedHostSuffixes.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else { return false }
        return !path.split(separator: "/", omittingEmptySubsequences: false).contains { component in
            component.isEmpty || component == "." || component == ".."
        }
    }

    /// Installs `variant` and returns its directory. Safe to call again after a
    /// failure or cancellation: verified files are kept, partial files resume.
    @discardableResult
    public func install(
        _ variant: BuiltInModelVariant,
        progress: @escaping @Sendable (BuiltInDownloadProgress) -> Void
    ) async throws -> URL {
        if let existing = store.location(of: variant) {
            progress(.init(phase: .finished, completedBytes: variant.totalBytes, totalBytes: variant.totalBytes, currentFile: nil))
            return existing.directory
        }
        for file in variant.files where !Self.isSafeRelativePath(file.path) {
            throw BuiltInModelDownloadError.invalidManifestPath(file.path)
        }

        let fileManager = FileManager.default
        let staging = store.stagingDirectory(for: variant)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

        let alreadyStaged = variant.files.reduce(Int64(0)) { total, file in
            let size = BuiltInModelStore.fileSize(at: staging.appendingPathComponent(file.path)) ?? 0
            return total + min(size, file.size)
        }
        let remaining = variant.totalBytes - alreadyStaged
        if let available = store.freeDiskBytes(), available < remaining + Self.diskSafetyMarginBytes {
            throw BuiltInModelDownloadError.insufficientDiskSpace(
                requiredBytes: remaining + Self.diskSafetyMarginBytes,
                availableBytes: available
            )
        }

        var completed: Int64 = 0
        for file in variant.files {
            try Task.checkCancellation()
            guard let url = variant.downloadURL(for: file), Self.isAllowed(host: url.host) else {
                throw BuiltInModelDownloadError.disallowedHost(variant.downloadURL(for: file)?.host ?? "")
            }
            let destination = staging.appendingPathComponent(file.path)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let base = completed
            try await fetch(file, from: url, to: destination) { fileBytes, phase in
                progress(.init(
                    phase: phase,
                    completedBytes: base + fileBytes,
                    totalBytes: variant.totalBytes,
                    currentFile: file.path
                ))
            }
            completed += file.size
        }

        let destination = store.installDirectory(for: variant)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: staging, to: destination)
        // Every file was hashed moments ago; first use need not hash them again.
        store.recordVerifiedWeights(of: variant, at: destination)
        var root = store.modelsRoot
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? root.setResourceValues(values)

        progress(.init(phase: .finished, completedBytes: variant.totalBytes, totalBytes: variant.totalBytes, currentFile: nil))
        return destination
    }

    // MARK: - One file

    private func fetch(
        _ file: BuiltInModelFile,
        from url: URL,
        to destination: URL,
        report: @escaping @Sendable (Int64, BuiltInDownloadProgress.Phase) -> Void
    ) async throws {
        let fileManager = FileManager.default
        var existing = BuiltInModelStore.fileSize(at: destination) ?? 0
        if existing > file.size {
            try? fileManager.removeItem(at: destination)
            existing = 0
        }

        // A zero-byte pinned file has nothing to fetch (`existing < file.size`
        // is false for it), but still needs to exist on disk to verify below.
        if existing == 0 {
            fileManager.createFile(atPath: destination.path, contents: nil)
        }

        if existing < file.size {
            let sink = try FileSink(url: destination, startOffset: existing, expectedSize: file.size, path: file.path) { written in
                report(written, .downloading)
            }
            var request = URLRequest(url: url)
            if existing > 0 {
                request.setValue("bytes=\(existing)-", forHTTPHeaderField: "Range")
            }
            let delegate = DownloadDelegate(sink: sink, path: file.path, resumedFrom: existing)
            let session = URLSession(configuration: sessionConfiguration, delegate: delegate, delegateQueue: delegate.queue)
            defer { session.finishTasksAndInvalidate() }
            let task = session.dataTask(with: request)
            try await withTaskCancellationHandler {
                try await delegate.run(task)
            } onCancel: {
                task.cancel()
            }
        }

        report(file.size, .verifying)
        guard BuiltInModelStore.fileSize(at: destination) == file.size else {
            try? fileManager.removeItem(at: destination)
            throw BuiltInModelDownloadError.sizeMismatch(path: file.path)
        }
        let digest = try Self.sha256(of: destination)
        guard digest == file.sha256.lowercased() else {
            try? fileManager.removeItem(at: destination)
            throw BuiltInModelDownloadError.checksumMismatch(path: file.path)
        }
    }

    static func sha256(of url: URL) throws -> String {
        #if canImport(CryptoKit)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 4 << 20) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        #else
        throw BuiltInModelDownloadError.hashingUnavailable
        #endif
    }
}

// MARK: - Plumbing

/// Appends received bytes to the partial file, refusing to exceed the pinned size.
private final class FileSink: @unchecked Sendable {
    private let handle: FileHandle
    private let expectedSize: Int64
    private let path: String
    private let onWrite: @Sendable (Int64) -> Void
    private var written: Int64

    init(
        url: URL,
        startOffset: Int64,
        expectedSize: Int64,
        path: String,
        onWrite: @escaping @Sendable (Int64) -> Void
    ) throws {
        handle = try FileHandle(forWritingTo: url)
        try handle.seek(toOffset: UInt64(startOffset))
        self.expectedSize = expectedSize
        self.path = path
        self.onWrite = onWrite
        written = startOffset
    }

    /// Discards everything written so far (the server ignored our Range header).
    func restart() throws {
        try handle.truncate(atOffset: 0)
        try handle.seek(toOffset: 0)
        written = 0
    }

    func append(_ data: Data) throws {
        guard written + Int64(data.count) <= expectedSize else {
            throw BuiltInModelDownloadError.sizeMismatch(path: path)
        }
        try handle.write(contentsOf: data)
        written += Int64(data.count)
        onWrite(written)
    }

    func close() {
        try? handle.close()
    }
}

/// Bridges URLSession's delegate callbacks (serialized on `queue`) to async/await.
private final class DownloadDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let queue: OperationQueue
    private let sink: FileSink
    private let path: String
    private let resumedFrom: Int64
    private var continuation: CheckedContinuation<Void, Error>?
    private var failure: Error?

    init(sink: FileSink, path: String, resumedFrom: Int64) {
        self.sink = sink
        self.path = path
        self.resumedFrom = resumedFrom
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    func run(_ task: URLSessionDataTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.addOperation {
                self.continuation = continuation
                task.resume()
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard request.url?.scheme?.lowercased() == "https",
              BuiltInModelDownloader.isAllowed(host: request.url?.host) else {
            failure = BuiltInModelDownloadError.disallowedHost(request.url?.host ?? "")
            completionHandler(nil)
            task.cancel()
            return
        }
        completionHandler(request)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        do {
            switch status {
            case 206 where resumedFrom > 0:
                break
            case 200:
                // Full body: either a fresh download or a server that ignored Range.
                if resumedFrom > 0 { try sink.restart() }
            default:
                throw BuiltInModelDownloadError.unexpectedStatus(path: path, status: status)
            }
            completionHandler(.allow)
        } catch {
            failure = error
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard failure == nil else { return }
        do {
            try sink.append(data)
        } catch {
            failure = error
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        sink.close()
        let continuation = self.continuation
        self.continuation = nil
        if let failure {
            continuation?.resume(throwing: failure)
        } else if let error {
            let cancelled = (error as NSError).code == NSURLErrorCancelled
            continuation?.resume(throwing: cancelled ? CancellationError() : error)
        } else {
            continuation?.resume()
        }
    }
}
