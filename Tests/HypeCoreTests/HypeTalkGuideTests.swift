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

// MARK: - P4 docs conformance (control-property-consistency Decision 6)
//
// The guide and `HypeTalk-LLM-Context.md` are hand-reconciled against
// `PartPropertyRegistry` rather than mechanically generated (design.md
// task 4.1's "or hand-reconcile" option) — these tests ARE the
// enforcement mock §4 calls for: a two-direction walk between the
// docs and the registry, so drift fails a test the moment it's typed
// instead of silently rotting the AI's property vocabulary again.
@Suite("HypeTalkGuide + HypeTalk-LLM-Context.md — registry docs conformance")
struct HypeTalkGuideRegistryConformanceTests {

    // MARK: - Direction 1: every registry canonical appears in the guide

    /// Every NON-legacy registry canonical property name must appear
    /// (case-insensitively, as a substring) somewhere in the guide —
    /// mock §4 / design.md Decision 6's "every registry-canonical
    /// property appears in the guide" direction. Section placement is
    /// deliberately not asserted (a property may live in the
    /// universal "Part properties" paragraph or a type-scoped
    /// "Framework control properties" bullet) — only that it's
    /// documented SOMEWHERE, so the AI never has to guess a name the
    /// registry actually dispatches.
    @Test("every non-legacy registry canonical property appears in the guide")
    func everyNonLegacyCanonicalAppearsInGuide() {
        let text = HypeTalkGuide.llmContext.lowercased()
        let missing = PartPropertyRegistry.descriptors
            .filter { !$0.legacy }
            .map(\.canonical)
            .filter { !text.contains($0) }
        #expect(missing.isEmpty, "guide is missing registry canonical name(s): \(missing.sorted().joined(separator: ", "))")
    }

    /// Legacy properties (htmlContent, menuItems, family, the 11
    /// classic no-op stubs, …) are deliberately NOT part of the main
    /// vocabulary — but the guide's "Legacy / not exposed to scripts"
    /// note must still NAME every one of them (mock §2.3's "Not
    /// exposed, by decision" note, echoed into the docs surface).
    @Test("every legacy registry canonical is named under the guide's legacy note")
    func everyLegacyCanonicalIsNamed() {
        let text = HypeTalkGuide.llmContext.lowercased()
        let missing = PartPropertyRegistry.descriptors
            .filter(\.legacy)
            .map(\.canonical)
            .filter { !text.contains($0) }
        #expect(missing.isEmpty, "guide's legacy note is missing: \(missing.sorted().joined(separator: ", "))")
    }

    // MARK: - Direction 2: every property name the docs claim resolves through the registry

    /// Every token in the guide's own structured "Part properties"
    /// list must resolve via `PartPropertyRegistry.resolveGet` on at
    /// least one live `PartType` — catches a typo'd or made-up
    /// property name creeping into the prose the moment it's typed.
    /// A minimum count guards against the extractor itself silently
    /// regressing to zero matches (which would make this test
    /// vacuously green).
    @Test("every property token in the guide's Part-properties list resolves through the registry")
    func guideTokensResolveThroughRegistry() {
        let tokens = Self.extractPropertyTokens(from: HypeTalkGuide.llmContext)
        #expect(tokens.count >= 30, "extractor found only \(tokens.count) tokens — check the guide's 'Part properties' line format")
        let unresolved = tokens.filter { !Self.resolvesOnAnyType($0) }
        #expect(unresolved.isEmpty, "guide names that don't resolve on any part type: \(unresolved.joined(separator: ", "))")
    }

    /// Same walk for `HypeTalk-LLM-Context.md`'s part-properties list.
    @Test("every property token in HypeTalk-LLM-Context.md's Part-properties list resolves through the registry")
    func mdTokensResolveThroughRegistry() throws {
        let md = try Self.llmContextMarkdown()
        let tokens = Self.extractPropertyTokens(from: md)
        #expect(tokens.count >= 20, "extractor found only \(tokens.count) tokens — check the .md file's 'Part properties' line format")
        let unresolved = tokens.filter { !Self.resolvesOnAnyType($0) }
        #expect(unresolved.isEmpty, "HypeTalk-LLM-Context.md names that don't resolve on any part type: \(unresolved.joined(separator: ", "))")
    }

    // MARK: - Strict-subset relationship (mock §4)

    /// `HypeTalk-LLM-Context.md`'s part-properties list must never
    /// name a property the guide doesn't also cover — the "strict
    /// subset" relationship mock §4 requires (Decision 6). Checked
    /// against the guide's FULL text (not just its own "Part
    /// properties" bucket) because the guide documents some of these
    /// names in type-scoped "Framework control properties" bullets
    /// instead of the universal paragraph.
    @Test("HypeTalk-LLM-Context.md's Part-properties list is a strict subset of the guide")
    func mdIsStrictSubsetOfGuide() throws {
        let md = try Self.llmContextMarkdown()
        let mdTokens = Self.extractPropertyTokens(from: md)
        let guideText = HypeTalkGuide.llmContext.lowercased()
        let extra = mdTokens.filter { !guideText.contains($0) }
        #expect(extra.isEmpty, "HypeTalk-LLM-Context.md names the guide never documents: \(extra.joined(separator: ", "))")
    }

    // MARK: - Breaking-change notes (Design-Review Condition C4)

    /// Both docs must state the `size` pair breaking change AND the
    /// GET-lenient/SET-strict posture — the Design-Review condition
    /// (C4) that sent this back for a rewrite: prose stating only
    /// "SET is strict" without also stating "GET stays lenient" is
    /// incomplete and misleading about the `the <x> of` read path.
    @Test("both docs state the size-pair breaking change")
    func bothDocsStateSizeBreakingChange() throws {
        let guide = HypeTalkGuide.llmContext
        let md = try Self.llmContextMarkdown()
        for (label, text) in [("guide", guide), ("HypeTalk-LLM-Context.md", md)] {
            #expect(text.contains("use textSize to set the text size"), "\(label) is missing the size/textSize breaking-change copy")
        }
    }

    @Test("both docs state the GET-lenient / SET-strict posture explicitly")
    func bothDocsStateGetSetPosture() throws {
        let guide = HypeTalkGuide.llmContext
        let md = try Self.llmContextMarkdown()
        for (label, text) in [("guide", guide), ("HypeTalk-LLM-Context.md", md)] {
            let lower = text.lowercased()
            #expect(lower.contains("runtime error"), "\(label) doesn't state SET is a runtime error")
            #expect(lower.contains("stays lenient") || lower.contains("stays permissive"),
                    "\(label) doesn't state that GET stays lenient — the Design-Review C4 condition")
            #expect(lower.contains("reads back \"\"") || lower.contains("reads back `\"\"`"),
                    "\(label) doesn't state GET's fully-unknown-name fallback")
        }
    }

    @Test("both docs state the three-field secure-masking set")
    func bothDocsStateSecureMasking() throws {
        let guide = HypeTalkGuide.llmContext
        let md = try Self.llmContextMarkdown()
        for (label, text) in [("guide", guide), ("HypeTalk-LLM-Context.md", md)] {
            let lower = text.lowercased()
            #expect(lower.contains("textcontent") && lower.contains("htmlcontent") && lower.contains("searchtext"),
                    "\(label) doesn't name all three secure-maskable field-body properties")
            #expect(lower.contains("(masked)"), "\(label) doesn't state the \"(masked)\" sentinel")
        }
    }

    // MARK: - Helpers

    private static func packageRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private static func llmContextMarkdown() throws -> String {
        let url = try packageRoot().appendingPathComponent("HypeTalk-LLM-Context.md")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Splits `s` on top-level commas only — commas nested inside
    /// parenthesized alias/format notes (e.g. `rect (alias
    /// "rectangle", "l,t,r,b")`) do NOT split the entry apart.
    private static func topLevelSplit(_ s: Substring, separator: Character = ",") -> [String] {
        var parts: [String] = []
        var depth = 0
        var current = ""
        for ch in s {
            switch ch {
            case "(": depth += 1; current.append(ch)
            case ")": depth -= 1; current.append(ch)
            case separator where depth == 0:
                parts.append(current)
                current = ""
            default:
                current.append(ch)
            }
        }
        parts.append(current)
        return parts
    }

    /// Extracts the property-name tokens out of a `**Part
    /// properties**` (or `**Part properties:**`) structured list line
    /// — the one consistent, machine-parseable format both docs use
    /// for their core property vocabulary. Strips trailing
    /// parenthetical alias/format notes, backticks, and punctuation;
    /// drops any fragment that isn't a bare identifier (multi-word
    /// prose like `shortName / longName` is intentionally dropped
    /// rather than mis-tokenized — coverage for those names comes
    /// from `everyNonLegacyCanonicalAppearsInGuide` instead, which
    /// only requires substring presence).
    private static func extractPropertyTokens(from text: String, keyword: String = "Part properties") -> [String] {
        var tokens: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let keywordRange = line.range(of: keyword) else { continue }
            var depth = 0
            var colonIndex: String.Index?
            var i = keywordRange.lowerBound
            while i < line.endIndex {
                switch line[i] {
                case "(": depth += 1
                case ")": depth -= 1
                case ":" where depth == 0: colonIndex = i
                default: break
                }
                if colonIndex != nil { break }
                i = line.index(after: i)
            }
            guard let colonIndex else { continue }
            let rest = line[line.index(after: colonIndex)...].drop { $0 == "*" || $0 == " " }
            for rawToken in topLevelSplit(rest) {
                var token = rawToken.trimmingCharacters(in: .whitespaces)
                if let parenIndex = token.firstIndex(of: "(") {
                    token = String(token[token.startIndex..<parenIndex]).trimmingCharacters(in: .whitespaces)
                }
                token = token.trimmingCharacters(in: CharacterSet(charactersIn: " .`*"))
                guard !token.isEmpty else { continue }
                guard token.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else { continue }
                tokens.append(token.lowercased())
            }
        }
        return tokens
    }

    /// True when `loweredName` resolves to `.property` via
    /// `PartPropertyRegistry.resolveGet` for at least one live
    /// `PartType` — checked against both the default field style and
    /// `.search`, since a small number of names (`prompt`, `searchText`)
    /// only resolve on a search-styled field.
    private static func resolvesOnAnyType(_ loweredName: String) -> Bool {
        for type in PartType.allCases where type != .unknown {
            var part = Part(partType: type, name: "x")
            if case .property = PartPropertyRegistry.resolveGet(loweredName, for: part) { return true }
            part.fieldStyle = .search
            if case .property = PartPropertyRegistry.resolveGet(loweredName, for: part) { return true }
        }
        return false
    }
}
