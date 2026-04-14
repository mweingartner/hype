import Foundation

/// A single card in a stack.
public struct Card: Identifiable, Codable, Sendable {
    public var id: UUID
    public var stackId: UUID
    public var backgroundId: UUID
    public var name: String
    public var sortKey: String
    public var marked: Bool
    public var script: String

    public init(
        id: UUID = UUID(),
        stackId: UUID,
        backgroundId: UUID,
        name: String = "",
        sortKey: String = "a0",
        marked: Bool = false,
        script: String = ""
    ) {
        self.id = id
        self.stackId = stackId
        self.backgroundId = backgroundId
        self.name = name
        self.sortKey = sortKey
        self.marked = marked
        self.script = script
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        stackId = try c.decode(UUID.self, forKey: .stackId)
        backgroundId = try c.decode(UUID.self, forKey: .backgroundId)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        sortKey = try c.decodeIfPresent(String.self, forKey: .sortKey) ?? "a0"
        marked = try c.decodeIfPresent(Bool.self, forKey: .marked) ?? false
        script = try c.decodeIfPresent(String.self, forKey: .script) ?? ""
    }
}
