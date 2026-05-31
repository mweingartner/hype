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

    @Test("target platform parser accepts automation-friendly aliases")
    func targetPlatformParserAcceptsAutomationAliases() {
        #expect(HypeTargetPlatform.parse("macos") == .macOS)
        #expect(HypeTargetPlatform.parse("i-phone") == .iPhone)
        #expect(HypeTargetPlatform.parse("iPad") == .iPad)
        #expect(HypeTargetPlatform.parse("tv os") == .tvOS)
        #expect(HypeTargetPlatform.parseList("macOS,iPad,tvOS") == [.macOS, .iPad, .tvOS])
        #expect(HypeTargetPlatform.parseList("macOS,unknown") == nil)
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

    @Test("layout resolver scales authored card into target safe area")
    func layoutResolverScalesAuthoredCardIntoTargetSafeArea() throws {
        let cardId = UUID()
        let part = Part(partType: .button, cardId: cardId, left: 400, top: 300, width: 100, height: 50)
        let profile = HypeDeviceProfileCatalog.defaultProfile(for: .iPhone)

        let resolution = LayoutResolver().resolve(
            parts: [part],
            constraints: [],
            profile: profile,
            sourceCanvasWidth: 800,
            sourceCanvasHeight: 600,
            policy: .scaleToFit
        )
        let geometry = try #require(resolution.geometries[part.id])

        #expect(resolution.layoutPolicy == .scaleToFit)
        #expect(abs(resolution.contentScaleX - 0.49125) < 0.001)
        #expect(abs(geometry.left - 196.5) < 0.1)
        #expect(abs(geometry.top - 438.5) < 0.1)
        #expect(abs(geometry.width - 49.125) < 0.1)
    }

    @Test("deployment targets decode missing layoutPolicy as fixed")
    func deploymentTargetsDecodeMissingLayoutPolicy() throws {
        let json = """
        {
          "selectedPlatforms": ["macOS", "iPhone"],
          "primaryPlatform": "macOS",
          "selectionPromptAcknowledged": true,
          "supportedOrientations": ["resizable", "portrait"]
        }
        """.data(using: .utf8)!

        let targets = try JSONDecoder().decode(StackDeploymentTargets.self, from: json)

        #expect(targets.layoutPolicy == .fixed)
        #expect(targets.selectedPlatforms == [.macOS, .iPhone])
    }

    @Test("deployment planner creates runtime-only platform plans")
    func deploymentPlannerCreatesRuntimeOnlyPlans() {
        var document = HypeDocument.newDocument(name: "Deployable")
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [.macOS, .iPhone, .iPad, .tvOS],
            primaryPlatform: .macOS,
            selectionPromptAcknowledged: true,
            layoutPolicy: .scaleToFit
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
        #expect(runtimeDocument.stack.deploymentTargets.layoutPolicy == .scaleToFit)
    }

    @Test("deployment validation reports unsupported existing parts per target")
    func deploymentValidationReportsUnsupportedExistingParts() throws {
        var document = HypeDocument.newDocument(name: "Validation")
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [.tvOS],
            primaryPlatform: .tvOS,
            selectionPromptAcknowledged: true
        )
        let field = Part(partType: .field, cardId: document.cards[0].id, name: "Search Term")
        document.addPart(field)

        let planner = StackDeploymentPlanner()
        let plan = try #require(planner.plans(for: document).first)
        let report = planner.validate(document: document, for: plan)

        #expect(!report.isDeployable)
        #expect(report.issues.count == 1)
        #expect(report.issues.first?.partId == field.id)
        #expect(report.issues.first?.partType == .field)
        #expect(report.issues.first?.platform == .tvOS)
        #expect(report.issues.first?.reason.contains("tvOS text-entry adapter") == true)
    }

    @Test("runtime package builder rejects unsupported target parts")
    func runtimePackageBuilderRejectsUnsupportedTargetParts() throws {
        var document = HypeDocument.newDocument(name: "Unsupported Export")
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [.tvOS],
            primaryPlatform: .tvOS,
            selectionPromptAcknowledged: true
        )
        document.addPart(Part(partType: .field, cardId: document.cards[0].id, name: "Name Field"))

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("HypeUnsupportedRuntimePackageTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: output) }

        #expect(throws: TargetRuntimePackageBuilderError.self) {
            try TargetRuntimePackageBuilder().buildPackages(for: document, at: output)
        }
    }

    @Test("runtime package builder embeds self-contained stack and runtime-only shell metadata")
    func runtimePackageBuilderEmbedsSelfContainedStack() throws {
        var document = HypeDocument.newDocument(name: "Runtime Export")
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [.iPhone],
            primaryPlatform: .iPhone,
            selectionPromptAcknowledged: true,
            supportedOrientations: [.portrait, .landscape],
            layoutPolicy: .scaleToFit
        )
        document.stack.runtimeModeEnabled = false
        document.scriptGlobals["draft"] = "not persisted"
        let button = Part(partType: .button, cardId: document.cards[0].id, name: "Start")
        document.addPart(button)

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("HypeRuntimePackageTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: output) }

        let result = try TargetRuntimePackageBuilder().buildPackages(for: document, at: output).first
        let package = try #require(result)
        let manifest = try TargetRuntimePackageBuilder().validatePackage(at: package.packageURL)
        let embeddedStackURL = package.packageURL
            .appendingPathComponent(TargetRuntimePackageBuilder.stackDirectoryName, isDirectory: true)
            .appendingPathComponent(TargetRuntimePackageBuilder.embeddedStackName, isDirectory: true)
        let runtimeDocument = try HypeSQLiteStackStore().load(fromPackageAt: embeddedStackURL)
        let shellSource = try String(
            contentsOf: package.packageURL
                .appendingPathComponent(TargetRuntimePackageBuilder.shellDirectoryName, isDirectory: true)
                .appendingPathComponent("Sources", isDirectory: true)
                .appendingPathComponent("HypeRuntimeApp.swift"),
            encoding: .utf8
        )

        #expect(manifest.platform == .iPhone)
        #expect(manifest.runtimeOnly)
        #expect(!manifest.includesAuthoringUI)
        #expect(manifest.layoutPolicy == .scaleToFit)
        #expect(manifest.runtimeAIProviderPolicy == .appleFoundationModels)
        #expect(manifest.appIntentKinds.contains(.askStackAI))
        #expect(manifest.embeddedStackPath == "Stack/Stack.hype")
        #expect(runtimeDocument.stack.runtimeModeEnabled)
        #expect(runtimeDocument.scriptGlobals.isEmpty)
        #expect(shellSource.contains("HypeSQLiteStackStore().load"))
        #expect(shellSource.contains("HypeRuntimeCardView"))
        #expect(shellSource.contains("LayoutResolver().resolve"))
        #expect(shellSource.contains("profileId: \"iphone-portrait\""))
        #expect(!shellSource.contains("PropertyInspector"))
        #expect(!shellSource.contains("ScriptEditor"))
    }

    @Test("AI tools expose target profile and availability queries")
    func aiToolsExposeTargetQueries() async {
        let toolNames = Set(HypeToolDefinitions.cardControlAuthoringTools.map(\.function.name))
        #expect(toolNames.contains("list_target_profiles"))
        #expect(toolNames.contains("get_part_target_availability"))
        #expect(toolNames.contains("get_hig_layout_guide"))
        #expect(toolNames.contains("validate_hig_layout"))
        #expect(toolNames.contains("apply_hig_layout"))
        #expect(toolNames.contains("pin_part_to_safe_area"))
        #expect(toolNames.contains("add_part_layout_constraint"))
        #expect(toolNames.contains("list_part_layout_constraints"))

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

        let layoutPreview = await executor.execute(
            toolName: "preview_layout_profile",
            arguments: ["profile_id": "tvos-1080p"],
            document: &document,
            currentCardId: cardId
        )
        #expect(layoutPreview.contains("Layout preview for tvOS 1080p"))
        #expect(layoutPreview.contains("policy=fixed"))

        let deploymentPlan = await executor.execute(
            toolName: "plan_stack_deployment",
            arguments: [:],
            document: &document,
            currentCardId: cardId
        )
        #expect(deploymentPlan.contains("macOS: kind=macOSStandalone"))
        #expect(deploymentPlan.contains("tvOS: kind=tvOSRuntimeShell"))
        #expect(deploymentPlan.contains("deployable=true"))

        document.addPart(Part(partType: .field, cardId: cardId, name: "TV Search"))
        let blockedDeploymentPlan = await executor.execute(
            toolName: "plan_stack_deployment",
            arguments: [:],
            document: &document,
            currentCardId: cardId
        )
        #expect(blockedDeploymentPlan.contains("deployable=false"))
        #expect(blockedDeploymentPlan.contains("unsupportedParts=[field \"TV Search\"]"))

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
            arguments: ["property": "layoutPolicy", "value": "scaleToFit"],
            document: &document,
            currentCardId: cardId
        )
        let layoutPolicy = await executor.execute(
            toolName: "get_stack_property",
            arguments: ["property": "layoutPolicy"],
            document: &document,
            currentCardId: cardId
        )
        #expect(layoutPolicy == "scaleToFit")

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

    @Test("HIG layout metrics encode platform minimums and source attribution")
    func higLayoutMetricsEncodePlatformRules() {
        let phone = HIGLayoutCatalog.metrics(for: HypeDeviceProfileCatalog.defaultProfile(for: .iPhone))
        let tv = HIGLayoutCatalog.metrics(for: HypeDeviceProfileCatalog.defaultProfile(for: .tvOS))
        let guide = HIGLayoutCatalog.guide(profile: HypeDeviceProfileCatalog.defaultProfile(for: .iPhone))

        #expect(phone.minimumHitWidth == 44)
        #expect(phone.minimumHitHeight == 44)
        #expect(tv.minimumHitWidth == 66)
        #expect(tv.prefersFocusSafeSpacing)
        #expect(guide.contains("safeArea"))
        #expect(guide.contains("developer.apple.com/design/human-interface-guidelines/layout"))
    }

    @Test("HIG layout validation reports unsafe small controls")
    func higLayoutValidationReportsSmallUnsafeControls() async {
        var document = HypeDocument.newDocument(name: "Unsafe")
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [.iPhone],
            primaryPlatform: .iPhone,
            selectionPromptAcknowledged: true,
            layoutPolicy: .fixed
        )
        document.addPart(Part(partType: .button, cardId: document.cards[0].id, name: "Tiny", left: -10, top: 4, width: 20, height: 20))
        let executor = HypeToolExecutor()

        let report = await executor.execute(
            toolName: "validate_hig_layout",
            arguments: ["profile_ids": "iphone-portrait"],
            document: &document,
            currentCardId: document.cards[0].id
        )

        #expect(report.hasPrefix("FAIL:"))
        #expect(report.contains("outside safe content"))
        #expect(report.contains("interactive hit area"))
    }

    @Test("AI HIG layout tools arrange, constrain, and validate multi-target controls")
    func aiHIGLayoutToolsArrangeConstrainAndValidate() async throws {
        var document = HypeDocument.newDocument(name: "Responsive")
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [.macOS, .iPhone, .iPad],
            primaryPlatform: .macOS,
            selectionPromptAcknowledged: true,
            layoutPolicy: .fixed
        )
        let cardId = document.cards[0].id
        var name = Part(partType: .field, cardId: cardId, name: "Name", left: 5, top: 5, width: 80, height: 18)
        name.textSize = 12
        let submit = Part(partType: .button, cardId: cardId, name: "Submit", left: 100, top: 5, width: 80, height: 20)
        document.addPart(name)
        document.addPart(submit)
        let executor = HypeToolExecutor()

        let guide = await executor.execute(
            toolName: "get_hig_layout_guide",
            arguments: ["profile_id": "iphone-portrait"],
            document: &document,
            currentCardId: cardId
        )
        #expect(guide.contains("Minimum interactive hit target"))

        let applied = await executor.execute(
            toolName: "apply_hig_layout",
            arguments: [
                "layout_type": "vertical_stack",
                "part_names": "Name, Submit",
                "profile_id": "iphone-portrait",
                "fill_width": "true",
            ],
            document: &document,
            currentCardId: cardId
        )

        #expect(applied.contains("Applied HIG vertical_stack layout"))
        #expect(document.stack.deploymentTargets.layoutPolicy == .scaleToFit)
        let namePart = try #require(document.parts.first { $0.name == "Name" })
        let submitPart = try #require(document.parts.first { $0.name == "Submit" })
        #expect(namePart.height > 44)
        #expect(submitPart.height > 44)
        #expect(namePart.textSize >= 17)
        #expect(document.constraints.count >= 6)

        let constraints = await executor.execute(
            toolName: "list_part_layout_constraints",
            arguments: ["part_names": "Name, Submit"],
            document: &document,
            currentCardId: cardId
        )
        #expect(constraints.contains("Name.left"))
        #expect(constraints.contains("Submit.top"))

        let pin = await executor.execute(
            toolName: "pin_part_to_safe_area",
            arguments: ["part_name": "Submit", "edges": "bottom", "margin": "20"],
            document: &document,
            currentCardId: cardId
        )
        #expect(pin.contains("Pinned part \"Submit\""))

        let report = await executor.execute(
            toolName: "validate_hig_layout",
            arguments: [:],
            document: &document,
            currentCardId: cardId
        )
        #expect(report.hasPrefix("OK:") || report.hasPrefix("WARN:"))
        #expect(!report.contains("interactive hit area"))
        #expect(!report.contains("outside safe content"))
    }
}
