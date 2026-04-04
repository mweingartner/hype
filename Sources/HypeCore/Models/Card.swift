import Foundation

/// A single card in a stack.
public struct Card: Identifiable, Codable, Sendable {
    public var id: UUID
    public var stackId: UUID
    public var backgroundId: UUID
    public var name: String
    public var sortKey: String
    public var marked: Bool

    public init(
        id: UUID = UUID(),
        stackId: UUID,
        backgroundId: UUID,
        name: String = "",
        sortKey: String = "a0",
        marked: Bool = false
    ) {
        self.id = id
        self.stackId = stackId
        self.backgroundId = backgroundId
        self.name = name
        self.sortKey = sortKey
        self.marked = marked
    }
}
