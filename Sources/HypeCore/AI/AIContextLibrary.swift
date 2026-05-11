import Foundation
#if canImport(AppKit)
import AppKit
#endif

public enum AIContextSourceKind: String, Codable, Sendable, CaseIterable {
    case file
    case image
    case directory
    case textNote
}

public enum AIContextAccessMode: String, Codable, Sendable {
    case embedded
    case referenced
}

public enum AIContextRole: String, Codable, Sendable, CaseIterable {
    case rules
    case asset
    case styleGuide
    case example
    case projectMemory
    case reference
    case unknown

    public var displayName: String {
        switch self {
        case .rules: return "Rules"
        case .asset: return "Asset"
        case .styleGuide: return "Style Guide"
        case .example: return "Example"
        case .projectMemory: return "Project Memory"
        case .reference: return "Reference"
        case .unknown: return "Unknown"
        }
    }
}

public enum AIContextStatus: String, Codable, Sendable {
    case ready
    case stale
    case missing
    case error
}

public struct AIContextChunk: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var index: Int
    public var text: String

    public init(id: UUID = UUID(), index: Int, text: String) {
        self.id = id
        self.index = index
        self.text = text
    }
}

public struct AIContextSource: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var kind: AIContextSourceKind
    public var accessMode: AIContextAccessMode
    public var bookmarkData: Data?
    public var importedAt: Date
    public var lastIndexedAt: Date?
    public var status: AIContextStatus
    public var itemIds: [UUID]

    public init(
        id: UUID = UUID(),
        name: String,
        kind: AIContextSourceKind,
        accessMode: AIContextAccessMode = .embedded,
        bookmarkData: Data? = nil,
        importedAt: Date = Date(),
        lastIndexedAt: Date? = Date(),
        status: AIContextStatus = .ready,
        itemIds: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.accessMode = accessMode
        self.bookmarkData = bookmarkData
        self.importedAt = importedAt
        self.lastIndexedAt = lastIndexedAt
        self.status = status
        self.itemIds = itemIds
    }
}

public struct AIContextItem: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var sourceId: UUID
    public var name: String
    public var relativePath: String
    public var mimeType: String
    public var role: AIContextRole
    public var textSummary: String
    public var textChunks: [AIContextChunk]
    public var data: Data?
    public var thumbnailData: Data?
    public var width: Int?
    public var height: Int?
    public var byteCount: Int
    public var hash: String
    public var importedAt: Date

    public init(
        id: UUID = UUID(),
        sourceId: UUID,
        name: String,
        relativePath: String,
        mimeType: String,
        role: AIContextRole,
        textSummary: String = "",
        textChunks: [AIContextChunk] = [],
        data: Data? = nil,
        thumbnailData: Data? = nil,
        width: Int? = nil,
        height: Int? = nil,
        byteCount: Int = 0,
        hash: String = "",
        importedAt: Date = Date()
    ) {
        self.id = id
        self.sourceId = sourceId
        self.name = name
        self.relativePath = relativePath
        self.mimeType = mimeType
        self.role = role
        self.textSummary = textSummary
        self.textChunks = textChunks
        self.data = data
        self.thumbnailData = thumbnailData
        self.width = width
        self.height = height
        self.byteCount = byteCount
        self.hash = hash
        self.importedAt = importedAt
    }

    public var isText: Bool { !textChunks.isEmpty }
    public var isImage: Bool { mimeType.hasPrefix("image/") }
    public var isImportableAsset: Bool { data != nil && (isImage || mimeType.hasPrefix("audio/")) }
}

public struct AIContextSearchResult: Identifiable, Sendable, Equatable {
    public var id: UUID { item.id }
    public var item: AIContextItem
    public var score: Int
    public var snippet: String

    public init(item: AIContextItem, score: Int, snippet: String) {
        self.item = item
        self.score = score
        self.snippet = snippet
    }
}

public struct AIContextLibrary: Codable, Sendable, Equatable {
    public var sources: [AIContextSource]
    public var items: [AIContextItem]

    public init(sources: [AIContextSource] = [], items: [AIContextItem] = []) {
        self.sources = sources
        self.items = items
    }

    public var itemCount: Int { items.count }
    public var sourceCount: Int { sources.count }

    public mutating func addSource(_ source: AIContextSource, items newItems: [AIContextItem]) {
        var source = source
        source.itemIds = newItems.map(\.id)
        sources.removeAll { $0.id == source.id }
        items.removeAll { $0.sourceId == source.id }
        sources.append(source)
        items.append(contentsOf: newItems)
    }

    public mutating func removeSource(id: UUID) {
        sources.removeAll { $0.id == id }
        items.removeAll { $0.sourceId == id }
    }

    public mutating func removeItem(id: UUID) {
        items.removeAll { $0.id == id }
        for index in sources.indices {
            sources[index].itemIds.removeAll { $0 == id }
        }
    }

    public func item(id: UUID) -> AIContextItem? {
        items.first { $0.id == id }
    }

    public func source(id: UUID) -> AIContextSource? {
        sources.first { $0.id == id }
    }

    public func search(query: String, role: AIContextRole? = nil, limit: Int = 8) -> [AIContextSearchResult] {
        let terms = query
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 1 }

        let filtered = role.map { wanted in items.filter { $0.role == wanted } } ?? items
        guard !filtered.isEmpty else { return [] }
        if terms.isEmpty {
            return filtered.prefix(max(1, limit)).map {
                AIContextSearchResult(item: $0, score: 1, snippet: snippet(for: $0, terms: []))
            }
        }

        return filtered.compactMap { item -> AIContextSearchResult? in
            let haystack = searchableText(for: item)
            var score = 0
            for term in terms where haystack.contains(term) {
                score += item.name.lowercased().contains(term) ? 5 : 1
                score += item.relativePath.lowercased().contains(term) ? 3 : 0
                score += item.role.rawValue.lowercased().contains(term) ? 2 : 0
            }
            guard score > 0 else { return nil }
            return AIContextSearchResult(item: item, score: score, snippet: snippet(for: item, terms: terms))
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score { return lhs.item.name < rhs.item.name }
            return lhs.score > rhs.score
        }
        .prefix(max(1, limit))
        .map { $0 }
    }

    public func promptSummary(maxItems: Int = 12) -> String {
        guard !items.isEmpty else { return "No AI context has been attached to this stack." }
        let roleGroups = Dictionary(grouping: items, by: \.role)
            .map { "\($0.key.displayName): \($0.value.count)" }
            .sorted()
            .joined(separator: ", ")
        let lines = items.prefix(maxItems).map { item -> String in
            let dimensions = item.width.map { width in
                "\(width)x\(item.height ?? 0)"
            } ?? ""
            let detail = dimensions.isEmpty ? "\(item.byteCount) bytes" : "\(dimensions), \(item.byteCount) bytes"
            let summary = item.textSummary.isEmpty ? "" : " - \(item.textSummary.prefix(180))"
            return "- \(item.id.uuidString.prefix(8)) \(item.role.displayName) \(item.mimeType) \"\(item.relativePath)\" (\(detail))\(summary)"
        }
        let more = items.count > maxItems ? "\n- ... \(items.count - maxItems) more item(s)" : ""
        return "Sources: \(sources.count), items: \(items.count). Roles: \(roleGroups).\n\(lines.joined(separator: "\n"))\(more)"
    }

    private func searchableText(for item: AIContextItem) -> String {
        ([item.name, item.relativePath, item.mimeType, item.role.rawValue, item.textSummary] + item.textChunks.map(\.text))
            .joined(separator: "\n")
            .lowercased()
    }

    private func snippet(for item: AIContextItem, terms: [String]) -> String {
        let text = ([item.textSummary] + item.textChunks.map(\.text))
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return item.isImage ? "Image asset \(item.width ?? 0)x\(item.height ?? 0), \(item.byteCount) bytes." : "\(item.mimeType), \(item.byteCount) bytes."
        }
        let lower = text.lowercased()
        let firstMatch = terms.compactMap { lower.range(of: $0)?.lowerBound }.min()
        let start = firstMatch.map { max(text.startIndex, text.index($0, offsetBy: -140, limitedBy: text.startIndex) ?? text.startIndex) } ?? text.startIndex
        let end = text.index(start, offsetBy: 420, limitedBy: text.endIndex) ?? text.endIndex
        return String(text[start..<end]).replacingOccurrences(of: "\n", with: " ")
    }
}

public enum AIContextIngestor {
    public static let maxDirectoryItems = 200
    public static let maxDirectoryDepth = 5
    public static let maxTextBytes = 512_000
    public static let maxBinaryBytes = 25_000_000
    public static let chunkCharacterCount = 4_000
    public static let maxChunksPerItem = 24

    public enum IngestError: Error, Equatable {
        case unsupportedFileType(String)
        case fileTooLarge(String)
        case readFailed(String)
        case directoryEnumerationFailed(String)
    }

    public static func makeTextNote(title: String, text: String, role: AIContextRole = .rules) -> (AIContextSource, [AIContextItem]) {
        let sourceId = UUID()
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "AI Context Note" : title
        let data = Data(text.utf8)
        let item = textItem(
            sourceId: sourceId,
            name: name,
            relativePath: name,
            mimeType: "text/plain",
            role: role,
            data: data
        )
        return (AIContextSource(id: sourceId, name: name, kind: .textNote), [item])
    }

    public static func ingestFile(url: URL, role: AIContextRole = .reference) throws -> (AIContextSource, [AIContextItem]) {
        let sourceId = UUID()
        let item = try ingestFileItem(url: url, sourceId: sourceId, baseURL: url.deletingLastPathComponent(), role: role)
        let kind: AIContextSourceKind = item.isImage ? .image : .file
        let source = AIContextSource(id: sourceId, name: url.lastPathComponent, kind: kind)
        return (source, [item])
    }

    public static func ingestDirectory(url: URL, role: AIContextRole = .reference) throws -> (AIContextSource, [AIContextItem]) {
        let sourceId = UUID()
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw IngestError.directoryEnumerationFailed(url.lastPathComponent)
        }

        var items: [AIContextItem] = []
        for case let fileURL as URL in enumerator {
            if items.count >= maxDirectoryItems { break }
            let relative = relativePath(fileURL, baseURL: url)
            let depth = relative.split(separator: "/").count
            if depth > maxDirectoryDepth {
                enumerator.skipDescendants()
                continue
            }
            let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true {
                if values?.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            if values?.isDirectory == true { continue }
            if let item = try? ingestFileItem(url: fileURL, sourceId: sourceId, baseURL: url, role: inferredRole(for: fileURL, fallback: role)) {
                items.append(item)
            }
        }

        let source = AIContextSource(id: sourceId, name: url.lastPathComponent, kind: .directory)
        return (source, items)
    }

    private static func ingestFileItem(
        url: URL,
        sourceId: UUID,
        baseURL: URL,
        role: AIContextRole
    ) throws -> AIContextItem {
        let ext = url.pathExtension.lowercased()
        let mime = mimeType(forExtension: ext)
        guard supportedExtensions.contains(ext) else {
            throw IngestError.unsupportedFileType(url.lastPathComponent)
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        let maxBytes = mime.hasPrefix("text/") || textualExtensions.contains(ext) ? maxTextBytes : maxBinaryBytes
        guard size <= maxBytes else {
            throw IngestError.fileTooLarge(url.lastPathComponent)
        }
        guard let data = try? Data(contentsOf: url) else {
            throw IngestError.readFailed(url.lastPathComponent)
        }

        if mime.hasPrefix("image/") {
            return imageItem(sourceId: sourceId, url: url, baseURL: baseURL, role: role, data: data, mimeType: mime)
        }
        return textItem(
            sourceId: sourceId,
            name: url.deletingPathExtension().lastPathComponent,
            relativePath: relativePath(url, baseURL: baseURL),
            mimeType: mime,
            role: role,
            data: data
        )
    }

    private static func textItem(
        sourceId: UUID,
        name: String,
        relativePath: String,
        mimeType: String,
        role: AIContextRole,
        data: Data
    ) -> AIContextItem {
        let text = String(data: Data(data.prefix(maxTextBytes)), encoding: .utf8) ?? ""
        let chunks = chunks(for: text)
        let summary = summarize(text)
        return AIContextItem(
            sourceId: sourceId,
            name: name,
            relativePath: relativePath,
            mimeType: mimeType,
            role: role,
            textSummary: summary,
            textChunks: chunks,
            data: data,
            byteCount: data.count,
            hash: stableHash(data)
        )
    }

    private static func imageItem(
        sourceId: UUID,
        url: URL,
        baseURL: URL,
        role: AIContextRole,
        data: Data,
        mimeType: String
    ) -> AIContextItem {
        var width: Int?
        var height: Int?
        #if canImport(AppKit)
        if let image = NSImage(data: data) {
            width = Int(image.size.width.rounded())
            height = Int(image.size.height.rounded())
        }
        #endif
        return AIContextItem(
            sourceId: sourceId,
            name: url.deletingPathExtension().lastPathComponent,
            relativePath: relativePath(url, baseURL: baseURL),
            mimeType: mimeType,
            role: role == .reference ? .asset : role,
            textSummary: "Visual asset \(url.lastPathComponent)\(width.map { " \($0)x\(height ?? 0)" } ?? "").",
            data: data,
            thumbnailData: data,
            width: width,
            height: height,
            byteCount: data.count,
            hash: stableHash(data)
        )
    }

    private static func chunks(for text: String) -> [AIContextChunk] {
        guard !text.isEmpty else { return [] }
        var chunks: [AIContextChunk] = []
        var index = text.startIndex
        var chunkIndex = 0
        while index < text.endIndex && chunks.count < maxChunksPerItem {
            let end = text.index(index, offsetBy: chunkCharacterCount, limitedBy: text.endIndex) ?? text.endIndex
            chunks.append(AIContextChunk(index: chunkIndex, text: String(text[index..<end])))
            index = end
            chunkIndex += 1
        }
        return chunks
    }

    private static func summarize(_ text: String) -> String {
        let cleaned = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(6)
            .joined(separator: " ")
        return String(cleaned.prefix(600))
    }

    private static func inferredRole(for url: URL, fallback: AIContextRole) -> AIContextRole {
        let lower = url.lastPathComponent.lowercased()
        if lower.contains("rule") || lower.contains("design") || lower.contains("spec") { return .rules }
        if lower.contains("style") || lower.contains("brand") || lower.contains("theme") { return .styleGuide }
        if imageExtensions.contains(url.pathExtension.lowercased()) { return .asset }
        return fallback
    }

    private static func relativePath(_ url: URL, baseURL: URL) -> String {
        let base = baseURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path.hasPrefix(base) {
            let rel = String(path.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return rel.isEmpty ? url.lastPathComponent : rel
        }
        return url.lastPathComponent
    }

    private static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "json", "csv", "tsv", "yaml", "yml", "xml",
        "hype", "hypetalk", "script", "rules", "rtf"
    ]
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp"]
    private static let supportedExtensions: Set<String> = textExtensions.union(imageExtensions)
    private static let textualExtensions: Set<String> = textExtensions

    private static func mimeType(forExtension ext: String) -> String {
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "json": return "application/json"
        case "csv": return "text/csv"
        case "tsv": return "text/tab-separated-values"
        case "md", "markdown": return "text/markdown"
        case "yaml", "yml": return "application/yaml"
        case "xml": return "application/xml"
        case "rtf": return "text/rtf"
        default: return "text/plain"
        }
    }

    private static func stableHash(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data.prefix(2_000_000) {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}
