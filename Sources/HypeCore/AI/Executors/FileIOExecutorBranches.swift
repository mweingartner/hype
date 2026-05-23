import Foundation

// MARK: - URLSessionProviding

/// An abstraction over `URLSession` data-fetch for the `fetch_url` AI tool.
///
/// The production conformance is `URLSession` (via `URLSession.shared`).
/// Tests inject a stub backed by `MockURLProtocol` so no real network
/// request is made.
public protocol URLSessionProviding: Sendable {
    /// Fetches the data at `url` and returns it together with the URL response.
    func data(from url: URL) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProviding {}

// MARK: - FileIOExecutorBranches

/// Executor branches for the file-I/O and URL-fetch AI tools:
/// `fetch_url`, `read_file`, `write_file`, `list_directory`.
///
/// These are extracted from `HypeToolExecutor.execute` to reduce file size.
/// All tool names, arguments, and return strings are identical to the original;
/// this is a pure mechanical move with no behavioral change.
///
/// Dependencies are injected so tests can avoid real network and filesystem I/O.
/// Production callers pass the defaults and get identical behavior.
package enum FileIOExecutorBranches {

    // MARK: - Tool case branches

    /// Handles the `fetch_url` tool case.
    ///
    /// - Parameters:
    ///   - arguments: Tool argument dictionary (expects key `"url"`).
    ///   - urlSession: URLSession-compatible provider. Defaults to `URLSession.shared`.
    package static func executeFetchURL(
        arguments: [String: String],
        urlSession: any URLSessionProviding = URLSession.shared
    ) async -> String {
        let urlStr = arguments["url"] ?? ""
        guard let url = URL(string: urlStr) else { return "Invalid URL" }
        do {
            let (data, _) = try await urlSession.data(from: url)
            let text = String(data: data, encoding: .utf8) ?? "(binary data)"
            return String(text.prefix(5000))  // Limit response size
        } catch {
            return "Fetch error: \(error.localizedDescription)"
        }
    }

    /// Handles the `read_file` tool case.
    ///
    /// - Parameters:
    ///   - arguments: Tool argument dictionary (expects key `"path"`).
    ///   - fileSystem: Filesystem provider. Defaults to `FileManager.default`.
    package static func executeReadFile(
        arguments: [String: String],
        fileSystem: any FileSystemProviding = FileManager.default
    ) -> String {
        let path = arguments["path"] ?? ""
        let url = URL(fileURLWithPath: path)
        do {
            let data = try fileSystem.read(from: url)
            let content = String(data: data, encoding: .utf8) ?? "(binary data)"
            return String(content.prefix(10000))
        } catch {
            return "Read error: \(error.localizedDescription)"
        }
    }

    /// Handles the `write_file` tool case.
    ///
    /// - Parameters:
    ///   - arguments: Tool argument dictionary (expects keys `"path"` and `"content"`).
    ///   - fileSystem: Filesystem provider. Defaults to `FileManager.default`.
    package static func executeWriteFile(
        arguments: [String: String],
        fileSystem: any FileSystemProviding = FileManager.default
    ) -> String {
        let path = arguments["path"] ?? ""
        let content = arguments["content"] ?? ""
        let url = URL(fileURLWithPath: path)
        guard let data = content.data(using: .utf8) else {
            return "Write error: content could not be encoded as UTF-8"
        }
        do {
            try fileSystem.write(data, to: url)
            return "Wrote \(content.count) characters to \(path)"
        } catch {
            return "Write error: \(error.localizedDescription)"
        }
    }

    /// Handles the `list_directory` tool case.
    ///
    /// - Parameters:
    ///   - arguments: Tool argument dictionary (expects key `"path"`).
    ///   - fileSystem: Filesystem provider. Defaults to `FileManager.default`.
    package static func executeListDirectory(
        arguments: [String: String],
        fileSystem: any FileSystemProviding = FileManager.default
    ) -> String {
        let path = arguments["path"] ?? "."
        let url = URL(fileURLWithPath: path)
        do {
            let items = try fileSystem.contents(ofDirectory: url)
            return items.map(\.lastPathComponent).joined(separator: "\n")
        } catch {
            return "List error: \(error.localizedDescription)"
        }
    }
}
