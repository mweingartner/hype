import Foundation

/// Executor branches for the file-I/O and URL-fetch AI tools:
/// `fetch_url`, `read_file`, `write_file`, `list_directory`.
///
/// These are extracted from `HypeToolExecutor.execute` to reduce file size.
/// All tool names, arguments, and return strings are identical to the original;
/// this is a pure mechanical move with no behavioral change.
///
/// These branches have no dependencies on `HypeToolExecutor` itself —
/// they only use Foundation APIs.
package enum FileIOExecutorBranches {

    // MARK: - Tool case branches

    /// Handles the `fetch_url` tool case.
    package static func executeFetchURL(
        arguments: [String: String]
    ) async -> String {
        let urlStr = arguments["url"] ?? ""
        guard let url = URL(string: urlStr) else { return "Invalid URL" }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let text = String(data: data, encoding: .utf8) ?? "(binary data)"
            return String(text.prefix(5000))  // Limit response size
        } catch {
            return "Fetch error: \(error.localizedDescription)"
        }
    }

    /// Handles the `read_file` tool case.
    package static func executeReadFile(
        arguments: [String: String]
    ) -> String {
        let path = arguments["path"] ?? ""
        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            return String(content.prefix(10000))
        } catch {
            return "Read error: \(error.localizedDescription)"
        }
    }

    /// Handles the `write_file` tool case.
    package static func executeWriteFile(
        arguments: [String: String]
    ) -> String {
        let path = arguments["path"] ?? ""
        let content = arguments["content"] ?? ""
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            return "Wrote \(content.count) characters to \(path)"
        } catch {
            return "Write error: \(error.localizedDescription)"
        }
    }

    /// Handles the `list_directory` tool case.
    package static func executeListDirectory(
        arguments: [String: String]
    ) -> String {
        let path = arguments["path"] ?? "."
        do {
            let items = try FileManager.default.contentsOfDirectory(atPath: path)
            return items.joined(separator: "\n")
        } catch {
            return "List error: \(error.localizedDescription)"
        }
    }
}
