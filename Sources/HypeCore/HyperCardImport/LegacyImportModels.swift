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
            .map { line -> String in
                let text = String(line)
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                guard trimmed.caseInsensitiveCompare("gonext") == .orderedSame else {
                    return text
                }
                let indent = text.prefix { $0 == " " || $0 == "\t" }
                return "\(indent)go next"
            }
        return commentOutDisabledHandlerTails(in: lines).joined(separator: "\n")
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
