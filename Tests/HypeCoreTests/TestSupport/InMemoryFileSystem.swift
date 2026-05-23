import Foundation
@testable import HypeCore

// MARK: - InMemoryFileSystem

/// An in-memory `FileSystemProviding` stub for use in tests.
///
/// Backed by a `[String: Data]` dictionary keyed by canonical path string.
/// Thread-safe via `NSLock`. Marked `@unchecked Sendable` because the lock
/// provides the necessary synchronisation that Swift's type system cannot
/// verify statically.
///
/// All paths are normalised to the `standardized` representation of the URL
/// to avoid mismatches between `/tmp/foo` and `/private/tmp/foo` on macOS.
package final class InMemoryFileSystem: FileSystemProviding, @unchecked Sendable {

    private let lock = NSLock()
    /// Maps normalised path → file data. Directories are represented as entries
    /// with empty `Data` and the path ending with a `/`.
    private var files: [String: Data] = [:]

    package init() {}

    // MARK: - Helpers

    private func key(for url: URL) -> String {
        url.standardized.path
    }

    private func directoryKey(for url: URL) -> String {
        let path = url.standardized.path
        return path.hasSuffix("/") ? path : path + "/"
    }

    // MARK: - FileSystemProviding

    package func fileExists(atPath path: String) -> Bool {
        let normalised = URL(fileURLWithPath: path).standardized.path
        return lock.withLock {
            files[normalised] != nil || files[normalised + "/"] != nil
        }
    }

    package func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]?
    ) throws {
        let dk = directoryKey(for: url)
        lock.withLock {
            files[dk] = Data()
        }
    }

    package func write(_ data: Data, to url: URL) throws {
        let k = key(for: url)
        lock.withLock {
            files[k] = data
        }
    }

    package func read(from url: URL) throws -> Data {
        let k = key(for: url)
        return try lock.withLock {
            guard let data = files[k] else {
                throw CocoaError(.fileNoSuchFile)
            }
            return data
        }
    }

    package func contents(ofDirectory url: URL) throws -> [URL] {
        let prefix = directoryKey(for: url)
        return lock.withLock {
            files.keys
                .filter { $0.hasPrefix(prefix) && $0 != prefix }
                .compactMap { path -> URL? in
                    // Only direct children — no recursive descent.
                    let relative = String(path.dropFirst(prefix.count))
                    if relative.contains("/") { return nil }
                    return URL(fileURLWithPath: path)
                }
                .sorted { $0.path < $1.path }
        }
    }

    package func removeItem(at url: URL) throws {
        let k = key(for: url)
        try lock.withLock {
            guard files.removeValue(forKey: k) != nil else {
                throw CocoaError(.fileNoSuchFile)
            }
        }
    }

    package func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        let normalised = URL(fileURLWithPath: path).standardized.path
        return try lock.withLock {
            guard let data = files[normalised] else {
                throw CocoaError(.fileNoSuchFile)
            }
            return [.size: data.count as NSNumber]
        }
    }
}
