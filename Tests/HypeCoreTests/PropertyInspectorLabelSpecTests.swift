import Testing
import Foundation

/// Source-scan conformance tests for `control-property-consistency`
/// P3 — the Properties Inspector's label spec (design-mock.md §2.3,
/// §2.4; acceptance criteria 13–18, 20).
///
/// `PropertyInspector.swift` lives in the `Hype` (AppKit) app target,
/// which is compiled by `swift build` but not executed under
/// `swift test` (AGENTS.md excludes `HypeTests` from headless runs).
/// Design Decision 7 puts this suite here instead: it reads the
/// inspector's SOURCE TEXT (via `#filePath`-relative package-root
/// navigation, the same pattern `AudioKitMusicTests.packageRoot()`
/// uses) and asserts on the literal Swift it finds. That runs
/// headless and still catches a label regression the moment it's
/// typed. Render-level verification — does the row actually *look*
/// right on screen for criteria 19/21 — is the Designer's Sign-off
/// checklist, not this suite; this suite proves the string is there,
/// not that it draws correctly.
@Suite("PropertyInspector label-spec conformance (source scan)")
struct PropertyInspectorLabelSpecTests {

    // MARK: - Source loading

    private static func propertyInspectorSource() throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                let sourceURL = url
                    .appendingPathComponent("Sources")
                    .appendingPathComponent("Hype")
                    .appendingPathComponent("Views")
                    .appendingPathComponent("PropertyInspector.swift")
                return try String(contentsOf: sourceURL, encoding: .utf8)
            }
        }
        throw CocoaError(.fileNoSuchFile)
    }

    /// Count of non-overlapping occurrences of `needle` in `haystack`.
    private static func occurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let range = haystack.range(of: needle, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<haystack.endIndex
        }
        return count
    }

    // MARK: - Criterion 14 — no raw rawValue rendering of the 7 enums

    @Test("PartType never renders via rawValue/.capitalized — headline, Type row, and script-editor window titles all use displayName")
    func partTypeUsesDisplayName() throws {
        let source = try Self.propertyInspectorSource()
        #expect(!source.contains("partType.rawValue.capitalized"))
        // Headline (PI:74), Type row (PI:936), and the two
        // script-editor-window-title sites (resolved `.part` target
        // + the bare-`partId` fallback).
        #expect(Self.occurrences(of: "part.partType.displayName", in: source) >= 4)
    }

    @Test("ButtonStyle / FieldStyle pickers render via displayName, never rawValue")
    func buttonAndFieldStyleUseDisplayName() throws {
        let source = try Self.propertyInspectorSource()
        #expect(!source.contains("Text(style.rawValue).tag(style)"))
        #expect(Self.occurrences(of: "Text(style.displayName).tag(style)", in: source) == 2)
    }

    @Test("ShapeType / SpriteShapeType / ChartType pickers render via displayName, never rawValue")
    func typeEnumPickersUseDisplayName() throws {
        let source = try Self.propertyInspectorSource()
        #expect(!source.contains("Text(type.rawValue).tag(type)"))
        #expect(!source.contains("Text(type.rawValue.capitalized).tag(type)"))
        // ShapeType (shape part), SpriteShapeType (scene shape node), ChartType.
        #expect(Self.occurrences(of: "Text(type.displayName).tag(type)", in: source) == 3)
    }

    @Test("SceneScaleMode picker renders via displayName, never rawValue")
    func sceneScaleModeUsesDisplayName() throws {
        let source = try Self.propertyInspectorSource()
        #expect(!source.contains("Text(mode.rawValue).tag(mode)"))
        #expect(source.contains("Text(mode.displayName).tag(mode)"))
    }

    // MARK: - Criterion 15 — exact §2.3/§2.4 label strings

    @Test("§2.3/§2.4 exact label strings are present at their sites")
    func exactLabelStrings() throws {
        let source = try Self.propertyInspectorSource()
        let required = [
            // Common / field
            "Text(\"Contents\")",
            "propertyRow(\"Selected Segment\"",
            // Progress "Total" retired → "Max"
            "propertyRow(\"Max\", binding: bindPartDoubleString(part.id, \\.progressTotal))",
            // Synth music toggle rename (fixes the Pattern/Tempo double-labeling)
            "Toggle(\"Show Pattern Name\"",
            "Toggle(\"Show Control Type\"",
            "Toggle(\"Show Instrument Popup\"",
            "Toggle(\"Show Tempo\"",
            // Apple Music — row AND picker case both say "Artist"
            "propertyRow(\"Artist\"",
            "case .artist: return \"Artist\"",
            // Chart
            "Toggle(\"Interactive\", isOn: bindChartBool(part.id, \\.interactable",
            // "Text Color" — all four sites (part text formatting,
            // part multi-select, label-node single, label-node multi)
            "colorPropertyRow(label: \"Text Color\", partId: part.id, keyPath: \\.fontColor",
            "multiColorRow(label: \"Text Color\", keyPath: \\.fontColor)",
            "ColorPicker(\"Text Color\", selection: bindNodeColor(partId: partId, nodeId: node.id, getter: { $0.fontColor }",
            "Text(\"Text Color\").font(.system(size: 11))",
            // Physics renames
            "Toggle(\"Affected by Gravity\"",
            "Toggle(\"Allow Rotation\"",
            // Node visibility polarity flip — single node panel + multi node panel
            "Toggle(\"Visible\", isOn: bindNodeVisible(partId: partId, nodeId: node.id))",
            "Toggle(\"Visible\", isOn: Binding(",
            // Scene3D
            "Toggle(\"Auto Lighting\"",
            // PDF
            "Text(\"Display Mode\")",
            // Shape "Style" — part surface AND scene shape-node picker
            "Picker(\"Style\", selection: bindPartShapeType(part.id))",
            "Picker(\"Style\", selection: bindShapeType(partId: partId, nodeId: node.id))",
        ]
        for needle in required {
            #expect(source.contains(needle), "missing required label-spec string: \(needle)")
        }
    }

    // MARK: - §6 — units are appended to the accessibility label (Design Sign-off DS1)

    @Test("§6 units are spoken: propertyRow/numberField route the trailing unit into the accessibility label, and the new video Volume slider is labeled")
    func unitBearingRowsSpeakTheUnit() throws {
        let source = try Self.propertyInspectorSource()
        // Both units-bearing helpers must build their a11y label from the unit,
        // not the bare label (so VoiceOver announces "Span, degrees").
        #expect(Self.occurrences(of: ".accessibilityLabel(unitLabel(label, unit))", in: source) == 2)
        #expect(source.contains("private func spokenUnit")) // spoken-unit map exists
        // The spoken map covers the units actually used in §2.3/§2.4.
        for spoken in ["\"degrees\"", "\"seconds\"", "\"points\"", "\"times\""] {
            #expect(source.contains(spoken), "spokenUnit missing mapping for \(spoken)")
        }
        // The new video Volume slider (a labels-less Slider) carries an explicit label.
        #expect(source.contains(".accessibilityLabel(\"Volume\")"))
    }

    @Test("new §2.3 rows are present: Rotation, Hilite, video playback family, Show User Location, search-style Prompt/Search While Typing, Tracks")
    func newRowsPresent() throws {
        let source = try Self.propertyInspectorSource()
        let required = [
            "numberField(\"Rotation\", binding: bindPartDouble(part.id, \\.rotation), unit: \"\u{b0}\")",
            "Toggle(\"Hilite\", isOn: bindPartBool(part.id, \\.hilite))",
            "Toggle(\"Autoplay\", isOn: bindPartBool(part.id, \\.videoAutoplay))",
            "Toggle(\"Loop\", isOn: bindPartBool(part.id, \\.videoLoop))",
            "bindPartDouble(part.id, \\.videoVolume)",
            "numberField(\"Play Rate\", binding: bindPartDouble(part.id, \\.videoPlayRate), unit: \"\u{d7}\")",
            "Toggle(\"Show User Location\", isOn: bindPartBool(part.id, \\.mapShowsUserLocation))",
            "propertyRow(\"Prompt\", binding: bindPartString(part.id, \\.searchPrompt))",
            "Toggle(\"Search While Typing\", isOn: bindPartBool(part.id, \\.searchSendsImmediately))",
            "propertyRow(\"Tracks\", value: musicTrackCountDescription(part.musicTrackData))",
        ]
        for needle in required {
            #expect(source.contains(needle), "missing new-row string: \(needle)")
        }
    }

    // MARK: - Criterion 16 — no trailing colons on rendered labels

    @Test("no propertyRow/numberField/Toggle/sectionHeading label ends with a trailing colon")
    func noTrailingColons() throws {
        let source = try Self.propertyInspectorSource()
        let violations = Self.rowLabelArguments(in: source).filter { $0.hasSuffix(":") }
        #expect(violations.isEmpty, "trailing-colon labels found: \(violations)")
        // Regression pins for the two rows the design mock calls out
        // by name (design-mock §1.7, fixing PI:1538/1544).
        #expect(!source.contains("\"Stored Audio:\""))
        #expect(!source.contains("\"Duration:\""))
    }

    // MARK: - Criterion 17 — zero hand-rolled section headers remain

    @Test("hand-rolled 9pt bold section headers are gone; sectionHeading() is the only header treatment")
    func noHandRolledHeaders() throws {
        let source = try Self.propertyInspectorSource()
        // The exact font recipe every hand-rolled node/scene header
        // used before migrating to `sectionHeading()`.
        #expect(!source.contains("size: 9, weight: .bold"))
        let removedHeaderLiterals = [
            "Text(\"SPRITE\")", "Text(\"LABEL\")", "Text(\"SHAPE\")", "Text(\"AUDIO\")",
            "Text(\"VIDEO\")", "Text(\"EMITTER\")", "Text(\"PHYSICS\")", "Text(\"CROP\")",
            "Text(\"EFFECT\")", "Text(\"LIGHT\")", "Text(\"POSITION\")",
            "Text(\"Setup Checklist\")", "Text(\"Controls\")", "Text(\"Debug\")",
            "Text(\"Nodes\")", "Text(\"Events\")", "Text(\"Content\")",
        ]
        for literal in removedHeaderLiterals {
            #expect(!source.contains(literal), "hand-rolled header literal should have migrated to sectionHeading(): \(literal)")
        }
        // sectionHeading() itself is the sink for every migrated
        // header. A generous floor (56 call sites incl. the
        // definition at time of writing) proves the migration
        // happened without pinning a brittle exact count.
        #expect(Self.occurrences(of: "sectionHeading(", in: source) >= 45)
    }

    // MARK: - Criterion 18 — units never render as a label parenthetical

    @Test("no rendered row label contains a parenthesized unit — units use the trailing-Text idiom, dates use placeholders")
    func noParenthesizedUnitsInLabels() throws {
        let source = try Self.propertyInspectorSource()
        let removedUnitLiterals = [
            "\"Span (deg)\"", "\"Thickness (pts)\"",
            "\"Selected (yyyy-MM-dd)\"", "\"Selected Time (HH:mm:ss)\"",
            "\"Position Seconds\"", "\"Duration Seconds\"",
        ]
        for literal in removedUnitLiterals {
            #expect(!source.contains(literal), "unit should have moved out of the label: \(literal)")
        }
        let violations = Self.rowLabelArguments(in: source).filter { $0.contains("(") || $0.contains(")") }
        #expect(violations.isEmpty, "parenthesized-unit labels found: \(violations)")
        // The tempo (BPM) idiom (PI:1595-1605) is the canonical unit
        // pattern; the new/changed rows all reuse it via `unit:`.
        #expect(source.contains("unit: \"\u{b0}\""))   // ° — Rotation, Span
        #expect(source.contains("unit: \"\u{d7}\""))   // × — Play Rate
        #expect(source.contains("unit: \"pt\""))        // Divider Thickness
        #expect(source.contains("unit: \"s\""))         // Apple Music Position/Duration
        // Date rows carry their format as a TextField placeholder,
        // never in the label.
        #expect(source.contains("placeholder: \"yyyy-MM-dd\""))
        #expect(source.contains("placeholder: \"HH:mm:ss\""))
        #expect(source.contains("placeholder: \"yyyy-MM\""))
    }

    /// Every string literal passed as the label/title argument to
    /// `propertyRow(`, `numberField(`, `Toggle(`, or `sectionHeading(`
    /// — the four call sites the design mock's label table governs.
    private static func rowLabelArguments(in source: String) -> [String] {
        let pattern = #"(?:propertyRow|numberField|Toggle|sectionHeading)\(\s*"([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(source.startIndex..., in: source)
        var labels: [String] = []
        regex.enumerateMatches(in: source, range: range) { match, _, _ in
            guard let match, let labelRange = Range(match.range(at: 1), in: source) else { return }
            labels.append(String(source[labelRange]))
        }
        return labels
    }

    // MARK: - Criterion 20 — accessibility labels on labels-hidden controls

    @Test("every labels-hidden Picker/ColorPicker with an empty visible title has a nearby accessibilityLabel")
    func accessibilityLabelsOnLabelsHiddenControls() throws {
        let source = try Self.propertyInspectorSource()
        var searchStart = source.startIndex
        var uncoveredLines: [Int] = []
        var emptyTitledCount = 0

        while let hiddenRange = source.range(of: ".labelsHidden()", range: searchStart..<source.endIndex) {
            searchStart = hiddenRange.upperBound

            // Find the nearest preceding `Picker("` / `ColorPicker("`
            // opener — a plain substring search, so it works
            // regardless of how many lines the picker's option body
            // spans (some pickers list a dozen-plus static options).
            guard let openerRange = source.range(
                of: "Picker(\"",
                options: .backwards,
                range: source.startIndex..<hiddenRange.lowerBound
            ) else { continue }

            // Empty title: the character right after the opening
            // quote is the closing quote, i.e. `Picker("",`.
            let afterOpenQuote = openerRange.upperBound
            guard afterOpenQuote < source.endIndex, source[afterOpenQuote] == "\"" else { continue }
            emptyTitledCount += 1

            // Walk the contiguous fluent modifier chain starting at
            // `.labelsHidden()` (every subsequent non-blank line
            // begins with `.` until the chain ends) looking for
            // `.accessibilityLabel(`.
            let windowEnd = source.index(hiddenRange.upperBound, offsetBy: 400, limitedBy: source.endIndex) ?? source.endIndex
            let window = source[hiddenRange.lowerBound..<windowEnd]
            var covered = false
            for line in window.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { continue }
                if trimmed.contains("accessibilityLabel(") { covered = true; break }
                if !trimmed.hasPrefix(".") { break }
            }
            if !covered {
                let lineNumber = source[..<hiddenRange.lowerBound].reduce(into: 1) { count, ch in if ch == "\n" { count += 1 } }
                uncoveredLines.append(lineNumber)
            }
        }

        #expect(uncoveredLines.isEmpty, "empty-titled labels-hidden controls missing accessibilityLabel at (1-based) source lines: \(uncoveredLines)")
        // A floor on how many empty-titled controls this scan found
        // at all — guards against the regex/backward-search itself
        // silently matching nothing and the test passing vacuously.
        #expect(emptyTitledCount >= 15)
    }
}
