#if canImport(AppKit)
import Foundation
import HypeCore

/// AppKit-specific `FileAccessProvider` that confines all reads and writes to a
/// per-stack directory in `~/Library/Application Support/Hype/StackFiles/<stackId>/`.
///
/// The directory is created with POSIX permissions `0o700` on first use, so only
/// the running user can access it. All actual containment enforcement is delegated
/// to `SandboxedFileAccessProvider`, which validates paths before every I/O call.
public struct AppKitFileAccessProvider: FileAccessProvider, Sendable {

    private let stackId: UUID

    public init(stackId: UUID) {
        self.stackId = stackId
    }

    // MARK: - Sandbox root

    public func sandboxRoot() -> URL? {
        makeSandboxRoot()
    }

    /// Resolve (and create if necessary) the per-stack sandbox directory.
    ///
    /// Returns `nil` if the Application Support directory cannot be located —
    /// callers treat `nil` as deny-all.
    private func makeSandboxRoot() -> URL? {
        let fm = FileManager.default
        guard let appSupport = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }

        let dir = appSupport
            .appendingPathComponent("Hype", isDirectory: true)
            .appendingPathComponent("StackFiles", isDirectory: true)
            .appendingPathComponent(stackId.uuidString, isDirectory: true)

        do {
            try fm.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            return nil
        }
        return dir
    }

    // MARK: - FileAccessProvider

    public func readFile(named name: String) async throws -> String {
        let provider = SandboxedFileAccessProvider(root: makeSandboxRoot())
        return try await provider.readFile(named: name)
    }

    public func writeFile(_ contents: String, named name: String) async throws {
        let provider = SandboxedFileAccessProvider(root: makeSandboxRoot())
        try await provider.writeFile(contents, named: name)
    }
}
#endif
