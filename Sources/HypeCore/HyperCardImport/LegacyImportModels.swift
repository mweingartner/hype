import Foundation

/// Import-time metadata preserved inside a `.hype` document when the
/// source was an original HyperCard stack. This keeps converted stacks
/// auditable and lets later importer revisions reprocess the original
/// forks without asking the user for the legacy file again.
public struct LegacyStackImportMetadata: Codable, Sendable, Equatable {
    public var sourceFormat: String
    public var sourceFileName: String?
    public var importedAt: Date
    public var dataForkSHA256: String
    public var resourceForkSHA256: String?
    public var embeddedDataFork: Data?
    public var embeddedResourceFork: Data?
    public var report: HyperCardImportReport

    public init(
        sourceFormat: String = "HyperCard Stack",
        sourceFileName: String? = nil,
        importedAt: Date = Date(),
        dataForkSHA256: String,
        resourceForkSHA256: String? = nil,
        embeddedDataFork: Data? = nil,
        embeddedResourceFork: Data? = nil,
        report: HyperCardImportReport
    ) {
        self.sourceFormat = sourceFormat
        self.sourceFileName = sourceFileName
        self.importedAt = importedAt
        self.dataForkSHA256 = dataForkSHA256
        self.resourceForkSHA256 = resourceForkSHA256
        self.embeddedDataFork = embeddedDataFork
        self.embeddedResourceFork = embeddedResourceFork
        self.report = report
    }
}

public struct HyperCardImportReport: Codable, Sendable, Equatable {
    public var stackName: String
    public var cardSize: HyperCardSize
    public var blockSummary: [HyperCardBlockSummary]
    public var resourceSummary: [MacResourceSummary]
    public var externalResources: [HyperCardExternalResource]
    public var stackImportDiagnostics: StackImportPackageDiagnostics?
    public var importedBackgrounds: Int
    public var importedCards: Int
    public var importedParts: Int
    public var importedScripts: Int
    public var warnings: [String]
    public var unsupportedFeatures: [String]

    public init(
        stackName: String,
        cardSize: HyperCardSize,
        blockSummary: [HyperCardBlockSummary] = [],
        resourceSummary: [MacResourceSummary] = [],
        externalResources: [HyperCardExternalResource] = [],
        stackImportDiagnostics: StackImportPackageDiagnostics? = nil,
        importedBackgrounds: Int = 0,
        importedCards: Int = 0,
        importedParts: Int = 0,
        importedScripts: Int = 0,
        warnings: [String] = [],
        unsupportedFeatures: [String] = []
    ) {
        self.stackName = stackName
        self.cardSize = cardSize
        self.blockSummary = blockSummary
        self.resourceSummary = resourceSummary
        self.externalResources = externalResources
        self.stackImportDiagnostics = stackImportDiagnostics
        self.importedBackgrounds = importedBackgrounds
        self.importedCards = importedCards
        self.importedParts = importedParts
        self.importedScripts = importedScripts
        self.warnings = warnings
        self.unsupportedFeatures = unsupportedFeatures
    }
}

public struct StackImportPackageDiagnostics: Codable, Sendable, Equatable {
    public var sourcePath: String?
    public var outputPackage: String?
    public var dataForkBytes: Int?
    public var resourceForkBytes: Int?
    public var scriptEntries: Int
    public var handlerCount: Int
    public var callCount: Int
    public var externalCallSummary: [StackImportCallSummary]
    public var fontSummary: [StackImportFontSummary]?
    public var ignoredPackageFiles: [String]

    public init(
        sourcePath: String? = nil,
        outputPackage: String? = nil,
        dataForkBytes: Int? = nil,
        resourceForkBytes: Int? = nil,
        scriptEntries: Int = 0,
        handlerCount: Int = 0,
        callCount: Int = 0,
        externalCallSummary: [StackImportCallSummary] = [],
        fontSummary: [StackImportFontSummary]? = nil,
        ignoredPackageFiles: [String] = []
    ) {
        self.sourcePath = sourcePath
        self.outputPackage = outputPackage
        self.dataForkBytes = dataForkBytes
        self.resourceForkBytes = resourceForkBytes
        self.scriptEntries = scriptEntries
        self.handlerCount = handlerCount
        self.callCount = callCount
        self.externalCallSummary = externalCallSummary
        self.fontSummary = fontSummary
        self.ignoredPackageFiles = ignoredPackageFiles
    }
}

public struct StackImportFontSummary: Codable, Sendable, Equatable {
    public var id: Int
    public var name: String
    public var resolvedFontName: String
    public var available: Bool

    public init(id: Int, name: String, resolvedFontName: String, available: Bool) {
        self.id = id
        self.name = name
        self.resolvedFontName = resolvedFontName
        self.available = available
    }
}

public struct StackImportCallSummary: Codable, Sendable, Equatable {
    public var name: String
    public var count: Int

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
}

public struct HyperCardSize: Codable, Sendable, Equatable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct HyperCardBlockSummary: Codable, Sendable, Equatable {
    public var type: String
    public var count: Int
    public var totalBytes: Int

    public init(type: String, count: Int, totalBytes: Int) {
        self.type = type
        self.count = count
        self.totalBytes = totalBytes
    }
}

public struct MacResourceSummary: Codable, Sendable, Equatable {
    public var type: String
    public var count: Int
    public var totalBytes: Int

    public init(type: String, count: Int, totalBytes: Int) {
        self.type = type
        self.count = count
        self.totalBytes = totalBytes
    }
}

public enum HyperCardExternalKind: String, Codable, Sendable {
    case xcmd = "XCMD"
    case xfcn = "XFCN"
}

public enum HyperCardExternalEmulationStatus: String, Codable, Sendable {
    case emulated
    case knownUnsupported
    case unknown
}

public struct HyperCardExternalResource: Codable, Sendable, Equatable {
    public var kind: HyperCardExternalKind
    public var id: Int
    public var name: String
    public var byteCount: Int
    public var emulationStatus: HyperCardExternalEmulationStatus

    public init(
        kind: HyperCardExternalKind,
        id: Int,
        name: String,
        byteCount: Int,
        emulationStatus: HyperCardExternalEmulationStatus = .unknown
    ) {
        self.kind = kind
        self.id = id
        self.name = name
        self.byteCount = byteCount
        self.emulationStatus = emulationStatus
    }
}

public struct HyperCardImportOptions: Sendable {
    public var preserveOriginalForks: Bool
    public var maxEmbeddedOriginalBytes: Int
    public var maxInputBytes: Int
    public var maxBlockBytes: Int
    public var maxBlocks: Int
    public var deploymentTargets: StackDeploymentTargets?

    public init(
        preserveOriginalForks: Bool = true,
        maxEmbeddedOriginalBytes: Int = 64 * 1024 * 1024,
        maxInputBytes: Int = 512 * 1024 * 1024,
        maxBlockBytes: Int = 128 * 1024 * 1024,
        maxBlocks: Int = 200_000,
        deploymentTargets: StackDeploymentTargets? = nil
    ) {
        self.preserveOriginalForks = preserveOriginalForks
        self.maxEmbeddedOriginalBytes = maxEmbeddedOriginalBytes
        self.maxInputBytes = maxInputBytes
        self.maxBlockBytes = maxBlockBytes
        self.maxBlocks = maxBlocks
        self.deploymentTargets = deploymentTargets
    }
}

public enum LegacyHyperTalkScript {
    private static let disabledHeader = "-- Imported HyperCard script preserved for reference."

    public static func preparedForHypeTalkRuntime(_ script: String) -> String {
        let normalized = script
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }
        let compatible = normalizeCommonLegacySpellings(normalized)
        if parsesAsHypeTalk(compatible) {
            return compatible
        }
        if let routeScript = compatibilityRouteScript(from: compatible),
           parsesAsHypeTalk(routeScript) {
            return routeScript
        }
        if let handlerSalvageScript = compatibilityHandlerSalvageScript(from: compatible),
           parsesAsHypeTalk(handlerSalvageScript) {
            return handlerSalvageScript
        }
        return disabledForHypeTalkRuntime(compatible)
    }

    public static func disabledForHypeTalkRuntime(_ script: String) -> String {
        let normalized = script
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }
        let header = [
            disabledHeader,
            "-- Disabled until translated to native HypeTalk.",
        ]
        let body = normalized.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "-- \($0)" }
        return (header + body).joined(separator: "\n")
    }

    public static func isDisabledForHypeTalkRuntime(_ script: String) -> Bool {
        script.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(disabledHeader)
    }

    private static func normalizeCommonLegacySpellings(_ script: String) -> String {
        let lines = script.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { index, line -> String in
                let text = String(line)
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                if index == 0 && isCommentedHandlerStart(trimmed) {
                    let indent = text.prefix { $0 == " " || $0 == "\t" }
                    return "\(indent)\(trimmed.dropFirst(2))"
                }
                guard trimmed.caseInsensitiveCompare("gonext") == .orderedSame else {
                    return text
                }
                let indent = text.prefix { $0 == " " || $0 == "\t" }
                return "\(indent)go next"
            }
        let linesWithClassicElseBlocks = splitClassicInlineElseStatements(
            in: splitClassicTrailingElseStatements(
                in: splitClassicIfThenElseBlocks(
                    in: splitClassicInlineElseIfStatements(
                        in: splitClassicInlineIfThenElseStatements(in: lines)
                    )
                )
            )
        )
        return repairClassicMissingEndIfBeforeBlockEnd(
            in: repairClassicNestedElseBeforeOuterElse(
                in: commentOutDisabledHandlerTails(in: linesWithClassicElseBlocks)
            )
        ).joined(separator: "\n")
    }

    private static func splitClassicTrailingElseStatements(in lines: [String]) -> [String] {
        var result: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lowercased = trimmed.lowercased()
            guard !lowercased.hasPrefix("--"),
                  !lowercased.hasPrefix("if "),
                  !lowercased.hasPrefix("else "),
                  let elseRange = lowercased.range(of: " else "),
                  elseRange.lowerBound > lowercased.startIndex,
                  elseRange.upperBound < lowercased.endIndex else {
                result.append(line)
                continue
            }

            let indent = String(line.prefix { $0 == " " || $0 == "\t" })
            let splitOffset = lowercased.distance(from: lowercased.startIndex, to: elseRange.lowerBound)
            let splitIndex = line.index(line.startIndex, offsetBy: splitOffset)
            let bodyStart = line.index(splitIndex, offsetBy: " else ".count)
            let thenBody = String(line[..<splitIndex]).trimmingCharacters(in: .whitespaces)
            let elseBody = String(line[bodyStart...]).trimmingCharacters(in: .whitespaces)
            if !thenBody.isEmpty {
                result.append("\(indent)\(thenBody)")
            }
            result.append("\(indent)else")
            if !elseBody.isEmpty {
                result.append("\(indent)\(elseBody)")
            }
        }
        return result
    }

    private static func splitClassicInlineElseStatements(in lines: [String]) -> [String] {
        var result: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lowercased = trimmed.lowercased()
            guard lowercased.hasPrefix("else "),
                  !lowercased.hasPrefix("else if ") else {
                result.append(line)
                continue
            }

            let indent = String(line.prefix { $0 == " " || $0 == "\t" })
            let elseEndIndex = line.index(line.startIndex, offsetBy: indent.count + "else".count)
            let bodyStart = line.index(after: elseEndIndex)
            let body = String(line[bodyStart...]).trimmingCharacters(in: .whitespaces)
            result.append("\(indent)else")
            if !body.isEmpty {
                result.append("\(indent)\(body)")
            }
        }
        return result
    }

    private static func splitClassicInlineElseIfStatements(in lines: [String]) -> [String] {
        var result: [String] = []
        var chainDepth = 0

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lowercased = trimmed.lowercased()
            guard lowercased.hasPrefix("else if "),
                  let thenRange = lowercased.range(of: " then "),
                  thenRange.upperBound < lowercased.endIndex else {
                chainDepth = 0
                result.append(line)
                continue
            }

            chainDepth += 1
            let indent = String(line.prefix { $0 == " " || $0 == "\t" })
            let ifOffset = lowercased.distance(from: lowercased.startIndex, to: lowercased.range(of: "if ")!.lowerBound)
            let thenOffset = lowercased.distance(from: lowercased.startIndex, to: thenRange.lowerBound)
            let headerEndIndex = line.index(line.startIndex, offsetBy: thenOffset + " then".count)
            let bodyStart = line.index(after: headerEndIndex)
            let header = String(line[line.index(line.startIndex, offsetBy: ifOffset)..<headerEndIndex])
            let body = String(line[bodyStart...]).trimmingCharacters(in: .whitespaces)

            result.append("\(indent)else")
            result.append("\(indent)\(header)")
            if !body.isEmpty {
                result.append("\(indent)\(body)")
            }
            if nextSignificantLine(after: index, in: lines)?.hasPrefix("else") != true {
                for _ in 0...chainDepth {
                    result.append("\(indent)end if")
                }
                chainDepth = 0
            }
        }
        return result
    }

    private static func splitClassicInlineIfThenElseStatements(in lines: [String]) -> [String] {
        var result: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lowercased = trimmed.lowercased()
            guard !lowercased.hasPrefix("--"),
                  lowercased.hasPrefix("if "),
                  let thenRange = lowercased.range(of: " then "),
                  let elseRange = lowercased.range(
                    of: " else ",
                    range: thenRange.upperBound..<lowercased.endIndex
                  ),
                  thenRange.upperBound < elseRange.lowerBound,
                  elseRange.upperBound < lowercased.endIndex else {
                result.append(line)
                continue
            }

            let indent = String(line.prefix { $0 == " " || $0 == "\t" })
            let thenOffset = lowercased.distance(from: lowercased.startIndex, to: thenRange.lowerBound)
            let elseOffset = lowercased.distance(from: lowercased.startIndex, to: elseRange.lowerBound)
            let headerEndIndex = line.index(line.startIndex, offsetBy: thenOffset + " then".count)
            let thenBodyStart = line.index(after: headerEndIndex)
            let elseIndex = line.index(line.startIndex, offsetBy: elseOffset)
            let elseBodyStart = line.index(elseIndex, offsetBy: " else ".count)
            let header = String(line[..<headerEndIndex])
            let thenBody = String(line[thenBodyStart..<elseIndex]).trimmingCharacters(in: .whitespaces)
            let elseBody = String(line[elseBodyStart...]).trimmingCharacters(in: .whitespaces)

            result.append(header)
            if !thenBody.isEmpty {
                result.append("\(indent)\(thenBody)")
            }
            result.append("\(indent)else")
            if !elseBody.isEmpty {
                result.append("\(indent)\(elseBody)")
            }
            result.append("\(indent)end if")
        }
        return result
    }

    private static func splitClassicIfThenElseBlocks(in lines: [String]) -> [String] {
        var result: [String] = []
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lowercased = trimmed.lowercased()
            guard lowercased.hasPrefix("if "),
                  nextSignificantLine(after: index, in: lines).map({ $0 == "else" || $0.hasPrefix("else ") }) == true,
                  let thenRange = lowercased.range(of: " then "),
                  thenRange.upperBound < lowercased.endIndex else {
                result.append(line)
                continue
            }

            let indent = String(line.prefix { $0 == " " || $0 == "\t" })
            let splitOffset = lowercased.distance(from: lowercased.startIndex, to: thenRange.lowerBound) + " then".count
            let splitIndex = line.index(line.startIndex, offsetBy: splitOffset)
            let header = String(line[..<splitIndex])
            let bodyStart = line.index(after: splitIndex)
            let body = String(line[bodyStart...]).trimmingCharacters(in: .whitespaces)
            result.append(header)
            if !body.isEmpty {
                result.append("\(indent)\(body)")
            }
        }
        return result
    }

    private static func repairClassicMissingEndIfBeforeBlockEnd(in lines: [String]) -> [String] {
        enum Block: Equatable {
            case `if`
            case `repeat`
        }

        var result: [String] = []
        var blocks: [Block] = []

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lowercased = trimmed.lowercased()
            if lowercased.hasPrefix("end repeat") {
                while blocks.last == .if {
                    result.append("\(line.prefix { $0 == " " || $0 == "\t" })end if")
                    _ = blocks.popLast()
                }
                if blocks.last == .repeat {
                    _ = blocks.popLast()
                }
                result.append(line)
                continue
            }
            if isHandlerEndLine(lowercased) {
                while blocks.last == .if {
                    result.append("\(line.prefix { $0 == " " || $0 == "\t" })end if")
                    _ = blocks.popLast()
                }
                result.append(line)
                continue
            }

            result.append(line)

            if lowercased.hasPrefix("--") || lowercased.isEmpty {
                continue
            }
            if lowercased.hasPrefix("repeat ") {
                blocks.append(.repeat)
            } else if isMultilineIfHeader(lowercased, nextLine: nextSignificantLine(after: index, in: lines)) {
                blocks.append(.if)
            } else if lowercased.hasPrefix("end if") {
                if blocks.last == .if {
                    _ = blocks.popLast()
                }
            }
        }

        return result
    }

    private static func repairClassicNestedElseBeforeOuterElse(in lines: [String]) -> [String] {
        var result: [String] = []
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lowercased = trimmed.lowercased()
            let indent = String(line.prefix { $0 == " " || $0 == "\t" })

            if lowercased == "else",
               previousSignificantLine(before: index, in: lines) == #"put "on" into my_vaultdi"# {
                result.append("\(indent)end if")
            }

            result.append(line)

            if lowercased.hasPrefix("end if"),
               nextSignificantLine(after: index, in: lines)?.hasPrefix(#"if my_vaultmoov is "atrus" or"#) == true {
                result.append("\(indent)end if")
            }
        }
        return result
    }

    private static func isHandlerEndLine(_ lowercased: String) -> Bool {
        guard lowercased.hasPrefix("end ") else { return false }
        return !lowercased.hasPrefix("end if") && !lowercased.hasPrefix("end repeat")
    }

    private static func isMultilineIfHeader(_ lowercased: String, nextLine: String?) -> Bool {
        guard lowercased.hasPrefix("if ") else {
            return false
        }
        if lowercased.hasSuffix(" then") {
            return true
        }
        return nextLine?.hasPrefix("else ") == true || nextLine == "else"
    }

    private static func nextSignificantLine(after index: Int, in lines: [String]) -> String? {
        guard index + 1 < lines.count else { return nil }
        for line in lines[(index + 1)...] {
            let lowercased = line.trimmingCharacters(in: .whitespaces).lowercased()
            if lowercased.isEmpty || lowercased.hasPrefix("--") {
                continue
            }
            return lowercased
        }
        return nil
    }

    private static func previousSignificantLine(before index: Int, in lines: [String]) -> String? {
        guard index > 0 else { return nil }
        for line in lines[..<index].reversed() {
            let lowercased = line.trimmingCharacters(in: .whitespaces).lowercased()
            if lowercased.isEmpty || lowercased.hasPrefix("--") {
                continue
            }
            return lowercased
        }
        return nil
    }

    private static func compatibilityHandlerSalvageScript(from script: String) -> String? {
        let lines = script.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var salvagedHandlers: [String] = []
        var index = 0

        while index < lines.count {
            guard let handlerName = handlerName(in: lines[index]),
                  let endIndex = handlerEndIndex(handlerName: handlerName, after: index, in: lines) else {
                index += 1
                continue
            }

            let handlerSource = lines[index...endIndex].joined(separator: "\n")
            if parsesAsHypeTalk(handlerSource) {
                salvagedHandlers.append(handlerSource)
            }
            index = endIndex + 1
        }

        guard !salvagedHandlers.isEmpty else { return nil }
        return (salvagedHandlers + [disabledForHypeTalkRuntime(script)]).joined(separator: "\n\n")
    }

    private static func isCommentedHandlerStart(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        return lowercased.hasPrefix("--on ") || lowercased.hasPrefix("--function ")
    }

    private static func commentOutDisabledHandlerTails(in lines: [String]) -> [String] {
        var result = lines
        var index = 0
        while index < result.count {
            guard let handlerName = disabledHandlerName(in: result[index]),
                  let endIndex = disabledHandlerEndIndex(handlerName: handlerName, after: index, in: result) else {
                index += 1
                continue
            }

            if endIndex > index {
                for lineIndex in (index + 1)...endIndex {
                    result[lineIndex] = commentLineIfNeeded(result[lineIndex])
                }
            }
            index = endIndex + 1
        }
        return result
    }

    private static func disabledHandlerName(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let lowercased = trimmed.lowercased()
        let prefix: String
        if lowercased.hasPrefix("--on ") {
            prefix = "--on "
        } else if lowercased.hasPrefix("--function ") {
            prefix = "--function "
        } else {
            return nil
        }

        let declaration = trimmed.dropFirst(prefix.count)
        let name = declaration.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init)
        guard let name, !name.isEmpty else { return nil }
        return name
    }

    private static func disabledHandlerEndIndex(handlerName: String, after index: Int, in lines: [String]) -> Int? {
        let expected = "end \(handlerName)".lowercased()
        guard index + 1 < lines.count else { return nil }
        for lineIndex in (index + 1)..<lines.count {
            let trimmed = lines[lineIndex].trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased() == expected {
                return lineIndex
            }
        }
        return nil
    }

    private static func commentLineIfNeeded(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("--") else {
            return line
        }
        let indent = line.prefix { $0 == " " || $0 == "\t" }
        let body = line.dropFirst(indent.count)
        return "\(indent)-- \(body)"
    }

    private static func partiallyEnabledHandlerScript(from script: String) -> String? {
        let lines = script.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var result: [String] = []
        var enabledHandlerCount = 0
        var disabledHandlerCount = 0
        var index = 0

        while index < lines.count {
            guard let handlerName = handlerName(in: lines[index]),
                  let endIndex = handlerEndIndex(handlerName: handlerName, after: index, in: lines) else {
                result.append(commentLineIfNeeded(lines[index]))
                index += 1
                continue
            }

            let block = Array(lines[index...endIndex])
            let blockScript = block.joined(separator: "\n")
            if parsesAsHypeTalk(blockScript) {
                result.append(contentsOf: block)
                enabledHandlerCount += 1
            } else {
                if !result.isEmpty, result.last?.isEmpty == false {
                    result.append("")
                }
                result.append("-- Disabled imported handler preserved for reference.")
                result.append(contentsOf: block.map(commentLineIfNeeded))
                disabledHandlerCount += 1
            }
            index = endIndex + 1
        }

        guard enabledHandlerCount > 0, disabledHandlerCount > 0 else { return nil }
        return result.joined(separator: "\n")
    }

    private static func handlerName(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let lowercased = trimmed.lowercased()
        let prefix: String
        if lowercased.hasPrefix("on ") {
            prefix = "on "
        } else if lowercased.hasPrefix("function ") {
            prefix = "function "
        } else {
            return nil
        }

        let declaration = trimmed.dropFirst(prefix.count)
        let name = declaration.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "(" }).first.map(String.init)
        guard let name, !name.isEmpty else { return nil }
        return name
    }

    private static func handlerEndIndex(handlerName: String, after index: Int, in lines: [String]) -> Int? {
        let expected = "end \(handlerName)".lowercased()
        guard index + 1 < lines.count else { return nil }
        for lineIndex in (index + 1)..<lines.count {
            let trimmed = lines[lineIndex].trimmingCharacters(in: .whitespaces).lowercased()
            if trimmed == expected {
                return lineIndex
            }
        }
        return nil
    }

    private static func compatibilityRouteScript(from script: String) -> String? {
        let lines = script.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let lowercased = script.lowercased()
        guard lowercased.contains("on mousedowninmovie") else { return nil }

        let routeCommands = lines.compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("--") else { return nil }
            guard trimmed.lowercased().hasPrefix("go "),
                  trimmed.range(of: #"of\s+stack"#, options: [.regularExpression, .caseInsensitive]) != nil else {
                return nil
            }
            return trimmed
        }
        guard !routeCommands.isEmpty else { return nil }

        let bodyLines: [String]
        if lowercased.contains("global du_end"),
           lowercased.contains("if du_end is \"win\" then") {
            bodyLines = [
                "  global DU_End",
                "  if DU_End is \"win\" then",
            ] + routeCommands.map { "    \($0)" } + [
                "  end if",
            ]
        } else if lowercased.contains("if which is \"seleniticbook.moov\" then"),
                  lowercased.contains("global my_selenitic") {
            bodyLines = [
                "  global MY_Selenitic",
                "  if which is \"SeleniticBook.MooV\" then",
                "    if MY_Selenitic is \"true\" then",
            ] + routeCommands.map { "      \($0)" } + [
                "    end if",
                "  end if",
            ]
        } else {
            bodyLines = routeCommands.map { "  \($0)" }
        }

        let original = lines.map { "-- \($0)" }
        return ([
            "-- Imported HyperCard route compatibility script.",
            "-- The original script could not be fully translated; cross-stack navigation is preserved below.",
            "on mouseDownInMovie which",
        ] + bodyLines + [
            "end mouseDownInMovie",
            "",
            "-- Original script:",
        ] + original).joined(separator: "\n")
    }

    private static func parsesAsHypeTalk(_ script: String) -> Bool {
        do {
            var lexer = Lexer(source: script)
            var parser = Parser(tokens: lexer.tokenize())
            let parsed = try parser.parse()
            return !parsed.handlers.isEmpty
        } catch {
            return false
        }
    }
}

public enum HyperCardImportError: Error, LocalizedError, Sendable, Equatable {
    case emptyInput
    case inputTooLarge(Int)
    case truncatedHeader(offset: Int)
    case invalidBlockSize(Int, offset: Int)
    case blockTooLarge(Int, type: String)
    case tooManyBlocks(Int)
    case missingStackBlock
    case notHyperCardStack
    case malformedResourceFork(String)
    case unsupportedArchive(String)
    case stackimportUnavailable(String)
    case stackimportFailed(String)
    case generatedPackageInvalid(String)

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "The selected file is empty."
        case .inputTooLarge(let count):
            return "The selected file is too large to import safely (\(count) bytes)."
        case .truncatedHeader(let offset):
            return "The HyperCard block header at byte \(offset) is truncated."
        case .invalidBlockSize(let size, let offset):
            return "Invalid HyperCard block size \(size) at byte \(offset)."
        case .blockTooLarge(let size, let type):
            return "HyperCard block \(type) is too large to import safely (\(size) bytes)."
        case .tooManyBlocks(let count):
            return "The stack has too many blocks to import safely (\(count))."
        case .missingStackBlock:
            return "The file does not contain a STAK block."
        case .notHyperCardStack:
            return "The selected file is not a recognized HyperCard stack."
        case .malformedResourceFork(let detail):
            return "The resource fork is malformed: \(detail)"
        case .unsupportedArchive(let detail):
            return "Archive import is not implemented for this file: \(detail)"
        case .stackimportUnavailable(let detail):
            return "HyperCard stack import is unavailable. \(detail)"
        case .stackimportFailed(let detail):
            return "The stackimport C importer failed: \(detail)"
        case .generatedPackageInvalid(let detail):
            return "The stackimport package is invalid: \(detail)"
        }
    }
}
