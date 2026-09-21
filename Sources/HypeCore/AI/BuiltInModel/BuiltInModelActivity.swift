import Foundation

/// What the Built-in model engine is doing right now.
public enum BuiltInModelPhase: Sendable, Equatable {
    case idle
    /// Hashing weight files Hype did not download itself (first use only).
    case verifyingModel(name: String)
    case loadingModel(name: String)
    /// Prefilling the prompt. A cold first request reads ~50K tokens of tool
    /// schemas and language guide; later requests reuse the prompt cache.
    case readingPrompt(processedTokens: Int, totalTokens: Int)
    case generating
}

/// Process-wide, thread-safe activity readout for the Built-in model, so AI
/// surfaces can show specific progress instead of a bare spinner (HIG: prefer
/// determinate, descriptive progress for long generative work).
public final class BuiltInModelActivity: @unchecked Sendable {
    public static let shared = BuiltInModelActivity()
    public static let didChangeNotification = Notification.Name("hype.builtInModel.activityDidChange")
    /// Prefills shorter than this finish before a status line could be read.
    static let reportablePrefillTokens = 4_096

    private let lock = NSLock()
    private var current: BuiltInModelPhase = .idle

    public var phase: BuiltInModelPhase {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    public func report(_ phase: BuiltInModelPhase) {
        lock.lock()
        let changed = current != phase
        current = phase
        lock.unlock()
        guard changed else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    /// One short line for a status row, or nil when there is nothing worth saying.
    public var statusText: String? {
        switch phase {
        case .idle, .generating:
            return nil
        case .verifyingModel(let name):
            return "Verifying \(name) files — only needed once…"
        case .loadingModel(let name):
            return "Loading \(name)…"
        case .readingPrompt(let processed, let total):
            guard total >= Self.reportablePrefillTokens else { return nil }
            let percent = Int((Double(processed) / Double(max(total, 1)) * 100).rounded())
            return "Reading Hype's tools and language guide (\(percent)%) — only needed once…"
        }
    }
}
