import Foundation

// MARK: - FileSystemProviding

/// An abstraction over filesystem operations used by AI tool branches.
///
/// The production conformance is `FileManager.default` via the extension below.
/// Tests inject `InMemoryFileSystem` to avoid touching the real filesystem,
/// which can cause flakes in parallel runs due to `/tmp` races and permission
/// side-effects.
///
/// The surface area is deliberately limited to the operations actually needed by
/// `FileIOExecutorBranches`. It is not intended to replace `FileManager` in
/// general — only to provide a seam for test isolation in the tool layer.
public protocol FileSystemProviding: Sendable {

    /// Returns `true` when an item exists at the given path.
    func fileExists(atPath path: String) -> Bool

    /// Creates the directory hierarchy at the given URL.
    func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]?
    ) throws

    /// Writes `data` to the given URL atomically.
    func write(_ data: Data, to url: URL) throws

    /// Reads and returns the data at the given URL.
    func read(from url: URL) throws -> Data

    /// Returns the URLs of items directly inside the given directory URL.
    func contents(ofDirectory url: URL) throws -> [URL]

    /// Removes the item at the given URL.
    func removeItem(at url: URL) throws

    /// Returns the file-system attributes of the item at the given path.
    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any]
}

// MARK: - FileManager conformance

/// `FileManager` satisfies `FileSystemProviding` via forwarding methods.
///
/// `@retroactive` is not required because `FileManager` is Foundation's class
/// and this extension lives in the same module target that defines the protocol.
/// `@unchecked Sendable` is not added to `FileManager` itself — the conformance
/// is declared here; `FileManager`'s thread-safety is documented by Apple and
/// relied upon throughout the existing codebase.
extension FileManager: FileSystemProviding {

    public func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    public func read(from url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func contents(ofDirectory url: URL) throws -> [URL] {
        try contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])
    }
}
