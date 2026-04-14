import Foundation

/// A background shared by one or more cards.
public struct Background: Identifiable, Codable, Sendable {
    public var id: UUID
    public var stackId: UUID
    public var name: String
    public var sortKey: String
    public var script: String

    public init(
        id: UUID = UUID(),
        stackId: UUID,
        name: String = "",
        sortKey: String = "a0",
        script: String = ""
    ) {
        self.id = id
        self.stackId = stackId
        self.name = name
        self.sortKey = sortKey
        self.script = script
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        stackId = try c.decode(UUID.self, forKey: .stackId)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        sortKey = try c.decodeIfPresent(String.self, forKey: .sortKey) ?? "a0"
        script = try c.decodeIfPresent(String.self, forKey: .script) ?? ""
    }
}
