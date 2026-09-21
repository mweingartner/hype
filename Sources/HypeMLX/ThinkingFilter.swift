import Foundation

/// Splits a streamed reply into visible text and `<think>…</think>` reasoning,
/// never leaking a partially received tag to the author.
struct ThinkingFilter {
    private static let open = "<think>"
    private static let close = "</think>"

    private var pending = ""
    private var insideThinking: Bool
    private(set) var thinking = ""

    /// - Parameter startsInsideThinking: the generation prompt already opened
    ///   the `<think>` block, so the reply begins with reasoning text.
    init(startsInsideThinking: Bool = false) {
        insideThinking = startsInsideThinking
    }

    /// Feeds a decoded chunk; returns text that is safe to show now.
    mutating func consume(_ chunk: String) -> String {
        pending += chunk
        var visible = ""
        while true {
            let tag = insideThinking ? Self.close : Self.open
            if let range = pending.range(of: tag) {
                let before = String(pending[..<range.lowerBound])
                if insideThinking { thinking += before } else { visible += before }
                pending = String(pending[range.upperBound...])
                insideThinking.toggle()
                continue
            }
            // Hold back a tail that could still grow into the tag.
            let keep = Self.longestTagPrefix(atEndOf: pending, tag: tag)
            let emit = String(pending.dropLast(keep))
            if insideThinking { thinking += emit } else { visible += emit }
            pending = String(pending.suffix(keep))
            return visible
        }
    }

    /// Flushes whatever is still buffered when generation ends.
    mutating func finish() -> String {
        defer { pending = "" }
        if insideThinking {
            thinking += pending
            return ""
        }
        return pending
    }

    private static func longestTagPrefix(atEndOf text: String, tag: String) -> Int {
        let limit = min(text.count, tag.count - 1)
        guard limit > 0 else { return 0 }
        for length in stride(from: limit, to: 0, by: -1) where tag.hasPrefix(text.suffix(length)) {
            return length
        }
        return 0
    }
}
