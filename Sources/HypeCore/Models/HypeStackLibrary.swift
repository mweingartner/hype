import Foundation

public struct HypeStackLibrary: Codable, Equatable, Sendable {
    public var entries: [HypeStackLibraryEntry]
    public var usedStackAliases: [String]

    public init(
        entries: [HypeStackLibraryEntry] = [],
        usedStackAliases: [String] = []
    ) {
        self.entries = entries
        self.usedStackAliases = Self.stableAliases(usedStackAliases)
    }

    public var isEmpty: Bool {
        entries.isEmpty && usedStackAliases.isEmpty
    }

    public func resolution(for alias: String) -> HypeStackLibraryResolution {
        let key = Self.lookupKey(alias)
        let matches = entries.filter { entry in
            entry.lookupKeys.contains(key)
        }
        if matches.count == 1, let entry = matches.first {
            return .resolved(entry)
        }
        if matches.count > 1 {
            return .ambiguous(alias: alias, candidates: matches)
        }
        return .missing(alias: alias)
    }

    public mutating func startUsing(_ alias: String) -> HypeStackLibraryUseResult {
        switch resolution(for: alias) {
        case .resolved(let entry):
            usedStackAliases = Self.stableAliases(usedStackAliases + [entry.primaryAlias])
            return .started(entry)
        case .ambiguous(let alias, let candidates):
            return .ambiguous(alias: alias, candidates: candidates)
        case .missing(let alias):
            return .missing(alias: alias)
        }
    }

    public mutating func stopUsing(_ alias: String) -> HypeStackLibraryUseResult {
        switch resolution(for: alias) {
        case .resolved(let entry):
            let stopKeys = entry.lookupKeys
            usedStackAliases.removeAll { stopKeys.contains(Self.lookupKey($0)) }
            return .stopped(entry)
        case .ambiguous(let alias, let candidates):
            return .ambiguous(alias: alias, candidates: candidates)
        case .missing(let alias):
            return .missing(alias: alias)
        }
    }

    public static func lookupKey(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: #"[\s_\-\.]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stableAliases(_ aliases: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for alias in aliases {
            let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = lookupKey(trimmed)
            guard seen.insert(key).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }
}

public struct HypeStackLibraryEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var stackName: String
    public var aliases: [String]
    public var source: HypeStackLibrarySource
    public var packagePath: String?
    public var documentPath: String?
    public var legacyFirstCardId: Int?
    public var cardCount: Int?
    public var stackScript: String?
    public var cardReferences: [HypeStackLibraryCardReference]
    public var metadata: [HypeStackLibraryMetadataEntry]

    public init(
        id: UUID = UUID(),
        stackName: String,
        aliases: [String] = [],
        source: HypeStackLibrarySource,
        packagePath: String? = nil,
        documentPath: String? = nil,
        legacyFirstCardId: Int? = nil,
        cardCount: Int? = nil,
        stackScript: String? = nil,
        cardReferences: [HypeStackLibraryCardReference] = [],
        metadata: [HypeStackLibraryMetadataEntry] = []
    ) {
        self.id = id
        self.stackName = stackName
        self.aliases = Self.stableAliases(aliases + [stackName])
        self.source = source
        self.packagePath = packagePath
        self.documentPath = documentPath
        self.legacyFirstCardId = legacyFirstCardId
        self.cardCount = cardCount
        self.stackScript = stackScript
        self.cardReferences = cardReferences
        self.metadata = metadata
    }

    public var primaryAlias: String {
        aliases.first ?? stackName
    }

    public var lookupKeys: Set<String> {
        Set(aliases.map(HypeStackLibrary.lookupKey))
    }

    private static func stableAliases(_ aliases: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for alias in aliases {
            let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = HypeStackLibrary.lookupKey(trimmed)
            guard seen.insert(key).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }
}

public struct HypeStackLibraryCardReference: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var legacyCardId: Int?
    public var name: String
    public var sortIndex: Int?
    public var hypeCardId: UUID?

    public init(
        id: UUID = UUID(),
        legacyCardId: Int? = nil,
        name: String = "",
        sortIndex: Int? = nil,
        hypeCardId: UUID? = nil
    ) {
        self.id = id
        self.legacyCardId = legacyCardId
        self.name = name
        self.sortIndex = sortIndex
        self.hypeCardId = hypeCardId
    }
}

public enum HypeStackLibrarySource: String, Codable, Equatable, Sendable {
    case importedStackPackage
    case looseResourceStack
    case embeddedHypeDocument
}

public struct HypeStackLibraryMetadataEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var key: String
    public var value: String

    public init(id: UUID = UUID(), key: String, value: String) {
        self.id = id
        self.key = key
        self.value = value
    }
}

public enum HypeStackLibraryResolution: Equatable, Sendable {
    case resolved(HypeStackLibraryEntry)
    case ambiguous(alias: String, candidates: [HypeStackLibraryEntry])
    case missing(alias: String)
}

public enum HypeStackLibraryUseResult: Equatable, Sendable {
    case started(HypeStackLibraryEntry)
    case stopped(HypeStackLibraryEntry)
    case ambiguous(alias: String, candidates: [HypeStackLibraryEntry])
    case missing(alias: String)
}
