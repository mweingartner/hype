import Foundation

/// Generates HypeDocument structures from AI prompts.
public struct StackGenerator: Sendable {

    public init() {}

    /// System prompt for stack generation.
    public static let systemPrompt = """
    You are a HyperCard stack designer. When asked to create a stack, respond with a JSON object describing the stack structure.

    The JSON must have this format:
    {
      "name": "Stack Name",
      "cards": [
        {
          "name": "Card Name",
          "parts": [
            {
              "type": "button|field|shape",
              "name": "Part Name",
              "left": 100, "top": 100, "width": 200, "height": 40,
              "style": "roundRect",
              "textContent": "Click Me",
              "script": "on mouseUp\\n  go next\\nend mouseUp"
            }
          ]
        }
      ]
    }

    Design visually appealing, well-organized stacks with proper spacing.
    Use modern colors and clean layouts. Default canvas is 800x600.
    """

    /// Parse AI-generated JSON into a HypeDocument.
    public func parseGeneratedStack(json: String) -> HypeDocument? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let name = dict["name"] as? String ?? "Untitled"
        var doc = HypeDocument(stack: Stack(name: name))
        let bg = Background(stackId: doc.stack.id)
        doc.backgrounds = [bg]

        guard let cards = dict["cards"] as? [[String: Any]] else { return doc }

        for (i, cardDict) in cards.enumerated() {
            let card = Card(
                stackId: doc.stack.id,
                backgroundId: bg.id,
                name: cardDict["name"] as? String ?? "",
                sortKey: String(format: "a%06d", i)
            )
            doc.cards.append(card)

            guard let parts = cardDict["parts"] as? [[String: Any]] else { continue }
            for partDict in parts {
                let typeStr = partDict["type"] as? String ?? "button"
                let partType: PartType = typeStr == "field" ? .field : typeStr == "shape" ? .shape : .button

                var part = Part(
                    partType: partType,
                    cardId: card.id,
                    name: partDict["name"] as? String ?? "",
                    left: partDict["left"] as? Double ?? 100,
                    top: partDict["top"] as? Double ?? 100,
                    width: partDict["width"] as? Double ?? 120,
                    height: partDict["height"] as? Double ?? 40
                )
                part.textContent = partDict["textContent"] as? String ?? ""
                part.script = (partDict["script"] as? String ?? "").replacingOccurrences(of: "\\n", with: "\n")

                if let style = partDict["style"] as? String {
                    part.buttonStyle = ButtonStyle(rawValue: style) ?? .roundRect
                }
                if let fillColor = partDict["fillColor"] as? String {
                    part.fillColor = fillColor
                }

                doc.parts.append(part)
            }
        }

        return doc
    }
}
