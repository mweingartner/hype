import Testing
import Foundation
@testable import HypeCore

// Regression tests for the scene-authoring wrong-language defense.
//
// Bug report: asking for a sprite-scene game ("add player, blue_dot,
// red_dot with physics / WASD controls / score / lives") produced a
// proposal whose `sceneScript` field was full of JavaScript +
// Swift SpriteKit API calls:
//
//     var score = 0;
//     self.updateScoreDisplay = function() { ... };
//     self.physicsBody = SKPhysicsBody(edgeLoopFrom: self.frame);
//     self.enumerateChildrenWithNodePattern('blue_dot', function(node) {...});
//
// That text landed in Hype's Script Editor where it was obviously
// wrong-language. Two layers of defense fix this:
//   1. The scene-authoring system prompt now explicitly states the
//      script language is HypeTalk (not JS/Swift/Obj-C/etc.) and
//      lists the forbidden tokens.
//   2. Every script field in the returned proposal is run through
//      `sanitizedHypeTalkScript`, which detects hard signals like
//      `function(`, `self.`, `SKPhysicsBody`, etc. and replaces
//      wrong-language content with a TODO comment — so the wrong
//      code never reaches the document.
//
// These tests pin down detector behavior and the sanitizer pass.
@Suite("Scene script sanitization — non-HypeTalk defense")
struct SceneScriptSanitizationTests {

    // MARK: - looksLikeNonHypeTalkScript

    @Test("detects the exact JavaScript + Swift SpriteKit repro from the bug report")
    func detectsBugReproScript() {
        let jsScript = """
        var score = 0; var lives = 3; self.updateScoreDisplay = function() { var label = self.childNodeWithName('score_label'); if (label) label.text = 'Score: ' + score + '  Lives: ' + lives; };
        self.physicsBody = SKPhysicsBody(edgeLoopFrom: self.frame);
        """
        #expect(SceneAuthoringAssistant.looksLikeNonHypeTalkScript(jsScript))
    }

    @Test("detects a Swift-flavored SpriteKit script")
    func detectsSwiftScript() {
        let swift = #"""
        let body = SKPhysicsBody(circleOfRadius: 20)
        body.isDynamic = true
        node.physicsBody = body
        """#
        #expect(SceneAuthoringAssistant.looksLikeNonHypeTalkScript(swift))
    }

    @Test("detects a JS arrow-function event handler")
    func detectsArrowFunction() {
        let js = "const onTick = (dt) => { score += 1; }"
        #expect(SceneAuthoringAssistant.looksLikeNonHypeTalkScript(js))
    }

    @Test("detects a self.childNodeWithName call")
    func detectsChildNodeLookup() {
        let mix = "self.childNodeWithName('player').position = { x: 100, y: 100 };"
        #expect(SceneAuthoringAssistant.looksLikeNonHypeTalkScript(mix))
    }

    // MARK: - Valid HypeTalk does NOT trigger the detector

    @Test("allows a canonical HypeTalk mouseUp handler")
    func allowsHypeTalkHandler() {
        let ht = """
        on mouseUp
          put "Hello" into field "greeting"
          go next
        end mouseUp
        """
        #expect(!SceneAuthoringAssistant.looksLikeNonHypeTalkScript(ht))
    }

    @Test("allows a HypeTalk keyDown handler with variables")
    func allowsHypeTalkKeyDown() {
        let ht = """
        on keyDown
          global speed
          set the loc of sprite "player" to "300,400"
          if the key is "w" then set the loc of sprite "player" to "300,380"
        end keyDown
        """
        #expect(!SceneAuthoringAssistant.looksLikeNonHypeTalkScript(ht))
    }

    @Test("allows a HypeTalk beginContact handler")
    func allowsHypeTalkBeginContact() {
        let ht = """
        on beginContact nodeA, nodeB
          add 10 to score
          put score into field "scoreLabel"
        end beginContact
        """
        #expect(!SceneAuthoringAssistant.looksLikeNonHypeTalkScript(ht))
    }

    @Test("allows a HypeTalk script with a user function")
    func allowsHypeTalkUserFunction() {
        let ht = """
        function double(n)
          return n * 2
        end double

        on mouseUp
          put double(5) into field "out"
        end mouseUp
        """
        #expect(!SceneAuthoringAssistant.looksLikeNonHypeTalkScript(ht))
    }

    @Test("allows an empty script")
    func allowsEmptyScript() {
        #expect(!SceneAuthoringAssistant.looksLikeNonHypeTalkScript(""))
        #expect(!SceneAuthoringAssistant.looksLikeNonHypeTalkScript("   \n  \n  "))
    }

    @Test("allows a HypeTalk-only comment block")
    func allowsHypeTalkComments() {
        let ht = """
        -- placeholder for future logic
        -- keep handlers short
        """
        #expect(!SceneAuthoringAssistant.looksLikeNonHypeTalkScript(ht))
    }

    // MARK: - Edge cases: soft-signal combinations without a handler

    @Test("detects JS without a handler block when multiple soft signals combine")
    func detectsMultipleSoftSignals() {
        // `var`, `return`, `;` — three soft signals, no `on ... end`.
        let js = "var x = 5; var y = 10; return x + y;"
        #expect(SceneAuthoringAssistant.looksLikeNonHypeTalkScript(js))
    }

    @Test("soft signals without threshold leave HypeTalk alone")
    func softSignalsBelowThreshold() {
        // HypeTalk that happens to contain a comment mentioning `var`
        // — only one soft signal. Should NOT trigger.
        let ht = """
        on mouseUp
          -- note: some other languages use var keyword
          put "hello" into field "greeting"
        end mouseUp
        """
        #expect(!SceneAuthoringAssistant.looksLikeNonHypeTalkScript(ht))
    }

    // MARK: - sanitizedHypeTalkScript

    @Test("sanitizer blanks non-HypeTalk scripts and leaves HypeTalk alone")
    func sanitizerSwapsOnlyWhenNeeded() {
        let js = "self.physicsBody = SKPhysicsBody();"
        let htBefore = "on mouseUp\n  go next\nend mouseUp"

        let jsAfter = SceneAuthoringAssistant.sanitizedHypeTalkScript(js) ?? ""
        let htAfter = SceneAuthoringAssistant.sanitizedHypeTalkScript(htBefore) ?? ""

        // JS turned into a TODO placeholder comment.
        #expect(jsAfter != js)
        #expect(jsAfter.contains("TODO"))
        #expect(jsAfter.contains("HypeTalk"))
        // HypeTalk untouched.
        #expect(htAfter == htBefore)
    }

    @Test("sanitizer returns empty string untouched (no placeholder for empty)")
    func sanitizerLeavesEmptyAlone() {
        #expect(SceneAuthoringAssistant.sanitizedHypeTalkScript("") == "")
    }

    // MARK: - End-to-end: normalizer strips JS from a full proposal

    @Test("normalizeCreateProposal strips non-HypeTalk scripts from nodes and sceneScript")
    func normalizerStripsJSFromProposal() {
        let jsScript = "var x = 1; self.physicsBody = SKPhysicsBody();"
        let badNode = SceneBlueprintNode(
            name: "player",
            nodeType: .sprite,
            position: PointSpec(x: 100, y: 100),
            script: jsScript
        )
        let goodNode = SceneBlueprintNode(
            name: "dot",
            nodeType: .sprite,
            position: PointSpec(x: 200, y: 200),
            script: "on mouseUp\n  beep\nend mouseUp"
        )
        let proposal = SceneCreateProposal(
            areaName: "arena",
            sceneName: "main",
            createSpriteAreaIfMissing: false,
            summary: "test scene",
            checklist: [],
            scene: SceneBlueprint(
                size: SizeSpec(width: 400, height: 300),
                backgroundColor: "#FFFFFF",
                gravity: VectorSpec(dx: 0, dy: 0),
                scaleMode: .aspectFit,
                showsPhysics: false,
                showsFPS: false,
                showsNodeCount: false,
                sceneScript: jsScript,
                nodes: [badNode, goodNode]
            )
        )
        // userRequest doesn't contain bounce keywords, so only the
        // sanitization pass runs (not the physics-bounce pass).
        let normalized = SceneAuthoringAssistant.normalizeCreateProposal(
            proposal,
            for: "build a scene"
        )
        // Bad node's script was blanked with a TODO.
        #expect(normalized.scene.nodes[0].script?.contains("TODO") == true)
        #expect(normalized.scene.nodes[0].script?.contains("SKPhysicsBody") == false)
        // Good node's script was preserved.
        #expect(normalized.scene.nodes[1].script?.contains("on mouseUp") == true)
        // Scene script was blanked too.
        #expect(normalized.scene.sceneScript.contains("TODO"))
        #expect(!normalized.scene.sceneScript.contains("SKPhysicsBody"))
        // A warning was added to the checklist and summary.
        #expect(normalized.checklist.contains(where: { $0.key == "hypetalk-scripts" }))
        #expect(normalized.summary.contains("non-HypeTalk"))
    }

    @Test("normalizeRepairProposal strips non-HypeTalk scripts from addNodes and sceneUpdates")
    func normalizerStripsJSFromRepairProposal() {
        let jsScript = "var score = 0; self.updateScoreDisplay = function() {};"
        let sceneUpdate = SceneUpdate(script: jsScript)
        var diff = SceneDiff()
        diff.sceneUpdates = sceneUpdate
        diff.addNodes = [
            HypeNodeSpec(name: "player", nodeType: .sprite, script: jsScript),
            HypeNodeSpec(name: "dot", nodeType: .sprite, script: "on mouseUp\n  beep\nend mouseUp")
        ]
        let proposal = SceneRepairProposal(
            areaName: "arena",
            summary: "",
            issues: [],
            diff: diff
        )
        let scene = SceneSpec(name: "main", size: SizeSpec(width: 400, height: 300))
        let normalized = SceneAuthoringAssistant.normalizeRepairProposal(
            proposal,
            for: "fix my scene",
            currentScene: scene
        )
        let updatedScript = normalized.diff.sceneUpdates?.script ?? ""
        #expect(updatedScript.contains("TODO"))
        #expect(!updatedScript.contains("function"))
        let nodes = normalized.diff.addNodes ?? []
        #expect(nodes[0].script.contains("TODO"))
        #expect(!nodes[0].script.contains("function"))
        // Good node preserved.
        #expect(nodes[1].script.contains("on mouseUp"))
        // Summary flagged it.
        #expect(normalized.summary.contains("non-HypeTalk"))
    }

    @Test("system prompts include the HypeTalk language rules block")
    func systemPromptIncludesLanguageRules() {
        // The block itself lists the forbidden tokens — verify it
        // says HypeTalk, mentions the forbidden languages by name,
        // and shows a handler-block example + the forbidden tokens.
        let rules = SceneAuthoringAssistant.hypeTalkScriptLanguageRules
        #expect(rules.contains("HypeTalk"),
                "rules must mention HypeTalk by name")
        #expect(rules.lowercased().contains("javascript"),
                "rules must mention JavaScript as a forbidden language")
        #expect(rules.lowercased().contains("swift"),
                "rules must mention Swift as a forbidden language")
        #expect(rules.contains("handlerName"),
                "rules must show the on/end handler template")
        #expect(rules.contains("function("),
                "rules must call out the JS `function(` forbidden token")
        #expect(rules.contains("self."),
                "rules must call out the `self.` forbidden token")
        #expect(rules.contains("SKPhysicsBody"),
                "rules must call out SKPhysicsBody as a forbidden token")
    }
}
