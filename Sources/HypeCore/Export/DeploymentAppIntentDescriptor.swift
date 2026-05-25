import Foundation

public enum DeploymentAppIntentKind: String, Codable, CaseIterable, Sendable, Equatable {
    case openCard
    case runStackMessage
    case askStackAI
    case searchStackContent
}

public struct DeploymentAppIntentDescriptor: Codable, Sendable, Equatable, Identifiable {
    public var id: DeploymentAppIntentKind { kind }
    public var kind: DeploymentAppIntentKind
    public var title: String
    public var description: String
    public var requiresAppleIntelligence: Bool

    public init(
        kind: DeploymentAppIntentKind,
        title: String,
        description: String,
        requiresAppleIntelligence: Bool = false
    ) {
        self.kind = kind
        self.title = title
        self.description = description
        self.requiresAppleIntelligence = requiresAppleIntelligence
    }
}

public enum DeploymentAppIntentCatalog {
    public static let iOSRuntimeIntents: [DeploymentAppIntentDescriptor] = [
        DeploymentAppIntentDescriptor(
            kind: .openCard,
            title: "Open Hype Card",
            description: "Open a named card in the deployed Hype stack."
        ),
        DeploymentAppIntentDescriptor(
            kind: .runStackMessage,
            title: "Run Hype Message",
            description: "Send a named HypeTalk message through the runtime dispatcher."
        ),
        DeploymentAppIntentDescriptor(
            kind: .askStackAI,
            title: "Ask Stack AI",
            description: "Ask the deployed stack's Apple on-device AI provider for a response.",
            requiresAppleIntelligence: true
        ),
        DeploymentAppIntentDescriptor(
            kind: .searchStackContent,
            title: "Search Hype Stack",
            description: "Search indexed stack content exposed by the runtime."
        ),
    ]

    public static func intents(for platform: HypeTargetPlatform) -> [DeploymentAppIntentDescriptor] {
        switch platform {
        case .iPhone, .iPad:
            return iOSRuntimeIntents
        case .macOS, .tvOS:
            return []
        }
    }
}
