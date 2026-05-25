import Foundation

public enum HypeDeploymentKind: String, Codable, CaseIterable, Sendable, Equatable {
    case macOSStandalone
    case iPhoneRuntimeShell
    case iPadRuntimeShell
    case tvOSRuntimeShell
}

public struct HypeDeploymentPlan: Codable, Sendable, Equatable {
    public var kind: HypeDeploymentKind
    public var platform: HypeTargetPlatform
    public var profile: HypeDeviceProfile
    public var runtimeOnly: Bool
    public var includesAuthoringUI: Bool
    public var stackName: String
    public var runtimeAIProviderPolicy: RuntimeAIProviderPolicy
    public var appIntents: [DeploymentAppIntentDescriptor]

    public init(
        kind: HypeDeploymentKind,
        platform: HypeTargetPlatform,
        profile: HypeDeviceProfile,
        runtimeOnly: Bool,
        includesAuthoringUI: Bool,
        stackName: String,
        runtimeAIProviderPolicy: RuntimeAIProviderPolicy,
        appIntents: [DeploymentAppIntentDescriptor]
    ) {
        self.kind = kind
        self.platform = platform
        self.profile = profile
        self.runtimeOnly = runtimeOnly
        self.includesAuthoringUI = includesAuthoringUI
        self.stackName = stackName
        self.runtimeAIProviderPolicy = runtimeAIProviderPolicy
        self.appIntents = appIntents
    }
}

/// Produces target-specific deployment plans without mutating the source stack.
///
/// Deployed apps are runtime-only by design: no object palette, property
/// inspector, script editor, AI/debug panels, or edit-mode toggle. Platform
/// shells embed the stack package and project it through browse-mode runtime
/// services for the target OS.
public struct StackDeploymentPlanner: Sendable {
    public init() {}

    public func plans(for document: HypeDocument) -> [HypeDeploymentPlan] {
        var targets = document.stack.deploymentTargets
        targets.normalize()
        return targets.selectedPlatforms.map { platform in
            HypeDeploymentPlan(
                kind: kind(for: platform),
                platform: platform,
                profile: HypeDeviceProfileCatalog.defaultProfile(for: platform),
                runtimeOnly: true,
                includesAuthoringUI: false,
                stackName: document.stack.name,
                runtimeAIProviderPolicy: runtimeAIProviderPolicy(
                    for: platform,
                    settings: document.stack.runtimeAISettings
                ),
                appIntents: DeploymentAppIntentCatalog.intents(for: platform)
            )
        }
    }

    public func runtimeDocument(forDeployment document: HypeDocument) -> HypeDocument {
        var copy = document
        copy.stack.runtimeModeEnabled = true
        copy.scriptGlobals = [:]
        return copy
    }

    private func runtimeAIProviderPolicy(
        for platform: HypeTargetPlatform,
        settings: RuntimeAISettings
    ) -> RuntimeAIProviderPolicy {
        guard settings.providerPolicy == .automatic else { return settings.providerPolicy }
        switch platform {
        case .macOS:
            return .automatic
        case .iPhone, .iPad:
            return .appleFoundationModels
        case .tvOS:
            return .disabled
        }
    }

    private func kind(for platform: HypeTargetPlatform) -> HypeDeploymentKind {
        switch platform {
        case .macOS: return .macOSStandalone
        case .iPhone: return .iPhoneRuntimeShell
        case .iPad: return .iPadRuntimeShell
        case .tvOS: return .tvOSRuntimeShell
        }
    }
}
