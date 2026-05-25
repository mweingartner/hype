import Foundation

public enum RuntimeAIToolSideEffect: String, Codable, Sendable, Equatable {
    case readOnly
    case runtimeStateMutation
}

public struct RuntimeAIToolDescriptor: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var description: String
    public var sideEffect: RuntimeAIToolSideEffect

    public init(name: String, description: String, sideEffect: RuntimeAIToolSideEffect) {
        self.name = name
        self.description = description
        self.sideEffect = sideEffect
    }
}

public struct RuntimeAIToolCall: Codable, Sendable, Equatable {
    public var name: String
    public var arguments: [String: String]

    public init(name: String, arguments: [String: String] = [:]) {
        self.name = name
        self.arguments = arguments
    }
}

public struct RuntimeAIToolResult: Codable, Sendable, Equatable {
    public var name: String
    public var output: String
    public var mutatedRuntimeState: Bool

    public init(name: String, output: String, mutatedRuntimeState: Bool = false) {
        self.name = name
        self.output = output
        self.mutatedRuntimeState = mutatedRuntimeState
    }
}

public enum RuntimeAIToolCatalog {
    public static let defaultTools: [RuntimeAIToolDescriptor] = [
        RuntimeAIToolDescriptor(
            name: "current_card_summary",
            description: "Summarize the current card name, background, and visible object count.",
            sideEffect: .readOnly
        ),
        RuntimeAIToolDescriptor(
            name: "visible_object_list",
            description: "List visible runtime objects on the current card.",
            sideEffect: .readOnly
        ),
        RuntimeAIToolDescriptor(
            name: "target_profile",
            description: "Describe the current runtime target profile and safe area.",
            sideEffect: .readOnly
        ),
        RuntimeAIToolDescriptor(
            name: "set_runtime_variable",
            description: "Set a transient runtime variable in script globals.",
            sideEffect: .runtimeStateMutation
        ),
    ]

    public static func tools(for settings: RuntimeAISettings) -> [RuntimeAIToolDescriptor] {
        var normalized = settings
        normalized.normalize()
        return defaultTools.filter { tool in
            switch tool.sideEffect {
            case .readOnly:
                return true
            case .runtimeStateMutation:
                return normalized.allowRuntimeSideEffectTools
                    && normalized.allowedToolNames.contains(tool.name.lowercased())
            }
        }
    }
}

public struct RuntimeAIToolExecutor: Sendable {
    public init() {}

    public func execute(
        _ call: RuntimeAIToolCall,
        document: inout HypeDocument,
        currentCardId: UUID,
        targetPlatform: HypeTargetPlatform
    ) -> RuntimeAIToolResult {
        switch call.name.lowercased() {
        case "current_card_summary":
            guard let card = document.cards.first(where: { $0.id == currentCardId }) else {
                return RuntimeAIToolResult(name: call.name, output: "No current card.")
            }
            let visibleCount = document.effectivePartsForCard(card.id).filter(\.visible).count
            let backgroundName = document.backgrounds.first(where: { $0.id == card.backgroundId })?.name ?? ""
            return RuntimeAIToolResult(
                name: call.name,
                output: "Card: \(card.name)\nBackground: \(backgroundName)\nVisible objects: \(visibleCount)"
            )
        case "visible_object_list":
            guard let card = document.cards.first(where: { $0.id == currentCardId }) else {
                return RuntimeAIToolResult(name: call.name, output: "No current card.")
            }
            let rows = document.effectivePartsForCard(card.id)
                .filter(\.visible)
                .map { "\($0.name) [\($0.partType.rawValue)]" }
            return RuntimeAIToolResult(name: call.name, output: rows.joined(separator: "\n"))
        case "target_profile":
            let profile = HypeDeviceProfileCatalog.defaultProfile(for: targetPlatform)
            return RuntimeAIToolResult(
                name: call.name,
                output: "\(profile.displayName) \(profile.width)x\(profile.height), input=\(profile.inputModel.rawValue), safeArea=\(profile.safeArea.top),\(profile.safeArea.left),\(profile.safeArea.bottom),\(profile.safeArea.right)"
            )
        case "set_runtime_variable":
            let key = call.arguments["name"] ?? call.arguments["key"] ?? ""
            let value = call.arguments["value"] ?? ""
            guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return RuntimeAIToolResult(name: call.name, output: "Missing variable name.")
            }
            document.scriptGlobals[key] = value
            return RuntimeAIToolResult(name: call.name, output: "Set \(key).", mutatedRuntimeState: true)
        default:
            return RuntimeAIToolResult(name: call.name, output: "Unsupported runtime AI tool '\(call.name)'.")
        }
    }
}
