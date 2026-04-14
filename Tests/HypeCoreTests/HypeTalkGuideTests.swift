import Testing
import Foundation
@testable import HypeCore

/// Pins down the contents of `HypeTalkGuide.llmContext` — the HypeTalk
/// scripting guide silently injected into every Ollama chat request.
///
/// The purpose of these tests is threefold:
///
/// 1. **Size budget** — the guide is injected on *every* chat round, so
///    it must stay well under a couple thousand tokens or it will start
///    dominating the context window and crowding out the user's actual
///    conversation.
///
/// 2. **Coverage** — any future refactor that accidentally drops a
///    critical section (handlers, chunks, sprite scenes, generation
///    rules, etc.) should fail here rather than silently ship a guide
///    that no longer matches the language the interpreter implements.
///
/// 3. **Correctness of the wire format** — `point` values must still
///    be described as `"x,y"` strings, object refs must still use
///    double-quoted names, and so on. Drift from the interpreter's
///    actual surface will silently break AI-authored scripts.
@Suite("HypeTalkGuide llm context")
struct HypeTalkGuideTests {

    // MARK: - Sanity

    @Test("guide is non-empty")
    func guideIsNonEmpty() {
        #expect(!HypeTalkGuide.llmContext.isEmpty)
        #expect(HypeTalkGuide.llmContext.count > 500)
    }

    @Test("guide stays under the 16 KB budget so it is cheap to ship on every request")
    func guideStaysUnderBudget() {
        // Budget: 16 KB (≈ 4000 tokens). Raised from 12 KB on
        // 2026-04-10 to accommodate the Sound and Animation
        // sections. The guide now covers play/beep/wait/NAOD notes,
        // system sounds, animate command, tile maps, check_script
        // validation protocol, and the full sprite-scene command
        // set. At ~12.4 KB it's ≈3% of a 128K-context model.
        //
        // Raise the budget deliberately if future additions justify
        // it, but only with an accompanying note on the tradeoff.
        #expect(HypeTalkGuide.llmContext.count < 16384,
                "HypeTalkGuide.llmContext is \(HypeTalkGuide.llmContext.count) characters — bump the budget intentionally if this is expected")
    }

    // MARK: - Section coverage

    @Test("guide contains every major section heading")
    func guideContainsAllSectionHeadings() {
        let required = [
            "# HypeTalk scripting guide",
            "## Message routing",
            "## Handler syntax",
            "## Common events",
            "## Variables and data",
            "## Object references",
            "## Properties",
            "## Chunks",
            "## Control flow",
            "## Navigation",
            "## Dialogs",
            "## Sprite scenes",
            "## Canonical patterns",
            "## Generation rules",
        ]
        for heading in required {
            #expect(HypeTalkGuide.llmContext.contains(heading),
                    "guide is missing required section '\(heading)'")
        }
    }

    // MARK: - Critical syntax examples

    @Test("guide shows the canonical on/end handler form")
    func guideShowsHandlerForm() {
        let text = HypeTalkGuide.llmContext
        #expect(text.contains("on mouseUp"))
        #expect(text.contains("end mouseUp"))
        #expect(text.contains("on openCard"))
        #expect(text.contains("end openCard"))
    }

    @Test("guide describes the full message-passing chain")
    func guideDescribesMessageChain() {
        let text = HypeTalkGuide.llmContext
        // The chain must include every link the interpreter dispatches
        // through — anything dropped here will cause the model to write
        // scripts that assume the wrong routing.
        #expect(text.contains("sprite area part"))
        #expect(text.contains("card"))
        #expect(text.contains("background"))
        #expect(text.contains("stack"))
        #expect(text.contains("Hype"))
        #expect(text.contains("pass"))
    }

    @Test("guide lists every HypeTalk event the interpreter supports")
    func guideListsAllEvents() {
        let text = HypeTalkGuide.llmContext
        let events = [
            "mouseUp", "mouseDown", "mouseDragged", "mouseWithin",
            "openCard", "closeCard",
            "enterKey", "keyDown", "keyUp", "idle",
            "openScene", "closeScene", "sceneDidLoad", "frameUpdate",
            "beginContact", "endContact", "actionFinished",
        ]
        for event in events {
            #expect(text.contains(event), "guide is missing event '\(event)'")
        }
    }

    @Test("guide shows put/get/set core commands")
    func guideShowsCoreCommands() {
        let text = HypeTalkGuide.llmContext
        #expect(text.contains("put"))
        #expect(text.contains("into"))
        #expect(text.contains("set the"))
        #expect(text.contains(" of "))
        #expect(text.contains("global"))
        #expect(text.contains("add"))
        #expect(text.contains("subtract"))
    }

    @Test("guide shows chunk expression forms (word / item / line / char)")
    func guideShowsChunks() {
        let text = HypeTalkGuide.llmContext
        #expect(text.contains("word"))
        #expect(text.contains("item"))
        #expect(text.contains("line"))
        #expect(text.contains("char"))
        #expect(text.contains("the number of"))
        #expect(text.contains("the length of"))
    }

    @Test("guide shows control flow: if/repeat/exit/next")
    func guideShowsControlFlow() {
        let text = HypeTalkGuide.llmContext
        #expect(text.contains("if"))
        #expect(text.contains("then"))
        #expect(text.contains("else"))
        #expect(text.contains("end if"))
        #expect(text.contains("repeat"))
        #expect(text.contains("end repeat"))
        #expect(text.contains("exit repeat"))
        #expect(text.contains("next repeat"))
    }

    @Test("guide shows navigation commands")
    func guideShowsNavigation() {
        let text = HypeTalkGuide.llmContext
        #expect(text.contains("go next"))
        #expect(text.contains("go previous"))
        #expect(text.contains("go first"))
        #expect(text.contains("go last"))
        #expect(text.contains("go card"))
        #expect(text.contains("visual effect"))
    }

    @Test("guide shows object reference forms with quoted names")
    func guideShowsObjectReferences() {
        let text = HypeTalkGuide.llmContext
        #expect(text.contains("button \"OK\""))
        #expect(text.contains("field \"input\""))
        #expect(text.contains("card \"home\""))
        #expect(text.contains("sprite \"player\""))
        #expect(text.contains("label \"score\""))
        #expect(text.contains("shape \"wall\""))
        #expect(text.contains("spritearea \"game\""))
    }

    @Test("guide describes sprite-scene commands and physics primitives")
    func guideDescribesSpriteScenes() {
        let text = HypeTalkGuide.llmContext
        // Scene operations
        #expect(text.contains("create sprite"))
        #expect(text.contains("remove sprite"))
        #expect(text.contains("pause scene"))
        #expect(text.contains("resume scene"))
        // Physics
        #expect(text.contains("velocity"))
        #expect(text.contains("apply force"))
        #expect(text.contains("apply impulse"))
    }

    @Test("guide documents point and color wire formats")
    func guideDocumentsWireFormats() {
        let text = HypeTalkGuide.llmContext
        // Points are "x,y" strings — without this the AI will pass
        // arrays or individual numbers and the interpreter will reject.
        #expect(text.contains("\"x,y\""))
        // Colors are "#RRGGBB" hex.
        #expect(text.contains("\"#RRGGBB\""))
    }

    @Test("guide includes canonical pattern examples")
    func guideIncludesPatternExamples() {
        let text = HypeTalkGuide.llmContext
        // The button-navigates pattern — the smallest working handler.
        #expect(text.contains("go next"))
        // An idle handler that moves a sprite — teaches the pattern of
        // reading loc, splitting into items, mutating, and writing back.
        #expect(text.contains("on idle"))
        #expect(text.contains("item 1 of pos"))
        #expect(text.contains("item 2 of pos"))
        // Collision scoring pattern.
        #expect(text.contains("on beginContact"))
    }

    @Test("guide includes explicit generation rules")
    func guideIncludesGenerationRules() {
        let text = HypeTalkGuide.llmContext
        // The critical auto-wrapping exception for button scripts.
        #expect(text.contains("auto-wraps"))
        // The instruction to stick to the documented surface.
        #expect(text.lowercased().contains("do not invent"))
    }

    // MARK: - Drop-in verification for AIChatPanel

    @Test("guide is safe to interpolate inside a Swift multi-line string prompt")
    func guideInterpolatesCleanly() {
        // AIChatPanel builds the system prompt with `\(HypeTalkGuide.llmContext)`
        // inside a triple-quoted string. A stray closing triple-quote or
        // leading/trailing blank lines would break that. Do a minimal
        // smoke test that interpolation produces the expected shape.
        let wrapped = """
            PREFIX
            \(HypeTalkGuide.llmContext)
            SUFFIX
            """
        #expect(wrapped.hasPrefix("PREFIX\n"))
        #expect(wrapped.hasSuffix("\nSUFFIX"))
        #expect(wrapped.contains("# HypeTalk scripting guide"))
        #expect(!wrapped.contains("\"\"\""))  // no accidental triple-quote escape
    }
}
