import Foundation

public enum AIContextTrustBoundary: String, Sendable, Equatable {
    case authoringChat
    case assetRepositoryChat
    case localDebugMCP
    case runtime
}

public struct AIContextToolPolicy: Sendable, Equatable {
    public var provider: HypeAIProvider
    public var trustBoundary: AIContextTrustBoundary
    public var hasContext: Bool
    public var cloudSharingAllowed: Bool
    public var allowContextWrites: Bool

    public init(
        provider: HypeAIProvider,
        trustBoundary: AIContextTrustBoundary,
        hasContext: Bool,
        cloudSharingAllowed: Bool,
        allowContextWrites: Bool = true
    ) {
        self.provider = provider
        self.trustBoundary = trustBoundary
        self.hasContext = hasContext
        self.cloudSharingAllowed = cloudSharingAllowed
        self.allowContextWrites = allowContextWrites
    }

    public init(
        provider: HypeAIProvider,
        trustBoundary: AIContextTrustBoundary,
        document: HypeDocument,
        allowContextWrites: Bool = true
    ) {
        self.init(
            provider: provider,
            trustBoundary: trustBoundary,
            hasContext: !document.aiContextLibrary.items.isEmpty,
            cloudSharingAllowed: document.stack.aiContextCloudSharingAllowed,
            allowContextWrites: allowContextWrites
        )
    }

    public static func explicit(
        readExistingContext: Bool,
        writeContextNotes: Bool = true
    ) -> AIContextToolPolicy {
        AIContextToolPolicy(
            provider: .ollama,
            trustBoundary: .authoringChat,
            hasContext: readExistingContext,
            cloudSharingAllowed: readExistingContext,
            allowContextWrites: writeContextNotes
        )
    }

    public var canReadExistingContext: Bool {
        guard hasContext else { return false }
        if trustBoundary == .localDebugMCP {
            return true
        }
        if provider.requiresAIContextCloudOptIn {
            return cloudSharingAllowed
        }
        return true
    }

    public var canImportContextAssets: Bool {
        canReadExistingContext
    }

    public var canWriteContextNotes: Bool {
        allowContextWrites
    }

    public var withholdsExistingContext: Bool {
        hasContext && !canReadExistingContext
    }

    public var stateDescription: String {
        if canReadExistingContext {
            return trustBoundary == .localDebugMCP
                ? "AI context read tools are available through the local privileged MCP/debug boundary."
                : "AI context read tools are available to \(provider.displayName)."
        }
        if withholdsExistingContext {
            return "AI context exists but is withheld from \(provider.displayName) until stack.aiContextCloudSharingAllowed is enabled."
        }
        return "No AI context items are attached."
    }
}

public extension HypeAIProvider {
    var requiresAIContextCloudOptIn: Bool {
        switch self {
        case .openAI, .zAI, .miniMax:
            return true
        case .ollama, .llamaSwap, .llamaCpp:
            return false
        }
    }
}
