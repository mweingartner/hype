import Foundation

/// A Hype stack — the top-level document containing backgrounds and cards.
public struct Stack: Identifiable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var width: Int
    public var height: Int
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        name: String = "Untitled",
        width: Int = 800,
        height: Int = 600,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.width = width
        self.height = height
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}
