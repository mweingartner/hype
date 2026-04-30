import Foundation

/// A background shared by one or more cards.
public struct Background: Identifiable, Codable, Sendable {
    public var id: UUID
    public var stackId: UUID
    public var name: String
    public var sortKey: String
    public var script: String
    /// Optional background-scoped theme. When nil, falls through to
    /// the stack's theme. Setting this to a name not in the
    /// document's catalog is harmless — the cascade simply falls
    /// through to the next level. See ThemeResolver.swift.
    public var themeName: String?

    public init(
        id: UUID = UUID(),
        stackId: UUID,
        name: String = "",
        sortKey: String = "a0",
        script: String = "",
        themeName: String? = nil
    ) {
        self.id = id
        self.stackId = stackId
        self.name = name
        self.sortKey = sortKey
        self.script = script
        self.themeName = themeName
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        stackId = try c.decode(UUID.self, forKey: .stackId)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        sortKey = try c.decodeIfPresent(String.self, forKey: .sortKey) ?? "a0"
        script = try c.decodeIfPresent(String.self, forKey: .script) ?? ""
        // Backward-compatible: pre-theme backgrounds have no themeName.
        themeName = try c.decodeIfPresent(String.self, forKey: .themeName)
    }
}
