import Foundation

// MARK: - FileAccessError

/// Errors produced by file-access operations from HypeTalk scripts.
///
/// `scriptMessage` is the ONLY text that may be surfaced in `ScriptError.message`
/// — it intentionally omits any resolved or canonical path (Security Finding 7).
public enum FileAccessError: Error, Sendable, Equatable {
    case accessDenied
    case invalidPath
    case outsideSandbox
    case tooLarge
    case notFound
    case ioFailure

    /// User-facing description. MUST NOT contain any resolved/canonical path.
    public var scriptMessage: String {
        switch self {
        case .accessDenied:   return "File access is not enabled for this stack."
        case .invalidPath:    return "Invalid file name."
        case .outsideSandbox: return "File is in a restricted location."
        case .tooLarge:       return "File too large. Maximum 10 MB."
        case .notFound:       return "File not found."
        case .ioFailure:      return "Could not read or write the file."
        }
    }
}

// MARK: - FileAccessProvider

/// Provider for sandboxed file-read and file-write operations from HypeTalk
/// scripts. Injected into `ExecutionContext`; `StubFileAccessProvider` is the
/// deny-by-default implementation used when the stack has not enabled file access.
public protocol FileAccessProvider: Sendable {
    /// Returns the sandbox root URL, or `nil` to deny all access.
    func sandboxRoot() -> URL?
    /// Read the entire contents of the named file from the sandbox root as raw bytes.
    func readData(named name: String) async throws -> Data
    /// Write raw bytes to the named file in the sandbox root,
    /// replacing any existing content.
    func writeData(_ data: Data, named name: String) async throws
    /// Read the entire contents of the named file from the sandbox root as a UTF-8 string.
    func readFile(named name: String) async throws -> String
    /// Write `contents` to the named file in the sandbox root,
    /// replacing any existing content.
    func writeFile(_ contents: String, named name: String) async throws
}

// MARK: - StubFileAccessProvider

/// Deny-by-default implementation (Security Finding 4).
///
/// Injected whenever file access is disabled for the stack. Every call throws
/// `.accessDenied` so scripts get a clear, actionable error message rather than
/// a silent no-op.
public struct StubFileAccessProvider: FileAccessProvider, Sendable {
    public init() {}
    public func sandboxRoot() -> URL? { nil }
    public func readData(named name: String) async throws -> Data { throw FileAccessError.accessDenied }
    public func writeData(_ data: Data, named name: String) async throws { throw FileAccessError.accessDenied }
    public func readFile(named name: String) async throws -> String { throw FileAccessError.accessDenied }
    public func writeFile(_ contents: String, named name: String) async throws { throw FileAccessError.accessDenied }
}

// MARK: - SandboxedFileAccessProvider

/// Containment-based file-access provider. All reads and writes are confined
/// to a single directory (`root`); paths are validated pre- and
/// post-canonicalization to defeat symlink traversal.
///
/// NOTE (Security Finding 6): the sandbox root is keyed by stack UUID. A cloned
/// stack inherits the same UUID and therefore shares this directory. This is
/// documented as expected behaviour — it is NOT a cross-user privilege boundary.
public struct SandboxedFileAccessProvider: FileAccessProvider, Sendable {
    /// Maximum bytes for a single read (10 MB).
    public static let maxReadBytes  = 10 * 1024 * 1024
    /// Maximum bytes for a single write (10 MB).
    public static let maxWriteBytes = 10 * 1024 * 1024

    /// Defense-in-depth blocklist (Security Finding 5). Containment to `root`
    /// is the load-bearing security gate; these supplemental checks reject
    /// known-sensitive directories even if containment logic is ever loosened.
    static let blockedPathPrefixes: [String] = [
        "/etc/", "/usr/", "/bin/", "/sbin/", "/System/", "/var/db/",
        "/private/etc/", "/private/var/db/", "/Library/Keychains/",
    ]

    private let root: URL?

    public init(root: URL?) {
        self.root = root
    }

    public func sandboxRoot() -> URL? { root }

    // MARK: - Path validation

    /// Pure, unit-testable containment check.
    ///
    /// `name` MUST be a relative filename inside the sandbox; absolute paths
    /// are rejected. Traversal sequences (`..`) are rejected both before and
    /// after canonicalization (mirrors `MeshyImageInput.resolveFilePath`).
    ///
    /// - Parameters:
    ///   - name: A relative path provided by the HypeTalk script.
    ///   - root: The sandbox root directory URL.
    /// - Returns: The resolved `URL` within `root`.
    /// - Throws: `FileAccessError.invalidPath` for malformed inputs,
    ///   `FileAccessError.outsideSandbox` for containment failures.
    static func resolveSandboxedURL(name: String, root: URL) throws -> URL {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FileAccessError.invalidPath }
        // Reject absolute paths immediately.
        guard !trimmed.hasPrefix("/") else { throw FileAccessError.invalidPath }
        // Reject traversal pre-canonicalization (mirror MeshyImageInput).
        let standardized = (trimmed as NSString).standardizingPath
        for comp in standardized.split(separator: "/") where comp == ".." {
            throw FileAccessError.invalidPath
        }
        if standardized.hasPrefix("..") { throw FileAccessError.invalidPath }
        // Build candidate and resolve symlinks.
        let candidate = root.appendingPathComponent(trimmed)
        let resolved = candidate.resolvingSymlinksInPath()
        let canonicalRoot = root.resolvingSymlinksInPath()
        let rp = resolved.path
        let crp = canonicalRoot.path
        // Confirm the resolved path is inside (or equal to) the sandbox root.
        guard rp == crp || rp.hasPrefix(crp + "/") else {
            throw FileAccessError.outsideSandbox
        }
        // Defense-in-depth: reject known sensitive system directories.
        for blocked in blockedPathPrefixes where rp.hasPrefix(blocked) {
            throw FileAccessError.outsideSandbox
        }
        return resolved
    }

    // MARK: - Binary read (canonical containment path)

    /// Read raw bytes from the named file within the sandbox.
    ///
    /// This is the ONLY path that touches the filesystem for reads; `readFile`
    /// delegates to this method so there is a single containment gate.
    public func readData(named name: String) async throws -> Data {
        guard let root else { throw FileAccessError.accessDenied }
        let url = try Self.resolveSandboxedURL(name: name, root: root)
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { throw FileAccessError.notFound }
        // Stat-then-recheck to bound TOCTOU exposure on size.
        if let attrs = try? fm.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int, size > Self.maxReadBytes {
            throw FileAccessError.tooLarge
        }
        guard let data = try? Data(contentsOf: url) else { throw FileAccessError.ioFailure }
        guard data.count <= Self.maxReadBytes else { throw FileAccessError.tooLarge }
        return data
    }

    // MARK: - Binary write (canonical containment path)

    /// Write raw bytes to the named file within the sandbox.
    ///
    /// This is the ONLY path that touches the filesystem for writes; `writeFile`
    /// delegates to this method so there is a single containment gate.
    public func writeData(_ data: Data, named name: String) async throws {
        guard let root else { throw FileAccessError.accessDenied }
        guard data.count <= Self.maxWriteBytes else { throw FileAccessError.tooLarge }
        let url = try Self.resolveSandboxedURL(name: name, root: root)
        let fm = FileManager.default
        // Create intermediate directories within the sandbox.
        let parent = url.deletingLastPathComponent()
        try? fm.createDirectory(at: parent, withIntermediateDirectories: true)
        // Re-validate after mkdir: a symlink swap between mkdir and open
        // could redirect the write outside the sandbox (Security Finding 4).
        let reResolved = url.resolvingSymlinksInPath()
        let crp = root.resolvingSymlinksInPath().path
        guard reResolved.path == crp || reResolved.path.hasPrefix(crp + "/") else {
            throw FileAccessError.outsideSandbox
        }
        do {
            try data.write(to: reResolved, options: .atomic)
        } catch {
            throw FileAccessError.ioFailure
        }
    }

    // MARK: - Text read/write (expressed in terms of binary methods)

    public func readFile(named name: String) async throws -> String {
        let data = try await readData(named: name)
        return String(decoding: data, as: UTF8.self)
    }

    public func writeFile(_ contents: String, named name: String) async throws {
        try await writeData(Data(contents.utf8), named: name)
    }
}
