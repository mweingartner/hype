import Foundation

/// Prepares brief, local extractive summaries and claims each narration event once.
/// Explicit HypeTalk speech does not pass through this policy.
public struct AIResponseSpeechPlanner: Sendable {
    private var recentResponseIDs: [UUID] = []

    public init() {}

    public mutating func prepare(_ text: String, responseID: UUID) -> String? {
        guard !recentResponseIDs.contains(responseID), let summary = Self.summary(of: text) else { return nil }
        // Claim before the caller starts asynchronous synthesis. Equal wording
        // on a different message/turn is still a separate announcement.
        recentResponseIDs.append(responseID)
        if recentResponseIDs.count > 256 { recentResponseIDs.removeFirst() }
        return summary
    }

    public static func summary(of text: String) -> String? {
        let text = String(text.prefix(24_000))
        var insideFence = false
        var prose: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                insideFence.toggle()
                continue
            }
            guard !insideFence, !line.isEmpty,
                  !line.hasPrefix("#"), !line.hasPrefix("|"), !line.hasPrefix("!["),
                  !line.hasPrefix("{"), !line.hasPrefix("}"), !line.hasPrefix("\""),
                  !line.hasPrefix("["), !line.hasPrefix("<"),
                  !line.hasPrefix("Tool:"), !line.hasPrefix("__HYPE_") else { continue }
            line = line.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
                .replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"^\s*(?:[-*+]\s+|\d+[.)]\s+)"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "`", with: "")
            line = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            if !line.isEmpty { prose.append(line) }
        }
        var sentences: [String] = []
        for line in prose {
            line.enumerateSubstrings(in: line.startIndex..., options: .bySentences) { sentence, _, _, _ in
                if let sentence { sentences.append(sentence.trimmingCharacters(in: .whitespacesAndNewlines)) }
            }
        }
        guard !sentences.isEmpty else { return nil }
        let actions = ["created", "updated", "changed", "fixed", "added", "removed", "found", "completed", "failed", "could not", "will", "i’ll", "i'll"]
        func score(_ sentence: String) -> Int {
            let lower = sentence.lowercased()
            if ["here is", "here's", "certainly", "sure,"].contains(where: lower.hasPrefix) { return -1 }
            return actions.contains(where: lower.contains) ? 1 : 0
        }
        // Select salient prose rather than reading a truncated prefix of the
        // response. Keep selected sentences in their original order.
        let selected = sentences.indices.sorted {
            score(sentences[$0]) == score(sentences[$1]) ? $0 < $1 : score(sentences[$0]) > score(sentences[$1])
        }.prefix(2).sorted()
        var words: [String] = []
        for index in selected {
            let sentenceWords = sentences[index].split(whereSeparator: \.isWhitespace).map(String.init)
            let remaining = min(28, 45 - words.count)
            guard remaining > 0 else { break }
            words.append(contentsOf: sentenceWords.prefix(remaining))
            if sentenceWords.count > remaining, let last = words.popLast() {
                words.append(last.trimmingCharacters(in: .punctuationCharacters) + "…")
            }
        }
        let result = words.joined(separator: " ")
        // A pathological single token must not turn into an unbounded payload.
        guard !result.isEmpty else { return nil }
        return result.count <= 320 ? result : String(result.prefix(319)) + "…"
    }
}
