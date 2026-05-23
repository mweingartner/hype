import Foundation

/// Categorizes log messages for filtering and display.
public enum LogLevel: String, Sendable {
    case debug   = "DEBUG"
    case info    = "INFO"
    case warning = "WARN"
    case error   = "ERROR"
}

/// A single log entry with timestamp, level, and message.
public struct LogEntry: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let message: String
    public let source: String  // e.g. "Interpreter", "Dispatcher", "Transition"

    public init(level: LogLevel, message: String, source: String = "") {
        self.id = UUID()
        self.timestamp = Date()
        self.level = level
        self.message = message
        self.source = source
    }

    /// Formatted line for display and file output.
    public var formatted: String {
        let df = Self.dateFormatter
        return "[\(df.string(from: timestamp))] [\(level.rawValue)] \(source.isEmpty ? "" : "[\(source)] ")\(message)"
    }

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()
}

/// Centralized logging singleton for all Hype console output.
///
/// Every subsystem (interpreter, dispatcher, transition engine,
/// AI tools, etc.) logs through this singleton. The console
/// window observes `entriesPublisher` to display messages in
/// real time. Messages are also written to a rotating log file
/// on disk at `~/Library/Logs/Hype/console.log`.
///
/// Thread-safe: the entries array is protected by a lock so
/// background threads (AI, timers, SpriteKit callbacks) can
/// log without races.
public final class HypeLogger: @unchecked Sendable {

    public static let shared = HypeLogger()
    private static let maxLogMessageCharacters = 24_000

    private static let secretPatterns: [NSRegularExpression] = [
        try! NSRegularExpression(
            pattern: #"(?i)\b(api[_-]?key|x[-_]?api[-_]?key|access[_-]?token|refresh[_-]?token|secret|password)\b\s*[:=]\s*("[^"]*"|'[^']*'|[^\s,;}]+)"#
        ),
        try! NSRegularExpression(
            pattern: #"(?i)\b(authorization)\b\s*[:=]\s*("[^"]*"|'[^']*'|bearer\s+[^\s,;}]+|[^\s,;}]+)"#
        ),
    ]

    private let lock = NSLock()
    private var _entries: [LogEntry] = []
    private var fileHandle: FileHandle?
    private var logFilePath: String?

    /// Notification posted when a new entry is added.
    /// The console window observes this to refresh.
    public static let didLogNotification = Notification.Name("HypeLoggerDidLog")

    /// Construct a HypeLogger.
    ///
    /// - Parameter setupFileLogging: when `true` (the default), the
    ///   logger opens / appends to the rotating log file at
    ///   `~/Library/Logs/Hype/console.log`. Tests that want an
    ///   isolated, in-memory-only logger should pass `false` so the
    ///   shared file handle is not contended.
    ///
    /// Marked `internal` (not `private`) so tests can construct
    /// fresh, isolated logger instances via `@testable import`. The
    /// production path always uses `HypeLogger.shared`.
    internal init(setupFileLogging: Bool = true) {
        if setupFileLogging {
            setupLogFile()
        }
    }

    // MARK: - Public API

    /// All current log entries. Thread-safe read.
    public var entries: [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return _entries
    }

    /// Log a message at the given level.
    public func log(_ level: LogLevel, _ message: String, source: String = "") {
        let entry = LogEntry(
            level: level,
            message: Self.sanitizeForLog(message),
            source: source
        )
        lock.lock()
        _entries.append(entry)
        lock.unlock()

        // Write to file
        writeToFile(entry)

        // Notify observers (on main thread for UI)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didLogNotification, object: entry)
        }
    }

    /// Convenience methods
    public func debug(_ message: String, source: String = "") { log(.debug, message, source: source) }
    public func info(_ message: String, source: String = "") { log(.info, message, source: source) }
    public func warn(_ message: String, source: String = "") { log(.warning, message, source: source) }
    public func error(_ message: String, source: String = "") { log(.error, message, source: source) }

    /// Log a user/model/tool dialog item from an AI surface.
    public func aiDialog(role: String, content: String, source: String = "AI") {
        info("\(role.uppercased()):\n\(content)", source: source)
    }

    /// Log the raw request text sent to an AI provider.
    public func aiInput(_ message: String, source: String = "AI") {
        info("INPUT:\n\(message)", source: source)
    }

    /// Log the raw response text returned by an AI provider.
    public func aiOutput(_ message: String, source: String = "AI") {
        info("OUTPUT:\n\(message)", source: source)
    }

    /// Log a ScriptError in a stable console-friendly format.
    public func scriptError(_ error: ScriptError, source: String = "Script", context: String? = nil) {
        var parts: [String] = []
        if let context, !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(context)
        }
        parts.append("\(error.handler) line \(error.line): \(error.message)")
        if let objectId = error.objectId {
            parts.append("object=\(objectId.uuidString)")
        }
        self.error(parts.joined(separator: " | "), source: source)
    }

    /// Clear all in-memory entries (does not delete the log file).
    public func clear() {
        lock.lock()
        _entries.removeAll()
        lock.unlock()
    }

    /// The path to the log file on disk.
    public var logFileURL: URL? {
        logFilePath.map { URL(fileURLWithPath: $0) }
    }

    // MARK: - Sanitization

    private static func sanitizeForLog(_ message: String) -> String {
        var result = message
        for pattern in secretPatterns {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = pattern.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: "$1: [redacted]"
            )
        }
        guard result.count > maxLogMessageCharacters else { return result }
        let omitted = result.count - maxLogMessageCharacters
        return "\(result.prefix(maxLogMessageCharacters))\n[truncated \(omitted) characters]"
    }

    // MARK: - File I/O

    private func setupLogFile() {
        let logDir = NSHomeDirectory() + "/Library/Logs/Hype"
        try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        let path = logDir + "/console.log"
        logFilePath = path

        // Create or truncate the file for this session
        FileManager.default.createFile(atPath: path, contents: nil)
        fileHandle = FileHandle(forWritingAtPath: path)
        fileHandle?.seekToEndOfFile()

        // Write session header
        let header = "=== Hype Console Log — \(Date()) ===\n"
        if let data = header.data(using: .utf8) {
            fileHandle?.write(data)
        }
    }

    private func writeToFile(_ entry: LogEntry) {
        let line = entry.formatted + "\n"
        if let data = line.data(using: .utf8) {
            fileHandle?.write(data)
        }
    }
}
