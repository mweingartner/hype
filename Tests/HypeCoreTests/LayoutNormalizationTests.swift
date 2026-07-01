import Foundation
import Testing
@testable import HypeCore

// MARK: - Helpers

/// Parse a HypeTalk script and return its first handler.
private func parseHandler(_ source: String) throws -> Handler {
    var lexer = Lexer(source: source)
    let tokens = lexer.tokenize()
    var parser = Parser(tokens: tokens)
    let script = try parser.parse()
    guard let handler = script.handlers.first else {
        throw LayoutNormalizationError.parseFailure
    }
    return handler
}

private enum LayoutNormalizationError: Error {
    case parseFailure
}

// MARK: - Suite

@Suite("Layout normalization mutation-surface coverage")
struct LayoutNormalizationTests {

    // MARK: - TargetPreviewOverflow unit tests

    @Test("overflow helper returns empty set when all parts are inside bounds")
    func overflowHelperEmptyWhenInsideBounds() {
        let cardId = UUID()
        let part = Part(partType: .button, cardId: cardId, left: 10, top: 10, width: 50, height: 30)
        let profile = HypeDeviceProfileCatalog.defaultProfile(for: .macOS)

        let resolution = LayoutResolver().resolve(
            parts: [part],
            constraints: [],
            profile: profile,
            policy: .fixed
        )
        let ids = TargetPreviewOverflow.overflowingPartIds(resolution: resolution, profile: profile)
        #expect(ids.isEmpty)
    }

    @Test("overflow helper detects part extending past right edge")
    func overflowHelperDetectsRightEdgeOverflow() {
        let cardId = UUID()
        // Place a part whose right edge exceeds the macOS default canvas width (800).
        let part = Part(partType: .button, cardId: cardId, left: 780, top: 10, width: 50, height: 30)
        let profile = HypeDeviceProfileCatalog.defaultProfile(for: .macOS)

        let resolution = LayoutResolver().resolve(
            parts: [part],
            constraints: [],
            profile: profile,
            policy: .fixed
        )
        let ids = TargetPreviewOverflow.overflowingPartIds(resolution: resolution, profile: profile)
        #expect(ids.contains(part.id))
        #expect(ids.count == 1)
    }

    @Test("overflow helper detects part with negative top")
    func overflowHelperDetectsNegativeTop() {
        let cardId = UUID()
        let part = Part(partType: .button, cardId: cardId, left: 10, top: -5, width: 40, height: 20)
        let profile = HypeDeviceProfileCatalog.defaultProfile(for: .macOS)

        let resolution = LayoutResolver().resolve(
            parts: [part],
            constraints: [],
            profile: profile,
            policy: .fixed
        )
        let ids = TargetPreviewOverflow.overflowingPartIds(resolution: resolution, profile: profile)
        #expect(ids.contains(part.id))
    }

    @Test("overflow helper returns empty set for scaleToFit that fits within bounds")
    func overflowHelperEmptyForScaleToFitWithinBounds() {
        let cardId = UUID()
        // Source 800x600 part at (400, 300, 100, 50); iPhone profile.
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
        let ids = TargetPreviewOverflow.overflowingPartIds(resolution: resolution, profile: profile)
        // scaleToFit centers the content; the scaled part should be within bounds.
        #expect(ids.isEmpty)
    }

    @Test("overflow helper correctly handles part exactly at canvas edge (no overflow)")
    func overflowHelperEdgeExactlyAtBoundary() {
        let cardId = UUID()
        let profile = HypeDeviceProfileCatalog.defaultProfile(for: .macOS)
        // Part exactly at right/bottom edge (no overflow).
        let part = Part(partType: .button, cardId: cardId, left: 750, top: 570, width: 50, height: 30)
        // macOS default: 800x600 → left=750, width=50 → right=800, top=570, height=30 → bottom=600

        let resolution = LayoutResolver().resolve(
            parts: [part],
            constraints: [],
            profile: profile,
            policy: .fixed
        )
        let ids = TargetPreviewOverflow.overflowingPartIds(resolution: resolution, profile: profile)
        #expect(ids.isEmpty)
    }

    // MARK: - Script interpreter: set the layoutPolicy

    @Test("script set layoutPolicy on macOS-only clamps to fixed")
    func scriptSetLayoutPolicyMacOSOnlyClampedToFixed() async throws {
        var document = HypeDocument.newDocument(name: "MacOnly")
        // Start on macOS-only with scaleToFit stored (would be invalid but tests clamping).
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [.macOS],
            primaryPlatform: .macOS,
            selectionPromptAcknowledged: true,
            layoutPolicy: .fixed
        )
        let cardId = document.cards[0].id

        let handler = try parseHandler("""
        on mouseUp
          set the layoutPolicy of this stack to "scaleToFit"
        end mouseUp
        """)

        let result = await Interpreter().executeAsync(
            handler: handler,
            params: [],
            context: ExecutionContext(targetId: cardId, currentCardId: cardId, document: document)
        )
        #expect(result.status == .completed)
        let modified = try #require(result.modifiedDocument)
        // macOS-only: scaleToFit should be clamped back to .fixed
        #expect(modified.stack.deploymentTargets.layoutPolicy == .fixed)
    }

    @Test("script set layoutPolicy on multi-target respects scaleToFit")
    func scriptSetLayoutPolicyMultiTargetRespectsScaleToFit() async throws {
        var document = HypeDocument.newDocument(name: "MultiTarget")
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [.macOS, .iPhone],
            primaryPlatform: .macOS,
            selectionPromptAcknowledged: true,
            layoutPolicy: .fixed
        )
        let cardId = document.cards[0].id

        let handler = try parseHandler("""
        on mouseUp
          set the layoutPolicy of this stack to "scaleToFit"
        end mouseUp
        """)

        let result = await Interpreter().executeAsync(
            handler: handler,
            params: [],
            context: ExecutionContext(targetId: cardId, currentCardId: cardId, document: document)
        )
        #expect(result.status == .completed)
        let modified = try #require(result.modifiedDocument)
        #expect(modified.stack.deploymentTargets.layoutPolicy == .scaleToFit)
    }

    @Test("script set targetPlatforms to macOS clamps existing scaleToFit policy")
    func scriptSetTargetPlatformsToMacOSClampsPolicy() async throws {
        var document = HypeDocument.newDocument(name: "PlatformClamp")
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [.macOS, .iPhone],
            primaryPlatform: .macOS,
            selectionPromptAcknowledged: true,
            layoutPolicy: .scaleToFit
        )
        let cardId = document.cards[0].id

        let handler = try parseHandler("""
        on mouseUp
          set the targetPlatforms of this stack to "macOS"
        end mouseUp
        """)

        let result = await Interpreter().executeAsync(
            handler: handler,
            params: [],
            context: ExecutionContext(targetId: cardId, currentCardId: cardId, document: document)
        )
        #expect(result.status == .completed)
        let modified = try #require(result.modifiedDocument)
        // Switching to macOS-only must clamp scaleToFit → fixed.
        #expect(modified.stack.deploymentTargets.selectedPlatforms == [.macOS])
        #expect(modified.stack.deploymentTargets.layoutPolicy == .fixed)
    }

    // MARK: - AI tool executor: set_stack_property layoutPolicy

    @Test("AI set_stack_property layoutPolicy=stretchToFill on macOS-only clamps to fixed")
    func aiSetLayoutPolicyStretchMacOSClamped() async {
        var document = HypeDocument.newDocument(name: "MacOnlyAI")
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [.macOS],
            primaryPlatform: .macOS,
            selectionPromptAcknowledged: true,
            layoutPolicy: .fixed
        )
        let cardId = document.cards[0].id
        let executor = HypeToolExecutor()

        _ = await executor.execute(
            toolName: "set_stack_property",
            arguments: ["property": "layoutPolicy", "value": "stretchToFill"],
            document: &document,
            currentCardId: cardId
        )
        #expect(document.stack.deploymentTargets.layoutPolicy == .fixed)
    }

    @Test("AI set_stack_property layoutPolicy=stretchToFill on multi-target is preserved")
    func aiSetLayoutPolicyStretchMultiTargetPreserved() async {
        var document = HypeDocument.newDocument(name: "MultiAI")
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [.macOS, .iPad],
            primaryPlatform: .macOS,
            selectionPromptAcknowledged: true,
            layoutPolicy: .fixed
        )
        let cardId = document.cards[0].id
        let executor = HypeToolExecutor()

        _ = await executor.execute(
            toolName: "set_stack_property",
            arguments: ["property": "layoutPolicy", "value": "stretchToFill"],
            document: &document,
            currentCardId: cardId
        )
        #expect(document.stack.deploymentTargets.layoutPolicy == .stretchToFill)
    }

    @Test("AI set_stack_property targetPlatforms=macOS with prior scaleToFit clamps to fixed")
    func aiSetTargetPlatformsMacOSClampsScaleToFit() async {
        var document = HypeDocument.newDocument(name: "ClampAI")
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [.macOS, .iPhone],
            primaryPlatform: .macOS,
            selectionPromptAcknowledged: true,
            layoutPolicy: .scaleToFit
        )
        let cardId = document.cards[0].id
        let executor = HypeToolExecutor()

        _ = await executor.execute(
            toolName: "set_stack_property",
            arguments: ["property": "targetPlatforms", "value": "macOS"],
            document: &document,
            currentCardId: cardId
        )
        #expect(document.stack.deploymentTargets.selectedPlatforms == [.macOS])
        #expect(document.stack.deploymentTargets.layoutPolicy == .fixed)
    }

    // MARK: - Property/metamorphic tests for LayoutResolver

    @Test("scaleToFit offsets are always non-negative (property test)")
    func scaleToFitOffsetsAlwaysNonNegative() {
        let cardId = UUID()
        // Seeded deterministic loop over varied source sizes.
        let configs: [(Double, Double, Double, Double)] = [
            (100, 200, 393, 759),
            (800, 600, 393, 759),
            (1920, 1080, 1740, 960),
            (400, 900, 393, 759),
            (393, 759, 393, 759),  // Source == safe area: offsets exactly 0
            (1, 1, 393, 759),      // Degenerate 1×1 source
            (10000, 10000, 393, 759), // Very large source
        ]
        for (srcW, srcH, safeW, safeH) in configs {
            let part = Part(partType: .button, cardId: cardId, left: 0, top: 0, width: 10, height: 10)
            // Build a synthetic profile matching safeW/safeH (no safe insets).
            let profile = HypeDeviceProfile(
                id: "test-\(Int(srcW))x\(Int(srcH))",
                platform: .iPhone,
                displayName: "Test",
                width: Int(safeW),
                height: Int(safeH),
                orientation: .portrait,
                inputModel: .touch
            )
            let resolution = LayoutResolver().resolve(
                parts: [part],
                constraints: [],
                profile: profile,
                sourceCanvasWidth: srcW,
                sourceCanvasHeight: srcH,
                policy: .scaleToFit
            )
            #expect(resolution.contentOffsetX >= 0,
                    "offsetX should be >= 0 for \(srcW)x\(srcH) into \(safeW)x\(safeH)")
            #expect(resolution.contentOffsetY >= 0,
                    "offsetY should be >= 0 for \(srcW)x\(srcH) into \(safeW)x\(safeH)")
            // Centering symmetry: 2*offsetX + srcW*scale ≈ safeW, same for Y.
            let scale = resolution.contentScaleX
            let projectedW = srcW * scale
            let projectedH = srcH * scale
            #expect(abs(2 * resolution.contentOffsetX + projectedW - safeW) < 0.001,
                    "Centering symmetry X failed for \(srcW)x\(srcH)")
            #expect(abs(2 * resolution.contentOffsetY + projectedH - safeH) < 0.001,
                    "Centering symmetry Y failed for \(srcW)x\(srcH)")
        }
    }

    @Test("scaleToFit subordinate axis offset is zero, dominant axis offset is zero")
    func scaleToFitExactlyOneAxisHasZeroOffset() {
        let cardId = UUID()
        // Wide source → Y is dominant (Y scale < X scale) → offsetY ≈ 0, offsetX > 0.
        let widePart = Part(partType: .button, cardId: cardId, left: 0, top: 0, width: 5, height: 5)
        let profile = HypeDeviceProfileCatalog.defaultProfile(for: .iPhone)

        let wideRes = LayoutResolver().resolve(
            parts: [widePart],
            constraints: [],
            profile: profile,
            sourceCanvasWidth: 800,
            sourceCanvasHeight: 600,
            policy: .scaleToFit
        )
        // 800x600 into 393x759 safe: scale = min(393/800, 759/600) = 0.49125 → X dominant
        // offsetX = (393 - 393)/2 = 0; offsetY = (759 - 294.75)/2 > 0
        #expect(abs(wideRes.contentOffsetX) < 0.001)
        #expect(wideRes.contentOffsetY > 0)
    }

    @Test("fixed policy is idempotent on geometry (no coordinate change)")
    func fixedPolicyIsIdentity() {
        let cardId = UUID()
        let part = Part(partType: .button, cardId: cardId, left: 42, top: 73, width: 120, height: 55)
        let profile = HypeDeviceProfileCatalog.defaultProfile(for: .macOS)

        let resolution = LayoutResolver().resolve(
            parts: [part],
            constraints: [],
            profile: profile,
            sourceCanvasWidth: Double(profile.width),
            sourceCanvasHeight: Double(profile.height),
            policy: .fixed
        )
        let geo = resolution.geometries[part.id]!
        // Fixed with source == target and no safe-area insets: coords unchanged.
        #expect(abs(geo.left - part.left) < 0.001)
        #expect(abs(geo.top - part.top) < 0.001)
        #expect(abs(geo.width - part.width) < 0.001)
        #expect(abs(geo.height - part.height) < 0.001)
    }

    @Test("stretchToFill maps source corners to safe-area corners")
    func stretchToFillMapsCornersToSafeAreaCorners() throws {
        let cardId = UUID()
        // Place a part at (0,0) with size equal to the source canvas.
        let srcW = 800.0
        let srcH = 600.0
        let part = Part(partType: .button, cardId: cardId, left: 0, top: 0, width: srcW, height: srcH)
        let profile = HypeDeviceProfileCatalog.defaultProfile(for: .iPhone)

        let resolution = LayoutResolver().resolve(
            parts: [part],
            constraints: [],
            profile: profile,
            sourceCanvasWidth: srcW,
            sourceCanvasHeight: srcH,
            policy: .stretchToFill
        )
        let geo = try #require(resolution.geometries[part.id])

        // The part should fill the entire safe area (offset by safeLeft/safeTop).
        let safeLeft = Double(profile.safeArea.left)
        let safeTop = Double(profile.safeArea.top)
        let safeWidth = Double(profile.width) - profile.safeArea.left - profile.safeArea.right
        let safeHeight = Double(profile.height) - profile.safeArea.top - profile.safeArea.bottom

        #expect(abs(geo.left - safeLeft) < 0.001)
        #expect(abs(geo.top - safeTop) < 0.001)
        #expect(abs(geo.width - safeWidth) < 0.1)
        #expect(abs(geo.height - safeHeight) < 0.1)
    }

    @Test("clampedLayoutPolicy is idempotent")
    func clampedLayoutPolicyIsIdempotent() {
        let targets = StackDeploymentTargets(
            selectedPlatforms: [.macOS],
            primaryPlatform: .macOS,
            selectionPromptAcknowledged: true,
            layoutPolicy: .fixed
        )
        for policy in TargetLayoutPolicy.allCases {
            let once = targets.clampedLayoutPolicy(policy)
            let twice = targets.clampedLayoutPolicy(once)
            #expect(once == twice, "clampedLayoutPolicy(\(policy)) should be idempotent")
        }

        let multi = StackDeploymentTargets(
            selectedPlatforms: [.macOS, .iPhone],
            primaryPlatform: .macOS,
            selectionPromptAcknowledged: true,
            layoutPolicy: .fixed
        )
        for policy in TargetLayoutPolicy.allCases {
            let once = multi.clampedLayoutPolicy(policy)
            let twice = multi.clampedLayoutPolicy(once)
            #expect(once == twice, "clampedLayoutPolicy(\(policy)) should be idempotent on multi-target")
        }
    }

    @Test("LayoutResolver produces finite geometry on degenerate inputs")
    func layoutResolverFiniteOnDegenerateInputs() {
        let cardId = UUID()
        let part = Part(partType: .button, cardId: cardId, left: 0, top: 0, width: 1, height: 1)
        let profile = HypeDeviceProfileCatalog.defaultProfile(for: .iPhone)

        for policy in TargetLayoutPolicy.allCases {
            // 1×1 source
            let res = LayoutResolver().resolve(
                parts: [part],
                constraints: [],
                profile: profile,
                sourceCanvasWidth: 1,
                sourceCanvasHeight: 1,
                policy: policy
            )
            let geo = res.geometries[part.id]!
            #expect(geo.left.isFinite, "left should be finite for \(policy)")
            #expect(geo.top.isFinite, "top should be finite for \(policy)")
            #expect(geo.width.isFinite, "width should be finite for \(policy)")
            #expect(geo.height.isFinite, "height should be finite for \(policy)")
        }
    }

    // MARK: - Verify HIG layout tool still promotes multi-target fixed → scaleToFit

    @Test("apply_hig_layout promotes multi-target fixed policy to scaleToFit via defaultedLayoutPolicy")
    func applyHIGLayoutPromotesMultiTargetFixedToScaleToFit() async {
        var document = HypeDocument.newDocument(name: "HIG Promote")
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [.macOS, .iPhone],
            primaryPlatform: .macOS,
            selectionPromptAcknowledged: true,
            layoutPolicy: .fixed
        )
        let cardId = document.cards[0].id
        document.addPart(Part(partType: .button, cardId: cardId, name: "Btn", left: 10, top: 10, width: 80, height: 30))

        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "apply_hig_layout",
            arguments: [
                "layout_type": "vertical_stack",
                "part_names": "Btn",
                "fill_width": "false",
            ],
            document: &document,
            currentCardId: cardId
        )

        // defaultedLayoutPolicy should have promoted .fixed → .scaleToFit for multi-target.
        #expect(document.stack.deploymentTargets.layoutPolicy == .scaleToFit)
    }

    @Test("apply_hig_layout with explicit layout_policy=fixed on multi-target clamps (not promotes)")
    func applyHIGLayoutWithExplicitFixedClampsNotPromotes() async {
        var document = HypeDocument.newDocument(name: "HIG Clamp")
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [.macOS, .iPhone],
            primaryPlatform: .macOS,
            selectionPromptAcknowledged: true,
            layoutPolicy: .fixed
        )
        let cardId = document.cards[0].id
        document.addPart(Part(partType: .button, cardId: cardId, name: "Btn", left: 10, top: 10, width: 80, height: 30))

        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "apply_hig_layout",
            arguments: [
                "layout_type": "vertical_stack",
                "part_names": "Btn",
                "layout_policy": "fixed",
                "fill_width": "false",
            ],
            document: &document,
            currentCardId: cardId
        )

        // Explicit clamp on multi-target: .fixed stays .fixed (no auto-promotion).
        #expect(document.stack.deploymentTargets.layoutPolicy == .fixed)
    }
}
