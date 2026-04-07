import Foundation

/// Executes AI tool calls against a HypeDocument.
public struct HypeToolExecutor: Sendable {

    public init() {}

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
            if let style = arguments["style"], let bs = ButtonStyle(rawValue: style) {
                part.buttonStyle = bs
            }
            if let script = arguments["script"] {
                part.script = wrapScript(script)
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
            if let text = arguments["text"] { part.textContent = text }
            if let style = arguments["style"], let fs = FieldStyle(rawValue: style) {
                part.fieldStyle = fs
            }
            if let script = arguments["script"] { part.script = wrapScript(script) }
            document.addPart(part)
            let layer = place.backgroundId != nil ? " on background" : ""
            return "Created field '\(part.name)'\(layer)"

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
                case "fillcolor", "fill_color": document.parts[index].fillColor = value
                case "strokecolor", "stroke_color": document.parts[index].strokeColor = value
                case "visible": document.parts[index].visible = (value.lowercased() == "true")
                case "enabled": document.parts[index].enabled = (value.lowercased() == "true")
                case "script": document.parts[index].script = value
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

        case "get_stack_info":
            let cardCount = document.cards.count
            let bgNames = document.backgrounds.map(\.name).joined(separator: ", ")
            let currentCard = document.cards.first(where: { $0.id == currentCardId })
            return "Stack '\(document.stack.name)': \(cardCount) cards, backgrounds: [\(bgNames)], current card: \(currentCard?.name ?? "unnamed")"

        case "get_card_parts":
            let cardParts = document.partsForCard(currentCardId)
            if let card = document.cards.first(where: { $0.id == currentCardId }) {
                let bgParts = document.partsForBackground(card.backgroundId)
                let allParts = bgParts + cardParts
                if allParts.isEmpty {
                    return "No parts on current card"
                }
                let descriptions = allParts.map { p in
                    "[\(p.partType.rawValue)] '\(p.name)' at (\(Int(p.left)),\(Int(p.top))) \(Int(p.width))x\(Int(p.height))"
                }
                return "Parts on current card: \(descriptions.joined(separator: "; "))"
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

        default:
            return "Unknown tool: \(toolName)"
        }
    }
}
