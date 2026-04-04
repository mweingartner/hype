import Foundation

/// A background shared by one or more cards.
public struct Background: Identifiable, Codable, Sendable {
    public var id: UUID
    public var stackId: UUID
    public var name: String
    public var sortKey: String

    public init(
        id: UUID = UUID(),
        stackId: UUID,
        name: String = "",
        sortKey: String = "a0"
    ) {
        self.id = id
        self.stackId = stackId
        self.name = name
        self.sortKey = sortKey
    }
}
