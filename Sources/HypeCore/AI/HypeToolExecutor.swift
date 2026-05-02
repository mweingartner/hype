import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Executes AI tool calls against a HypeDocument.
public struct HypeToolExecutor: Sendable {

    // MARK: - Web-asset dependencies (all optional; nil = feature not wired)

    /// The per-chat-panel web-asset session. Holds candidate cache and per-turn soft cap.
    public let webAssetSession: WebAssetSession?
    /// The active web-asset search client for the selected provider.
    public let webAssetClient: (any WebAssetSearchClient)?
    /// The download + validation pipeline.
    public let webAssetPipeline: WebAssetImportPipeline?

    // MARK: - Initializers

    /// Zero-arg initializer that keeps ALL existing call sites source-compatible.
    /// Web-asset features are disabled when called this way.
    public init() {
        self.webAssetSession = nil
        self.webAssetClient = nil
        self.webAssetPipeline = nil
    }

    /// Full initializer with web-asset dependencies wired in.
    ///
    /// - Parameters:
    ///   - webAssetSession: A `WebAssetSession` actor for candidate caching and soft-cap tracking.
    ///   - webAssetClient:  A `WebAssetSearchClient` for the active provider.
    ///   - webAssetPipeline: A `WebAssetImportPipeline` for download + validation.
    public init(
        webAssetSession: WebAssetSession?,
        webAssetClient: (any WebAssetSearchClient)?,
        webAssetPipeline: WebAssetImportPipeline?
    ) {
        self.webAssetSession = webAssetSession
        self.webAssetClient = webAssetClient
        self.webAssetPipeline = webAssetPipeline
    }

    /// Heuristic: does the given asset name contain a substring
    /// commonly used in tile-set art assets? Used by the import
    /// paths (AI tool + SpriteRepositoryView) to default newly
    /// imported images to `.tileSet` when the filename strongly
    /// suggests it. Safe to be approximate — the user can always
    /// toggle kind manually in the repository browser's detail
    /// panel.
    ///
    /// `public` so `SpriteRepositoryView` in the Hype target can
    /// share the same heuristic without reimplementing it.
    public static func filenameLooksLikeTileset(_ name: String) -> Bool {
        let lower = name.lowercased()
        // Matches "tileset", "tile_set", "tiles", "tilemap" and
        // common prefixes/suffixes like "grass_tileset" or
        // "dungeon-tiles". Matching is substring-based so
        // "tile" alone wouldn't count — that's too loose.
        let keywords = ["tileset", "tile_set", "tile-set", "tilemap", "tilesheet", "tiles"]
        return keywords.contains { lower.contains($0) }
    }

    /// Determine whether to place on card or background based on arguments.
    private func placement(arguments: [String: String], currentCardId: UUID, document: HypeDocument) -> (cardId: UUID?, backgroundId: UUID?) {
        let onBg = (arguments["on_background"] ?? "").lowercased() == "true"
        if onBg {
            let bgId = document.cards.first(where: { $0.id == currentCardId })?.backgroundId
            return (cardId: nil, backgroundId: bgId)
        }
        return (cardId: currentCardId, backgroundId: nil)
    }

    private func boolArgument(_ value: String?) -> Bool? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else { return nil }
        switch raw {
        case "true", "yes", "1", "on": return true
        case "false", "no", "0", "off": return false
        default: return nil
        }
    }

    private func applyFieldStylingArguments(_ arguments: [String: String], to part: inout Part) {
        if let style = arguments["style"], let fs = FieldStyle(rawValue: style) {
            part.fieldStyle = fs
        }
        if let fillColor = arguments["fill_color"] {
            part.fillColor = fillColor
        }
        if let strokeColor = arguments["stroke_color"] {
            part.strokeColor = strokeColor
        }
        if let strokeWidth = arguments["stroke_width"], let value = Double(strokeWidth) {
            part.strokeWidth = value
        }
        if let textFont = arguments["text_font"] ?? arguments["font"], !textFont.isEmpty {
            part.textFont = textFont
        }
        if let textSize = arguments["text_size"] ?? arguments["size"], let value = Double(textSize) {
            part.textSize = value
        }
        if let align = arguments["text_align"] ?? arguments["align"],
           let textAlign = TextAlignment(rawValue: align.lowercased()) {
            part.textAlign = textAlign
        }
        if let locked = boolArgument(arguments["lock_text"]) {
            part.lockText = locked
        }
        if let showName = boolArgument(arguments["show_name"]) {
            part.showName = showName
        }

        // If the model asks for a border but omits style, choose the
        // field style that actually renders as an input box.
        if arguments["style"] == nil,
           (arguments["stroke_color"] != nil || arguments["stroke_width"] != nil) {
            part.fieldStyle = .rectangle
        }
    }

    private func sanitizedPartName(prefix: String, source: String, fallback: String) -> String {
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = source.isEmpty ? fallback : source
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_- "))
        let cleaned = String(base.unicodeScalars.map { allowed.contains($0) ? Character($0) : Character("_") })
            .replacingOccurrences(of: " ", with: "_")
            .lowercased()
        return "\(prefix)_\(cleaned)"
    }

    private func uniquePartName(_ seed: String, in document: HypeDocument) -> String {
        let trimmed = seed.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "part" : trimmed
        if !document.parts.contains(where: { $0.name.lowercased() == base.lowercased() }) {
            return base
        }
        var suffix = 2
        while document.parts.contains(where: { $0.name.lowercased() == "\(base)_\(suffix)".lowercased() }) {
            suffix += 1
        }
        return "\(base)_\(suffix)"
    }

    private func repairFormControls(
        arguments: [String: String],
        document: inout HypeDocument,
        currentCardId: UUID
    ) -> String {
        let requestedName = arguments["sprite_area_name"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let visibleAreas = document.effectivePartsForCard(currentCardId)
            .filter { $0.partType == .spriteArea }
        let candidate = visibleAreas.first { area in
            guard requestedName.isEmpty || area.name.lowercased() == requestedName else { return false }
            return area.activeSceneSpec?.allNodes.contains(where: { $0.nodeType == .label }) == true
        }

        guard let area = candidate,
              let areaIndex = document.parts.firstIndex(where: { $0.id == area.id }),
              let scene = area.activeSceneSpec else {
            return requestedName.isEmpty
                ? "No form-like Sprite Area with label nodes found on the current card"
                : "Sprite Area '\(requestedName)' with label nodes not found on the current card"
        }

        let labelNodes = scene.allNodes.filter { node in
            guard node.nodeType == .label, !node.isHidden else { return false }
            let text = (node.text ?? node.name).trimmingCharacters(in: .whitespacesAndNewlines)
            return !text.isEmpty
        }
        guard !labelNodes.isEmpty else {
            return "Sprite Area '\(area.name)' has no visible label nodes to convert"
        }

        var createdLabels = 0
        for node in labelNodes {
            let text = (node.text ?? node.name).trimmingCharacters(in: .whitespacesAndNewlines)
            let fontSize = node.fontSize ?? 14
            let width = node.size?.width ?? max(60, min(area.width, Double(text.count) * fontSize * 0.62 + 16))
            let height = node.size?.height ?? max(22, fontSize * 1.55)
            let left = area.left + node.position.x - width / 2
            let top = area.top + node.position.y - height / 2

            let duplicateExists = document.effectivePartsForCard(currentCardId).contains { part in
                guard part.partType == .field else { return false }
                return part.textContent == text
                    && abs(part.left - left) < 2
                    && abs(part.top - top) < 2
            }
            if duplicateExists { continue }

            var label = Part(
                partType: .field,
                cardId: area.cardId,
                backgroundId: area.backgroundId,
                name: uniquePartName(
                    sanitizedPartName(prefix: "label", source: node.name, fallback: text),
                    in: document
                ),
                left: max(0, left),
                top: max(0, top),
                width: width,
                height: height
            )
            label.textContent = text
            label.fieldStyle = .transparent
            label.lockText = true
            label.showName = false
            label.strokeWidth = 0
            if let fontName = node.fontName, !fontName.isEmpty {
                label.textFont = fontName
            } else if !document.stack.defaultFont.isEmpty {
                label.textFont = document.stack.defaultFont
            }
            label.textSize = fontSize
            label.textAlign = .center
            document.addPart(label)
            createdLabels += 1
        }

        let nonLabelNodes = scene.allNodes.filter { $0.nodeType != .label && $0.nodeType != .group }
        let hasSceneOrPartScript = !area.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !scene.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if nonLabelNodes.isEmpty && !hasSceneOrPartScript {
            document.removePart(id: area.id)
            return "Converted \(createdLabels) SpriteKit label node(s) from '\(area.name)' into locked field labels and removed the unused Sprite Area"
        }

        let labelIds = Set(labelNodes.map(\.id))
        document.parts[areaIndex].updateActiveSceneSpec { spec in
            for id in labelIds {
                _ = spec.removeNode(id: id)
            }
        }
        let keepReason = hasSceneOrPartScript
            ? "it has a script"
            : "it still contains non-label nodes"
        return "Converted \(createdLabels) SpriteKit label node(s) from '\(area.name)' into locked field labels and left the Sprite Area because \(keepReason)"
    }

    /// Auto-wrap a script in `on mouseUp`/`end mouseUp` if it's not already wrapped in a handler.
    private func wrapScript(_ script: String) -> String {
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        // Already wrapped in a handler block?
        let lower = trimmed.lowercased()
        if lower.hasPrefix("on ") || lower.hasPrefix("function ") {
            return trimmed
        }
        // Wrap bare commands in on mouseUp
        return "on mouseUp\n  \(trimmed)\nend mouseUp"
    }

    /// Parse-validate a HypeTalk script and return the parser's
    /// user-readable error text when it doesn't compile. Returns
    /// nil when the script is valid or empty.
    private func scriptParseErrorMessage(_ script: String) -> String? {
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var lexer = Lexer(source: script)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        do {
            _ = try parser.parse()
            return nil
        } catch let error as ParseError {
            return error.errorDescription ?? String(describing: error)
        } catch {
            return error.localizedDescription
        }
    }

    /// Parse-validate a HypeTalk script and return a user-readable
    /// error suffix (starting with "; parse error: ...") if the
    /// script doesn't compile. Returns an empty string when the
    /// script is valid or empty.
    private func scriptParseErrorSuffix(_ script: String) -> String {
        guard let message = scriptParseErrorMessage(script) else { return "" }
        return "; parse error in script: \(message)"
    }

    /// Apply a single property override to a theme. Property names are
    /// case-insensitive HypeTheme field names (`accent`, `cardBackground`,
    /// `defaultFontFamily`, etc.). Returns true on a recognized property,
    /// false otherwise. Keep the switch explicit — no reflection magic —
    /// so the AI's possible inputs are documented at this site.
    private func applyThemeFieldOverride(
        _ theme: inout HypeTheme,
        key: String,
        value: String
    ) -> Bool {
        let k = key.lowercased().replacingOccurrences(of: "_", with: "")
        let parsedColor = ColorRef.parse(value)
        switch k {
        // Surface colors
        case "cardbackground":      theme.cardBackground = parsedColor
        case "cardforeground":      theme.cardForeground = parsedColor
        case "backgroundfill":      theme.backgroundFill = parsedColor
        case "canvasmargin":        theme.canvasMargin = parsedColor
        // Part defaults
        case "buttonbackground":    theme.buttonBackground = parsedColor
        case "buttonforeground":    theme.buttonForeground = parsedColor
        case "buttonborder":        theme.buttonBorder = parsedColor
        case "buttonhilite":        theme.buttonHilite = parsedColor
        case "fieldbackground":     theme.fieldBackground = parsedColor
        case "fieldforeground":     theme.fieldForeground = parsedColor
        case "fieldborder":         theme.fieldBorder = parsedColor
        case "shapefilldefault":    theme.shapeFillDefault = parsedColor
        case "shapestrokedefault":  theme.shapeStrokeDefault = parsedColor
        // Accent + selection
        case "accent":              theme.accent = parsedColor
        case "selectionfill":       theme.selectionFill = parsedColor
        case "selectionstroke":     theme.selectionStroke = parsedColor
        // Chrome
        case "toolbarbackground":   theme.toolbarBackground = parsedColor
        case "inspectorbackground": theme.inspectorBackground = parsedColor
        case "paneldivider":        theme.panelDivider = parsedColor
        // Typography (strings)
        case "defaultfontfamily":   theme.defaultFontFamily = value
        case "headingfontfamily":   theme.headingFontFamily = value
        case "monospacefontfamily": theme.monospaceFontFamily = value
        case "defaultfontsize":     if let n = Double(value) { theme.defaultFontSize = n }
        case "headingfontsize":     if let n = Double(value) { theme.headingFontSize = n }
        case "labelfontsize":       if let n = Double(value) { theme.labelFontSize = n }
        // Structure
        case "cornerradiussmall":   if let n = Double(value) { theme.cornerRadiusSmall = n }
        case "cornerradiusmedium":  if let n = Double(value) { theme.cornerRadiusMedium = n }
        case "cornerradiuslarge":   if let n = Double(value) { theme.cornerRadiusLarge = n }
        case "spacingunit":         if let n = Double(value) { theme.spacingUnit = n }
        case "strokewidththin":     if let n = Double(value) { theme.strokeWidthThin = n }
        case "strokewidthmedium":   if let n = Double(value) { theme.strokeWidthMedium = n }
        case "shadowopacity":       if let n = Double(value) { theme.shadowOpacity = n }
        case "shadowradius":        if let n = Double(value) { theme.shadowRadius = n }
        // Theme metadata (rename via this path is allowed for user themes)
        case "name":                theme.name = value
        default:
            return false
        }
        return true
    }

    /// Best-effort wrong-language detector for AI-written scripts.
    ///
    /// The parser is intentionally permissive and can accept some
    /// JavaScript-like text once it has been auto-wrapped in a
    /// handler. We therefore reject a small set of unambiguously
    /// foreign tokens before relying on parse validation alone.
    private func nonHypeTalkScriptMessage(
        rawScript: String,
        wrappedScript: String
    ) -> String? {
        let hardSignals: [String] = [
            "hype.",
            "self.", "this.",
            "function(", "function (",
            "=>",
            "skphysicsbody", "sknode", "skaction", "skspritenode", "sklabelnode",
            "skshapenode", "skscene", "skfield",
            "childnodewithname(",
            "enumeratechildrenwithnodepattern(",
            "document.", "window.",
            "addeventlistener",
            "console.log(",
            "@objc", "nonisolated",
        ]

        func firstHardSignal(in script: String) -> String? {
            let lower = script.lowercased()
            return hardSignals.first(where: { lower.contains($0) })
        }

        if let signal = firstHardSignal(in: rawScript) ?? firstHardSignal(in: wrappedScript) {
            return "script contains non-HypeTalk token '\(signal)'"
        }
        if SceneAuthoringAssistant.looksLikeNonHypeTalkScript(rawScript) {
            return "script looks like JavaScript / Swift rather than HypeTalk"
        }
        return nil
    }

    /// Reject invalid AI-authored scripts before they mutate the
    /// document. This keeps malformed JavaScript-like output from
    /// being stored as if it were valid HypeTalk.
    ///
    /// - Returns: A `ScriptDraftRefusal` when the draft is invalid; `nil` when
    ///   the draft passes all validation stages and may be committed.
    ///
    /// The returned refusal can be encoded as a sentinel tool-result string
    /// (`refusal.encodedSentinel()`) so the `AIChatPanel`'s iteration loop
    /// can classify, surface, and retry it automatically.
    private func refusalForInvalidDraft(
        toolName: String,
        arguments: [String: String],
        targetDescription: String,
        rawScript: String,
        wrappedScript: String,
        document: HypeDocument,
        currentCardId: UUID
    ) -> ScriptDraftRefusal? {
        // Size cap check: oversized drafts are always refused, even if they parse.
        // The ScriptDraftRefusal init adds the truncation failure and logs the event.
        //
        // Both `rawScript` and `wrappedScript` are bounded here (NOT just `rawScript`)
        // so a wrap that pushes a borderline-sized script over the cap can't slip
        // an oversized payload into the parser. Use `>=` (not `>`) so the boundary
        // value triggers truncation — matches `ScriptDraftRefusal.init`'s clamp.
        if rawScript.count >= ScriptDraftRefusal.scriptSizeCap
            || wrappedScript.count >= ScriptDraftRefusal.scriptSizeCap
        {
            return ScriptDraftRefusal(
                toolName: toolName,
                originalArguments: arguments,
                targetDescription: targetDescription,
                rawScript: rawScript,
                wrappedScript: wrappedScript,
                failures: []  // ScriptDraftRefusal init appends the forbiddenPattern failure on truncation.
            )
        }

        let context = ScriptDraftContext(
            targetDescription: targetDescription,
            document: document,
            currentCardId: currentCardId
        )
        let result = HypeTalkScriptValidator().validate(
            rawScript: rawScript,
            wrappedScript: wrappedScript,
            context: context
        )
        switch result {
        case .passed:
            return nil
        case .failed(let reasons):
            return ScriptDraftRefusal(
                toolName: toolName,
                originalArguments: arguments,
                targetDescription: targetDescription,
                rawScript: rawScript,
                wrappedScript: wrappedScript,
                failures: reasons
            )
        }
    }

    // Legacy helper kept for use by `checkScriptResponse(...)` (the `check_script`
    // tool surface). Do NOT remove — `checkScriptResponse` calls this to build its
    // FAIL: message. The host gate uses `refusalForInvalidDraft` instead.
    private func invalidScriptStorageMessage(
        targetDescription: String,
        rawScript: String,
        wrappedScript: String
    ) -> String? {
        if let message = nonHypeTalkScriptMessage(rawScript: rawScript, wrappedScript: wrappedScript) {
            return "Refused to store invalid script for \(targetDescription): \(message). Call check_script first."
        }
        guard let message = scriptParseErrorMessage(wrappedScript) else { return nil }
        return "Refused to store invalid script for \(targetDescription): \(message). Call check_script first."
    }

    /// Response body for the `check_script` tool call. Returns a
    /// clear OK / FAIL string the AI can pattern-match on to decide
    /// whether to iterate.
    ///
    /// Empty scripts are treated as a soft fail ("nothing to check")
    /// so the AI doesn't slip through an accidentally blank script.
    /// Bare command scripts are auto-wrapped in `on mouseUp ... end
    /// mouseUp` (matching what `create_button` does) before parsing,
    /// so a validator call on `"go next"` passes just like the
    /// stored form would.
    func checkScriptResponse(_ script: String) -> String {
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "EMPTY: check_script received an empty script. Nothing to validate — pass the HypeTalk source you intend to store."
        }
        // Auto-wrap bare commands the same way the storage tools do,
        // so the AI can validate either a full handler block or a
        // one-liner like "go next" and get the same answer either way.
        let wrapped = wrapScript(script)
        if let message = nonHypeTalkScriptMessage(rawScript: script, wrappedScript: wrapped) {
            return "FAIL: \(message). Rewrite it in HypeTalk and call check_script again."
        }
        var lexer = Lexer(source: wrapped)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        do {
            let parsed = try parser.parse()
            let n = parsed.handlers.count
            let plural = n == 1 ? "handler" : "handlers"
            let handlerNames = parsed.handlers.map { "'\($0.name)'" }.joined(separator: ", ")
            if n == 0 {
                return "OK: script parsed, but it contains no handler blocks. If you meant to attach a one-liner to a button, create_button auto-wraps it in 'on mouseUp ... end mouseUp'."
            }
            return "OK: \(n) \(plural) parsed (\(handlerNames)). Script is ready to store."
        } catch let error as ParseError {
            let description = error.errorDescription ?? String(describing: error)
            return "FAIL: \(description). Fix the script and call check_script again."
        } catch {
            return "FAIL: \(error.localizedDescription). Fix the script and call check_script again."
        }
    }

    /// Build a comprehensive description of a part including all relevant properties.
    private func describePartFull(_ p: Part) -> String {
        var props: [String] = []
        let layer = p.backgroundId != nil ? " (background)" : ""
        props.append("[\(p.partType.rawValue)] '\(p.name)'\(layer) at (\(Int(p.left)),\(Int(p.top))) \(Int(p.width))x\(Int(p.height))")

        // State
        if !p.visible { props.append("visible=false") }
        if !p.enabled { props.append("enabled=false") }

        // Type-specific properties
        switch p.partType {
        case .button:
            props.append("style=\(p.buttonStyle.rawValue)")
            if p.hilite { props.append("hilite=true") }
            if !p.showName { props.append("showName=false") }
            if !p.popupItems.isEmpty { props.append("popupItems=\"\(p.popupItems.replacingOccurrences(of: "\n", with: "|"))\"") }
            if !p.textContent.isEmpty { props.append("text=\"\(p.textContent)\"") }
        case .field:
            props.append("style=\(p.fieldStyle.rawValue)")
            if !p.textContent.isEmpty {
                let preview = String(p.textContent.prefix(100))
                props.append("text=\"\(preview)\(p.textContent.count > 100 ? "..." : "")\"")
            }
            if p.lockText { props.append("lockText=true") }
            if p.enterKeyEnabled { props.append("enterKeyEnabled=true") }
        case .shape:
            props.append("shapeType=\(p.shapeType.rawValue)")
            if !p.fillColor.isEmpty { props.append("fillColor=\(p.fillColor)") }
            if !p.strokeColor.isEmpty { props.append("strokeColor=\(p.strokeColor)") }
            if p.strokeWidth != 1 { props.append("strokeWidth=\(p.strokeWidth)") }
            if p.cornerRadius != 8 { props.append("cornerRadius=\(p.cornerRadius)") }
        case .webpage:
            props.append("url=\"\(p.url)\"")
        case .video:
            props.append("videoURL=\"\(p.videoURL)\"")
        case .image:
            props.append("hasImage=\(p.imageData != nil)")
            if p.invertOnClick { props.append("invertOnClick=true") }
            if p.transparentBackground { props.append("transparentBackground=true") }
        case .chart:
            if let config = ChartConfig.fromJSON(p.chartData) {
                props.append("chartType=\(config.chartType.rawValue)")
                if !config.title.isEmpty { props.append("chartTitle=\"\(config.title)\"") }
                if !config.xAxisLabel.isEmpty { props.append("xAxisLabel=\"\(config.xAxisLabel)\"") }
                if !config.yAxisLabel.isEmpty { props.append("yAxisLabel=\"\(config.yAxisLabel)\"") }
                props.append("showLegend=\(config.showLegend)")
                props.append("showGrid=\(config.showGrid)")
                for series in config.series {
                    let dataDesc = series.data.map { "\($0.name)=\($0.value)" }.joined(separator: ",")
                    props.append("series '\(series.name)' color=\(series.color) data=[\(dataDesc)]")
                }
            }
        case .spriteArea:
            if let areaSpec = p.spriteAreaSpecModel,
               let sceneConfig = areaSpec.activeScene {
                props.append("sceneName=\(sceneConfig.name)")
                props.append("sceneCount=\(areaSpec.scenes.count)")
                props.append("sceneSize=\(Int(sceneConfig.size.width))x\(Int(sceneConfig.size.height))")
                props.append("nodeCount=\(sceneConfig.nodes.count)")
            }
        case .calendar:
            if !p.selectedDate.isEmpty { props.append("selectedDate=\(p.selectedDate)") }
            if !p.displayMonth.isEmpty { props.append("displayMonth=\(p.displayMonth)") }
            if !p.minDate.isEmpty { props.append("minDate=\(p.minDate)") }
            if !p.maxDate.isEmpty { props.append("maxDate=\(p.maxDate)") }
            props.append("calendarStyle=\(p.calendarStyle)")
        case .pdf:
            if !p.pdfURL.isEmpty { props.append("pdfURL=\(p.pdfURL)") }
            props.append("pdfCurrentPage=\(p.pdfCurrentPage)")
            props.append("pdfDisplayMode=\(p.pdfDisplayMode)")
        case .map:
            props.append(String(format: "center=%.4f,%.4f", p.mapCenterLat, p.mapCenterLon))
            props.append(String(format: "span=%.4f", p.mapSpan))
            props.append("mapType=\(p.mapType)")
            if !p.mapAnnotationsJSON.isEmpty {
                if let data = p.mapAnnotationsJSON.data(using: .utf8),
                   let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    props.append("annotations=\(arr.count)")
                }
            }
        case .colorWell:
            props.append("colorHex=\(p.colorWellHex)")
            if !p.colorWellInteractive { props.append("interactive=false") }
        case .stepper, .slider:
            props.append("value=\(p.controlValue)")
            props.append("min=\(p.controlMin)")
            props.append("max=\(p.controlMax)")
            if p.partType == .stepper { props.append("step=\(p.controlStep)") }
        case .toggle:
            props.append("on=\(p.controlValue >= 0.5)")
        case .segmented:
            props.append("segments=\(p.segmentItems)")
            props.append("selectedSegment=\(Int(p.controlValue))")
        case .audioRecorder:
            props.append("recording=\(p.audioRecording)")
            props.append(String(format: "duration=%.1f", p.audioDuration))
            if !p.audioOutputPath.isEmpty { props.append("outputPath=\(p.audioOutputPath)") }
            props.append("format=\(p.audioFormat)")
        case .scene3D:
            if !p.scene3DURL.isEmpty { props.append("modelURL=\(p.scene3DURL)") }
            if !p.scene3DAllowsCameraControl { props.append("allowsCameraControl=false") }
            if !p.scene3DAutoLighting { props.append("autoLighting=false") }
            if !p.scene3DBackground.isEmpty { props.append("background=\(p.scene3DBackground)") }
            props.append("antialiasing=\(p.scene3DAntialiasing)")
        }

        // Common text styling (if non-default)
        if p.textFont != "System" && !p.textFont.isEmpty { props.append("font=\(p.textFont)") }
        if p.textSize != 14 && p.textSize != 0 { props.append("textSize=\(p.textSize)") }
        if p.textAlign != .left { props.append("textAlign=\(p.textAlign.rawValue)") }
        if p.textStyle != "plain" && !p.textStyle.isEmpty { props.append("textStyle=\(p.textStyle)") }

        // Script
        if !p.script.isEmpty {
            let scriptPreview = String(p.script.prefix(80))
            props.append("script=\"\(scriptPreview)\(p.script.count > 80 ? "..." : "")\"")
        }

        return props.joined(separator: ", ")
    }

    private func cardIndex(
        named cardName: String,
        currentCardId: UUID,
        in document: HypeDocument
    ) -> Int? {
        let trimmed = cardName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return document.cards.firstIndex(where: { $0.id == currentCardId })
        }
        return document.cards.firstIndex(where: { $0.name.lowercased() == trimmed.lowercased() })
    }

    private func backgroundIndex(
        named backgroundName: String,
        currentCardId: UUID,
        in document: HypeDocument
    ) -> Int? {
        let trimmed = backgroundName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            guard let card = document.cards.first(where: { $0.id == currentCardId }) else { return nil }
            return document.backgrounds.firstIndex(where: { $0.id == card.backgroundId })
        }
        return document.backgrounds.firstIndex(where: { $0.name.lowercased() == trimmed.lowercased() })
    }

    private func scopedPartIndex(
        named partName: String,
        currentCardId: UUID,
        in document: HypeDocument,
        partType: PartType? = nil
    ) -> Int? {
        let trimmed = partName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()

        func matches(_ part: Part) -> Bool {
            guard part.name.lowercased() == lower else { return false }
            if let partType {
                return part.partType == partType
            }
            return true
        }

        let cardParts = document.partsForCard(currentCardId)
        for part in cardParts where matches(part) {
            if let idx = document.parts.firstIndex(where: { $0.id == part.id }) {
                return idx
            }
        }

        if let card = document.cards.first(where: { $0.id == currentCardId }) {
            let backgroundParts = document.partsForBackground(card.backgroundId)
            for part in backgroundParts where matches(part) {
                if let idx = document.parts.firstIndex(where: { $0.id == part.id }) {
                    return idx
                }
            }
        }

        let globalMatches = document.parts.indices.filter { matches(document.parts[$0]) }
        if globalMatches.count == 1 {
            return globalMatches[0]
        }
        return nil
    }

    private func spriteAreaIndex(
        named areaName: String,
        currentCardId: UUID,
        in document: HypeDocument
    ) -> Int? {
        scopedPartIndex(
            named: areaName,
            currentCardId: currentCardId,
            in: document,
            partType: .spriteArea
        )
    }

    @discardableResult
    private func modifyActiveScene(
        partIndex: Int,
        document: inout HypeDocument,
        transform: (inout SceneSpec) -> Void
    ) -> Bool {
        guard document.parts.indices.contains(partIndex) else { return false }
        var part = document.parts[partIndex]
        part.updateActiveSceneSpec(transform)
        document.parts[partIndex] = part
        return true
    }

    @discardableResult
    private func modifySpriteAreaSpec(
        partIndex: Int,
        document: inout HypeDocument,
        transform: (inout SpriteAreaSpec) -> Void
    ) -> Bool {
        guard document.parts.indices.contains(partIndex) else { return false }
        var part = document.parts[partIndex]
        part.updateSpriteAreaSpec(transform)
        document.parts[partIndex] = part
        return true
    }

    /// Execute a tool call and return the result string.
    ///
    /// ## Tool result string contract
    /// - `"__HYPE_INTERNAL_DRAFT_REFUSED_v1:<json>"` — host gate refused a script draft;
    ///   `AIChatPanel` iterates via `ScriptDraftCoordinator`.
    /// - `"__HYPE_INTERNAL_CAPTURE_v1:<json>"` — `AIChatPanel` decodes and injects the image
    ///   as a synthetic user message; budget consumption is enforced by the chat panel BEFORE
    ///   this executor branch runs.
    /// - `"CREATED_CARD:<uuid>"` — caller updates `currentCardId`.
    /// - `"NAVIGATE:<dest>"` — caller resolves and updates `currentCardId`.
    /// - Any other string — success or read-only result; surface as-is.
    public func execute(
        toolName: String,
        arguments: [String: String],
        document: inout HypeDocument,
        currentCardId: UUID
    ) async -> String {
        switch toolName {
        case "create_card":
            let bgName = arguments["background_name"]
            let card = document.addCard(
                afterIndex: document.sortedCards.firstIndex(where: { $0.id == currentCardId }),
                backgroundName: bgName
            )
            return "CREATED_CARD:\(card.id)"

        case "create_background":
            let name = arguments["name"] ?? "New Background"
            let bg = document.addBackground(name: name)
            return "Created background '\(bg.name)'"

        case "go_to_card":
            let dest = arguments["destination"] ?? "next"
            // Resolve numeric card references to support "go to card 4" etc.
            if let num = Int(dest), num > 0, num <= document.sortedCards.count {
                let card = document.sortedCards[num - 1]
                return "NAVIGATE:\(card.name.isEmpty ? String(num) : card.name)"
            }
            // Return the destination for the caller to handle navigation
            return "NAVIGATE:\(dest)"

        case "delete_card":
            return "Card deletion requires user confirmation"

        case "create_button":
            let place = placement(arguments: arguments, currentCardId: currentCardId, document: document)
            var part = Part(
                partType: .button,
                cardId: place.cardId,
                backgroundId: place.backgroundId,
                name: arguments["name"] ?? "Button",
                left: Double(arguments["left"] ?? "100") ?? 100,
                top: Double(arguments["top"] ?? "100") ?? 100,
                width: Double(arguments["width"] ?? "120") ?? 120,
                height: Double(arguments["height"] ?? "40") ?? 40
            )
            // Apply stack-level default font
            let stackFont = document.stack.defaultFont
            if !stackFont.isEmpty { part.textFont = stackFont }
            if let style = arguments["style"], let bs = ButtonStyle(rawValue: style) {
                part.buttonStyle = bs
            }
            if let script = arguments["script"] {
                let wrapped = wrapScript(script)
                if let refusal = refusalForInvalidDraft(
                    toolName: toolName,
                    arguments: arguments,
                    targetDescription: "button '\(part.name)'",
                    rawScript: script,
                    wrappedScript: wrapped,
                    document: document,
                    currentCardId: currentCardId
                ) {
                    // Refuse outright — do NOT add the part to the document.
                    return refusal.encodedSentinel()
                }
                part.script = wrapped
            }
            document.addPart(part)
            let layer = place.backgroundId != nil ? " on background" : ""
            return "Created button '\(part.name)'\(layer)"

        case "create_field":
            let place = placement(arguments: arguments, currentCardId: currentCardId, document: document)
            var part = Part(
                partType: .field,
                cardId: place.cardId,
                backgroundId: place.backgroundId,
                name: arguments["name"] ?? "Field",
                left: Double(arguments["left"] ?? "100") ?? 100,
                top: Double(arguments["top"] ?? "100") ?? 100,
                width: Double(arguments["width"] ?? "200") ?? 200,
                height: Double(arguments["height"] ?? "30") ?? 30
            )
            // Apply stack-level default font
            let stackFont = document.stack.defaultFont
            if !stackFont.isEmpty { part.textFont = stackFont }
            if let text = arguments["text"] { part.textContent = text }
            applyFieldStylingArguments(arguments, to: &part)
            if let script = arguments["script"] {
                let wrapped = wrapScript(script)
                if let refusal = refusalForInvalidDraft(
                    toolName: toolName,
                    arguments: arguments,
                    targetDescription: "field '\(part.name)'",
                    rawScript: script,
                    wrappedScript: wrapped,
                    document: document,
                    currentCardId: currentCardId
                ) {
                    // Refuse outright — do NOT add the part to the document.
                    return refusal.encodedSentinel()
                }
                part.script = wrapped
            }
            document.addPart(part)
            let layer = place.backgroundId != nil ? " on background" : ""
            return "Created field '\(part.name)'\(layer)"

        case "create_label":
            let place = placement(arguments: arguments, currentCardId: currentCardId, document: document)
            var part = Part(
                partType: .field,
                cardId: place.cardId,
                backgroundId: place.backgroundId,
                name: arguments["name"] ?? "Label",
                left: Double(arguments["left"] ?? "100") ?? 100,
                top: Double(arguments["top"] ?? "100") ?? 100,
                width: Double(arguments["width"] ?? "160") ?? 160,
                height: Double(arguments["height"] ?? "24") ?? 24
            )
            let stackFont = document.stack.defaultFont
            if !stackFont.isEmpty { part.textFont = stackFont }
            part.textContent = arguments["text"] ?? part.name
            part.fieldStyle = .transparent
            part.lockText = true
            part.showName = false
            part.strokeWidth = 0
            if let textFont = arguments["text_font"], !textFont.isEmpty {
                part.textFont = textFont
            }
            if let textSize = arguments["text_size"], let value = Double(textSize) {
                part.textSize = value
            }
            if let align = arguments["text_align"],
               let textAlign = TextAlignment(rawValue: align.lowercased()) {
                part.textAlign = textAlign
            }
            document.addPart(part)
            let layer = place.backgroundId != nil ? " on background" : ""
            return "Created label '\(part.name)'\(layer)"

        case "create_shape":
            let place = placement(arguments: arguments, currentCardId: currentCardId, document: document)
            var part = Part(
                partType: .shape,
                cardId: place.cardId,
                backgroundId: place.backgroundId,
                name: arguments["name"] ?? "Shape",
                left: Double(arguments["left"] ?? "100") ?? 100,
                top: Double(arguments["top"] ?? "100") ?? 100,
                width: Double(arguments["width"] ?? "100") ?? 100,
                height: Double(arguments["height"] ?? "100") ?? 100
            )
            if let st = arguments["shape_type"], let shapeType = ShapeType(rawValue: st) {
                part.shapeType = shapeType
            }
            if let fc = arguments["fill_color"] { part.fillColor = fc }
            if let sc = arguments["stroke_color"] { part.strokeColor = sc }
            if let sw = arguments["stroke_width"] { part.strokeWidth = Double(sw) ?? 1 }
            document.addPart(part)
            let shapeLayer = place.backgroundId != nil ? " on background" : ""
            return "Created shape '\(part.name)'\(shapeLayer)"

        case "create_webpage":
            let place = placement(arguments: arguments, currentCardId: currentCardId, document: document)
            var part = Part(
                partType: .webpage,
                cardId: place.cardId,
                backgroundId: place.backgroundId,
                name: arguments["name"] ?? "Webpage",
                left: Double(arguments["left"] ?? "100") ?? 100,
                top: Double(arguments["top"] ?? "100") ?? 100,
                width: Double(arguments["width"] ?? "400") ?? 400,
                height: Double(arguments["height"] ?? "300") ?? 300
            )
            part.url = arguments["url"] ?? "http://"
            document.addPart(part)
            let webLayer = place.backgroundId != nil ? " on background" : ""
            return "Created webpage '\(part.name)' with URL \(part.url)\(webLayer)"

        case "create_video":
            let place = placement(arguments: arguments, currentCardId: currentCardId, document: document)
            var part = Part(
                partType: .video,
                cardId: place.cardId,
                backgroundId: place.backgroundId,
                name: arguments["name"] ?? "Video",
                left: Double(arguments["left"] ?? "100") ?? 100,
                top: Double(arguments["top"] ?? "100") ?? 100,
                width: Double(arguments["width"] ?? "400") ?? 400,
                height: Double(arguments["height"] ?? "300") ?? 300
            )
            part.videoURL = arguments["video_url"] ?? ""
            document.addPart(part)
            let videoLayer = place.backgroundId != nil ? " on background" : ""
            return "Created video '\(part.name)' with URL \(part.videoURL)\(videoLayer)"

        case "create_chart":
            let place = placement(arguments: arguments, currentCardId: currentCardId, document: document)
            var part = Part(
                partType: .chart,
                cardId: place.cardId,
                backgroundId: place.backgroundId,
                name: arguments["name"] ?? "Chart",
                left: Double(arguments["left"] ?? "100") ?? 100,
                top: Double(arguments["top"] ?? "100") ?? 100,
                width: Double(arguments["width"] ?? "300") ?? 300,
                height: Double(arguments["height"] ?? "200") ?? 200
            )
            let chartType = ChartType(rawValue: arguments["chart_type"] ?? "bar") ?? .bar
            // Default-initialise ChartConfig (showLegend/showGrid both true)
            // then override each field if the AI supplied it. The x/y axis
            // labels are a named chart part (title + series) that the
            // ChartHostView renders with sensible fallbacks, but we still
            // let the caller set them explicitly here — that ensures a
            // chart created for a specific domain (e.g. "Month" / "Sales")
            // gets the right labels at create time instead of depending
            // on a follow-up set_part_property call.
            var config = ChartConfig(chartType: chartType, title: arguments["title"] ?? "")
            if let xl = arguments["x_axis_label"] { config.xAxisLabel = xl }
            if let yl = arguments["y_axis_label"] { config.yAxisLabel = yl }
            if let sl = arguments["show_legend"] {
                config.showLegend = (sl.lowercased() == "true")
            }
            if let sg = arguments["show_grid"] {
                config.showGrid = (sg.lowercased() == "true")
            }
            // Parse data points from multiple formats
            var dataPoints: [ChartDataPoint] = []

            if let dataJSON = arguments["data_json"], !dataJSON.isEmpty {
                if let jsonData = dataJSON.data(using: .utf8) {
                    // Try array of {"name":"X","value":123,"color":"#hex"} (also accepts legacy "label" key)
                    if let rawPoints = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
                        for raw in rawPoints {
                            let name = raw["name"] as? String ?? raw["label"] as? String ?? ""
                            let value: Double
                            if let v = raw["value"] as? Double { value = v }
                            else if let v = raw["value"] as? Int { value = Double(v) }
                            else if let v = raw["value"] as? String { value = Double(v) ?? 0 }
                            else { value = 0 }
                            let color = raw["color"] as? String ?? ""
                            dataPoints.append(ChartDataPoint(name: name, value: value, color: color))
                        }
                    }
                }
            }

            // Also try simple "data" parameter: "Jan=120,Feb=150,Mar=180"
            if dataPoints.isEmpty, let simpleData = arguments["data"], !simpleData.isEmpty {
                let pairs = simpleData.split(separator: ",")
                for pair in pairs {
                    let parts = pair.split(separator: "=", maxSplits: 1)
                    if parts.count == 2 {
                        let name = parts[0].trimmingCharacters(in: .whitespaces)
                        let value = Double(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
                        dataPoints.append(ChartDataPoint(name: name, value: value))
                    }
                }
            }

            let seriesName = arguments["series_name"] ?? "Series 1"
            let seriesColor = arguments["series_color"] ?? "#4A90D9"
            // Always create a series (even empty) so the chart has structure
            config.series.append(ChartSeries(name: seriesName, color: seriesColor, data: dataPoints))
            part.chartData = config.toJSON()
            document.addPart(part)
            let chartLayer = place.backgroundId != nil ? " on background" : ""
            return "Created chart '\(part.name)' (\(chartType.rawValue))\(chartLayer)"

        case "create_pdf":
            let place = placement(arguments: arguments, currentCardId: currentCardId, document: document)
            var part = Part(
                partType: .pdf,
                cardId: place.cardId,
                backgroundId: place.backgroundId,
                name: arguments["name"] ?? "PDF",
                left: Double(arguments["left"] ?? "100") ?? 100,
                top: Double(arguments["top"] ?? "100") ?? 100,
                width: Double(arguments["width"] ?? "400") ?? 400,
                height: Double(arguments["height"] ?? "500") ?? 500
            )
            part.pdfURL = arguments["pdfurl"] ?? ""
            part.pdfCurrentPage = Int(arguments["current_page"] ?? "1") ?? 1
            let mode = (arguments["display_mode"] ?? "continuous").lowercased()
            switch mode {
            case "single", "continuous", "twoup", "twoupcontinuous":
                part.pdfDisplayMode = mode == "twoup" ? "twoUp" : (mode == "twoupcontinuous" ? "twoUpContinuous" : mode)
            default:
                part.pdfDisplayMode = "continuous"
            }
            if let auto = arguments["auto_scales"] {
                part.pdfAutoScales = (auto.lowercased() == "true")
            }
            document.addPart(part)
            let layer = place.backgroundId != nil ? " on background" : ""
            return "Created pdf '\(part.name)'\(layer)"

        case "create_map":
            let place = placement(arguments: arguments, currentCardId: currentCardId, document: document)
            var part = Part(
                partType: .map,
                cardId: place.cardId,
                backgroundId: place.backgroundId,
                name: arguments["name"] ?? "Map",
                left: Double(arguments["left"] ?? "100") ?? 100,
                top: Double(arguments["top"] ?? "100") ?? 100,
                width: Double(arguments["width"] ?? "400") ?? 400,
                height: Double(arguments["height"] ?? "300") ?? 300
            )
            if let lat = arguments["center_lat"], let v = Double(lat) { part.mapCenterLat = v }
            if let lon = arguments["center_lon"], let v = Double(lon) { part.mapCenterLon = v }
            if let span = arguments["span"], let v = Double(span) { part.mapSpan = v }
            let kind = (arguments["map_type"] ?? "standard").lowercased()
            switch kind {
            case "standard", "satellite", "hybrid", "mutedstandard":
                part.mapType = kind == "mutedstandard" ? "mutedStandard" : kind
            default:
                part.mapType = "standard"
            }
            document.addPart(part)
            let layer = place.backgroundId != nil ? " on background" : ""
            return "Created map '\(part.name)'\(layer)"

        case "add_map_annotation":
            let mapName = arguments["map_name"] ?? ""
            guard let idx = scopedPartIndex(named: mapName, currentCardId: currentCardId, in: document),
                  document.parts[idx].partType == .map else {
                return "Map '\(mapName)' not found"
            }
            guard let lat = Double(arguments["lat"] ?? ""), let lon = Double(arguments["lon"] ?? "") else {
                return "Invalid lat/lon for annotation"
            }
            let title = arguments["title"] ?? ""
            // Append to the existing JSON array; tolerate empty/malformed input.
            var existing: [[String: Any]] = []
            let raw = document.parts[idx].mapAnnotationsJSON
            if !raw.isEmpty,
               let data = raw.data(using: .utf8),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                existing = arr
            }
            existing.append(["lat": lat, "lon": lon, "title": title])
            if let updated = try? JSONSerialization.data(withJSONObject: existing),
               let json = String(data: updated, encoding: .utf8) {
                document.parts[idx].mapAnnotationsJSON = json
            }
            return "Added annotation to map '\(mapName)' (\(existing.count) total)"

        case "clear_map_annotations":
            let mapName = arguments["map_name"] ?? ""
            guard let idx = scopedPartIndex(named: mapName, currentCardId: currentCardId, in: document),
                  document.parts[idx].partType == .map else {
                return "Map '\(mapName)' not found"
            }
            document.parts[idx].mapAnnotationsJSON = ""
            return "Cleared annotations on map '\(mapName)'"

        case "create_color_well":
            let place = placement(arguments: arguments, currentCardId: currentCardId, document: document)
            var part = Part(
                partType: .colorWell,
                cardId: place.cardId,
                backgroundId: place.backgroundId,
                name: arguments["name"] ?? "ColorWell",
                left: Double(arguments["left"] ?? "100") ?? 100,
                top: Double(arguments["top"] ?? "100") ?? 100,
                width: Double(arguments["width"] ?? "60") ?? 60,
                height: Double(arguments["height"] ?? "30") ?? 30
            )
            part.colorWellHex = arguments["color"] ?? "#FF5500"
            if let interactive = arguments["interactive"] {
                part.colorWellInteractive = (interactive.lowercased() == "true")
            }
            document.addPart(part)
            let layer = place.backgroundId != nil ? " on background" : ""
            return "Created colorWell '\(part.name)'\(layer)"

        case "create_stepper":
            let place = placement(arguments: arguments, currentCardId: currentCardId, document: document)
            var part = Part(
                partType: .stepper,
                cardId: place.cardId,
                backgroundId: place.backgroundId,
                name: arguments["name"] ?? "Stepper",
                left: Double(arguments["left"] ?? "100") ?? 100,
                top: Double(arguments["top"] ?? "100") ?? 100,
                width: Double(arguments["width"] ?? "70") ?? 70,
                height: Double(arguments["height"] ?? "24") ?? 24
            )
            part.controlValue = Double(arguments["value"] ?? "0") ?? 0
            part.controlMin = Double(arguments["min"] ?? "0") ?? 0
            part.controlMax = Double(arguments["max"] ?? "100") ?? 100
            part.controlStep = Double(arguments["step"] ?? "1") ?? 1
            document.addPart(part)
            let layer = place.backgroundId != nil ? " on background" : ""
            return "Created stepper '\(part.name)'\(layer)"

        case "create_slider":
            let place = placement(arguments: arguments, currentCardId: currentCardId, document: document)
            var part = Part(
                partType: .slider,
                cardId: place.cardId,
                backgroundId: place.backgroundId,
                name: arguments["name"] ?? "Slider",
                left: Double(arguments["left"] ?? "100") ?? 100,
                top: Double(arguments["top"] ?? "100") ?? 100,
                width: Double(arguments["width"] ?? "200") ?? 200,
                height: Double(arguments["height"] ?? "24") ?? 24
            )
            part.controlValue = Double(arguments["value"] ?? "0") ?? 0
            part.controlMin = Double(arguments["min"] ?? "0") ?? 0
            part.controlMax = Double(arguments["max"] ?? "100") ?? 100
            document.addPart(part)
            let layer = place.backgroundId != nil ? " on background" : ""
            return "Created slider '\(part.name)'\(layer)"

        case "create_toggle":
            let place = placement(arguments: arguments, currentCardId: currentCardId, document: document)
            var part = Part(
                partType: .toggle,
                cardId: place.cardId,
                backgroundId: place.backgroundId,
                name: arguments["name"] ?? "Toggle",
                left: Double(arguments["left"] ?? "100") ?? 100,
                top: Double(arguments["top"] ?? "100") ?? 100,
                width: Double(arguments["width"] ?? "44") ?? 44,
                height: Double(arguments["height"] ?? "26") ?? 26
            )
            let on = (arguments["on"] ?? "false").lowercased() == "true"
            part.controlValue = on ? 1 : 0
            document.addPart(part)
            let layer = place.backgroundId != nil ? " on background" : ""
            return "Created toggle '\(part.name)'\(layer)"

        case "create_scene3d":
            let place = placement(arguments: arguments, currentCardId: currentCardId, document: document)
            var part = Part(
                partType: .scene3D,
                cardId: place.cardId,
                backgroundId: place.backgroundId,
                name: arguments["name"] ?? "Scene3D",
                left: Double(arguments["left"] ?? "100") ?? 100,
                top: Double(arguments["top"] ?? "100") ?? 100,
                width: Double(arguments["width"] ?? "400") ?? 400,
                height: Double(arguments["height"] ?? "300") ?? 300
            )
            part.scene3DURL = arguments["model_url"] ?? ""
            if let camera = arguments["allows_camera_control"] {
                part.scene3DAllowsCameraControl = (camera.lowercased() == "true")
            }
            if let lighting = arguments["auto_lighting"] {
                part.scene3DAutoLighting = (lighting.lowercased() == "true")
            }
            part.scene3DBackground = arguments["background"] ?? ""
            let aa = (arguments["antialiasing"] ?? "multisampling4X")
            switch aa.lowercased() {
            case "none": part.scene3DAntialiasing = "none"
            case "multisampling2x": part.scene3DAntialiasing = "multisampling2X"
            case "multisampling4x": part.scene3DAntialiasing = "multisampling4X"
            case "multisampling8x": part.scene3DAntialiasing = "multisampling8X"
            default: part.scene3DAntialiasing = "multisampling4X"
            }
            document.addPart(part)
            let layer = place.backgroundId != nil ? " on background" : ""
            return "Created scene3D '\(part.name)'\(layer)"

        case "create_audio_recorder":
            let place = placement(arguments: arguments, currentCardId: currentCardId, document: document)
            var part = Part(
                partType: .audioRecorder,
                cardId: place.cardId,
                backgroundId: place.backgroundId,
                name: arguments["name"] ?? "Recorder",
                left: Double(arguments["left"] ?? "100") ?? 100,
                top: Double(arguments["top"] ?? "100") ?? 100,
                width: Double(arguments["width"] ?? "180") ?? 180,
                height: Double(arguments["height"] ?? "44") ?? 44
            )
            let fmt = (arguments["format"] ?? "m4a").lowercased()
            part.audioFormat = (fmt == "caf") ? "caf" : "m4a"
            part.audioOutputPath = arguments["output_path"] ?? ""
            document.addPart(part)
            let layer = place.backgroundId != nil ? " on background" : ""
            return "Created audio recorder '\(part.name)'\(layer)"

        case "create_segmented":
            let place = placement(arguments: arguments, currentCardId: currentCardId, document: document)
            var part = Part(
                partType: .segmented,
                cardId: place.cardId,
                backgroundId: place.backgroundId,
                name: arguments["name"] ?? "Segmented",
                left: Double(arguments["left"] ?? "100") ?? 100,
                top: Double(arguments["top"] ?? "100") ?? 100,
                width: Double(arguments["width"] ?? "240") ?? 240,
                height: Double(arguments["height"] ?? "26") ?? 26
            )
            part.segmentItems = (arguments["segments"] ?? "First|Second|Third")
            part.controlValue = Double(arguments["selected_segment"] ?? "0") ?? 0
            document.addPart(part)
            let layer = place.backgroundId != nil ? " on background" : ""
            return "Created segmented '\(part.name)'\(layer)"

        case "create_calendar":
            let place = placement(arguments: arguments, currentCardId: currentCardId, document: document)
            var part = Part(
                partType: .calendar,
                cardId: place.cardId,
                backgroundId: place.backgroundId,
                name: arguments["name"] ?? "Calendar",
                left: Double(arguments["left"] ?? "100") ?? 100,
                top: Double(arguments["top"] ?? "100") ?? 100,
                width: Double(arguments["width"] ?? "260") ?? 260,
                height: Double(arguments["height"] ?? "180") ?? 180
            )
            part.selectedDate = arguments["selected_date"] ?? ""
            part.displayMonth = arguments["display_month"] ?? ""
            part.minDate = arguments["min_date"] ?? ""
            part.maxDate = arguments["max_date"] ?? ""
            let style = (arguments["style"] ?? "graphical").lowercased()
            // Whitelist styles to keep the live picker happy.
            switch style {
            case "graphical", "textual", "clockandcalendar":
                part.calendarStyle = style == "clockandcalendar" ? "clockAndCalendar" : style
            default:
                part.calendarStyle = "graphical"
            }
            document.addPart(part)
            let layer = place.backgroundId != nil ? " on background" : ""
            return "Created calendar '\(part.name)'\(layer)"

        case "repair_form_controls":
            return repairFormControls(
                arguments: arguments,
                document: &document,
                currentCardId: currentCardId
            )

        case "set_part_property":
            let partName = arguments["part_name"] ?? ""
            let property = arguments["property"] ?? ""
            let value = arguments["value"] ?? ""
            if let index = scopedPartIndex(named: partName, currentCardId: currentCardId, in: document) {
                switch property.lowercased() {
                case "name": document.parts[index].name = value
                case "left": document.parts[index].left = Double(value) ?? 0
                case "top": document.parts[index].top = Double(value) ?? 0
                case "width": document.parts[index].width = Double(value) ?? 100
                case "height": document.parts[index].height = Double(value) ?? 40
                case "text", "textcontent": document.parts[index].textContent = value
                case "url": document.parts[index].url = value
                case "videourl", "video_url": document.parts[index].videoURL = value
                case "fillcolor", "fill_color": document.parts[index].fillColor = value
                case "strokecolor", "stroke_color": document.parts[index].strokeColor = value
                case "visible": document.parts[index].visible = (value.lowercased() == "true")
                case "enabled": document.parts[index].enabled = (value.lowercased() == "true")
                // Calendar-specific properties — settable on calendar parts only.
                case "selecteddate", "selected_date": document.parts[index].selectedDate = value
                case "displaymonth", "display_month": document.parts[index].displayMonth = value
                case "mindate", "min_date": document.parts[index].minDate = value
                case "maxdate", "max_date": document.parts[index].maxDate = value
                case "calendarstyle", "calendar_style", "style": document.parts[index].calendarStyle = value
                // PDF-specific
                case "pdfurl", "pdf_url": document.parts[index].pdfURL = value
                case "currentpage", "current_page": document.parts[index].pdfCurrentPage = Int(value) ?? 1
                case "displaymode", "display_mode": document.parts[index].pdfDisplayMode = value
                case "autoscales", "auto_scales": document.parts[index].pdfAutoScales = (value.lowercased() == "true")
                // Map-specific
                case "centerlat", "center_lat": document.parts[index].mapCenterLat = Double(value) ?? 0
                case "centerlon", "center_lon": document.parts[index].mapCenterLon = Double(value) ?? 0
                case "span": document.parts[index].mapSpan = Double(value) ?? 0.05
                case "maptype", "map_type": document.parts[index].mapType = value
                case "annotations": document.parts[index].mapAnnotationsJSON = value
                // ColorWell-specific
                case "color", "colorhex", "color_hex": document.parts[index].colorWellHex = value
                case "interactive": document.parts[index].colorWellInteractive = (value.lowercased() == "true")
                // Form controls (stepper / slider / toggle / segmented).
                case "value":
                    if document.parts[index].partType == .toggle {
                        document.parts[index].controlValue = (value.lowercased() == "true") ? 1 : 0
                    } else {
                        document.parts[index].controlValue = Double(value) ?? 0
                    }
                case "on": document.parts[index].controlValue = (value.lowercased() == "true") ? 1 : 0
                case "min", "minvalue", "min_value": document.parts[index].controlMin = Double(value) ?? 0
                case "max", "maxvalue", "max_value": document.parts[index].controlMax = Double(value) ?? 100
                case "step", "increment": document.parts[index].controlStep = Double(value) ?? 1
                case "segments", "segmentitems", "segment_items": document.parts[index].segmentItems = value
                case "selectedsegment", "selected_segment": document.parts[index].controlValue = Double(value) ?? 0
                // AudioRecorder
                case "recording": document.parts[index].audioRecording = (value.lowercased() == "true")
                case "outputpath", "output_path", "filepath", "file_path": document.parts[index].audioOutputPath = value
                case "format": document.parts[index].audioFormat = value
                // Scene3D
                case "modelurl", "model_url", "sceneurl", "scene_url": document.parts[index].scene3DURL = value
                case "allowscameracontrol", "allows_camera_control", "cameracontrol": document.parts[index].scene3DAllowsCameraControl = (value.lowercased() == "true")
                case "autolighting", "auto_lighting", "defaultlighting": document.parts[index].scene3DAutoLighting = (value.lowercased() == "true")
                case "antialiasing", "anti_aliasing": document.parts[index].scene3DAntialiasing = value
                case "background3d", "background_3d", "scenebackground": document.parts[index].scene3DBackground = value
                case "script":
                    // Wrap bare commands and validate via the host gate
                    // before mutating the document.
                    let wrapped = wrapScript(value)
                    if let refusal = refusalForInvalidDraft(
                        toolName: toolName,
                        arguments: arguments,
                        targetDescription: "part '\(partName)'",
                        rawScript: value,
                        wrappedScript: wrapped,
                        document: document,
                        currentCardId: currentCardId
                    ) {
                        return refusal.encodedSentinel()
                    }

                    // Sprite-area parts: the user-visible script
                    // lives on the ACTIVE SCENE, not on the part
                    // itself. The Script Editor title "bounder / main"
                    // is [spriteAreaName] / [sceneName], and edits
                    // there flow into SceneSpec.script. The part-
                    // level script is a rarely-used fallback in the
                    // dispatch chain. When the AI calls this with a
                    // sprite-area target, write to the scene so the
                    // result shows up where the user will see it
                    // and where frameUpdate / mouseDown / etc.
                    // actually run. Otherwise scripts land on a
                    // storage slot that's effectively invisible and
                    // the user reasonably thinks "nothing happened."
                    if document.parts[index].partType == .spriteArea {
                        var wroteToScene = false
                        var sceneName = "main"
                        modifySpriteAreaSpec(partIndex: index, document: &document) { areaSpec in
                            guard let entry = areaSpec.activeSceneEntry,
                                  let sceneIdx = areaSpec.scenes.firstIndex(where: { $0.id == entry.id })
                            else { return }
                            areaSpec.scenes[sceneIdx].scene.script = wrapped
                            areaSpec.setActiveScene(areaSpec.scenes[sceneIdx].scene)
                            sceneName = areaSpec.scenes[sceneIdx].scene.name
                            wroteToScene = true
                        }
                        if wroteToScene {
                            return "Set script of scene '\(sceneName)' in sprite area '\(partName)' (routed to the scene — this is the script shown in the \(partName)/\(sceneName) Script Editor)"
                        }
                        // No active scene — fall through to part-level script below.
                    }
                    document.parts[index].script = wrapped
                case "style":
                    let part = document.parts[index]
                    switch part.partType {
                    case .button:
                        if let bs = ButtonStyle(rawValue: value) {
                            document.parts[index].buttonStyle = bs
                        } else {
                            let valid = ButtonStyle.allCases.map(\.rawValue).joined(separator: ", ")
                            return "Invalid button style '\(value)'. Valid: \(valid)"
                        }
                    case .field:
                        if let fs = FieldStyle(rawValue: value) {
                            document.parts[index].fieldStyle = fs
                        } else {
                            let valid = FieldStyle.allCases.map(\.rawValue).joined(separator: ", ")
                            return "Invalid field style '\(value)'. Valid: \(valid)"
                        }
                    case .shape:
                        if let st = ShapeType(rawValue: value) {
                            document.parts[index].shapeType = st
                        } else {
                            let valid = ShapeType.allCases.map(\.rawValue).joined(separator: ", ")
                            return "Invalid shape type '\(value)'. Valid: \(valid)"
                        }
                    default:
                        return "Part type '\(part.partType.rawValue)' does not support style property"
                    }
                case "hilite": document.parts[index].hilite = (value.lowercased() == "true")
                case "autohilite": document.parts[index].autoHilite = (value.lowercased() == "true")
                case "showname": document.parts[index].showName = (value.lowercased() == "true")
                case "locktext": document.parts[index].lockText = (value.lowercased() == "true")
                case "transparentbackground", "transparent_background", "transparent",
                     "transparentbg", "alpha":
                    // Image / GIF chroma-key flag — see ImageRenderer
                    // and ImageChromaKey for the masking algorithm.
                    document.parts[index].transparentBackground = (value.lowercased() == "true")
                case "textfont", "font": document.parts[index].textFont = value
                case "textsize", "size": document.parts[index].textSize = Double(value) ?? 14
                case "textalign": document.parts[index].textAlign = TextAlignment(rawValue: value.lowercased()) ?? .left
                case "textstyle": document.parts[index].textStyle = value
                case "strokewidth": document.parts[index].strokeWidth = Double(value) ?? 1
                case "cornerradius": document.parts[index].cornerRadius = Double(value) ?? 8
                case "chartdata", "chart_data":
                    document.parts[index].chartData = value
                case "charttype", "chart_type":
                    var config = ChartConfig.fromJSON(document.parts[index].chartData) ?? ChartConfig()
                    config.chartType = ChartType(rawValue: value) ?? .bar
                    document.parts[index].chartData = config.toJSON()
                case "charttitle", "chart_title":
                    var config = ChartConfig.fromJSON(document.parts[index].chartData) ?? ChartConfig()
                    config.title = value
                    document.parts[index].chartData = config.toJSON()
                case "xaxislabel", "x_axis_label", "xlabel", "x_label":
                    var config = ChartConfig.fromJSON(document.parts[index].chartData) ?? ChartConfig()
                    config.xAxisLabel = value
                    document.parts[index].chartData = config.toJSON()
                case "yaxislabel", "y_axis_label", "ylabel", "y_label":
                    var config = ChartConfig.fromJSON(document.parts[index].chartData) ?? ChartConfig()
                    config.yAxisLabel = value
                    document.parts[index].chartData = config.toJSON()
                case "showlegend", "show_legend":
                    var config = ChartConfig.fromJSON(document.parts[index].chartData) ?? ChartConfig()
                    config.showLegend = (value.lowercased() == "true")
                    document.parts[index].chartData = config.toJSON()
                case "showgrid", "show_grid":
                    var config = ChartConfig.fromJSON(document.parts[index].chartData) ?? ChartConfig()
                    config.showGrid = (value.lowercased() == "true")
                    document.parts[index].chartData = config.toJSON()
                default: return "Unknown property '\(property)'"
                }
                return "Set \(property) of '\(partName)' to '\(value)'"
            }
            return "Part '\(partName)' not found"

        case "delete_part":
            let partName = arguments["part_name"] ?? ""
            if let index = scopedPartIndex(named: partName, currentCardId: currentCardId, in: document) {
                document.removePart(id: document.parts[index].id)
                return "Deleted part '\(partName)'"
            }
            return "Part '\(partName)' not found"

        case "check_script":
            // Standalone syntax checker the AI is instructed to call
            // BEFORE storing any script. This complements the
            // `scriptParseErrorSuffix` that already runs on
            // create_button / create_field / set_part_property — the
            // AI should use `check_script` first so it never even
            // reaches the storage call with broken code. The tool
            // wraps bare command scripts the same way the storage
            // tools do, so a one-liner like "go next" validates as
            // though it were attached to a button.
            let rawScript = arguments["script"] ?? ""
            return checkScriptResponse(rawScript)

        case "set_chart_data_point_color":
            // Structured setter for per-data-point colors on a chart.
            // Complements the HypeTalk `set the color of data point N of
            // series N of chart "X" to "#RRGGBB"` surface — the AI can
            // use whichever path fits the tool-calling style.
            let chartName = arguments["chart_name"] ?? ""
            let seriesRef = arguments["series"] ?? "1"
            let pointRef = arguments["point"] ?? ""
            let color = arguments["color"] ?? ""
            guard !chartName.isEmpty, !pointRef.isEmpty, !color.isEmpty else {
                return "set_chart_data_point_color requires chart_name, point, and color"
            }
            guard let partIndex = scopedPartIndex(
                named: chartName,
                currentCardId: currentCardId,
                in: document,
                partType: .chart
            ) else {
                return "Chart '\(chartName)' not found"
            }
            guard var config = ChartConfig.fromJSON(document.parts[partIndex].chartData) else {
                return "Chart '\(chartName)' has no data"
            }
            // Resolve series by 1-based index or name.
            let seriesIdx: Int
            if let num = Int(seriesRef), num > 0, num <= config.series.count {
                seriesIdx = num - 1
            } else if let idx = config.series.firstIndex(where: {
                $0.name.lowercased() == seriesRef.lowercased()
            }) {
                seriesIdx = idx
            } else {
                return "Series '\(seriesRef)' not found in chart '\(chartName)'"
            }
            // Resolve point by 1-based index or name.
            let pointIdx: Int
            if let num = Int(pointRef), num > 0, num <= config.series[seriesIdx].data.count {
                pointIdx = num - 1
            } else if let idx = config.series[seriesIdx].data.firstIndex(where: {
                $0.name.lowercased() == pointRef.lowercased()
            }) {
                pointIdx = idx
            } else {
                return "Data point '\(pointRef)' not found in series '\(config.series[seriesIdx].name)'"
            }
            config.series[seriesIdx].data[pointIdx].color = color
            document.parts[partIndex].chartData = config.toJSON()
            let pointName = config.series[seriesIdx].data[pointIdx].name
            return "Set color of '\(pointName)' in chart '\(chartName)' to \(color)"

        case "get_chart_data_points":
            // Read-side companion: dump the series + per-point names,
            // values, and effective colors for a chart. Useful after
            // set_chart_data_point_color for the AI to verify its edit.
            let chartName = arguments["chart_name"] ?? ""
            guard let partIndex = scopedPartIndex(
                named: chartName,
                currentCardId: currentCardId,
                in: document,
                partType: .chart
            ) else {
                return "Chart '\(chartName)' not found"
            }
            let part = document.parts[partIndex]
            guard let config = ChartConfig.fromJSON(part.chartData) else {
                return "Chart '\(chartName)' has no data"
            }
            if config.series.isEmpty { return "Chart '\(chartName)' has no series" }
            var lines: [String] = ["Chart '\(chartName)' (\(config.chartType.rawValue)):"]
            for (sidx, series) in config.series.enumerated() {
                lines.append("  Series \(sidx + 1) '\(series.name)' color=\(series.color):")
                for (pidx, point) in series.data.enumerated() {
                    let effective = point.color.isEmpty ? series.color : point.color
                    lines.append("    Point \(pidx + 1) '\(point.name)'=\(point.value) color=\(effective)\(point.color.isEmpty ? " (inherited)" : "")")
                }
            }
            return lines.joined(separator: "\n")

        case "get_stack_info":
            let cardCount = document.cards.count
            let bgNames = document.backgrounds.map(\.name).joined(separator: ", ")
            let currentCard = document.cards.first(where: { $0.id == currentCardId })
            return "Stack '\(document.stack.name)': \(cardCount) cards, size: \(document.stack.width)x\(document.stack.height), backgrounds: [\(bgNames)], current card: \(currentCard?.name ?? "unnamed")"

        case "get_stack_property":
            let property = arguments["property"] ?? ""
            switch property.lowercased() {
            case "id":
                return document.stack.id.uuidString
            case "name":
                return document.stack.name
            case "width":
                return String(document.stack.width)
            case "height":
                return String(document.stack.height)
            case "defaultfont", "default_font":
                return document.stack.defaultFont
            case "webassetsallowed", "web_assets_allowed":
                return String(document.stack.webAssetsAllowed)
            case "cardcount", "card_count":
                return String(document.cards.count)
            case "backgroundcount", "background_count":
                return String(document.backgrounds.count)
            case "script":
                return document.stack.script
            case "theme":
                return document.stack.themeName
            default:
                return "Unknown stack property '\(property)'. Valid: id, name, width, height, defaultFont, webAssetsAllowed, cardCount, backgroundCount, script, theme"
            }

        case "get_card_property":
            let cardName = arguments["card_name"] ?? ""
            let property = arguments["property"] ?? ""
            guard let idx = cardIndex(named: cardName, currentCardId: currentCardId, in: document) else {
                return cardName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No current card" : "Card '\(cardName)' not found"
            }
            let card = document.cards[idx]
            switch property.lowercased() {
            case "id":
                return card.id.uuidString
            case "name":
                return card.name
            case "marked":
                return String(card.marked)
            case "sortkey", "sort_key":
                return card.sortKey
            case "background", "backgroundname", "background_name":
                return document.backgrounds.first(where: { $0.id == card.backgroundId })?.name ?? ""
            case "number", "cardnumber", "card_number":
                if let visibleIndex = document.sortedCards.firstIndex(where: { $0.id == card.id }) {
                    return String(visibleIndex + 1)
                }
                return ""
            case "script":
                return card.script
            case "theme":
                return card.themeName ?? ""
            case "effectivetheme", "effective_theme":
                return document.effectiveTheme(forCard: card.id).name
            default:
                return "Unknown card property '\(property)'. Valid: id, name, marked, sortKey, backgroundName, cardNumber, script, theme, effectiveTheme"
            }

        case "get_background_property":
            let bgName = arguments["background_name"] ?? ""
            let property = arguments["property"] ?? ""
            guard let idx = backgroundIndex(named: bgName, currentCardId: currentCardId, in: document) else {
                return bgName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No current background" : "Background '\(bgName)' not found"
            }
            let background = document.backgrounds[idx]
            switch property.lowercased() {
            case "id":
                return background.id.uuidString
            case "name":
                return background.name
            case "sortkey", "sort_key":
                return background.sortKey
            case "cardcount", "card_count":
                return String(document.cardsForBackground(background.id).count)
            case "script":
                return background.script
            case "theme":
                return background.themeName ?? ""
            default:
                return "Unknown background property '\(property)'. Valid: id, name, sortKey, cardCount, script, theme"
            }

        case "get_card_parts":
            let cardParts = document.partsForCard(currentCardId)
            if let card = document.cards.first(where: { $0.id == currentCardId }) {
                let bgParts = document.partsForBackground(card.backgroundId)
                let allParts = bgParts + cardParts
                if allParts.isEmpty {
                    return "No parts on current card"
                }
                let descriptions = allParts.map { p in describePartFull(p) }
                return "Parts on current card:\n\(descriptions.joined(separator: "\n"))"
            }
            return "No parts"

        case "get_background_parts":
            let bgName = arguments["background_name"] ?? ""
            guard let idx = backgroundIndex(named: bgName, currentCardId: currentCardId, in: document) else {
                return bgName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No current background" : "Background '\(bgName)' not found"
            }
            let background = document.backgrounds[idx]
            let bgParts = document.partsForBackground(background.id)
            guard !bgParts.isEmpty else {
                return "No parts on background '\(background.name)'"
            }
            let descriptions = bgParts.map { p in describePartFull(p) }
            return "Parts on background '\(background.name)':\n\(descriptions.joined(separator: "\n"))"

        case "fetch_url":
            let urlStr = arguments["url"] ?? ""
            guard let url = URL(string: urlStr) else { return "Invalid URL" }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let text = String(data: data, encoding: .utf8) ?? "(binary data)"
                return String(text.prefix(5000))  // Limit response size
            } catch {
                return "Fetch error: \(error.localizedDescription)"
            }

        case "read_file":
            let path = arguments["path"] ?? ""
            do {
                let content = try String(contentsOfFile: path, encoding: .utf8)
                return String(content.prefix(10000))
            } catch {
                return "Read error: \(error.localizedDescription)"
            }

        case "write_file":
            let path = arguments["path"] ?? ""
            let content = arguments["content"] ?? ""
            do {
                try content.write(toFile: path, atomically: true, encoding: .utf8)
                return "Wrote \(content.count) characters to \(path)"
            } catch {
                return "Write error: \(error.localizedDescription)"
            }

        case "list_directory":
            let path = arguments["path"] ?? "."
            do {
                let items = try FileManager.default.contentsOfDirectory(atPath: path)
                return items.joined(separator: "\n")
            } catch {
                return "List error: \(error.localizedDescription)"
            }

        case "create_sprite_area":
            let name = arguments["name"] ?? "Sprite Area"
            let sceneName = arguments["scene_name"] ?? "main"
            let left = Double(arguments["left"] ?? "20") ?? 20
            let top = Double(arguments["top"] ?? "20") ?? 20
            let width = Double(arguments["width"] ?? "400") ?? 400
            let height = Double(arguments["height"] ?? "300") ?? 300
            let place = placement(arguments: arguments, currentCardId: currentCardId, document: document)

            var newPart = Part(partType: .spriteArea, cardId: place.cardId, backgroundId: place.backgroundId,
                               name: name, left: left, top: top, width: width, height: height)
            newPart.setSpriteAreaSpec(
                SpriteAreaSpec(defaultSceneNamed: sceneName, fallbackSize: SizeSpec(width: width, height: height))
            )
            document.addPart(newPart)
            return "Created sprite area '\(name)' with scene '\(sceneName)' at (\(Int(left)),\(Int(top))) \(Int(width))x\(Int(height))"

        case "get_scene_spec":
            let areaName = arguments["sprite_area_name"] ?? ""
            guard let partIndex = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }
            let part = document.parts[partIndex]
            return part.activeSceneSpec?.toJSON() ?? "No scene spec"

        case "set_scene_script":
            let areaName = arguments["sprite_area_name"] ?? ""
            let requestedSceneName = arguments["scene_name"] ?? ""
            let rawScript = arguments["script"] ?? ""
            let wrapped = wrapScript(rawScript)
            if let refusal = refusalForInvalidDraft(
                toolName: toolName,
                arguments: arguments,
                targetDescription: "scene script in sprite area '\(areaName)'",
                rawScript: rawScript,
                wrappedScript: wrapped,
                document: document,
                currentCardId: currentCardId
            ) {
                return refusal.encodedSentinel()
            }

            guard let partIdx = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }

            var resolvedSceneName = requestedSceneName.isEmpty ? "" : requestedSceneName
            var wroteScript = false
            modifySpriteAreaSpec(partIndex: partIdx, document: &document) { areaSpec in
                let sceneIdx: Int?
                if !requestedSceneName.isEmpty {
                    sceneIdx = areaSpec.scenes.firstIndex { $0.scene.name.lowercased() == requestedSceneName.lowercased() }
                } else if let entry = areaSpec.activeSceneEntry {
                    sceneIdx = areaSpec.scenes.firstIndex { $0.id == entry.id }
                } else {
                    sceneIdx = nil
                }
                guard let idx = sceneIdx else { return }
                areaSpec.scenes[idx].scene.script = wrapped
                // If this is the active scene, also update the
                // cached activeScene mirror so live rebuilds pick
                // up the change immediately.
                if areaSpec.scenes[idx].id == areaSpec.activeSceneID {
                    areaSpec.setActiveScene(areaSpec.scenes[idx].scene)
                }
                resolvedSceneName = areaSpec.scenes[idx].scene.name
                wroteScript = true
            }

            if !wroteScript {
                if !requestedSceneName.isEmpty {
                    return "Scene '\(requestedSceneName)' not found in sprite area '\(areaName)'"
                }
                return "Sprite area '\(areaName)' has no active scene"
            }

            return "Set script of scene '\(resolvedSceneName)' in sprite area '\(areaName)'"

        case "apply_scene_diff":
            let areaName = arguments["sprite_area_name"] ?? ""
            let diffJson = arguments["diff_json"] ?? ""
            guard let partIdx = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }
            guard var spec = document.parts[partIdx].activeSceneSpec else {
                return "Invalid scene spec"
            }
            guard let diffData = diffJson.data(using: .utf8),
                  let diff = try? JSONDecoder().decode(SceneDiff.self, from: diffData) else {
                return "Invalid diff JSON"
            }
            diff.apply(to: &spec)
            _ = modifyActiveScene(partIndex: partIdx, document: &document) { $0 = spec }
            return "Applied scene diff to '\(areaName)'. Scene now has \(spec.nodes.count) nodes."

        case "add_sprite_to_scene":
            let areaName = arguments["sprite_area_name"] ?? ""
            let spriteName = arguments["sprite_name"] ?? "sprite"
            let assetName = arguments["asset_name"]
            let x = Double(arguments["x"] ?? "100") ?? 100
            let y = Double(arguments["y"] ?? "100") ?? 100
            let w: Double? = arguments["width"].flatMap { Double($0) }
            let h: Double? = arguments["height"].flatMap { Double($0) }
            guard let partIdx = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }
            guard document.parts[partIdx].activeSceneSpec != nil else {
                return "Invalid scene spec"
            }
            var newNode = HypeNodeSpec(name: spriteName, nodeType: .sprite)
            newNode.position = PointSpec(x: x, y: y)
            if let w = w, let h = h { newNode.size = SizeSpec(width: w, height: h) }
            // Look up asset in repository
            if let an = assetName, let asset = document.spriteRepository.asset(byName: an) {
                newNode.assetRef = document.spriteRepository.assetRef(for: asset)
            }
            _ = modifyActiveScene(partIndex: partIdx, document: &document) { $0.nodes.append(newNode) }
            return "Added sprite '\(spriteName)' to scene in '\(areaName)' at (\(Int(x)),\(Int(y)))"

        case "create_tilemap":
            let areaName = arguments["sprite_area_name"] ?? ""
            let tilemapName = arguments["tilemap_name"] ?? "tilemap"
            let cols = Int(arguments["columns"] ?? "10") ?? 10
            let rows = Int(arguments["rows"] ?? "10") ?? 10
            // Whether the caller supplied an explicit tile_size —
            // needed so the asset metadata can fill in a default
            // without overriding a user-chosen size.
            let explicitTileSize: Double? = arguments["tile_size"].flatMap { Double($0) }
            let tilesetAsset = arguments["tileset_asset"]
            guard let partIdx = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }
            guard document.parts[partIdx].activeSceneSpec != nil else {
                return "Invalid scene spec"
            }
            let initialTileSize = explicitTileSize ?? 32
            var tmSpec = TileMapSpec(columns: cols, rows: rows, tileWidth: initialTileSize, tileHeight: initialTileSize)
            tmSpec.tileData = Array(repeating: Array(repeating: -1, count: cols), count: rows)
            var tilesetInfo = ""
            if let tsName = tilesetAsset, let asset = document.spriteRepository.asset(byName: tsName) {
                tmSpec.tileSetAssetRef = document.spriteRepository.assetRef(for: asset)
                // See Interpreter.createTileMap for the full
                // rationale. Without this wire-up,
                // TileMapSpec.tileSetColumns defaulted to 1 and
                // multi-column tilesets rendered as a vertical strip.
                if asset.isTileSet {
                    tmSpec.tileSetColumns = asset.tileColumns
                    if explicitTileSize == nil {
                        tmSpec.tileWidth = Double(asset.tileWidth)
                        tmSpec.tileHeight = Double(asset.tileHeight)
                    }
                    tilesetInfo = ", tileset '\(asset.name)' (\(asset.tileColumns)x\(asset.tileRows) tiles, \(asset.tileWidth)x\(asset.tileHeight)px each)"
                } else {
                    tilesetInfo = ", tileset '\(asset.name)' (NOT CLASSIFIED — call classify_asset_as_tileset first for correct multi-column rendering)"
                }
            }
            var tmNode = HypeNodeSpec(name: tilemapName, nodeType: .tileMap, position: PointSpec(x: 0, y: 0))
            tmNode.tileMapSpec = tmSpec
            _ = modifyActiveScene(partIndex: partIdx, document: &document) { $0.nodes.append(tmNode) }
            let effectiveTileSize = Int(tmSpec.tileWidth)
            return "Created tile map '\(tilemapName)' (\(cols)x\(rows) cells, \(effectiveTileSize)x\(effectiveTileSize)px tiles) in '\(areaName)'\(tilesetInfo)"

        case "classify_asset_as_tileset":
            // Mark an existing repository asset as a tile set and
            // stamp its grid metadata. Without this classification,
            // create_tilemap has no way to know how to slice the
            // sprite sheet and falls back to tileSetColumns=1.
            let assetName = arguments["asset_name"] ?? ""
            let tileW = Int(arguments["tile_width"] ?? "0") ?? 0
            let tileH = Int(arguments["tile_height"] ?? "0") ?? 0
            let explicitCols = Int(arguments["tile_columns"] ?? "0")
            let explicitRows = Int(arguments["tile_rows"] ?? "0")
            guard tileW > 0, tileH > 0 else {
                return "classify_asset_as_tileset: tile_width and tile_height are required and must be > 0"
            }
            guard let assetIdx = document.spriteRepository.assets.firstIndex(where: {
                $0.name.lowercased() == assetName.lowercased()
            }) else {
                return "Asset '\(assetName)' not found in repository"
            }
            let asset = document.spriteRepository.assets[assetIdx]
            guard asset.width > 0, asset.height > 0 else {
                return "Asset '\(assetName)' has no image dimensions — can't classify as tileset"
            }
            // Auto-derive columns/rows from image dimensions when
            // not supplied. If the image is a non-integer multiple
            // of the tile size we still round down so partial
            // trailing tiles are dropped rather than crashing the
            // renderer.
            let cols = explicitCols ?? 0 > 0 ? explicitCols! : max(1, asset.width / tileW)
            let rows = explicitRows ?? 0 > 0 ? explicitRows! : max(1, asset.height / tileH)
            document.spriteRepository.updateAsset(id: asset.id) { mut in
                mut.kind = .tileSet
                mut.tileWidth = tileW
                mut.tileHeight = tileH
                mut.tileColumns = cols
                mut.tileRows = rows
            }
            return "Classified '\(assetName)' as tileset: \(cols)x\(rows) grid of \(tileW)x\(tileH)px tiles (\(cols * rows) total)"

        case "set_tile":
            // Structured per-cell tile setter. Complements HypeTalk's
            // `set tile col,row of tilemap "X" to N`. The tile_index
            // is a 0-based index into the tile set's tile groups
            // (left-to-right, top-to-bottom). Pass -1 to clear a
            // cell (empty tile).
            let areaName = arguments["sprite_area_name"] ?? ""
            let tilemapName = arguments["tilemap_name"] ?? ""
            guard let col = Int(arguments["column"] ?? "") else {
                return "set_tile: column is required"
            }
            guard let row = Int(arguments["row"] ?? "") else {
                return "set_tile: row is required"
            }
            guard let tileIndex = Int(arguments["tile_index"] ?? "") else {
                return "set_tile: tile_index is required (-1 for empty)"
            }
            guard let partIdx = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }
            guard let spec = document.parts[partIdx].activeSceneSpec else {
                return "Invalid scene spec in '\(areaName)'"
            }
            guard let node = spec.node(named: tilemapName), node.nodeType == .tileMap else {
                return "Tile map '\(tilemapName)' not found in '\(areaName)'"
            }
            guard var tmSpec = node.tileMapSpec else {
                return "Tile map '\(tilemapName)' has no tile map spec"
            }
            guard col >= 0, col < tmSpec.columns, row >= 0, row < tmSpec.rows else {
                return "set_tile: (\(col),\(row)) is out of bounds for tile map '\(tilemapName)' (\(tmSpec.columns)x\(tmSpec.rows))"
            }
            // Pad tileData to full dimensions if it was never
            // initialised — a brand-new tilemap gets an empty
            // [[Int]] which we lazily grow here.
            while tmSpec.tileData.count < tmSpec.rows {
                tmSpec.tileData.append(Array(repeating: -1, count: tmSpec.columns))
            }
            for r in 0..<tmSpec.tileData.count {
                while tmSpec.tileData[r].count < tmSpec.columns {
                    tmSpec.tileData[r].append(-1)
                }
            }
            tmSpec.tileData[row][col] = tileIndex
            _ = modifyActiveScene(partIndex: partIdx, document: &document) { scene in
                _ = scene.updateNode(id: node.id) { $0.tileMapSpec = tmSpec }
            }
            return "Set tile (\(col),\(row)) of '\(tilemapName)' to \(tileIndex)"

        case "fill_tilemap":
            // Fill every cell of a tile map with the same tile
            // index. Useful for painting a ground layer before
            // stamping obstacles.
            let areaName = arguments["sprite_area_name"] ?? ""
            let tilemapName = arguments["tilemap_name"] ?? ""
            guard let tileIndex = Int(arguments["tile_index"] ?? "") else {
                return "fill_tilemap: tile_index is required (-1 to clear)"
            }
            guard let partIdx = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }
            guard let spec = document.parts[partIdx].activeSceneSpec else {
                return "Invalid scene spec in '\(areaName)'"
            }
            guard let node = spec.node(named: tilemapName), node.nodeType == .tileMap else {
                return "Tile map '\(tilemapName)' not found in '\(areaName)'"
            }
            guard var tmSpec = node.tileMapSpec else {
                return "Tile map '\(tilemapName)' has no tile map spec"
            }
            tmSpec.tileData = Array(
                repeating: Array(repeating: tileIndex, count: tmSpec.columns),
                count: tmSpec.rows
            )
            _ = modifyActiveScene(partIndex: partIdx, document: &document) { scene in
                _ = scene.updateNode(id: node.id) { $0.tileMapSpec = tmSpec }
            }
            return "Filled tile map '\(tilemapName)' (\(tmSpec.columns)x\(tmSpec.rows)) with tile index \(tileIndex)"

        case "get_tilemap_info":
            // Diagnostic companion for tile map authoring. Reports
            // dimensions, tile size, tileset binding, and a
            // compact tileData preview so the AI can verify what
            // it just built.
            let areaName = arguments["sprite_area_name"] ?? ""
            let tilemapName = arguments["tilemap_name"] ?? ""
            guard let part = document.parts.first(where: {
                $0.partType == .spriteArea && $0.name.lowercased() == areaName.lowercased()
            }) else {
                return "Sprite area '\(areaName)' not found"
            }
            guard let spec = SceneSpec.fromJSON(part.sceneSpec) else {
                return "Invalid scene spec in '\(areaName)'"
            }
            guard let node = spec.node(named: tilemapName), node.nodeType == .tileMap else {
                return "Tile map '\(tilemapName)' not found in '\(areaName)'"
            }
            guard let tmSpec = node.tileMapSpec else {
                return "Tile map '\(tilemapName)' has no tile map spec"
            }
            var lines: [String] = [
                "Tile map '\(tilemapName)' in '\(areaName)':",
                "  Grid: \(tmSpec.columns) cols \u{00d7} \(tmSpec.rows) rows",
                "  Tile size: \(Int(tmSpec.tileWidth))\u{00d7}\(Int(tmSpec.tileHeight)) px",
                "  Tileset columns (sprite sheet): \(tmSpec.tileSetColumns)",
            ]
            if let ref = tmSpec.tileSetAssetRef,
               let asset = document.spriteRepository.asset(byId: ref.id) {
                let classification = asset.isTileSet
                    ? "tileSet (\(asset.tileColumns)x\(asset.tileRows))"
                    : "\(asset.kind.rawValue) (UNCLASSIFIED)"
                lines.append("  Tileset asset: '\(asset.name)' \(classification)")
            } else {
                lines.append("  Tileset asset: (none)")
            }
            // Count non-empty cells and show a tiny preview of the
            // top-left corner (up to 8x8) so the AI can sanity-check
            // tile placement.
            let nonEmpty = tmSpec.tileData.reduce(0) { acc, row in
                acc + row.filter { $0 >= 0 }.count
            }
            lines.append("  Non-empty cells: \(nonEmpty)/\(tmSpec.columns * tmSpec.rows)")
            let previewRows = min(tmSpec.tileData.count, 8)
            let previewCols = min(tmSpec.columns, 8)
            if previewRows > 0 && previewCols > 0 {
                lines.append("  Preview (top-left \(previewCols)x\(previewRows)):")
                for r in 0..<previewRows {
                    let row = tmSpec.tileData[r]
                    let cells = (0..<min(previewCols, row.count)).map { c -> String in
                        let v = row[c]
                        return v < 0 ? "  ." : String(format: "%3d", v)
                    }
                    lines.append("    " + cells.joined(separator: " "))
                }
            }
            return lines.joined(separator: "\n")

        case "create_camera":
            let areaName = arguments["sprite_area_name"] ?? ""
            let cameraName = arguments["camera_name"] ?? "camera"
            guard let partIdx = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }
            guard let spec = document.parts[partIdx].activeSceneSpec else {
                return "Invalid scene spec"
            }
            let camNode = HypeNodeSpec(name: cameraName, nodeType: .camera, position: PointSpec(x: spec.size.width / 2, y: spec.size.height / 2))
            _ = modifyActiveScene(partIndex: partIdx, document: &document) { $0.nodes.append(camNode) }
            return "Created camera '\(cameraName)' in '\(areaName)' at center (\(Int(spec.size.width / 2)),\(Int(spec.size.height / 2)))"

        case "list_repository_assets":
            if document.spriteRepository.assets.isEmpty {
                return "Sprite Repository is empty"
            }
            let descriptions = document.spriteRepository.assets.map { a -> String in
                var line = "[\(a.kind.rawValue)] '\(a.name)' \(a.width)x\(a.height) (\(a.data.count) bytes, \(a.slices.count) slices"
                if a.isTileSet {
                    line += ", tileset \(a.tileColumns)x\(a.tileRows) of \(a.tileWidth)x\(a.tileHeight)px"
                }
                return line + ")"
            }
            return "Repository assets:\n\(descriptions.joined(separator: "\n"))"

        case "import_repository_asset":
            let name = arguments["name"] ?? "asset"
            let filePath = arguments["file_path"] ?? ""
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else {
                return "Could not read file at '\(filePath)'"
            }
            #if canImport(AppKit)
            guard let image = NSImage(data: data) else {
                return "Could not load image from '\(filePath)'"
            }
            let size = image.size
            var asset = SpriteAsset(name: name, data: data, width: Int(size.width), height: Int(size.height))
            // Soft classification: if the filename hints at a
            // tileset, flag the asset as `.tileSet`. The AI should
            // still call `classify_asset_as_tileset` to set the
            // actual tile dimensions — this step only flips the
            // kind so the asset shows up as a tileset candidate in
            // the repository browser.
            if Self.filenameLooksLikeTileset(name) {
                asset.kind = .tileSet
            }
            document.spriteRepository.addAsset(asset)
            let hint = asset.kind == .tileSet
                ? " (auto-classified as tileSet by filename — call classify_asset_as_tileset to set tile dimensions)"
                : ""
            return "Imported '\(name)' (\(Int(size.width))x\(Int(size.height))) into Sprite Repository\(hint)"
            #else
            let asset = SpriteAsset(name: name, data: data)
            document.spriteRepository.addAsset(asset)
            return "Imported '\(name)' into Sprite Repository (dimensions unknown without AppKit)"
            #endif

        case "capture_scene_snapshot":
            let areaName = arguments["sprite_area_name"] ?? ""
            guard let part = document.parts.first(where: { $0.partType == .spriteArea && $0.name.lowercased() == areaName.lowercased() }) else {
                return "Sprite area '\(areaName)' not found"
            }
            guard let spec = part.activeSceneSpec else { return "No scene" }
            var lines: [String] = [
                "Scene '\(spec.name)' (\(Int(spec.size.width))x\(Int(spec.size.height)))",
                "Gravity: \(spec.gravity.dx),\(spec.gravity.dy)",
                "Paused: \(spec.isPaused)",
                "Nodes (\(spec.allNodes.count)):"
            ]
            for node in spec.allNodes {
                var desc = "  [\(node.nodeType.rawValue)] '\(node.name)' at (\(Int(node.position.x)),\(Int(node.position.y)))"
                if let size = node.size { desc += " \(Int(size.width))x\(Int(size.height))" }
                if let pb = node.physicsBody { desc += " [physics:\(pb.bodyType.rawValue)]" }
                if let text = node.text { desc += " text=\"\(text)\"" }
                if let ref = node.assetRef { desc += " asset=\"\(ref.name)\"" }
                lines.append(desc)
            }
            if !spec.joints.isEmpty {
                lines.append("Joints (\(spec.joints.count)):")
                for j in spec.joints {
                    lines.append("  \(j.jointType.rawValue) '\(j.nodeA)' <-> '\(j.nodeB)'")
                }
            }
            if !spec.fields.isEmpty {
                lines.append("Fields (\(spec.fields.count)):")
                for f in spec.fields {
                    lines.append("  \(f.fieldType.rawValue) strength=\(f.strength)")
                }
            }
            return lines.joined(separator: "\n")

        case "get_scene_diagnostics":
            let areaName = arguments["sprite_area_name"] ?? ""
            guard let part = document.parts.first(where: { $0.partType == .spriteArea && $0.name.lowercased() == areaName.lowercased() }) else {
                return "Sprite area '\(areaName)' not found"
            }
            guard let spec = part.activeSceneSpec else { return "Error: invalid scene spec JSON" }
            let report = spec.diagnostics(using: document.spriteRepository)
            if report.issues.isEmpty {
                return """
                No issues found. Scene is healthy.
                Nodes: \(report.nodeCount)
                Physics bodies: \(report.physicsBodyCount)
                Textured nodes: \(report.texturedNodeCount)
                Referenced assets: \(report.referencedAssetIDs.count)
                """
            }
            let lines = report.issues.map { issue in
                "\(issue.severity.rawValue.uppercased()): \(issue.message)"
            }
            return "Diagnostics for '\(areaName)':\n" + lines.joined(separator: "\n")

        // MARK: - Web Asset Search Tools

        case "search_web_for_sprite":
            // Gate 0: per-turn soft cap
            guard let session = webAssetSession else {
                return "Web asset search is off for this stack. Ask the user to enable it in Preferences → Web Asset Search → Current Stack."
            }
            let capAllowed = await session.shouldAllowDispatch()
            guard capAllowed else {
                return "Safety limit reached: too many web asset operations in one turn. Start a new message to continue."
            }
            // Gate 1: webAssetsAllowed
            guard document.stack.webAssetsAllowed else {
                return "Web asset search is off for this stack. Ask the user to enable it in Preferences → Web Asset Search → Current Stack."
            }
            // Gate 2: wired dependencies
            guard let client = webAssetClient else {
                return "search_web_for_sprite not configured: no search client available."
            }

            let query = arguments["query"] ?? ""
            guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
                return "search_web_for_sprite requires 'query'."
            }
            let maxResults = min(max(Int(arguments["max_results"] ?? "8") ?? 8, 1), 20)

            do {
                let results = try await client.search(WebAssetSearchQuery(query: query, maxResults: maxResults))
                _ = await session.recordSearch(query: query, results: results)
                if results.isEmpty {
                    return "No \(client.provider.displayName) results for \"\(query)\"."
                }
                let lines = results.map { r in
                    let w = r.width ?? 0; let h = r.height ?? 0
                    let lic = r.license.name.isEmpty ? "unknown" : r.license.name
                    return "candidate_id=\(r.id) provider=\(r.providerRaw.rawValue) title=\"\(r.title)\" size=\(w)x\(h) license=\(lic) url=\(r.downloadURL.absoluteString)"
                }
                return "Found \(results.count) candidate(s) from \(client.provider.displayName):\n" + lines.joined(separator: "\n")
            } catch let error as WebAssetSearchError {
                return formatWebAssetError(error, context: "search_web_for_sprite", phase: .search)
            } catch {
                return "search_web_for_sprite network error (transport failure)"
            }

        case "import_web_asset":
            // Gate 0: per-turn soft cap
            guard let session = webAssetSession else {
                return "Web asset search is off for this stack. Ask the user to enable it in Preferences → Web Asset Search → Current Stack."
            }
            let capAllowed2 = await session.shouldAllowDispatch()
            guard capAllowed2 else {
                return "Safety limit reached: too many web asset operations in one turn. Start a new message to continue."
            }
            // Gate 1: webAssetsAllowed
            guard document.stack.webAssetsAllowed else {
                return "Web asset search is off for this stack. Ask the user to enable it in Preferences → Web Asset Search → Current Stack."
            }
            // Gate 2: wired dependencies
            guard let client = webAssetClient, let pipeline = webAssetPipeline else {
                return "import_web_asset not configured: no search client or pipeline available."
            }

            let candidateId = arguments["candidate_id"] ?? ""
            let rawName = arguments["asset_name"] ?? ""
            guard !candidateId.isEmpty, !rawName.isEmpty else {
                return "import_web_asset requires 'candidate_id' and 'asset_name'."
            }
            // Gate 3: asset_name sanitization (Finding 8)
            guard let cleanedName = sanitizeAssetName(rawName) else {
                return "asset_name '\(rawName)' is invalid — use 1-128 characters, letters / digits / _ / - / . / space only"
            }
            guard let candidate = await session.candidate(id: candidateId) else {
                return "Unknown candidate_id '\(candidateId)'. Call search_web_for_sprite first; candidate ids only live for the current chat session."
            }
            let searchQuery = await session.queryForCandidate(id: candidateId) ?? ""

            do {
                let download = try await pipeline.fetch(candidate)
                let asset = WebAssetImportPipeline.makeSpriteAsset(
                    name: cleanedName,
                    searchQuery: searchQuery,
                    download: download
                )
                document.spriteRepository.addAsset(asset)
                let webAssets = document.spriteRepository.assets.filter { $0.provenance?.origin == .webSearch }
                document.stack.script = StackScriptAttributionSync.sync(
                    stackScript: document.stack.script,
                    webAssets: webAssets
                )
                return "Imported '\(cleanedName)' (\(download.width)x\(download.height), \(download.bytes.count) bytes) from \(candidate.providerRaw.displayName)."
            } catch let error as WebAssetSearchError {
                return formatWebAssetError(error, context: "import_web_asset", phase: .download)
            } catch {
                return "import_web_asset network error (transport failure)"
            }

        case "find_and_import_sprite":
            // Gate 0: per-turn soft cap
            guard let session = webAssetSession else {
                return "Web asset search is off for this stack. Ask the user to enable it in Preferences → Web Asset Search → Current Stack."
            }
            let capAllowed3 = await session.shouldAllowDispatch()
            guard capAllowed3 else {
                return "Safety limit reached: too many web asset operations in one turn. Start a new message to continue."
            }
            // Gate 1: webAssetsAllowed
            guard document.stack.webAssetsAllowed else {
                return "Web asset search is off for this stack. Ask the user to enable it in Preferences → Web Asset Search → Current Stack."
            }
            // Gate 2: wired dependencies
            guard let client = webAssetClient, let pipeline = webAssetPipeline else {
                return "find_and_import_sprite not configured: no search client or pipeline available."
            }

            let fQuery = arguments["query"] ?? ""
            let rawName3 = arguments["asset_name"] ?? ""
            guard !fQuery.isEmpty, !rawName3.isEmpty else {
                return "find_and_import_sprite requires 'query' and 'asset_name'."
            }
            // Gate 3: asset_name sanitization (Finding 8)
            guard let cleanedName3 = sanitizeAssetName(rawName3) else {
                return "asset_name '\(rawName3)' is invalid — use 1-128 characters, letters / digits / _ / - / . / space only"
            }

            do {
                let results = try await client.search(WebAssetSearchQuery(query: fQuery, maxResults: 8))
                _ = await session.recordSearch(query: fQuery, results: results)
                guard let first = results.first else {
                    return "No \(client.provider.displayName) results for \"\(fQuery)\". find_and_import_sprite did not install anything."
                }
                let download = try await pipeline.fetch(first)
                let asset = WebAssetImportPipeline.makeSpriteAsset(
                    name: cleanedName3,
                    searchQuery: fQuery,
                    download: download
                )
                document.spriteRepository.addAsset(asset)
                let webAssets3 = document.spriteRepository.assets.filter { $0.provenance?.origin == .webSearch }
                document.stack.script = StackScriptAttributionSync.sync(
                    stackScript: document.stack.script,
                    webAssets: webAssets3
                )
                return "Installed '\(cleanedName3)' from \(first.providerRaw.displayName) (query: \"\(fQuery)\")."
            } catch let error as WebAssetSearchError {
                return formatWebAssetError(error, context: "find_and_import_sprite", phase: .download)
            } catch {
                return "find_and_import_sprite network error (transport failure)"
            }

        // MARK: - Read-side granular queries

        case "get_part_property":
            let partName = arguments["part_name"] ?? ""
            let property = arguments["property"] ?? ""
            guard let partIndex = scopedPartIndex(named: partName, currentCardId: currentCardId, in: document) else {
                return "Part '\(partName)' not found"
            }
            let part = document.parts[partIndex]
            switch property.lowercased() {
            case "name": return part.name
            case "left": return String(part.left)
            case "top": return String(part.top)
            case "width": return String(part.width)
            case "height": return String(part.height)
            case "rotation": return String(part.rotation)
            case "text", "textcontent": return part.textContent
            case "url": return part.url
            case "videourl", "video_url": return part.videoURL
            case "fillcolor", "fill_color": return part.fillColor
            case "strokecolor", "stroke_color": return part.strokeColor
            case "strokewidth": return String(part.strokeWidth)
            case "cornerradius": return String(part.cornerRadius)
            case "visible": return String(part.visible)
            case "enabled": return String(part.enabled)
            case "hilite": return String(part.hilite)
            case "autohilite": return String(part.autoHilite)
            case "showname": return String(part.showName)
            case "locktext": return String(part.lockText)
            case "transparentbackground", "transparent_background", "transparent",
                 "transparentbg", "alpha":
                return String(part.transparentBackground)
            // Calendar-specific properties — readable on any part,
            // but only meaningful when the part's type is .calendar.
            case "selecteddate", "selected_date": return part.selectedDate
            case "displaymonth", "display_month": return part.displayMonth
            case "mindate", "min_date": return part.minDate
            case "maxdate", "max_date": return part.maxDate
            case "calendarstyle", "calendar_style": return part.calendarStyle
            // PDF
            case "pdfurl", "pdf_url": return part.pdfURL
            case "currentpage", "current_page": return String(part.pdfCurrentPage)
            case "displaymode", "display_mode": return part.pdfDisplayMode
            case "autoscales", "auto_scales": return String(part.pdfAutoScales)
            // Map
            case "centerlat", "center_lat": return String(part.mapCenterLat)
            case "centerlon", "center_lon": return String(part.mapCenterLon)
            case "span": return String(part.mapSpan)
            case "maptype", "map_type": return part.mapType
            case "annotations": return part.mapAnnotationsJSON
            // ColorWell
            case "color", "colorhex", "color_hex": return part.colorWellHex
            case "interactive": return String(part.colorWellInteractive)
            // Form controls.
            case "value":
                if part.partType == .toggle { return String(part.controlValue >= 0.5) }
                if part.partType == .segmented { return String(Int(part.controlValue)) }
                return String(part.controlValue)
            case "on": return String(part.controlValue >= 0.5)
            case "min", "minvalue", "min_value": return String(part.controlMin)
            case "max", "maxvalue", "max_value": return String(part.controlMax)
            case "step", "increment": return String(part.controlStep)
            case "segments", "segmentitems": return part.segmentItems
            case "selectedsegment", "selected_segment": return String(Int(part.controlValue))
            // AudioRecorder
            case "recording": return String(part.audioRecording)
            case "duration": return String(part.audioDuration)
            case "outputpath", "output_path", "filepath", "file_path": return part.audioOutputPath
            case "format": return part.audioFormat
            // Scene3D
            case "modelurl", "model_url", "sceneurl", "scene_url": return part.scene3DURL
            case "allowscameracontrol", "allows_camera_control", "cameracontrol": return String(part.scene3DAllowsCameraControl)
            case "autolighting", "auto_lighting", "defaultlighting": return String(part.scene3DAutoLighting)
            case "antialiasing", "anti_aliasing": return part.scene3DAntialiasing
            case "background3d", "background_3d", "scenebackground": return part.scene3DBackground
            case "textfont", "font": return part.textFont
            case "textsize", "size": return String(part.textSize)
            case "textalign": return part.textAlign.rawValue
            case "textstyle": return part.textStyle
            case "script":
                if part.partType == .spriteArea {
                    let preview = part.activeSceneSpec?.script ?? ""
                    if preview.count > 5000 {
                        return String(preview.prefix(5000)) + "\u{2026}[truncated]"
                    }
                    return preview
                }
                let preview = part.script
                if preview.count > 5000 {
                    return String(preview.prefix(5000)) + "\u{2026}[truncated]"
                }
                return preview
            case "style":
                switch part.partType {
                case .button: return part.buttonStyle.rawValue
                case .field: return part.fieldStyle.rawValue
                case .shape: return part.shapeType.rawValue
                default: return "Part type '\(part.partType.rawValue)' does not support style property"
                }
            case "charttype", "chart_type":
                if let cfg = ChartConfig.fromJSON(part.chartData) { return cfg.chartType.rawValue }
                return ""
            case "charttitle", "chart_title":
                if let cfg = ChartConfig.fromJSON(part.chartData) { return cfg.title }
                return ""
            case "xaxislabel", "x_axis_label", "xlabel", "x_label":
                if let cfg = ChartConfig.fromJSON(part.chartData) { return cfg.xAxisLabel }
                return ""
            case "yaxislabel", "y_axis_label", "ylabel", "y_label":
                if let cfg = ChartConfig.fromJSON(part.chartData) { return cfg.yAxisLabel }
                return ""
            case "showlegend", "show_legend":
                if let cfg = ChartConfig.fromJSON(part.chartData) { return String(cfg.showLegend) }
                return "true"
            case "showgrid", "show_grid":
                if let cfg = ChartConfig.fromJSON(part.chartData) { return String(cfg.showGrid) }
                return "true"
            case "chartdata", "chart_data":
                return part.chartData
            default:
                return "Unknown property '\(property)'"
            }

        case "get_node_property":
            let areaName = arguments["sprite_area_name"] ?? ""
            let nodeName = arguments["node_name"] ?? ""
            let property = arguments["property"] ?? ""
            let requestedSceneName = arguments["scene_name"] ?? ""
            guard let partIndex = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }
            let part = document.parts[partIndex]
            guard let areaSpec = part.spriteAreaSpecModel else {
                return "Invalid scene spec in '\(areaName)'"
            }
            let scene: SceneSpec
            if requestedSceneName.isEmpty {
                guard let active = areaSpec.activeScene else {
                    return "Sprite area '\(areaName)' has no active scene"
                }
                scene = active
            } else {
                guard let entry = areaSpec.scenes.first(where: {
                    $0.scene.name.lowercased() == requestedSceneName.lowercased()
                }) else {
                    return "Scene '\(requestedSceneName)' not found in sprite area '\(areaName)'"
                }
                scene = entry.scene
            }
            guard let node = scene.node(named: nodeName) else {
                return "Node '\(nodeName)' not found in '\(areaName)'"
            }
            return nodePropertyValue(node: node, property: property)

        case "list_all_cards":
            if document.sortedCards.isEmpty {
                return "Stack has no cards"
            }
            var lines: [String] = []
            for (idx, card) in document.sortedCards.enumerated() {
                let displayName = card.name.isEmpty ? "Card \(idx + 1)" : card.name
                let bgName = document.backgrounds.first(where: { $0.id == card.backgroundId })?.name ?? "(unknown)"
                let suffix = card.id == currentCardId ? " \u{2014} current card" : ""
                lines.append("Card \(idx + 1): \"\(displayName)\" (background: \"\(bgName)\")\(suffix)")
            }
            return lines.joined(separator: "\n")

        case "list_backgrounds":
            if document.backgrounds.isEmpty {
                return "Stack has no backgrounds"
            }
            var lines: [String] = []
            for bg in document.backgrounds {
                let count = document.cardsForBackground(bg.id).count
                let plural = count == 1 ? "card" : "cards"
                lines.append("\"\(bg.name)\" (used by \(count) \(plural))")
            }
            return lines.joined(separator: "\n")

        case "list_scene_nodes":
            let areaName = arguments["sprite_area_name"] ?? ""
            let requestedSceneName = arguments["scene_name"] ?? ""
            guard let partIndex = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }
            let part = document.parts[partIndex]
            guard let areaSpec = part.spriteAreaSpecModel else {
                return "Invalid scene spec in '\(areaName)'"
            }
            let scene: SceneSpec
            if requestedSceneName.isEmpty {
                guard let active = areaSpec.activeScene else {
                    return "Sprite area '\(areaName)' has no active scene"
                }
                scene = active
            } else {
                guard let entry = areaSpec.scenes.first(where: {
                    $0.scene.name.lowercased() == requestedSceneName.lowercased()
                }) else {
                    return "Scene '\(requestedSceneName)' not found in sprite area '\(areaName)'"
                }
                scene = entry.scene
            }
            let all = scene.allNodes
            if all.isEmpty {
                return "Scene '\(scene.name)' in '\(areaName)' has no nodes"
            }
            let limit = 100
            var lines: [String] = []
            for node in all.prefix(limit) {
                var line = "\(node.name): \(node.nodeType.rawValue) at (\(Int(node.position.x)),\(Int(node.position.y))) [zPos=\(node.zPosition), alpha=\(node.alpha)]"
                if let pb = node.physicsBody {
                    line += " physics:\(pb.bodyType.rawValue)"
                }
                lines.append(line)
            }
            if all.count > limit {
                lines.append("\u{2026}(\(all.count - limit) more)")
            }
            return lines.joined(separator: "\n")

        case "list_scene_joints":
            let areaName = arguments["sprite_area_name"] ?? ""
            let requestedSceneName = arguments["scene_name"] ?? ""
            guard let partIndex = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }
            let part = document.parts[partIndex]
            guard let areaSpec = part.spriteAreaSpecModel else {
                return "Invalid scene spec in '\(areaName)'"
            }
            let scene: SceneSpec
            if requestedSceneName.isEmpty {
                guard let active = areaSpec.activeScene else {
                    return "Sprite area '\(areaName)' has no active scene"
                }
                scene = active
            } else {
                guard let entry = areaSpec.scenes.first(where: {
                    $0.scene.name.lowercased() == requestedSceneName.lowercased()
                }) else {
                    return "Scene '\(requestedSceneName)' not found in sprite area '\(areaName)'"
                }
                scene = entry.scene
            }
            if scene.joints.isEmpty {
                return "Scene '\(scene.name)' in '\(areaName)' has no joints"
            }
            let grouped = Dictionary(grouping: scene.joints, by: { $0.jointType })
            var lines: [String] = []
            for type in [JointType.pin, .spring, .sliding, .fixed, .limit] {
                guard let items = grouped[type], !items.isEmpty else { continue }
                lines.append("\(type.rawValue) (\(items.count)):")
                for j in items {
                    lines.append("  '\(j.nodeA)' <-> '\(j.nodeB)'")
                }
            }
            return lines.joined(separator: "\n")

        case "list_scene_constraints":
            let areaName = arguments["sprite_area_name"] ?? ""
            let requestedSceneName = arguments["scene_name"] ?? ""
            guard let partIndex = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }
            let part = document.parts[partIndex]
            guard let areaSpec = part.spriteAreaSpecModel else {
                return "Invalid scene spec in '\(areaName)'"
            }
            let scene: SceneSpec
            if requestedSceneName.isEmpty {
                guard let active = areaSpec.activeScene else {
                    return "Sprite area '\(areaName)' has no active scene"
                }
                scene = active
            } else {
                guard let entry = areaSpec.scenes.first(where: {
                    $0.scene.name.lowercased() == requestedSceneName.lowercased()
                }) else {
                    return "Scene '\(requestedSceneName)' not found in sprite area '\(areaName)'"
                }
                scene = entry.scene
            }
            if scene.sceneConstraints.isEmpty {
                return "Scene '\(scene.name)' in '\(areaName)' has no constraints"
            }
            var lines: [String] = []
            for c in scene.sceneConstraints {
                var line = "\(c.constraintType.rawValue): '\(c.sourceNode)' -> '\(c.targetNode)'"
                if let minD = c.minDistance { line += " min=\(minD)" }
                if let maxD = c.maxDistance { line += " max=\(maxD)" }
                lines.append(line)
            }
            return lines.joined(separator: "\n")

        case "get_scene_script":
            let areaName = arguments["sprite_area_name"] ?? ""
            let requestedSceneName = arguments["scene_name"] ?? ""
            guard let partIndex = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }
            let part = document.parts[partIndex]
            guard let areaSpec = part.spriteAreaSpecModel else {
                return "Invalid scene spec in '\(areaName)'"
            }
            let scene: SceneSpec
            if requestedSceneName.isEmpty {
                guard let active = areaSpec.activeScene else {
                    return "Sprite area '\(areaName)' has no active scene"
                }
                scene = active
            } else {
                guard let entry = areaSpec.scenes.first(where: {
                    $0.scene.name.lowercased() == requestedSceneName.lowercased()
                }) else {
                    return "Scene '\(requestedSceneName)' not found in sprite area '\(areaName)'"
                }
                scene = entry.scene
            }
            if scene.script.count > 5000 {
                return String(scene.script.prefix(5000)) + "\u{2026}[truncated]"
            }
            return scene.script

        case "get_node_script":
            let areaName = arguments["sprite_area_name"] ?? ""
            let nodeName = arguments["node_name"] ?? ""
            let requestedSceneName = arguments["scene_name"] ?? ""
            guard let partIndex = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }
            let part = document.parts[partIndex]
            guard let areaSpec = part.spriteAreaSpecModel else {
                return "Invalid scene spec in '\(areaName)'"
            }
            let scene: SceneSpec
            if requestedSceneName.isEmpty {
                guard let active = areaSpec.activeScene else {
                    return "Sprite area '\(areaName)' has no active scene"
                }
                scene = active
            } else {
                guard let entry = areaSpec.scenes.first(where: {
                    $0.scene.name.lowercased() == requestedSceneName.lowercased()
                }) else {
                    return "Scene '\(requestedSceneName)' not found in sprite area '\(areaName)'"
                }
                scene = entry.scene
            }
            guard let node = scene.node(named: nodeName) else {
                return "Node '\(nodeName)' not found in '\(areaName)'"
            }
            if node.script.count > 5000 {
                return String(node.script.prefix(5000)) + "\u{2026}[truncated]"
            }
            return node.script

        case "get_stack_script":
            let script = document.stack.script
            if script.count > 5000 {
                return String(script.prefix(5000)) + "\u{2026}[truncated]"
            }
            return script

        case "get_card_script":
            let cardName = arguments["card_name"] ?? ""
            guard let idx = cardIndex(named: cardName, currentCardId: currentCardId, in: document) else {
                return cardName.isEmpty ? "No current card" : "Card '\(cardName)' not found"
            }
            let resolved = document.cards[idx]
            if resolved.script.count > 5000 {
                return String(resolved.script.prefix(5000)) + "\u{2026}[truncated]"
            }
            return resolved.script

        case "get_background_script":
            let bgName = arguments["background_name"] ?? ""
            guard let idx = backgroundIndex(named: bgName, currentCardId: currentCardId, in: document) else {
                return bgName.isEmpty ? "No current background" : "Background '\(bgName)' not found"
            }
            let bg = document.backgrounds[idx]
            if bg.script.count > 5000 {
                return String(bg.script.prefix(5000)) + "\u{2026}[truncated]"
            }
            return bg.script

        // MARK: - Script-setter tools (stack / card / background)

        case "set_stack_script":
            let rawScript = arguments["script"] ?? ""
            let wrapped = wrapScript(rawScript)
            if let refusal = refusalForInvalidDraft(
                toolName: toolName,
                arguments: arguments,
                targetDescription: "the stack",
                rawScript: rawScript,
                wrappedScript: wrapped,
                document: document,
                currentCardId: currentCardId
            ) {
                return refusal.encodedSentinel()
            }
            document.stack.script = wrapped
            return "Set stack script"

        case "set_card_script":
            let rawScript = arguments["script"] ?? ""
            let cardName = arguments["card_name"] ?? ""
            let wrapped = wrapScript(rawScript)
            if let refusal = refusalForInvalidDraft(
                toolName: toolName,
                arguments: arguments,
                targetDescription: cardName.isEmpty ? "the current card" : "card '\(cardName)'",
                rawScript: rawScript,
                wrappedScript: wrapped,
                document: document,
                currentCardId: currentCardId
            ) {
                return refusal.encodedSentinel()
            }
            let targetIndex = cardIndex(named: cardName, currentCardId: currentCardId, in: document)
            guard let idx = targetIndex else {
                return cardName.isEmpty ? "No current card" : "Card '\(cardName)' not found"
            }
            document.cards[idx].script = wrapped
            let displayName = document.cards[idx].name.isEmpty ? "current card" : "card '\(document.cards[idx].name)'"
            return "Set script of \(displayName)"

        case "set_background_script":
            let bgName = arguments["background_name"] ?? ""
            let rawScript = arguments["script"] ?? ""
            let wrapped = wrapScript(rawScript)
            if let refusal = refusalForInvalidDraft(
                toolName: toolName,
                arguments: arguments,
                targetDescription: bgName.isEmpty ? "the current background" : "background '\(bgName)'",
                rawScript: rawScript,
                wrappedScript: wrapped,
                document: document,
                currentCardId: currentCardId
            ) {
                return refusal.encodedSentinel()
            }
            guard let idx = backgroundIndex(named: bgName, currentCardId: currentCardId, in: document) else {
                return bgName.isEmpty ? "No current background" : "Background '\(bgName)' not found"
            }
            document.backgrounds[idx].script = wrapped
            return "Set script of background '\(document.backgrounds[idx].name)'"

        // MARK: - Scene-node creators

        case "add_label_to_scene":
            let areaName = arguments["sprite_area_name"] ?? ""
            let labelName = arguments["label_name"] ?? "label"
            let text = arguments["text"] ?? ""
            let x = Double(arguments["x"] ?? "0") ?? 0
            let y = Double(arguments["y"] ?? "0") ?? 0
            let requestedSceneName = arguments["scene_name"] ?? ""
            guard let partIdx = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }
            var node = HypeNodeSpec(name: labelName, nodeType: .label, position: PointSpec(x: x, y: y))
            node.text = text
            if let fontName = arguments["font_name"] { node.fontName = fontName }
            if let fontSize = arguments["font_size"], let v = Double(fontSize) { node.fontSize = v }
            if let fontColor = arguments["font_color"] { node.fontColor = fontColor }
            if let zPos = arguments["z_position"], let v = Double(zPos) { node.zPosition = v }
            let appended = appendNodeToScene(
                node: node,
                partIndex: partIdx,
                requestedSceneName: requestedSceneName,
                areaName: areaName,
                document: &document
            )
            switch appended {
            case .success(let sceneName):
                return "Added label '\(labelName)' to scene '\(sceneName)' in '\(areaName)' at (\(Int(x)),\(Int(y)))"
            case .failure(let msg):
                return msg
            }

        case "add_shape_to_scene":
            let areaName = arguments["sprite_area_name"] ?? ""
            let shapeName = arguments["shape_name"] ?? "shape"
            let shapeTypeStr = arguments["shape_type"] ?? "rect"
            let x = Double(arguments["x"] ?? "0") ?? 0
            let y = Double(arguments["y"] ?? "0") ?? 0
            let requestedSceneName = arguments["scene_name"] ?? ""
            guard let shapeType = SpriteShapeType(rawValue: shapeTypeStr) else {
                let valid = SpriteShapeType.allCases.map(\.rawValue).joined(separator: ", ")
                return "Invalid shape_type '\(shapeTypeStr)'. Valid: \(valid)"
            }
            guard let partIdx = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }
            var node = HypeNodeSpec(name: shapeName, nodeType: .shape, position: PointSpec(x: x, y: y))
            if let w = Double(arguments["width"] ?? ""), let h = Double(arguments["height"] ?? "") {
                node.size = SizeSpec(width: w, height: h)
            }
            var shape = ShapeNodeSpec(shapeType: shapeType)
            if let fill = arguments["fill_color"] { shape.fillColor = fill }
            if let stroke = arguments["stroke_color"] { shape.strokeColor = stroke }
            if let lw = arguments["line_width"], let v = Double(lw) { shape.lineWidth = v }
            if let cr = arguments["corner_radius"], let v = Double(cr) { shape.cornerRadius = v }
            node.shapeSpec = shape
            if let zPos = arguments["z_position"], let v = Double(zPos) { node.zPosition = v }
            let appended = appendNodeToScene(
                node: node,
                partIndex: partIdx,
                requestedSceneName: requestedSceneName,
                areaName: areaName,
                document: &document
            )
            switch appended {
            case .success(let sceneName):
                return "Added shape '\(shapeName)' (\(shapeType.rawValue)) to scene '\(sceneName)' in '\(areaName)' at (\(Int(x)),\(Int(y)))"
            case .failure(let msg):
                return msg
            }

        case "add_emitter_to_scene":
            let areaName = arguments["sprite_area_name"] ?? ""
            let emitterName = arguments["emitter_name"] ?? "emitter"
            let x = Double(arguments["x"] ?? "0") ?? 0
            let y = Double(arguments["y"] ?? "0") ?? 0
            let requestedSceneName = arguments["scene_name"] ?? ""
            guard let partIdx = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }
            var emitter = EmitterSpec()
            if let br = arguments["birth_rate"], let v = Double(br) { emitter.particleBirthRate = v }
            if let lt = arguments["lifetime"], let v = Double(lt) { emitter.particleLifetime = v }
            if let sp = arguments["speed"], let v = Double(sp) { emitter.particleSpeed = v }
            if let ang = arguments["emission_angle"], let v = Double(ang) { emitter.emissionAngle = v }
            if let color = arguments["particle_color"] { emitter.particleColor = color }
            if let scale = arguments["particle_scale"], let v = Double(scale) { emitter.particleScale = v }
            var node = HypeNodeSpec(name: emitterName, nodeType: .emitter, position: PointSpec(x: x, y: y))
            node.emitterSpec = emitter
            let appended = appendNodeToScene(
                node: node,
                partIndex: partIdx,
                requestedSceneName: requestedSceneName,
                areaName: areaName,
                document: &document
            )
            switch appended {
            case .success(let sceneName):
                return "Added emitter '\(emitterName)' to scene '\(sceneName)' in '\(areaName)' at (\(Int(x)),\(Int(y)))"
            case .failure(let msg):
                return msg
            }

        case "add_audio_to_scene":
            let areaName = arguments["sprite_area_name"] ?? ""
            let audioName = arguments["audio_name"] ?? "audio"
            let requestedSceneName = arguments["scene_name"] ?? ""
            guard let partIdx = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }
            var node = HypeNodeSpec(name: audioName, nodeType: .audio)
            if let assetName = arguments["asset_name"],
               let asset = document.spriteRepository.asset(byName: assetName) {
                node.assetRef = document.spriteRepository.assetRef(for: asset)
            }
            if let loop = arguments["loop"] { node.audioLoop = (loop.lowercased() == "true") }
            if let vol = arguments["volume"], let v = Double(vol) { node.audioVolume = v }
            if let ap = arguments["autoplay"] { node.audioAutoplay = (ap.lowercased() == "true") }
            if let pos = arguments["positional"] { node.audioPositional = (pos.lowercased() == "true") }
            let appended = appendNodeToScene(
                node: node,
                partIndex: partIdx,
                requestedSceneName: requestedSceneName,
                areaName: areaName,
                document: &document
            )
            switch appended {
            case .success(let sceneName):
                return "Added audio '\(audioName)' to scene '\(sceneName)' in '\(areaName)'"
            case .failure(let msg):
                return msg
            }

        case "add_video_to_scene":
            let areaName = arguments["sprite_area_name"] ?? ""
            let videoName = arguments["video_name"] ?? "video"
            let assetName = arguments["asset_name"] ?? ""
            let x = Double(arguments["x"] ?? "0") ?? 0
            let y = Double(arguments["y"] ?? "0") ?? 0
            let requestedSceneName = arguments["scene_name"] ?? ""
            guard let partIdx = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }
            var node = HypeNodeSpec(name: videoName, nodeType: .video, position: PointSpec(x: x, y: y))
            if !assetName.isEmpty, let asset = document.spriteRepository.asset(byName: assetName) {
                node.assetRef = document.spriteRepository.assetRef(for: asset)
            }
            if let w = Double(arguments["width"] ?? ""), let h = Double(arguments["height"] ?? "") {
                node.size = SizeSpec(width: w, height: h)
            }
            if let loop = arguments["loop"] { node.videoLoop = (loop.lowercased() == "true") }
            if let ap = arguments["autoplay"] { node.videoAutoplay = (ap.lowercased() == "true") }
            let appended = appendNodeToScene(
                node: node,
                partIndex: partIdx,
                requestedSceneName: requestedSceneName,
                areaName: areaName,
                document: &document
            )
            switch appended {
            case .success(let sceneName):
                return "Added video '\(videoName)' to scene '\(sceneName)' in '\(areaName)' at (\(Int(x)),\(Int(y)))"
            case .failure(let msg):
                return msg
            }

        case "add_group_to_scene":
            let areaName = arguments["sprite_area_name"] ?? ""
            let groupName = arguments["group_name"] ?? "group"
            let x = Double(arguments["x"] ?? "0") ?? 0
            let y = Double(arguments["y"] ?? "0") ?? 0
            let requestedSceneName = arguments["scene_name"] ?? ""
            guard let partIdx = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }
            let node = HypeNodeSpec(name: groupName, nodeType: .group, position: PointSpec(x: x, y: y))
            let appended = appendNodeToScene(
                node: node,
                partIndex: partIdx,
                requestedSceneName: requestedSceneName,
                areaName: areaName,
                document: &document
            )
            switch appended {
            case .success(let sceneName):
                return "Added group '\(groupName)' to scene '\(sceneName)' in '\(areaName)' at (\(Int(x)),\(Int(y)))"
            case .failure(let msg):
                return msg
            }

        case "add_joint_to_scene":
            let areaName = arguments["sprite_area_name"] ?? ""
            let jointTypeStr = arguments["joint_type"] ?? ""
            let nodeA = arguments["node_a"] ?? ""
            let nodeB = arguments["node_b"] ?? ""
            let requestedSceneName = arguments["scene_name"] ?? ""
            guard let jointType = JointType(rawValue: jointTypeStr) else {
                return "Invalid joint_type '\(jointTypeStr)'. Valid: pin, spring, sliding, fixed, limit"
            }
            guard !nodeA.isEmpty, !nodeB.isEmpty else {
                return "add_joint_to_scene: node_a and node_b are required"
            }
            guard let partIdx = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }
            var anchorA: PointSpec?
            if let ax = arguments["anchor_a_x"], let ay = arguments["anchor_a_y"],
               let axv = Double(ax), let ayv = Double(ay) {
                anchorA = PointSpec(x: axv, y: ayv)
            }
            var anchorB: PointSpec?
            if let bx = arguments["anchor_b_x"], let by = arguments["anchor_b_y"],
               let bxv = Double(bx), let byv = Double(by) {
                anchorB = PointSpec(x: bxv, y: byv)
            }
            let springFreq: Double? = arguments["spring_frequency"].flatMap { Double($0) }
            let springDamp: Double? = arguments["spring_damping"].flatMap { Double($0) }
            let joint = JointSpec(
                jointType: jointType,
                nodeA: nodeA,
                nodeB: nodeB,
                anchorA: anchorA,
                anchorB: anchorB,
                springFrequency: springFreq,
                springDamping: springDamp
            )
            let result = appendSceneChild(
                partIndex: partIdx,
                requestedSceneName: requestedSceneName,
                areaName: areaName,
                document: &document
            ) { scene in
                scene.joints.append(joint)
            }
            switch result {
            case .success(let sceneName):
                return "Added \(jointType.rawValue) joint '\(nodeA)' <-> '\(nodeB)' to scene '\(sceneName)' in '\(areaName)'"
            case .failure(let msg):
                return msg
            }

        case "add_constraint_to_scene":
            let areaName = arguments["sprite_area_name"] ?? ""
            let typeStr = arguments["constraint_type"] ?? ""
            let sourceNode = arguments["source_node"] ?? ""
            let targetNode = arguments["target_node"] ?? ""
            let requestedSceneName = arguments["scene_name"] ?? ""
            guard let constraintType = SceneConstraintType(rawValue: typeStr) else {
                return "Invalid constraint_type '\(typeStr)'. Valid: distance, orient, position"
            }
            guard !sourceNode.isEmpty, !targetNode.isEmpty else {
                return "add_constraint_to_scene: source_node and target_node are required"
            }
            guard let partIdx = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }
            let minDistance: Double? = arguments["min_distance"].flatMap { Double($0) }
            let maxDistance: Double? = arguments["max_distance"].flatMap { Double($0) }
            let constraint = SceneConstraintSpec(
                constraintType: constraintType,
                sourceNode: sourceNode,
                targetNode: targetNode,
                minDistance: minDistance,
                maxDistance: maxDistance
            )
            let result = appendSceneChild(
                partIndex: partIdx,
                requestedSceneName: requestedSceneName,
                areaName: areaName,
                document: &document
            ) { scene in
                scene.sceneConstraints.append(constraint)
            }
            switch result {
            case .success(let sceneName):
                return "Added \(constraintType.rawValue) constraint '\(sourceNode)' -> '\(targetNode)' to scene '\(sceneName)' in '\(areaName)'"
            case .failure(let msg):
                return msg
            }

        case "add_physics_field_to_scene":
            let areaName = arguments["sprite_area_name"] ?? ""
            let typeStr = arguments["field_type"] ?? ""
            let requestedSceneName = arguments["scene_name"] ?? ""
            guard let fieldType = FieldType(rawValue: typeStr) else {
                return "Invalid field_type '\(typeStr)'. Valid: linearGravity, radialGravity, vortex, noise, turbulence, spring, drag, electric, magnetic"
            }
            guard let strengthStr = arguments["strength"], let strength = Double(strengthStr) else {
                return "add_physics_field_to_scene: strength is required"
            }
            guard let partIdx = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }
            var region: SizeSpec?
            if let rw = arguments["region_width"], let rh = arguments["region_height"],
               let rwv = Double(rw), let rhv = Double(rh) {
                region = SizeSpec(width: rwv, height: rhv)
            }
            var direction: PointSpec?
            if let dx = arguments["direction_x"], let dy = arguments["direction_y"],
               let dxv = Double(dx), let dyv = Double(dy) {
                direction = PointSpec(x: dxv, y: dyv)
            }
            let field = FieldSpec(
                fieldType: fieldType,
                strength: strength,
                region: region,
                direction: direction
            )
            let result = appendSceneChild(
                partIndex: partIdx,
                requestedSceneName: requestedSceneName,
                areaName: areaName,
                document: &document
            ) { scene in
                scene.fields.append(field)
            }
            switch result {
            case .success(let sceneName):
                return "Added \(fieldType.rawValue) field (strength=\(strength)) to scene '\(sceneName)' in '\(areaName)'"
            case .failure(let msg):
                return msg
            }

        case "create_image":
            let place = placement(arguments: arguments, currentCardId: currentCardId, document: document)
            var part = Part(
                partType: .image,
                cardId: place.cardId,
                backgroundId: place.backgroundId,
                name: arguments["name"] ?? "Image",
                left: Double(arguments["left"] ?? "100") ?? 100,
                top: Double(arguments["top"] ?? "100") ?? 100,
                width: Double(arguments["width"] ?? "200") ?? 200,
                height: Double(arguments["height"] ?? "200") ?? 200
            )
            var source = ""
            if let path = arguments["file_path"], !path.isEmpty {
                if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                    part.imageData = data
                    source = " from file '\(path)'"
                } else {
                    return "Could not read image file at '\(path)'"
                }
            } else if let assetName = arguments["asset_name"], !assetName.isEmpty {
                guard let asset = document.spriteRepository.asset(byName: assetName) else {
                    return "Asset '\(assetName)' not found in repository"
                }
                part.imageData = asset.data
                source = " from asset '\(assetName)'"
            }
            document.addPart(part)
            let layer = place.backgroundId != nil ? " on background" : ""
            return "Created image '\(part.name)'\(layer)\(source)"

        // MARK: - Scene-node setters

        case "set_node_property":
            let areaName = arguments["sprite_area_name"] ?? ""
            let nodeName = arguments["node_name"] ?? ""
            let property = arguments["property"] ?? ""
            let value = arguments["value"] ?? ""
            let requestedSceneName = arguments["scene_name"] ?? ""
            guard let partIdx = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }
            guard !property.isEmpty else {
                return "set_node_property: property is required"
            }
            var resolvedSceneName = ""
            var nodeFoundFlag = false
            var sceneFoundFlag = false
            modifySpriteAreaSpec(partIndex: partIdx, document: &document) { areaSpec in
                let sceneIdx: Int?
                if !requestedSceneName.isEmpty {
                    sceneIdx = areaSpec.scenes.firstIndex { $0.scene.name.lowercased() == requestedSceneName.lowercased() }
                } else if let entry = areaSpec.activeSceneEntry {
                    sceneIdx = areaSpec.scenes.firstIndex { $0.id == entry.id }
                } else {
                    sceneIdx = nil
                }
                guard let idx = sceneIdx else { return }
                sceneFoundFlag = true
                guard let nodeFound = areaSpec.scenes[idx].scene.node(named: nodeName) else {
                    return
                }
                nodeFoundFlag = true
                _ = areaSpec.scenes[idx].scene.updateNode(id: nodeFound.id) { node in
                    applyNodeProperty(&node, property: property, value: value)
                }
                if areaSpec.scenes[idx].id == areaSpec.activeSceneID {
                    areaSpec.setActiveScene(areaSpec.scenes[idx].scene)
                }
                resolvedSceneName = areaSpec.scenes[idx].scene.name
            }
            if !sceneFoundFlag {
                return !requestedSceneName.isEmpty
                    ? "Scene '\(requestedSceneName)' not found in sprite area '\(areaName)'"
                    : "Sprite area '\(areaName)' has no active scene"
            }
            if !nodeFoundFlag {
                return "Node '\(nodeName)' not found in '\(areaName)'"
            }
            return "Set \(property) of '\(nodeName)' in scene '\(resolvedSceneName)' of '\(areaName)' to '\(value)'"

        case "set_node_script":
            let areaName = arguments["sprite_area_name"] ?? ""
            let nodeName = arguments["node_name"] ?? ""
            let rawScript = arguments["script"] ?? ""
            let requestedSceneName = arguments["scene_name"] ?? ""
            let wrapped = wrapScript(rawScript)
            if let refusal = refusalForInvalidDraft(
                toolName: toolName,
                arguments: arguments,
                targetDescription: "node '\(nodeName)' in sprite area '\(areaName)'",
                rawScript: rawScript,
                wrappedScript: wrapped,
                document: document,
                currentCardId: currentCardId
            ) {
                return refusal.encodedSentinel()
            }
            guard let partIdx = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }
            var resolvedSceneName = ""
            var nodeFoundFlag = false
            var sceneFoundFlag = false
            modifySpriteAreaSpec(partIndex: partIdx, document: &document) { areaSpec in
                let sceneIdx: Int?
                if !requestedSceneName.isEmpty {
                    sceneIdx = areaSpec.scenes.firstIndex { $0.scene.name.lowercased() == requestedSceneName.lowercased() }
                } else if let entry = areaSpec.activeSceneEntry {
                    sceneIdx = areaSpec.scenes.firstIndex { $0.id == entry.id }
                } else {
                    sceneIdx = nil
                }
                guard let idx = sceneIdx else { return }
                sceneFoundFlag = true
                guard let nodeFound = areaSpec.scenes[idx].scene.node(named: nodeName) else {
                    return
                }
                nodeFoundFlag = true
                _ = areaSpec.scenes[idx].scene.updateNode(id: nodeFound.id) { n in
                    n.script = wrapped
                }
                if areaSpec.scenes[idx].id == areaSpec.activeSceneID {
                    areaSpec.setActiveScene(areaSpec.scenes[idx].scene)
                }
                resolvedSceneName = areaSpec.scenes[idx].scene.name
            }
            if !sceneFoundFlag {
                return !requestedSceneName.isEmpty
                    ? "Scene '\(requestedSceneName)' not found in sprite area '\(areaName)'"
                    : "Sprite area '\(areaName)' has no active scene"
            }
            if !nodeFoundFlag {
                return "Node '\(nodeName)' not found in '\(areaName)'"
            }
            return "Set script of '\(nodeName)' in scene '\(resolvedSceneName)' of '\(areaName)'"

        case "set_physics_body":
            let areaName = arguments["sprite_area_name"] ?? ""
            let nodeName = arguments["node_name"] ?? ""
            let requestedSceneName = arguments["scene_name"] ?? ""
            guard let partIdx = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }
            var resolvedSceneName = ""
            var nodeFoundFlag = false
            var sceneFoundFlag = false
            modifySpriteAreaSpec(partIndex: partIdx, document: &document) { areaSpec in
                let sceneIdx: Int?
                if !requestedSceneName.isEmpty {
                    sceneIdx = areaSpec.scenes.firstIndex { $0.scene.name.lowercased() == requestedSceneName.lowercased() }
                } else if let entry = areaSpec.activeSceneEntry {
                    sceneIdx = areaSpec.scenes.firstIndex { $0.id == entry.id }
                } else {
                    sceneIdx = nil
                }
                guard let idx = sceneIdx else { return }
                sceneFoundFlag = true
                guard let nodeFound = areaSpec.scenes[idx].scene.node(named: nodeName) else {
                    return
                }
                nodeFoundFlag = true
                _ = areaSpec.scenes[idx].scene.updateNode(id: nodeFound.id) { n in
                    var body = n.physicsBody ?? PhysicsBodySpec()
                    if let bt = arguments["body_type"], let bodyType = PhysicsBodyType(rawValue: bt) {
                        body.bodyType = bodyType
                    }
                    if let dyn = arguments["is_dynamic"] {
                        body.isDynamic = (dyn.lowercased() == "true")
                    }
                    if let r = arguments["restitution"], let v = Double(r) {
                        body.restitution = v
                    }
                    if let f = arguments["friction"], let v = Double(f) {
                        body.friction = v
                    }
                    if let m = arguments["mass"], let v = Double(m) {
                        body.mass = v
                    }
                    if let g = arguments["affected_by_gravity"] {
                        body.affectedByGravity = (g.lowercased() == "true")
                    }
                    if let ar = arguments["allows_rotation"] {
                        body.allowsRotation = (ar.lowercased() == "true")
                    }
                    if let vx = arguments["velocity_x"], let v = Double(vx) {
                        body.velocityX = v
                    }
                    if let vy = arguments["velocity_y"], let v = Double(vy) {
                        body.velocityY = v
                    }
                    n.physicsBody = body
                }
                if areaSpec.scenes[idx].id == areaSpec.activeSceneID {
                    areaSpec.setActiveScene(areaSpec.scenes[idx].scene)
                }
                resolvedSceneName = areaSpec.scenes[idx].scene.name
            }
            if !sceneFoundFlag {
                return !requestedSceneName.isEmpty
                    ? "Scene '\(requestedSceneName)' not found in sprite area '\(areaName)'"
                    : "Sprite area '\(areaName)' has no active scene"
            }
            if !nodeFoundFlag {
                return "Node '\(nodeName)' not found in '\(areaName)'"
            }
            return "Configured physics body on '\(nodeName)' in scene '\(resolvedSceneName)' of '\(areaName)'"

        case "delete_scene_node":
            let areaName = arguments["sprite_area_name"] ?? ""
            let nodeName = arguments["node_name"] ?? ""
            let requestedSceneName = arguments["scene_name"] ?? ""
            guard let partIdx = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }
            var resolvedSceneName = ""
            var nodeFoundFlag = false
            var sceneFoundFlag = false
            modifySpriteAreaSpec(partIndex: partIdx, document: &document) { areaSpec in
                let sceneIdx: Int?
                if !requestedSceneName.isEmpty {
                    sceneIdx = areaSpec.scenes.firstIndex { $0.scene.name.lowercased() == requestedSceneName.lowercased() }
                } else if let entry = areaSpec.activeSceneEntry {
                    sceneIdx = areaSpec.scenes.firstIndex { $0.id == entry.id }
                } else {
                    sceneIdx = nil
                }
                guard let idx = sceneIdx else { return }
                sceneFoundFlag = true
                guard let nodeFound = areaSpec.scenes[idx].scene.node(named: nodeName) else {
                    return
                }
                nodeFoundFlag = true
                _ = areaSpec.scenes[idx].scene.removeNode(id: nodeFound.id)
                if areaSpec.scenes[idx].id == areaSpec.activeSceneID {
                    areaSpec.setActiveScene(areaSpec.scenes[idx].scene)
                }
                resolvedSceneName = areaSpec.scenes[idx].scene.name
            }
            if !sceneFoundFlag {
                return !requestedSceneName.isEmpty
                    ? "Scene '\(requestedSceneName)' not found in sprite area '\(areaName)'"
                    : "Sprite area '\(areaName)' has no active scene"
            }
            if !nodeFoundFlag {
                return "Node '\(nodeName)' not found in '\(areaName)'"
            }
            return "Deleted node '\(nodeName)' from scene '\(resolvedSceneName)' of '\(areaName)'"

        // MARK: - Actions

        case "add_action":
            let areaName = arguments["sprite_area_name"] ?? ""
            let nodeName = arguments["node_name"] ?? ""
            let actionTypeStr = arguments["action_type"] ?? ""
            let requestedSceneName = arguments["scene_name"] ?? ""
            guard let actionType = ActionType(rawValue: actionTypeStr) else {
                let valid = "moveTo, moveBy, rotateTo, rotateBy, scaleTo, scaleBy, fadeTo, fadeIn, fadeOut, sequence, group, repeatForever, repeatCount, wait, removeFromParent, followPath, setTexture, animate, playAudio, stopAudio, changeVolume, resize, hide, unhide, colorize, speedTo, speedBy"
                return "Invalid action_type '\(actionTypeStr)'. Valid: \(valid)"
            }
            guard let partIdx = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }
            let duration = Double(arguments["duration"] ?? "0.25") ?? 0.25
            let actionName = arguments["name"] ?? ""
            var parameters: [String: String] = [:]
            if let json = arguments["parameters_json"], !json.isEmpty,
               let data = json.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for (k, v) in dict {
                    if let str = v as? String {
                        parameters[k] = str
                    } else if let num = v as? NSNumber {
                        parameters[k] = num.stringValue
                    } else if let bool = v as? Bool {
                        parameters[k] = bool ? "true" : "false"
                    } else {
                        parameters[k] = String(describing: v)
                    }
                }
            }
            let action = ActionSpec(
                actionType: actionType,
                name: actionName,
                duration: duration,
                parameters: parameters,
                children: nil
            )
            var resolvedSceneName = ""
            var nodeFoundFlag = false
            var sceneFoundFlag = false
            modifySpriteAreaSpec(partIndex: partIdx, document: &document) { areaSpec in
                let sceneIdx: Int?
                if !requestedSceneName.isEmpty {
                    sceneIdx = areaSpec.scenes.firstIndex { $0.scene.name.lowercased() == requestedSceneName.lowercased() }
                } else if let entry = areaSpec.activeSceneEntry {
                    sceneIdx = areaSpec.scenes.firstIndex { $0.id == entry.id }
                } else {
                    sceneIdx = nil
                }
                guard let idx = sceneIdx else { return }
                sceneFoundFlag = true
                guard let nodeFound = areaSpec.scenes[idx].scene.node(named: nodeName) else {
                    return
                }
                nodeFoundFlag = true
                _ = areaSpec.scenes[idx].scene.updateNode(id: nodeFound.id) { n in
                    n.actions.append(action)
                }
                if areaSpec.scenes[idx].id == areaSpec.activeSceneID {
                    areaSpec.setActiveScene(areaSpec.scenes[idx].scene)
                }
                resolvedSceneName = areaSpec.scenes[idx].scene.name
            }
            if !sceneFoundFlag {
                return !requestedSceneName.isEmpty
                    ? "Scene '\(requestedSceneName)' not found in sprite area '\(areaName)'"
                    : "Sprite area '\(areaName)' has no active scene"
            }
            if !nodeFoundFlag {
                return "Node '\(nodeName)' not found in '\(areaName)'"
            }
            return "Added \(actionType.rawValue) action (duration=\(duration)) to '\(nodeName)' in scene '\(resolvedSceneName)' of '\(areaName)'"

        case "remove_all_actions":
            let areaName = arguments["sprite_area_name"] ?? ""
            let nodeName = arguments["node_name"] ?? ""
            let requestedSceneName = arguments["scene_name"] ?? ""
            guard let partIdx = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }
            var resolvedSceneName = ""
            var nodeFoundFlag = false
            var sceneFoundFlag = false
            var removedCount = 0
            modifySpriteAreaSpec(partIndex: partIdx, document: &document) { areaSpec in
                let sceneIdx: Int?
                if !requestedSceneName.isEmpty {
                    sceneIdx = areaSpec.scenes.firstIndex { $0.scene.name.lowercased() == requestedSceneName.lowercased() }
                } else if let entry = areaSpec.activeSceneEntry {
                    sceneIdx = areaSpec.scenes.firstIndex { $0.id == entry.id }
                } else {
                    sceneIdx = nil
                }
                guard let idx = sceneIdx else { return }
                sceneFoundFlag = true
                guard let nodeFound = areaSpec.scenes[idx].scene.node(named: nodeName) else {
                    return
                }
                nodeFoundFlag = true
                removedCount = nodeFound.actions.count
                _ = areaSpec.scenes[idx].scene.updateNode(id: nodeFound.id) { n in
                    n.actions = []
                }
                if areaSpec.scenes[idx].id == areaSpec.activeSceneID {
                    areaSpec.setActiveScene(areaSpec.scenes[idx].scene)
                }
                resolvedSceneName = areaSpec.scenes[idx].scene.name
            }
            if !sceneFoundFlag {
                return !requestedSceneName.isEmpty
                    ? "Scene '\(requestedSceneName)' not found in sprite area '\(areaName)'"
                    : "Sprite area '\(areaName)' has no active scene"
            }
            if !nodeFoundFlag {
                return "Node '\(nodeName)' not found in '\(areaName)'"
            }
            return "Removed \(removedCount) action(s) from '\(nodeName)' in scene '\(resolvedSceneName)' of '\(areaName)'"

        // MARK: - Stack / card / background admin

        case "set_stack_property":
            let property = arguments["property"] ?? ""
            let value = arguments["value"] ?? ""
            switch property.lowercased() {
            case "width":
                guard let w = Double(value) else {
                    return "Invalid value for width: '\(value)' (expected a number)"
                }
                document.stack.width = Int(w)
            case "height":
                guard let h = Double(value) else {
                    return "Invalid value for height: '\(value)' (expected a number)"
                }
                document.stack.height = Int(h)
            case "name":
                document.stack.name = value
            case "defaultfont", "default_font":
                document.stack.defaultFont = value
            case "webassetsallowed", "web_assets_allowed":
                document.stack.webAssetsAllowed = (value.lowercased() == "true")
            default:
                return "Unknown stack property '\(property)'. Valid: width, height, name, defaultFont, webAssetsAllowed"
            }
            return "Set \(property) of stack to \(value)"

        case "set_card_property":
            let cardName = arguments["card_name"] ?? ""
            let property = arguments["property"] ?? ""
            let value = arguments["value"] ?? ""
            guard let idx = cardIndex(named: cardName, currentCardId: currentCardId, in: document) else {
                return cardName.isEmpty ? "No current card" : "Card '\(cardName)' not found"
            }
            switch property.lowercased() {
            case "name":
                document.cards[idx].name = value
            case "marked":
                document.cards[idx].marked = (value.lowercased() == "true")
            case "sortkey", "sort_key":
                document.cards[idx].sortKey = value
            case "background", "backgroundname", "background_name":
                guard let background = document.backgroundByName(value) else {
                    return "Background '\(value)' not found"
                }
                document.cards[idx].backgroundId = background.id
            case "script":
                let wrapped = wrapScript(value)
                document.cards[idx].script = wrapped
                let suffix = scriptParseErrorSuffix(wrapped)
                let displayName = document.cards[idx].name.isEmpty ? "current card" : "card '\(document.cards[idx].name)'"
                return "Set script of \(displayName)\(suffix)"
            case "theme":
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                document.cards[idx].themeName = trimmed.isEmpty ? nil : trimmed
            default:
                return "Unknown card property '\(property)'. Valid: name, marked, sortKey, backgroundName, script, theme"
            }
            let displayName = document.cards[idx].name.isEmpty ? "current card" : "card '\(document.cards[idx].name)'"
            return "Set \(property) of \(displayName) to \(value)"

        case "set_background_property":
            let bgName = arguments["background_name"] ?? ""
            let property = arguments["property"] ?? ""
            let value = arguments["value"] ?? ""
            guard let idx = backgroundIndex(named: bgName, currentCardId: currentCardId, in: document) else {
                return bgName.isEmpty ? "No current background" : "Background '\(bgName)' not found"
            }
            switch property.lowercased() {
            case "name":
                document.backgrounds[idx].name = value
            case "sortkey", "sort_key":
                document.backgrounds[idx].sortKey = value
            case "script":
                let wrapped = wrapScript(value)
                document.backgrounds[idx].script = wrapped
                let suffix = scriptParseErrorSuffix(wrapped)
                return "Set script of background '\(document.backgrounds[idx].name)'\(suffix)"
            case "theme":
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                document.backgrounds[idx].themeName = trimmed.isEmpty ? nil : trimmed
            default:
                return "Unknown background property '\(property)'. Valid: name, sortKey, script, theme"
            }
            return "Set \(property) of background '\(document.backgrounds[idx].name)' to \(value)"

        case "set_card_name":
            let newName = arguments["new_name"] ?? ""
            guard !newName.isEmpty else {
                return "set_card_name: new_name is required"
            }
            let cardName = arguments["card_name"] ?? ""
            guard let idx = cardIndex(named: cardName, currentCardId: currentCardId, in: document) else {
                return "Card '\(cardName)' not found"
            }
            let oldName = document.cards[idx].name
            document.cards[idx].name = newName
            let oldDisplay = oldName.isEmpty ? "(unnamed)" : oldName
            return "Renamed card '\(oldDisplay)' to '\(newName)'"

        case "set_background_name":
            let bgName = arguments["background_name"] ?? ""
            let newName = arguments["new_name"] ?? ""
            guard !newName.isEmpty else {
                return "set_background_name: new_name is required"
            }
            guard let idx = backgroundIndex(named: bgName, currentCardId: currentCardId, in: document) else {
                return "Background '\(bgName)' not found"
            }
            let oldName = document.backgrounds[idx].name
            document.backgrounds[idx].name = newName
            return "Renamed background '\(oldName)' to '\(newName)'"

        case "set_card_background":
            let bgName = arguments["background_name"] ?? ""
            guard !bgName.isEmpty else {
                return "set_card_background: background_name is required"
            }
            guard let bg = document.backgroundByName(bgName) else {
                return "Background '\(bgName)' not found"
            }
            let cardName = arguments["card_name"] ?? ""
            guard let idx = cardIndex(named: cardName, currentCardId: currentCardId, in: document) else {
                return "Card '\(cardName)' not found"
            }
            document.cards[idx].backgroundId = bg.id
            let cardDisplay = document.cards[idx].name.isEmpty ? "Card \(idx + 1)" : document.cards[idx].name
            return "Card '\(cardDisplay)' now uses background '\(bg.name)'"

        case "reorder_card":
            let cardName = arguments["card_name"] ?? ""
            let posStr = arguments["new_position"] ?? ""
            guard !cardName.isEmpty else {
                return "reorder_card: card_name is required"
            }
            guard let requestedPos = Int(posStr), requestedPos >= 1 else {
                return "Invalid new_position '\(posStr)' (expected 1-based integer)"
            }
            // Work against the sortKey-ordered view so the user's
            // 1-based index lines up with the visible card order.
            let ordered = document.sortedCards
            guard let currentSortedIdx = ordered.firstIndex(where: { $0.name.lowercased() == cardName.lowercased() }) else {
                return "Card '\(cardName)' not found"
            }
            let movedCard = ordered[currentSortedIdx]
            var reordered = ordered
            reordered.remove(at: currentSortedIdx)
            let clamped = max(0, min(requestedPos - 1, reordered.count))
            reordered.insert(movedCard, at: clamped)
            // Rebuild sortKeys using the same formatting pattern as
            // addCard so the new ordering is stable and round-trips
            // through encode/decode unchanged.
            for (i, card) in reordered.enumerated() {
                if let srcIdx = document.cards.firstIndex(where: { $0.id == card.id }) {
                    document.cards[srcIdx].sortKey = String(format: "a%06d", i)
                }
            }
            return "Moved card '\(cardName)' to position \(clamped + 1)"

        case "duplicate_part":
            let partName = arguments["part_name"] ?? ""
            guard !partName.isEmpty else {
                return "duplicate_part: part_name is required"
            }
            guard let originalIdx = scopedPartIndex(named: partName, currentCardId: currentCardId, in: document) else {
                return "Part '\(partName)' not found"
            }
            let dx = Double(arguments["dx"] ?? "20") ?? 20
            let dy = Double(arguments["dy"] ?? "20") ?? 20
            let requestedName = arguments["new_name"] ?? ""
            let original = document.parts[originalIdx]
            var copy = original
            copy.id = UUID()
            copy.name = requestedName.isEmpty ? "\(original.name) 2" : requestedName
            copy.left = original.left + dx
            copy.top = original.top + dy
            document.addPart(copy)
            return "Duplicated '\(original.name)' as '\(copy.name)'"

        // MARK: - Scene-level admin

        case "set_scene_property":
            let areaName = arguments["sprite_area_name"] ?? ""
            let property = arguments["property"] ?? ""
            let value = arguments["value"] ?? ""
            let requestedSceneName = arguments["scene_name"] ?? ""
            guard let partIdx = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }
            // Apply the property change to either the named scene (via
            // modifySpriteAreaSpec) or the active scene (via modifyActiveScene).
            // Return a specific error string if the value fails to parse,
            // but let the mutation succeed silently when it applies cleanly.
            var applyError: String?
            let applyProperty: (inout SceneSpec) -> Void = { scene in
                switch property.lowercased() {
                case "gravity":
                    let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    guard parts.count == 2, let dx = Double(parts[0]), let dy = Double(parts[1]) else {
                        applyError = "Invalid gravity '\(value)' (expected 'dx,dy')"
                        return
                    }
                    scene.gravity = VectorSpec(dx: dx, dy: dy)
                case "backgroundcolor", "background_color":
                    scene.backgroundColor = value
                case "ispaused", "is_paused":
                    scene.isPaused = (value.lowercased() == "true")
                case "showsphysics", "shows_physics":
                    scene.showsPhysics = (value.lowercased() == "true")
                case "showsfps", "shows_fps":
                    scene.showsFPS = (value.lowercased() == "true")
                case "showsnodecount", "shows_node_count":
                    scene.showsNodeCount = (value.lowercased() == "true")
                case "scalemode", "scale_mode":
                    guard let mode = SceneScaleMode(rawValue: value) else {
                        applyError = "Invalid scaleMode '\(value)'. Valid: fill, aspectFill, aspectFit, resizeFill"
                        return
                    }
                    scene.scaleMode = mode
                case "size":
                    let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    guard parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]) else {
                        applyError = "Invalid size '\(value)' (expected 'w,h')"
                        return
                    }
                    scene.size = SizeSpec(width: w, height: h)
                case "name":
                    scene.name = value
                default:
                    applyError = "Unknown scene property '\(property)'. Valid: gravity, backgroundColor, isPaused, showsPhysics, showsFPS, showsNodeCount, scaleMode, size, name"
                }
            }

            var resolvedSceneName = ""
            var sceneFound = false
            if requestedSceneName.isEmpty {
                modifySpriteAreaSpec(partIndex: partIdx, document: &document) { areaSpec in
                    guard let entry = areaSpec.activeSceneEntry,
                          let sceneIdx = areaSpec.scenes.firstIndex(where: { $0.id == entry.id })
                    else { return }
                    sceneFound = true
                    applyProperty(&areaSpec.scenes[sceneIdx].scene)
                    if applyError == nil, areaSpec.scenes[sceneIdx].id == areaSpec.activeSceneID {
                        areaSpec.setActiveScene(areaSpec.scenes[sceneIdx].scene)
                    }
                    resolvedSceneName = areaSpec.scenes[sceneIdx].scene.name
                }
                if !sceneFound {
                    return "Sprite area '\(areaName)' has no active scene"
                }
            } else {
                modifySpriteAreaSpec(partIndex: partIdx, document: &document) { areaSpec in
                    guard let sceneIdx = areaSpec.scenes.firstIndex(where: {
                        $0.scene.name.lowercased() == requestedSceneName.lowercased()
                    }) else { return }
                    sceneFound = true
                    applyProperty(&areaSpec.scenes[sceneIdx].scene)
                    if applyError == nil, areaSpec.scenes[sceneIdx].id == areaSpec.activeSceneID {
                        areaSpec.setActiveScene(areaSpec.scenes[sceneIdx].scene)
                    }
                    resolvedSceneName = areaSpec.scenes[sceneIdx].scene.name
                }
                if !sceneFound {
                    return "Scene '\(requestedSceneName)' not found in sprite area '\(areaName)'"
                }
            }
            if let err = applyError {
                return err
            }
            return "Set \(property) of scene '\(resolvedSceneName)' in sprite area '\(areaName)' to \(value)"

        case "add_scene":
            let areaName = arguments["sprite_area_name"] ?? ""
            let sceneName = arguments["scene_name"] ?? ""
            guard !sceneName.isEmpty else {
                return "add_scene: scene_name is required"
            }
            let activate = (arguments["activate"] ?? "").lowercased() == "true"
            guard let partIdx = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }
            var duplicate = false
            var addedName = sceneName
            modifySpriteAreaSpec(partIndex: partIdx, document: &document) { areaSpec in
                if areaSpec.scenes.contains(where: { $0.scene.name.lowercased() == sceneName.lowercased() }) {
                    duplicate = true
                    return
                }
                // Preserve the area's current design size so the new
                // scene opens at the same dimensions as its siblings.
                let newScene = SceneSpec(
                    name: sceneName,
                    size: areaSpec.designSize,
                    scaleMode: areaSpec.scaleMode
                )
                let entry = SpriteAreaScene(scene: newScene)
                areaSpec.scenes.append(entry)
                addedName = newScene.name
                if activate {
                    areaSpec.setActiveScene(newScene)
                    areaSpec.activeSceneID = entry.id
                }
            }
            if duplicate {
                return "Scene '\(sceneName)' already exists in sprite area '\(areaName)'"
            }
            return "Added scene '\(addedName)' to '\(areaName)'\(activate ? " (activated)" : "")"

        case "delete_scene":
            let areaName = arguments["sprite_area_name"] ?? ""
            let sceneName = arguments["scene_name"] ?? ""
            guard !sceneName.isEmpty else {
                return "delete_scene: scene_name is required"
            }
            guard let partIdx = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }
            var sceneFound = false
            var isOnlyScene = false
            var removedName = sceneName
            modifySpriteAreaSpec(partIndex: partIdx, document: &document) { areaSpec in
                guard let sceneIdx = areaSpec.scenes.firstIndex(where: {
                    $0.scene.name.lowercased() == sceneName.lowercased()
                }) else { return }
                sceneFound = true
                if areaSpec.scenes.count <= 1 {
                    isOnlyScene = true
                    return
                }
                let removedId = areaSpec.scenes[sceneIdx].id
                removedName = areaSpec.scenes[sceneIdx].scene.name
                areaSpec.scenes.remove(at: sceneIdx)
                // If we just removed the active scene, activate the
                // first remaining one so the area never has a stale
                // activeSceneID pointing at nothing.
                if areaSpec.activeSceneID == removedId, let firstRemaining = areaSpec.scenes.first {
                    areaSpec.activeSceneID = firstRemaining.id
                    areaSpec.setActiveScene(firstRemaining.scene)
                }
            }
            if !sceneFound {
                return "Scene '\(sceneName)' not found in sprite area '\(areaName)'"
            }
            if isOnlyScene {
                return "Cannot delete scene '\(sceneName)' — it is the only scene in sprite area '\(areaName)'"
            }
            return "Deleted scene '\(removedName)' from sprite area '\(areaName)'"

        case "rename_scene":
            let areaName = arguments["sprite_area_name"] ?? ""
            let sceneName = arguments["scene_name"] ?? ""
            let newName = arguments["new_name"] ?? ""
            guard !sceneName.isEmpty, !newName.isEmpty else {
                return "rename_scene: scene_name and new_name are required"
            }
            guard let partIdx = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }
            var sceneFound = false
            var duplicate = false
            var oldName = sceneName
            modifySpriteAreaSpec(partIndex: partIdx, document: &document) { areaSpec in
                guard let sceneIdx = areaSpec.scenes.firstIndex(where: {
                    $0.scene.name.lowercased() == sceneName.lowercased()
                }) else { return }
                sceneFound = true
                // Reject a rename that would collide with another
                // existing scene (case-insensitive) so sceneNames
                // stays unique and activateScene(named:) stays sane.
                if areaSpec.scenes.enumerated().contains(where: { pair in
                    pair.offset != sceneIdx && pair.element.scene.name.lowercased() == newName.lowercased()
                }) {
                    duplicate = true
                    return
                }
                oldName = areaSpec.scenes[sceneIdx].scene.name
                areaSpec.scenes[sceneIdx].scene.name = newName
                if areaSpec.scenes[sceneIdx].id == areaSpec.activeSceneID {
                    areaSpec.setActiveScene(areaSpec.scenes[sceneIdx].scene)
                }
            }
            if !sceneFound {
                return "Scene '\(sceneName)' not found in sprite area '\(areaName)'"
            }
            if duplicate {
                return "A scene named '\(newName)' already exists in sprite area '\(areaName)'"
            }
            return "Renamed scene '\(oldName)' to '\(newName)' in sprite area '\(areaName)'"

        case "set_active_scene":
            let areaName = arguments["sprite_area_name"] ?? ""
            let sceneName = arguments["scene_name"] ?? ""
            guard !sceneName.isEmpty else {
                return "set_active_scene: scene_name is required"
            }
            guard let partIdx = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }
            var activated = false
            modifySpriteAreaSpec(partIndex: partIdx, document: &document) { areaSpec in
                activated = areaSpec.activateScene(named: sceneName)
            }
            if !activated {
                return "Scene '\(sceneName)' not found in sprite area '\(areaName)'"
            }
            return "Active scene of '\(areaName)' is now '\(sceneName)'"

        case "list_scenes":
            let areaName = arguments["sprite_area_name"] ?? ""
            guard let partIndex = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }
            let part = document.parts[partIndex]
            guard let areaSpec = part.spriteAreaSpecModel else {
                return "Invalid scene spec in '\(areaName)'"
            }
            if areaSpec.scenes.isEmpty {
                return "Sprite area '\(areaName)' has no scenes"
            }
            var lines: [String] = []
            for entry in areaSpec.scenes {
                let s = entry.scene
                let w = Int(s.size.width)
                let h = Int(s.size.height)
                let marker = entry.id == areaSpec.activeSceneID ? " [active]" : ""
                lines.append("\(s.name): \(w)x\(h)\(marker)")
            }
            return lines.joined(separator: "\n")

        case "list_scene_physics_fields":
            let areaName = arguments["sprite_area_name"] ?? ""
            let requestedSceneName = arguments["scene_name"] ?? ""
            guard let partIndex = spriteAreaIndex(named: areaName, currentCardId: currentCardId, in: document) else {
                return "Sprite area '\(areaName)' not found"
            }
            let part = document.parts[partIndex]
            guard let areaSpec = part.spriteAreaSpecModel else {
                return "Invalid scene spec in '\(areaName)'"
            }
            let scene: SceneSpec
            if requestedSceneName.isEmpty {
                guard let active = areaSpec.activeScene else {
                    return "Sprite area '\(areaName)' has no active scene"
                }
                scene = active
            } else {
                guard let entry = areaSpec.scenes.first(where: {
                    $0.scene.name.lowercased() == requestedSceneName.lowercased()
                }) else {
                    return "Scene '\(requestedSceneName)' not found in sprite area '\(areaName)'"
                }
                scene = entry.scene
            }
            if scene.fields.isEmpty {
                return "Scene '\(scene.name)' in '\(areaName)' has no physics fields"
            }
            let lines = scene.fields.map { "\($0.fieldType.rawValue) strength=\($0.strength)" }
            return lines.joined(separator: "\n")

        // MARK: - Theme + property accessors

        case "list_themes":
            let themes = document.allAvailableThemes
            if themes.isEmpty {
                return "No themes available"
            }
            let lines = themes.map { theme -> String in
                let kind = theme.isBuiltIn ? "built-in" : "user"
                if let basedOn = theme.basedOn, !basedOn.isEmpty {
                    return "\(theme.name) [\(kind), based on \(basedOn)]"
                }
                return "\(theme.name) [\(kind)]"
            }
            return lines.joined(separator: "\n")

        case "create_theme":
            let baseName = arguments["base_theme_name"] ?? ""
            let newName = arguments["new_name"] ?? ""
            let overridesJSON = arguments["overrides_json"] ?? ""
            let trimmedNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedNew.isEmpty else {
                return "create_theme: new_name is required"
            }
            guard let source = document.theme(named: baseName) else {
                return "Theme '\(baseName)' not found. Use list_themes to see available themes."
            }
            // Collision check against both built-ins and user themes.
            if let existing = document.theme(named: trimmedNew) {
                let kind = existing.isBuiltIn ? "built-in" : "user"
                return "Theme '\(trimmedNew)' already exists (\(kind))"
            }
            var newTheme = source.duplicate(named: trimmedNew)
            var appliedOverrides = 0
            let trimmedOverrides = overridesJSON.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedOverrides.isEmpty {
                guard let data = trimmedOverrides.data(using: .utf8) else {
                    return "create_theme: overrides_json is not valid UTF-8"
                }
                let parsed: Any
                do {
                    parsed = try JSONSerialization.jsonObject(with: data, options: [])
                } catch {
                    return "create_theme: failed to parse overrides_json: \(error.localizedDescription)"
                }
                guard let dict = parsed as? [String: Any] else {
                    return "create_theme: overrides_json must be a JSON object"
                }
                for (key, rawValue) in dict {
                    let stringValue: String
                    switch rawValue {
                    case let s as String:
                        stringValue = s
                    case let n as NSNumber:
                        stringValue = n.stringValue
                    case let b as Bool:
                        stringValue = b ? "true" : "false"
                    default:
                        stringValue = String(describing: rawValue)
                    }
                    if applyThemeFieldOverride(&newTheme, key: key, value: stringValue) {
                        appliedOverrides += 1
                    }
                }
            }
            newTheme.isBuiltIn = false
            newTheme.modifiedAt = Date()
            document.themes.append(newTheme)
            if appliedOverrides > 0 {
                return "Created theme '\(trimmedNew)' based on '\(source.name)', with \(appliedOverrides) override(s)"
            }
            return "Created theme '\(trimmedNew)' based on '\(source.name)'"

        case "duplicate_theme":
            let sourceName = arguments["source_theme_name"] ?? ""
            let newName = arguments["new_name"] ?? ""
            let trimmedNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard document.theme(named: sourceName) != nil else {
                return "Theme '\(sourceName)' not found"
            }
            let copy: HypeTheme?
            if trimmedNew.isEmpty {
                copy = document.duplicateTheme(named: sourceName)
            } else {
                if let existing = document.theme(named: trimmedNew) {
                    let kind = existing.isBuiltIn ? "built-in" : "user"
                    return "Theme '\(trimmedNew)' already exists (\(kind))"
                }
                copy = document.duplicateTheme(named: sourceName, candidateName: trimmedNew)
            }
            guard let madeCopy = copy else {
                return "Theme '\(sourceName)' not found"
            }
            return "Duplicated '\(sourceName)' as '\(madeCopy.name)'"

        case "delete_theme":
            let themeName = arguments["theme_name"] ?? ""
            let trimmed = themeName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return "delete_theme: theme_name is required"
            }
            let lower = trimmed.lowercased()
            // Refuse to delete built-ins explicitly so the message
            // matches what the user sees from the Theme Designer.
            if let userTheme = document.themes.first(where: { $0.name.lowercased() == lower }) {
                let usage = document.usageCount(themeName: userTheme.name)
                let removedName = userTheme.name
                guard document.deleteTheme(id: userTheme.id) else {
                    return "Failed to delete theme '\(removedName)'"
                }
                var parts: [String] = []
                if usage.cards > 0 {
                    parts.append("\(usage.cards) card(s)")
                }
                if usage.backgrounds > 0 {
                    parts.append("\(usage.backgrounds) background(s)")
                }
                let cascade: String
                if parts.isEmpty && !usage.isStackDefault {
                    cascade = "no references to clear"
                } else {
                    var fragment = "Cleared references on " + (parts.isEmpty ? "0 card(s), 0 background(s)" : parts.joined(separator: ", "))
                    if usage.isStackDefault {
                        fragment += ", reset stack to System"
                    }
                    cascade = fragment
                }
                return "Deleted '\(removedName)'. \(cascade)."
            }
            if BuiltInThemes.find(named: trimmed) != nil {
                return "Cannot delete built-in theme '\(trimmed)'."
            }
            return "Theme '\(trimmed)' not found"

        case "set_theme_property":
            let themeName = arguments["theme_name"] ?? ""
            let property = arguments["property"] ?? ""
            let value = arguments["value"] ?? ""
            let trimmedName = themeName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else {
                return "set_theme_property: theme_name is required"
            }
            let lower = trimmedName.lowercased()
            if let userTheme = document.themes.first(where: { $0.name.lowercased() == lower }) {
                var recognized = false
                let updated = document.updateTheme(id: userTheme.id) { theme in
                    recognized = applyThemeFieldOverride(&theme, key: property, value: value)
                }
                guard updated else {
                    return "Failed to update theme '\(userTheme.name)' (rename collision or theme missing)"
                }
                if !recognized {
                    return "Unknown theme property '\(property)'"
                }
                return "Set \(property) of theme '\(userTheme.name)' to \(value)"
            }
            if BuiltInThemes.find(named: trimmedName) != nil {
                return "Cannot edit built-in theme '\(trimmedName)'. Use create_theme to clone it first."
            }
            return "Theme '\(trimmedName)' not found"

        // MARK: - Visual capture
        case "capture_card_image":
            let cardName = arguments["card_name"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let purpose = (arguments["purpose"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let remainingHint = Int(arguments["__captures_remaining_hint"] ?? "0") ?? 0

            // CardImageCapturer is @MainActor (because CardRenderer.renderToImage is @MainActor).
            // Hop to the main actor for the render call, then return the sentinel string.
            do {
                let captured = try await MainActor.run {
                    let capturer = CardImageCapturer()
                    return try capturer.capture(
                        cardName: cardName.isEmpty ? nil : cardName,
                        document: document,
                        currentCardId: currentCardId
                    )
                }
                let result = CardCaptureResult(
                    cardId: captured.cardId,
                    cardName: captured.cardName,
                    pixelWidth: captured.pixelWidth,
                    pixelHeight: captured.pixelHeight,
                    imageBase64: captured.imageBase64,
                    purpose: purpose,
                    capturesRemainingHint: remainingHint
                )
                return result.encodedSentinel()
            } catch CardImageCapturer.CaptureError.cardNotFound(let n) {
                return "Card '\(n)' not found"
            } catch CardImageCapturer.CaptureError.noCardLoaded {
                return "No card loaded — capture unavailable"
            } catch CardImageCapturer.CaptureError.imageTooLarge(let bytes) {
                return "Capture image too large after compression (\(bytes) bytes); cannot encode"
            } catch CardImageCapturer.CaptureError.encodingFailed {
                return "Capture encoding failed; cannot produce PNG"
            } catch CardImageCapturer.CaptureError.renderFailed {
                return "Card rendering failed; capture unavailable"
            } catch {
                return "Capture failed: \(error.localizedDescription)"
            }

        default:
            return "Unknown tool: \(toolName)"
        }
    }

    // MARK: - Scene-node helpers

    /// Result returned when mutating a scene within a SpriteAreaSpec.
    /// `success` carries the resolved scene name for the response string;
    /// `failure` carries a pre-formatted error message.
    private enum SceneMutationResult {
        case success(String)
        case failure(String)
    }

    /// Append a node to the target scene (active or named). Returns the
    /// resolved scene name on success, or a pre-formatted error string.
    private func appendNodeToScene(
        node: HypeNodeSpec,
        partIndex: Int,
        requestedSceneName: String,
        areaName: String,
        document: inout HypeDocument
    ) -> SceneMutationResult {
        return appendSceneChild(
            partIndex: partIndex,
            requestedSceneName: requestedSceneName,
            areaName: areaName,
            document: &document
        ) { scene in
            scene.nodes.append(node)
        }
    }

    /// Run `transform` on the active-or-named scene within a sprite area.
    /// Returns the resolved scene name on success, or a pre-formatted
    /// error string when the scene cannot be located.
    private func appendSceneChild(
        partIndex: Int,
        requestedSceneName: String,
        areaName: String,
        document: inout HypeDocument,
        transform: (inout SceneSpec) -> Void
    ) -> SceneMutationResult {
        var resolvedSceneName = ""
        var sceneFoundFlag = false
        modifySpriteAreaSpec(partIndex: partIndex, document: &document) { areaSpec in
            let sceneIdx: Int?
            if !requestedSceneName.isEmpty {
                sceneIdx = areaSpec.scenes.firstIndex {
                    $0.scene.name.lowercased() == requestedSceneName.lowercased()
                }
            } else if let entry = areaSpec.activeSceneEntry {
                sceneIdx = areaSpec.scenes.firstIndex { $0.id == entry.id }
            } else {
                sceneIdx = nil
            }
            guard let idx = sceneIdx else { return }
            sceneFoundFlag = true
            transform(&areaSpec.scenes[idx].scene)
            if areaSpec.scenes[idx].id == areaSpec.activeSceneID {
                areaSpec.setActiveScene(areaSpec.scenes[idx].scene)
            }
            resolvedSceneName = areaSpec.scenes[idx].scene.name
        }
        if !sceneFoundFlag {
            if !requestedSceneName.isEmpty {
                return .failure("Scene '\(requestedSceneName)' not found in sprite area '\(areaName)'")
            }
            return .failure("Sprite area '\(areaName)' has no active scene")
        }
        return .success(resolvedSceneName)
    }

    /// Read a dotted-key property value from a HypeNodeSpec. Mirrors the
    /// write path in `applyNodeProperty` so get/set are symmetric. Returns
    /// the bare value as a string, or an empty string when the property
    /// resolves to nil (e.g. a label's `text` when none is set).
    private func nodePropertyValue(node: HypeNodeSpec, property: String) -> String {
        switch property {
        case "position.x": return String(node.position.x)
        case "position.y": return String(node.position.y)
        case "size.width": return String(node.size?.width ?? 0)
        case "size.height": return String(node.size?.height ?? 0)
        case "rotation": return String(node.rotation)
        case "xScale": return String(node.xScale)
        case "yScale": return String(node.yScale)
        case "alpha": return String(node.alpha)
        case "isHidden": return String(node.isHidden)
        case "zPosition": return String(node.zPosition)
        case "name": return node.name
        case "text": return node.text ?? ""
        case "fontName": return node.fontName ?? ""
        case "fontSize": return node.fontSize.map { String($0) } ?? ""
        case "fontColor": return node.fontColor ?? ""
        case "script":
            let s = node.script
            if s.count > 5000 { return String(s.prefix(5000)) + "\u{2026}[truncated]" }
            return s
        case "shape.shapeType": return node.shapeSpec?.shapeType.rawValue ?? ""
        case "shape.fillColor": return node.shapeSpec?.fillColor ?? ""
        case "shape.strokeColor": return node.shapeSpec?.strokeColor ?? ""
        case "shape.lineWidth": return node.shapeSpec.map { String($0.lineWidth) } ?? ""
        case "shape.cornerRadius": return node.shapeSpec.map { String($0.cornerRadius) } ?? ""
        case "physics.enabled": return String(node.physicsBody != nil)
        case "physics.bodyType": return node.physicsBody?.bodyType.rawValue ?? ""
        case "physics.isDynamic": return node.physicsBody.map { String($0.isDynamic) } ?? ""
        case "physics.restitution": return node.physicsBody.map { String($0.restitution) } ?? ""
        case "physics.friction": return node.physicsBody.map { String($0.friction) } ?? ""
        case "physics.mass": return node.physicsBody?.mass.map { String($0) } ?? ""
        case "physics.affectedByGravity": return node.physicsBody.map { String($0.affectedByGravity) } ?? ""
        case "physics.allowsRotation": return node.physicsBody.map { String($0.allowsRotation) } ?? ""
        case "physics.linearDamping": return node.physicsBody?.linearDamping.map { String($0) } ?? ""
        case "physics.angularDamping": return node.physicsBody?.angularDamping.map { String($0) } ?? ""
        case "physics.velocityX": return node.physicsBody?.velocityX.map { String($0) } ?? ""
        case "physics.velocityY": return node.physicsBody?.velocityY.map { String($0) } ?? ""
        case "physics.angularVelocity": return node.physicsBody?.angularVelocity.map { String($0) } ?? ""
        case "emitter.birthRate": return node.emitterSpec.map { String($0.particleBirthRate) } ?? ""
        case "emitter.lifetime": return node.emitterSpec.map { String($0.particleLifetime) } ?? ""
        case "emitter.particleLifetime": return node.emitterSpec.map { String($0.particleLifetime) } ?? ""
        case "emitter.speed": return node.emitterSpec.map { String($0.particleSpeed) } ?? ""
        case "emitter.emissionAngle": return node.emitterSpec.map { String($0.emissionAngle) } ?? ""
        case "emitter.particleColor": return node.emitterSpec?.particleColor ?? ""
        case "emitter.particleScale": return node.emitterSpec.map { String($0.particleScale) } ?? ""
        case "emitter.particleAlpha": return node.emitterSpec.map { String($0.particleAlpha) } ?? ""
        case "audio.loop": return node.audioLoop.map { String($0) } ?? ""
        case "audio.volume": return node.audioVolume.map { String($0) } ?? ""
        case "audio.autoplay": return node.audioAutoplay.map { String($0) } ?? ""
        case "audio.positional": return node.audioPositional.map { String($0) } ?? ""
        case "video.loop": return node.videoLoop.map { String($0) } ?? ""
        case "video.autoplay": return node.videoAutoplay.map { String($0) } ?? ""
        case "camera.target": return node.cameraTarget ?? ""
        default: return "Unknown property '\(property)'"
        }
    }

    /// Apply a single dotted-key property write to a HypeNodeSpec.
    /// Mirrors SceneDiff.applyProperties (lines 144-242) for shared paths
    /// and extends it with emitter/audio/video/camera fields that
    /// SceneDiff doesn't cover. Unknown keys silently no-op.
    private func applyNodeProperty(_ node: inout HypeNodeSpec, property: String, value: String) {
        switch property {
        case "position.x":
            if let v = Double(value) { node.position.x = v }
        case "position.y":
            if let v = Double(value) { node.position.y = v }
        case "size.width":
            if let v = Double(value) {
                if node.size == nil { node.size = SizeSpec() }
                node.size?.width = v
            }
        case "size.height":
            if let v = Double(value) {
                if node.size == nil { node.size = SizeSpec() }
                node.size?.height = v
            }
        case "rotation":
            if let v = Double(value) { node.rotation = v }
        case "xScale":
            if let v = Double(value) { node.xScale = v }
        case "yScale":
            if let v = Double(value) { node.yScale = v }
        case "alpha":
            if let v = Double(value) { node.alpha = v }
        case "isHidden":
            node.isHidden = (value.lowercased() == "true")
        case "zPosition":
            if let v = Double(value) { node.zPosition = v }
        case "name":
            node.name = value
        case "text":
            node.text = value
        case "fontName":
            node.fontName = value
        case "fontSize":
            if let v = Double(value) { node.fontSize = v }
        case "fontColor":
            node.fontColor = value
        case "script":
            node.script = value
        case "shape.shapeType":
            if node.shapeSpec == nil { node.shapeSpec = ShapeNodeSpec() }
            if let shapeType = SpriteShapeType(rawValue: value) {
                node.shapeSpec?.shapeType = shapeType
            }
        case "shape.fillColor":
            if node.shapeSpec == nil { node.shapeSpec = ShapeNodeSpec() }
            node.shapeSpec?.fillColor = value
        case "shape.strokeColor":
            if node.shapeSpec == nil { node.shapeSpec = ShapeNodeSpec() }
            node.shapeSpec?.strokeColor = value
        case "shape.lineWidth":
            if node.shapeSpec == nil { node.shapeSpec = ShapeNodeSpec() }
            if let v = Double(value) { node.shapeSpec?.lineWidth = v }
        case "shape.cornerRadius":
            if node.shapeSpec == nil { node.shapeSpec = ShapeNodeSpec() }
            if let v = Double(value) { node.shapeSpec?.cornerRadius = v }
        case "physics.enabled":
            if value.lowercased() == "true" {
                if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
            } else {
                node.physicsBody = nil
            }
        case "physics.bodyType":
            if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
            if let bodyType = PhysicsBodyType(rawValue: value) {
                node.physicsBody?.bodyType = bodyType
            }
        case "physics.isDynamic":
            if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
            node.physicsBody?.isDynamic = (value.lowercased() == "true")
        case "physics.restitution":
            if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
            if let v = Double(value) { node.physicsBody?.restitution = v }
        case "physics.friction":
            if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
            if let v = Double(value) { node.physicsBody?.friction = v }
        case "physics.mass":
            if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
            if let v = Double(value) { node.physicsBody?.mass = v }
        case "physics.affectedByGravity":
            if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
            node.physicsBody?.affectedByGravity = (value.lowercased() == "true")
        case "physics.allowsRotation":
            if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
            node.physicsBody?.allowsRotation = (value.lowercased() == "true")
        case "physics.linearDamping":
            if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
            node.physicsBody?.linearDamping = Double(value)
        case "physics.angularDamping":
            if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
            node.physicsBody?.angularDamping = Double(value)
        case "physics.velocityX":
            if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
            node.physicsBody?.velocityX = Double(value)
        case "physics.velocityY":
            if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
            node.physicsBody?.velocityY = Double(value)
        case "physics.angularVelocity":
            if node.physicsBody == nil { node.physicsBody = PhysicsBodySpec() }
            node.physicsBody?.angularVelocity = Double(value)
        case "emitter.birthRate":
            if node.emitterSpec == nil { node.emitterSpec = EmitterSpec() }
            if let v = Double(value) { node.emitterSpec?.particleBirthRate = v }
        case "emitter.lifetime", "emitter.particleLifetime":
            if node.emitterSpec == nil { node.emitterSpec = EmitterSpec() }
            if let v = Double(value) { node.emitterSpec?.particleLifetime = v }
        case "emitter.speed":
            if node.emitterSpec == nil { node.emitterSpec = EmitterSpec() }
            if let v = Double(value) { node.emitterSpec?.particleSpeed = v }
        case "emitter.emissionAngle":
            if node.emitterSpec == nil { node.emitterSpec = EmitterSpec() }
            if let v = Double(value) { node.emitterSpec?.emissionAngle = v }
        case "emitter.particleColor":
            if node.emitterSpec == nil { node.emitterSpec = EmitterSpec() }
            node.emitterSpec?.particleColor = value
        case "emitter.particleScale":
            if node.emitterSpec == nil { node.emitterSpec = EmitterSpec() }
            if let v = Double(value) { node.emitterSpec?.particleScale = v }
        case "emitter.particleAlpha":
            if node.emitterSpec == nil { node.emitterSpec = EmitterSpec() }
            if let v = Double(value) { node.emitterSpec?.particleAlpha = v }
        case "audio.loop":
            node.audioLoop = (value.lowercased() == "true")
        case "audio.volume":
            if let v = Double(value) { node.audioVolume = v }
        case "audio.autoplay":
            node.audioAutoplay = (value.lowercased() == "true")
        case "audio.positional":
            node.audioPositional = (value.lowercased() == "true")
        case "video.loop":
            node.videoLoop = (value.lowercased() == "true")
        case "video.autoplay":
            node.videoAutoplay = (value.lowercased() == "true")
        case "camera.target":
            node.cameraTarget = value
        default:
            break
        }
    }

    // MARK: - Web Asset Helpers

    /// Sanitize an AI-supplied asset name before any embedding.
    ///
    /// Allow-list: ASCII letters, digits, underscore, hyphen, period, space.
    /// Uses an explicit ASCII-only `CharacterSet` — NOT `CharacterSet.alphanumerics`
    /// which includes non-ASCII Unicode "Letter" / "Digit" scalars and would
    /// permit homoglyph attacks (Security Finding B).
    ///
    /// - Parameter raw: The AI-supplied name string.
    /// - Returns: The sanitized name, or nil if it is empty, `.`, `..`, or >128 chars.
    private func sanitizeAssetName(_ raw: String) -> String? {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // ASCII-only allow-list per Security Finding B.
        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-. "
        )
        cleaned = String(cleaned.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : Character("_")
        })
        if cleaned.isEmpty || cleaned == "." || cleaned == ".." || cleaned.count > 128 {
            return nil
        }
        return cleaned
    }

    /// Phase context for error formatting (controls whether body summary is included).
    private enum WebAssetErrorPhase { case search, download }

    /// Map a `WebAssetSearchError` to a safe, concise AI-visible string.
    ///
    /// Transport-level `localizedDescription` is NEVER forwarded to the AI
    /// (Security Finding 5). `providerRejected` body summaries are trimmed to
    /// 100 printable characters and omitted entirely for download-phase errors
    /// (Security Finding 9).
    private func formatWebAssetError(
        _ error: WebAssetSearchError,
        context: String,
        phase: WebAssetErrorPhase
    ) -> String {
        switch error {
        case .notConfigured(let msg):
            return "\(context) not configured: \(msg)"

        case .providerRejected(let body):
            switch phase {
            case .search:
                // Trim to 100 printable chars; strip control characters.
                let printable = body.unicodeScalars.filter { scalar in
                    scalar.value >= 0x20 && scalar.value != 0x7F
                }.map { String($0) }.joined()
                let summary = String(printable.prefix(100))
                // Provider name from the error context (best-effort)
                return "\(context.replacingOccurrences(of: "_", with: " ").capitalized) rejected search: \(summary)"
            case .download:
                return "\(context.replacingOccurrences(of: "_", with: " ").capitalized) rejected download (HTTP error)."
            }

        case .httpOnly(let url):
            return "Rejected \(url): only HTTPS downloads are allowed."

        case .redirectBlocked(let from, let to):
            return "Rejected \(from): redirect to \(to) blocked."

        case .ssrfBlocked(let url):
            return "Rejected \(url): network target not allowed."

        case .payloadTooLarge(let url, _):
            return "Rejected \(url): download exceeded 50 MB OOM ceiling."

        case .imageTooLarge(let url, _):
            return "Rejected \(url): decoded image exceeds 100 MP memory safety rail."

        case .unsupportedMimeType(let t):
            return "Rejected image: MIME \"\(t)\" is not a supported image format (png, jpg, webp, gif, svg)."

        case .svgRejected(let why):
            return "Rejected SVG: failed sanitization (\(why))."

        case .decodeFailed(let url):
            return "Rejected \(url): image data did not decode."

        case .unknownCandidate(let id):
            return "Unknown candidate_id '\(id)'. Call search_web_for_sprite first; candidate ids only live for the current chat session."

        case .webAssetsDisabled:
            return "Web asset search is off for this stack."

        case .networkFailure:
            // Do NOT forward localizedDescription — fixed safe string only (Finding 5).
            return "\(context) network error (transport failure)"
        }
    }
}
