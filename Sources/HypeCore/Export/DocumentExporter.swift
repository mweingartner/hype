import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Export formats for Hype documents.
public enum ExportFormat: String, Sendable, CaseIterable {
    case json, html
}

/// Exports HypeDocument to various formats.
public struct DocumentExporter: Sendable {

    public init() {}

    /// Export document as JSON.
    public func exportJSON(document: HypeDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    /// Export document as a simple HTML page.
    public func exportHTML(document: HypeDocument) -> String {
        var html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <title>\(escapeHTML(document.stack.name))</title>
            <style>
                body { font-family: -apple-system, sans-serif; background: #f0f0f0; margin: 0; padding: 20px; }
                .card { background: white; width: \(document.stack.width)px; height: \(document.stack.height)px;
                        margin: 20px auto; position: relative; box-shadow: 0 2px 10px rgba(0,0,0,0.2); border-radius: 4px; }
                .part { position: absolute; }
                .paint-layer { position: absolute; left: 0; top: 0; width: 100%; height: 100%; pointer-events: none; }
                .button { display: flex; align-items: center; justify-content: center; border: 1px solid #ccc;
                          border-radius: 6px; background: #f8f8f8; cursor: pointer; font-size: 14px; }
                .field { border: 1px solid #ccc; padding: 4px; font-size: 14px; overflow: auto; background: white; }
                .shape { border: 1px solid black; }
                h2 { text-align: center; color: #333; }
            </style>
        </head>
        <body>
            <h2>\(escapeHTML(document.stack.name))</h2>
        """

        for (i, card) in document.sortedCards.enumerated() {
            let cardParts = document.effectivePartsForCard(card.id)
            let cardName = card.name.isEmpty ? "Card \(i + 1)" : card.name
            html += "<h3 style=\"text-align:center;color:#666\">\(escapeHTML(cardName))</h3>\n"
            html += "<div class=\"card\">\n"

            for part in cardParts where part.visible {
                let style = "left:\(Int(part.left))px;top:\(Int(part.top))px;width:\(Int(part.width))px;height:\(Int(part.height))px;"
                let cssClass = part.partType == .button ? "button" : part.partType == .field ? "field" : "shape"
                let content = part.partType == .button ? (part.showName ? part.name : part.textContent) : part.textContent
                html += "  <div class=\"part \(cssClass)\" style=\"\(style)\">\(escapeHTML(content))</div>\n"
            }

            html += paintLayerHTML(document.paintLayer(forCardId: card.id))
            html += "</div>\n"
        }

        html += "</body>\n</html>"
        return html
    }

    private func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func paintLayerHTML(_ layer: CardPaintLayer?) -> String {
        guard let layer, !layer.isEmpty else { return "" }
        #if canImport(AppKit)
        guard let pngData = PaintLayer(snapshot: layer).pngData() else { return "" }
        return "  <img class=\"paint-layer\" alt=\"Paint layer\" src=\"data:image/png;base64,\(pngData.base64EncodedString())\" />\n"
        #else
        return ""
        #endif
    }
}
