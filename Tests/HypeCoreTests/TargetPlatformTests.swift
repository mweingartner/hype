import Foundation
import Testing
@testable import HypeCore

@Suite("Target platform architecture")
struct TargetPlatformTests {
    @Test("new documents default to macOS and require target acknowledgement")
    func newDocumentDefaultsToMacOSButRequiresPrompt() {
        let document = HypeDocument.newDocument(name: "Targets")
        #expect(document.stack.deploymentTargets.selectedPlatforms == [.macOS])
        #expect(document.stack.deploymentTargets.primaryPlatform == .macOS)
        #expect(!document.stack.deploymentTargets.selectionPromptAcknowledged)
        #expect(document.stack.deploymentTargets.primaryProfile.id == "macos-default")
    }

    @Test("decoded legacy stacks default to acknowledged macOS target")
    func decodedLegacyStackDefaultsToAcknowledgedMacOSTarget() throws {
        let encoded = try JSONEncoder().encode(Stack(name: "Legacy"))
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "deploymentTargets")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let stack = try JSONDecoder().decode(Stack.self, from: legacy)
        #expect(stack.deploymentTargets.selectedPlatforms == [.macOS])
        #expect(stack.deploymentTargets.selectionPromptAcknowledged)
    }

    @Test("part availability uses strict selected-target intersection")
    func partAvailabilityUsesStrictIntersection() {
        #expect(PartAvailabilityCatalog.supports(.button, across: [.macOS, .iPhone, .iPad, .tvOS]))
        #expect(PartAvailabilityCatalog.supports(.spriteArea, across: [.macOS, .iPhone, .iPad, .tvOS]))
        #expect(!PartAvailabilityCatalog.supports(.field, across: [.macOS, .tvOS]))
        #expect(!PartAvailabilityCatalog.supports(.audioRecorder, across: [.iPhone, .tvOS]))
        #expect(PartAvailabilityCatalog.supports(.pdf, across: [.macOS, .iPhone, .iPad]))
    }

    @Test("layout resolver projects constraints into target safe content area")
    func layoutResolverProjectsIntoSafeContentArea() throws {
        let cardId = UUID()
        let part = Part(partType: .button, cardId: cardId, left: 10, top: 20, width: 88, height: 24)
        let constraint = LayoutConstraint(
            sourcePartId: part.id,
            sourceEdge: .right,
            targetType: .canvas,
            targetEdge: .right,
            distance: -20
        )
        let profile = HypeDeviceProfileCatalog.defaultProfile(for: .tvOS)
        let resolution = LayoutResolver().resolve(parts: [part], constraints: [constraint], profile: profile)
        let geometry = try #require(resolution.geometries[part.id])

        #expect(resolution.safeContentLeft == 90)
        #expect(resolution.safeContentWidth == 1740)
        #expect(geometry.left == 90.0 + 1740.0 - 20.0 - 88.0)
    }

    @Test("deployment planner creates runtime-only platform plans")
    func deploymentPlannerCreatesRuntimeOnlyPlans() {
        var document = HypeDocument.newDocument(name: "Deployable")
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [.macOS, .iPhone, .iPad, .tvOS],
            primaryPlatform: .macOS,
            selectionPromptAcknowledged: true
        )
        document.stack.runtimeModeEnabled = false
        document.scriptGlobals["session"] = "temporary"

        let planner = StackDeploymentPlanner()
        let plans = planner.plans(for: document)
        #expect(plans.map(\.platform) == [.macOS, .iPhone, .iPad, .tvOS])
        #expect(plans.allSatisfy { $0.runtimeOnly })
        #expect(plans.allSatisfy { !$0.includesAuthoringUI })
        #expect(plans.first?.kind == .macOSStandalone)
        #expect(plans.first(where: { $0.platform == .iPad })?.runtimeAIProviderPolicy == .appleFoundationModels)
        #expect(plans.first(where: { $0.platform == .iPad })?.appIntents.map(\.kind).contains(.askStackAI) == true)
        #expect(plans.first(where: { $0.platform == .tvOS })?.runtimeAIProviderPolicy == .disabled)

        let runtimeDocument = planner.runtimeDocument(forDeployment: document)
        #expect(runtimeDocument.stack.runtimeModeEnabled)
        #expect(runtimeDocument.scriptGlobals.isEmpty)
    }

    @Test("AI tools expose target profile and availability queries")
    func aiToolsExposeTargetQueries() async {
        let toolNames = Set(HypeToolDefinitions.cardControlAuthoringTools.map(\.function.name))
        #expect(toolNames.contains("list_target_profiles"))
        #expect(toolNames.contains("get_part_target_availability"))

        var document = HypeDocument.newDocument(name: "AI Targets")
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [.macOS, .tvOS],
            primaryPlatform: .macOS,
            selectionPromptAcknowledged: true
        )
        let cardId = document.cards[0].id
        let executor = HypeToolExecutor()

        let profiles = await executor.execute(
            toolName: "list_target_profiles",
            arguments: [:],
            document: &document,
            currentCardId: cardId
        )
        #expect(profiles.contains("Selected targets: macOS, tvOS"))
        #expect(profiles.contains("tvos-1080p"))

        let availability = await executor.execute(
            toolName: "get_part_target_availability",
            arguments: ["part_type": "field"],
            document: &document,
            currentCardId: cardId
        )
        #expect(availability.contains("field: not available"))
        #expect(availability.contains("tvOS: unsupported"))

        _ = await executor.execute(
            toolName: "set_stack_property",
            arguments: ["property": "targetPlatforms", "value": "macOS,iPhone,iPad"],
            document: &document,
            currentCardId: cardId
        )
        let targetPlatforms = await executor.execute(
            toolName: "get_stack_property",
            arguments: ["property": "targetPlatforms"],
            document: &document,
            currentCardId: cardId
        )
        #expect(targetPlatforms == "macOS,iPhone,iPad")

        _ = await executor.execute(
            toolName: "set_stack_property",
            arguments: ["property": "runtimeAIProviderPolicy", "value": "appleFoundationModels"],
            document: &document,
            currentCardId: cardId
        )
        let runtimePolicy = await executor.execute(
            toolName: "get_stack_property",
            arguments: ["property": "runtimeAIProviderPolicy"],
            document: &document,
            currentCardId: cardId
        )
        #expect(runtimePolicy == "appleFoundationModels")
    }
}
