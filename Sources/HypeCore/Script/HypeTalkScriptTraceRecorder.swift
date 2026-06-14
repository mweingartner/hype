import Foundation

public struct HypeTalkScriptTraceSource: Sendable, Codable, Equatable {
    public var kind: String
    public var objectId: UUID?

    public init(kind: String, objectId: UUID? = nil) {
        self.kind = kind
        self.objectId = objectId
    }
}

public struct HypeTalkScriptTraceEntry: Identifiable, Sendable, Codable, Equatable {
    public var id: UUID
    public var timestamp: Date
    public var message: String
    public var handler: String
    public var ownerDescription: String
    public var source: HypeTalkScriptTraceSource
    public var line: Int
    public var status: String
    public var durationMilliseconds: Double
    public var diagnostics: HypeTalkExecutionDiagnostics

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        message: String,
        handler: String,
        ownerDescription: String,
        source: HypeTalkScriptTraceSource,
        line: Int,
        status: String,
        durationMilliseconds: Double,
        diagnostics: HypeTalkExecutionDiagnostics
    ) {
        self.id = id
        self.timestamp = timestamp
        self.message = message
        self.handler = handler
        self.ownerDescription = ownerDescription
        self.source = source
        self.line = line
        self.status = status
        self.durationMilliseconds = durationMilliseconds
        self.diagnostics = diagnostics
    }
}

public struct HypeTalkRuntimeBudgetSummary: Sendable, Codable, Equatable {
    public static let defaultFrameBudgetMilliseconds = 16.67

    public var durationMilliseconds: Double
    public var budgetMilliseconds: Double
    public var budgetPercent: Double
    public var frameEquivalents: Double
    public var pressure: String

    public init(durationMilliseconds: Double, budgetMilliseconds: Double = Self.defaultFrameBudgetMilliseconds) {
        let normalizedBudget = max(0.001, budgetMilliseconds)
        self.durationMilliseconds = durationMilliseconds
        self.budgetMilliseconds = normalizedBudget
        self.budgetPercent = (durationMilliseconds / normalizedBudget) * 100.0
        self.frameEquivalents = durationMilliseconds / normalizedBudget
        switch self.budgetPercent {
        case ..<5:
            self.pressure = "minimal"
        case ..<25:
            self.pressure = "noticeable"
        case ..<75:
            self.pressure = "heavy"
        default:
            self.pressure = "over-budget"
        }
    }
}

public struct HypeTalkScriptTraceSnapshot: Sendable, Equatable {
    public var isEnabled: Bool
    public var entries: [HypeTalkScriptTraceEntry]

    public init(isEnabled: Bool, entries: [HypeTalkScriptTraceEntry]) {
        self.isEnabled = isEnabled
        self.entries = entries
    }
}

public final class HypeTalkScriptTraceRecorder: @unchecked Sendable {
    public static let shared = HypeTalkScriptTraceRecorder()

    private let lock = NSLock()
    private var enabled = false
    private var entries: [HypeTalkScriptTraceEntry] = []
    private let maximumEntries = 2_000

    public init() {}

    public var isEnabled: Bool {
        lock.withLock { enabled }
    }

    public func setEnabled(_ enabled: Bool) {
        lock.withLock {
            self.enabled = enabled
        }
    }

    public func record(_ entry: HypeTalkScriptTraceEntry) {
        lock.withLock {
            guard enabled else { return }
            entries.append(entry)
            if entries.count > maximumEntries {
                entries.removeFirst(entries.count - maximumEntries)
            }
        }
    }

    public func clear() {
        lock.withLock {
            entries.removeAll(keepingCapacity: true)
        }
    }

    public func snapshot() -> HypeTalkScriptTraceSnapshot {
        lock.withLock {
            HypeTalkScriptTraceSnapshot(isEnabled: enabled, entries: entries)
        }
    }
}
