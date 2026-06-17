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

    @Test("guide stays under the 80 KB budget so it is cheap to ship on every request")
    func guideStaysUnderBudget() {
        // Budget: 80 KB (≈ 20000 tokens). History:
        //   32 KB → 64 KB (2026-05-05): grammar-coverage expansion
        //     (Operators & Precedence, Constants, Built-in Functions,
        //      Stub commands table, control-flow and chunk expansion,
        //      ~20 AVOID bullets).
        //   64 KB → 80 KB (2026-05-29): Phases 1–5 real-command
        //     documentation. Several commands that were listed as
        //     stubs or no-ops are now fully implemented and must be
        //     documented accurately so the AI generates working code:
        //       - sort cards by <expr> (stable sort, rewrites card order)
        //       - push card / pop card / the recent cards (bounded history)
        //       - convert <container> to <date/time format>
        //       - find "needle" (navigates to match) + found-* getters
        //       - select <chunk> of field + selected-* getters
        //       - click-state getters (clickH/clickV/clickLoc/…)
        //       - the menus / the destination
        //       - do "<script>" (real eval, depth-capped)
        //       - read from file / write … to file (fileAccessAllowed gate)
        //       - import paint / export paint (fileAccessAllowed + AppKit)
        //       - video transport: currentTime, duration, playRate
        //       - host commands: lock/unlock screen, doMenu,
        //         open/save/close/print/edit script (desktop-app only)
        //     Stub table shrank (removed rows now documented elsewhere);
        //     two stale AVOID bullets corrected. Net: ~78 KB.
        //
        // At ~78 KB it's ≈16% of a 128K-context model — within typical
        // chat budgets. Documenting real command surface accurately
        // prevents the AI from refusing or mis-generating working commands,
        // which is the explicit reason for this increase.
        //
        // Raise the budget deliberately if future additions justify
        // it, but only with an accompanying note on the tradeoff.
        #expect(HypeTalkGuide.llmContext.count < 81920,
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
        // AudioKit music controls and commands
        for kind in ["musicPlayer", "pianoKeyboard", "stepSequencer", "musicMixer", "create_music_pattern", "export_music_pattern"] {
            #expect(text.contains(kind), "guide is missing music control/tool kind '\(kind)'")
        }
        // Audio + map property names that postdate the original guide
        for prop in ["recording", "playing", "outputPath", "musicState", "musicPatterns", "musicInstruments", "keyCount", "selectedDate", "currentPage", "centerLat", "centerLon", "maplocation", "color", "value", "on", "selectedSegment"] {
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
            "## AI Context Library",
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
            "listen",
            "openScene", "closeScene", "sceneDidLoad", "frameUpdate",
            "beginContact", "endContact", "actionFinished",
        ]
        for event in events {
            #expect(text.contains(event), "guide is missing event '\(event)'")
        }
        #expect(text.contains("arrows are \"up\", \"down\", \"left\", \"right\""))
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

    @Test("guide documents speech commands and listener routing")
    func guideDocumentsSpeechCommands() {
        let text = HypeTalkGuide.llmContext
        #expect(text.contains("say \"this is a test of the speech support in Hype!\""))
        #expect(text.contains("set activateListener to true"))
        #expect(text.contains("on listen spokenText"))
        #expect(text.contains("pass listen"))
        #expect(text.contains("OpenAI text-to-speech"))
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
        #expect(text.contains("create shape"))
        #expect(text.contains("remove sprite"))
        #expect(text.contains("pause scene"))
        #expect(text.contains("resume scene"))
        // Physics
        #expect(text.contains("velocity"))
        #expect(text.contains("apply force"))
        #expect(text.contains("apply impulse"))
    }

    @Test("guide documents AI context scripting and tool surface")
    func guideDocumentsAIContextSurface() {
        let text = HypeTalkGuide.llmContext
        for token in [
            "aiContextCount",
            "aiContextSummary",
            "aiContextCloudSharingAllowed",
            "list_ai_context",
            "search_ai_context",
            "read_ai_context_item",
            "import_context_asset",
            "write_ai_context_note",
            "projectMemory",
        ] {
            #expect(text.contains(token), "guide is missing AI context token '\(token)'")
        }
        #expect(text.lowercased().contains("untrusted source material"))
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

    // MARK: - Phases 1–5 real-command coverage

    @Test("guide documents Phase 1–5 real commands and no longer calls them stubs")
    func guideDocumentsRealCommands() {
        let text = HypeTalkGuide.llmContext

        // Phase 1: sort cards, push/pop card history, convert date/time
        #expect(text.contains("sort cards by"), "guide missing sort cards")
        #expect(text.contains("push card"), "guide missing push card")
        #expect(text.contains("pop card"), "guide missing pop card")
        #expect(text.contains("the recent cards"), "guide missing the recent cards")
        #expect(text.contains("convert"), "guide missing convert")
        #expect(text.contains("long date"), "guide missing date format keywords")

        // Phase 2: find (navigates), found-* getters, select + selected-* getters, click-* getters
        #expect(text.contains("find \"needle\""), "guide missing find command")
        #expect(text.contains("navigates"), "guide should state find navigates to match")
        #expect(text.contains("the foundText"), "guide missing foundText")
        #expect(text.contains("the foundChunk"), "guide missing foundChunk")
        #expect(text.contains("the foundField"), "guide missing foundField")
        #expect(text.contains("the foundLine"), "guide missing foundLine")
        #expect(text.contains("select word"), "guide missing select command")
        #expect(text.contains("the selectedText"), "guide missing selectedText")
        #expect(text.contains("the selectedChunk"), "guide missing selectedChunk")
        #expect(text.contains("the clickH"), "guide missing clickH")
        #expect(text.contains("the clickLoc"), "guide missing clickLoc")
        #expect(text.contains("the menus"), "guide missing the menus")
        #expect(text.contains("the destination"), "guide missing the destination")

        // Phase 3: host commands (lock screen, doMenu, open/save/close/print)
        #expect(text.contains("lock screen"), "guide missing lock screen")
        #expect(text.contains("unlock screen"), "guide missing unlock screen")
        #expect(text.contains("doMenu"), "guide missing doMenu")
        #expect(text.contains("doMenu \"Next Card\""), "guide missing doMenu menu-item example")
        #expect(text.contains("doMenu \"Revert\""), "guide missing doMenu AppKit menu example")
        #expect(text.contains("open stack"), "guide missing open stack")
        #expect(text.contains("Host commands"), "guide missing Host commands section")

        // Phase 4: do eval, file I/O
        #expect(text.contains("do \"put 1 + 1"), "guide missing do eval example")
        #expect(text.contains("read from file"), "guide missing read from file")
        #expect(text.contains("write"), "guide missing write to file")
        #expect(text.contains("fileAccessAllowed"), "guide missing fileAccessAllowed gate note")

        // Phase 5: import/export paint, video transport
        #expect(text.contains("import paint"), "guide missing import paint")
        #expect(text.contains("export paint"), "guide missing export paint")
        #expect(text.contains("the currentTime"), "guide missing currentTime getter")
        #expect(text.contains("the playRate"), "guide missing playRate getter")
        #expect(text.contains("the duration of video"), "guide missing video duration")

        // Negative: old stub table rows for now-real commands must be gone
        #expect(!text.contains("Does NOT highlight / scroll / locate"),
                "guide still has stale stub claim for find")
        #expect(!text.contains("No selection happens; field text is unaffected"),
                "guide still has stale stub claim for select")
        #expect(!text.contains("No-op (parsed but not evaluated)"),
                "guide still has stale stub claim for do")
        #expect(!text.contains("| `push card`, `pop card` | No-op"),
                "guide still has stale stub claim for push/pop card")
        #expect(!text.contains("Always return `\"\"`"),
                "guide still has stale stub claim for found-*/selected-* getters")
        // Negative: old stale AVOID bullets must be gone
        #expect(!text.contains("is a no-op. Inline the code directly"),
                "guide still has stale do-is-no-op AVOID bullet")
        #expect(!text.contains("both are stubs"),
                "guide still has stale find-is-stub AVOID bullet")
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
