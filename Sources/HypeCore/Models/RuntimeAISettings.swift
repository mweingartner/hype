import Foundation

/// Runtime AI policy stored with a stack.
///
/// This governs end-user deployed runtimes, not the macOS authoring assistant.
/// Authoring remains provider-selectable through user preferences; deployed
/// non-macOS runtimes default to Apple on-device AI where the target supports it.
public enum RuntimeAIProviderPolicy: String, Codable, CaseIterable, Sendable, Equatable {
    case automatic
    case appleFoundationModels
    case disabled

    public var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .appleFoundationModels: return "Apple Foundation Models"
        case .disabled: return "Disabled"
        }
    }

    public static func parse(_ value: String) -> RuntimeAIProviderPolicy? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        switch normalized {
        case "automatic", "auto":
            return .automatic
        case "applefoundationmodels", "apple", "foundationmodels":
            return .appleFoundationModels
        case "disabled", "off", "none":
            return .disabled
        default:
            return nil
        }
    }
}

public struct RuntimeAISettings: Codable, Sendable, Equatable {
    public var providerPolicy: RuntimeAIProviderPolicy
    public var allowRuntimeSideEffectTools: Bool
    public var allowedToolNames: [String]
    public var unavailableFallbackText: String
    public var persistTranscript: Bool

    public init(
        providerPolicy: RuntimeAIProviderPolicy = .automatic,
        allowRuntimeSideEffectTools: Bool = false,
        allowedToolNames: [String] = [],
        unavailableFallbackText: String = "AI is unavailable on this device.",
        persistTranscript: Bool = false
    ) {
        self.providerPolicy = providerPolicy
        self.allowRuntimeSideEffectTools = allowRuntimeSideEffectTools
        self.allowedToolNames = Self.normalizedTools(allowedToolNames)
        self.unavailableFallbackText = unavailableFallbackText
        self.persistTranscript = persistTranscript
    }

    public mutating func normalize() {
        allowedToolNames = Self.normalizedTools(allowedToolNames)
        if unavailableFallbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            unavailableFallbackText = "AI is unavailable on this device."
        }
    }

    public static let defaultRuntime = RuntimeAISettings()

    private static func normalizedTools(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in names {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !name.isEmpty, !seen.contains(name) else { continue }
            seen.insert(name)
            result.append(name)
        }
        return result
    }
}
