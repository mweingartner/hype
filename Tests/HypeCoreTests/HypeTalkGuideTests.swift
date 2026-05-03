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

    @Test("guide stays under the 32 KB budget so it is cheap to ship on every request")
    func guideStaysUnderBudget() {
        // Budget: 32 KB (≈ 8000 tokens). Raised from 16 KB on
        // 2026-05-02 to accommodate the Phase 1 + 2 framework
        // controls (Calendar, PDF, Map, ColorWell, Stepper, Slider,
        // Toggle, Segmented, Audio Recorder, Scene3D, Image
        // Filters), the centralized Framework Control Properties
        // table, and the System & Lifecycle Messages catalog
        // (recordingStarted/Stopped, playbackStarted/Stopped,
        // dateChanged, colorChanged, valueChanged, selectionChanged,
        // locationResolved). At ~26 KB it's ≈6% of a 128K-context
        // model — still well within typical chat budgets.
        //
        // Raise the budget deliberately if future additions justify
        // it, but only with an accompanying note on the tradeoff.
        #expect(HypeTalkGuide.llmContext.count < 32768,
                "HypeTalkGuide.llmContext is \(HypeTalkGuide.llmContext.count) characters — bump the budget intentionally if this is expected")
    }

    // MARK: - Framework controls + lifecycle messages coverage

    @Test("guide lists the framework control object types and key properties")
    func guideListsFrameworkControls() {
        let text = HypeTalkGuide.llmContext
        // Phase 1
        for kind in ["calendar", "pdf", "map", "colorWell"] {
            #expect(text.contains(kind), "guide is missing framework control kind '\(kind)'")
        }
        // Phase 2 form controls
        for kind in ["stepper", "slider", "toggle", "segmented"] {
            #expect(text.contains(kind), "guide is missing form control kind '\(kind)'")
        }
        // Phase 2 media + 3D
        for kind in ["recorder", "scene3d"] {
            #expect(text.contains(kind), "guide is missing media/3D control kind '\(kind)'")
        }
        // Audio + map property names that postdate the original guide
        for prop in ["recording", "playing", "outputPath", "selectedDate", "currentPage", "centerLat", "centerLon", "maplocation", "color", "value", "on", "selectedSegment"] {
            #expect(text.contains(prop), "guide is missing framework property '\(prop)'")
        }
    }

    @Test("guide lists every lifecycle message dispatched by the host runtime")
    func guideListsLifecycleMessages() {
        let text = HypeTalkGuide.llmContext
        let messages = [
            // Audio recorder
            "recordingStarted", "recordingStopped",
            "playbackStarted", "playbackStopped",
            // Calendar / ColorWell / Form controls
            "dateChanged", "colorChanged", "valueChanged", "selectionChanged",
            // Map
            "locationResolved",
        ]
        for msg in messages {
            #expect(text.contains(msg), "guide is missing lifecycle message '\(msg)'")
        }
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
        // The guide should demonstrate an idle handler as the pattern
        // for custom state / counters (the prior `item 1/2 of pos`
        // example was replaced in commit be88b19 with a `pulse` counter
        // that avoids steering the AI toward script-driven motion when
        // native physics should be used instead — see the explicit
        // "prefer native physics, do not simulate with on idle" rule
        // later in the guide).
        #expect(text.contains("on idle"))
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
