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

    nonisolated(unsafe) public static let shared = HypeLogger()

    private let lock = NSLock()
    private var _entries: [LogEntry] = []
    private var fileHandle: FileHandle?
    private var logFilePath: String?

    /// Notification posted when a new entry is added.
    /// The console window observes this to refresh.
    public static let didLogNotification = Notification.Name("HypeLoggerDidLog")

    private init() {
        setupLogFile()
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
        let entry = LogEntry(level: level, message: message, source: source)
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
