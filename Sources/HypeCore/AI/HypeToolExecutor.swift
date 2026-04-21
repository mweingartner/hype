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

    /// Parse-validate a HypeTalk script and return a user-readable
    /// error suffix (starting with "; parse error: ...") if the
    /// script doesn't compile. Returns an empty string when the
    /// script is valid or empty.
    ///
    /// Tool-call results append this string when the AI sets a
    /// script field, so the AI sees its own parse errors and can
    /// correct the next tool call. Without this, invalid scripts
    /// are silently stored — the part is created successfully but
    /// no handler ever fires at runtime, and the AI has no
    /// feedback to learn from.
    private func scriptParseErrorSuffix(_ script: String) -> String {
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        var lexer = Lexer(source: script)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        do {
            _ = try parser.parse()
            return ""
        } catch let error as ParseError {
            return "; parse error in script: \(error.errorDescription ?? String(describing: error))"
        } catch {
            return "; parse error in script: \(error.localizedDescription)"
        }
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

    private func spriteAreaIndex(named areaName: String, in document: HypeDocument) -> Int? {
        document.parts.firstIndex(where: {
            $0.partType == .spriteArea && $0.name.lowercased() == areaName.lowercased()
        })
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
            var parseSuffix = ""
            if let script = arguments["script"] {
                part.script = wrapScript(script)
                parseSuffix = scriptParseErrorSuffix(part.script)
            }
            document.addPart(part)
            let layer = place.backgroundId != nil ? " on background" : ""
            return "Created button '\(part.name)'\(layer)\(parseSuffix)"

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
            if let style = arguments["style"], let fs = FieldStyle(rawValue: style) {
                part.fieldStyle = fs
            }
            var parseSuffixField = ""
            if let script = arguments["script"] {
                part.script = wrapScript(script)
                parseSuffixField = scriptParseErrorSuffix(part.script)
            }
            document.addPart(part)
            let layer = place.backgroundId != nil ? " on background" : ""
            return "Created field '\(part.name)'\(layer)\(parseSuffixField)"

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

        case "set_part_property":
            let partName = arguments["part_name"] ?? ""
            let property = arguments["property"] ?? ""
            let value = arguments["value"] ?? ""
            if let index = document.parts.firstIndex(where: { $0.name.lowercased() == partName.lowercased() }) {
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
                case "script":
                    // Wrap bare commands and validate the final
                    // script so the AI sees parse errors in the
                    // returned result.
                    let wrapped = wrapScript(value)
                    let suffix = scriptParseErrorSuffix(wrapped)

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
                            return "Set script of scene '\(sceneName)' in sprite area '\(partName)'\(suffix) (routed to the scene — this is the script shown in the \(partName)/\(sceneName) Script Editor)"
                        }
                        // No active scene — fall through to part-level script below.
                    }
                    document.parts[index].script = wrapped
                    if !suffix.isEmpty {
                        return "Set script of '\(partName)'\(suffix)"
                    }
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
            if let part = document.parts.first(where: { $0.name.lowercased() == partName.lowercased() }) {
                document.removePart(id: part.id)
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
            guard let partIndex = document.parts.firstIndex(where: {
                $0.partType == .chart && $0.name.lowercased() == chartName.lowercased()
            }) else {
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
            guard let part = document.parts.first(where: {
                $0.partType == .chart && $0.name.lowercased() == chartName.lowercased()
            }) else {
                return "Chart '\(chartName)' not found"
            }
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
            guard let part = document.parts.first(where: { $0.partType == .spriteArea && $0.name.lowercased() == areaName.lowercased() }) else {
                return "Sprite area '\(areaName)' not found"
            }
            return part.activeSceneSpec?.toJSON() ?? "No scene spec"

        case "set_scene_script":
            let areaName = arguments["sprite_area_name"] ?? ""
            let requestedSceneName = arguments["scene_name"] ?? ""
            let rawScript = arguments["script"] ?? ""
            let wrapped = wrapScript(rawScript)
            let suffix = scriptParseErrorSuffix(wrapped)

            guard let partIdx = spriteAreaIndex(named: areaName, in: document) else {
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

            return "Set script of scene '\(resolvedSceneName)' in sprite area '\(areaName)'\(suffix)"

        case "apply_scene_diff":
            let areaName = arguments["sprite_area_name"] ?? ""
            let diffJson = arguments["diff_json"] ?? ""
            guard let partIdx = spriteAreaIndex(named: areaName, in: document) else {
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
            guard let partIdx = spriteAreaIndex(named: areaName, in: document) else {
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
            guard let partIdx = spriteAreaIndex(named: areaName, in: document) else {
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
            guard let partIdx = spriteAreaIndex(named: areaName, in: document) else {
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
            guard let partIdx = spriteAreaIndex(named: areaName, in: document) else {
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
            guard let partIdx = spriteAreaIndex(named: areaName, in: document) else {
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

        default:
            return "Unknown tool: \(toolName)"
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
