import Foundation

public enum HyperCardImportedGlobalSeeder {
    public static func newGameGlobals(
        from launcherDocument: HypeDocument,
        resourceDocuments: [HypeDocument]
    ) -> [String: String]? {
        guard let restoreData = restoreData(from: launcherDocument) else {
            return nil
        }
        guard let targets = resourceDocuments.lazy.compactMap(loadGlobalsTargets(in:)).first(where: { !$0.isEmpty }) else {
            return nil
        }
        var globals = globals(fromRestoreData: restoreData, targets: targets)
        globals["RestoreData"] = restoreData
        globals["Start_Game"] = "new"
        return globals
    }

    public static func restoreData(
        from document: HypeDocument,
        cardName: String = "Defaults",
        fieldName: String = "Defaults"
    ) -> String? {
        guard let card = document.cards.first(where: { $0.name.caseInsensitiveCompare(cardName) == .orderedSame }) else {
            return nil
        }
        let cardField = document.partsForCard(card.id).first { part in
            part.partType == .field && part.name.caseInsensitiveCompare(fieldName) == .orderedSame
        }
        let backgroundField = document.partsForBackground(card.backgroundId).first { part in
            part.partType == .field && part.name.caseInsensitiveCompare(fieldName) == .orderedSame
        }
        let text = (cardField ?? backgroundField)?.textContent
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        guard let text, !text.isEmpty else {
            return nil
        }
        return text
    }

    public static func loadGlobalsTargets(in document: HypeDocument) -> [String]? {
        let script = restoredLegacyScript(document.stack.script)
        guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        var inLoadGlobals = false
        var targets: [String] = []
        for rawLine in script.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if !inLoadGlobals {
                if line.range(of: #"^on\s+LoadGlobals\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
                    inLoadGlobals = true
                }
                continue
            }
            if line.range(of: #"^end\s+LoadGlobals\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
                break
            }
            guard !line.hasPrefix("--") else {
                continue
            }
            if let target = quotedArgument(in: line, command: "putit") {
                targets.append(target)
            }
        }
        return targets
    }

    public static func globals(fromRestoreData restoreData: String, targets: [String]) -> [String: String] {
        let lines = restoreData
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var globals: [String: String] = [:]
        var lineGlobals: [String: [Int: String]] = [:]

        for (index, target) in targets.enumerated() {
            let value = index < lines.count ? lines[index] : ""
            if let lineTarget = lineTarget(from: target) {
                lineGlobals[lineTarget.name, default: [:]][lineTarget.line] = value
            } else {
                globals[target] = value
            }
        }

        for (name, valuesByLine) in lineGlobals {
            let maxLine = valuesByLine.keys.max() ?? 0
            guard maxLine > 0 else { continue }
            globals[name] = (1...maxLine).map { valuesByLine[$0] ?? "" }.joined(separator: "\n")
        }
        return globals
    }

    private static func restoredLegacyScript(_ script: String) -> String {
        guard LegacyHyperTalkScript.isDisabledForHypeTalkRuntime(script) else {
            return script
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
        }
        return script
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .dropFirst(2)
            .map { line -> String in
                let text = String(line)
                if text.hasPrefix("-- ") {
                    return String(text.dropFirst(3))
                }
                if text == "--" {
                    return ""
                }
                return text
            }
            .joined(separator: "\n")
    }

    private static func quotedArgument(in line: String, command: String) -> String? {
        let pattern = #"^\#(command)\s+"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              match.numberOfRanges > 1,
              let argumentRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[argumentRange])
    }

    private static func lineTarget(from target: String) -> (line: Int, name: String)? {
        let pattern = #"^line\s+([0-9]+)\s+of\s+([A-Za-z_][A-Za-z0-9_]*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(target.startIndex..<target.endIndex, in: target)
        guard let match = regex.firstMatch(in: target, range: range),
              match.numberOfRanges == 3,
              let lineRange = Range(match.range(at: 1), in: target),
              let nameRange = Range(match.range(at: 2), in: target),
              let line = Int(target[lineRange]) else {
            return nil
        }
        return (line, String(target[nameRange]))
    }
}
