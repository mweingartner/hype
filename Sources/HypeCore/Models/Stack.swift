import Foundation

/// A Hype stack — the top-level document containing backgrounds and cards.
public struct Stack: Identifiable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var width: Int
    public var height: Int
    public var createdAt: Date
    public var modifiedAt: Date
    public var script: String
    /// The default font applied to every newly created button and
    /// field. Settable at runtime via HypeTalk:
    ///   `set the defaultFont of stack to "Helvetica"`
    ///   `put the defaultFont of stack into f`
    /// The value is written into `Part.textFont` at part-creation
    /// time in both the UI tool-drop path and the AI tool-call
    /// path. Existing parts are not retroactively changed —
    /// only new parts pick up the default.
    public var defaultFont: String
    public var networkManifest: StackNetworkManifest

    public init(
        id: UUID = UUID(),
        name: String = "Untitled",
        width: Int = 800,
        height: Int = 600,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        script: String = "",
        defaultFont: String = "Apple Braille",
        networkManifest: StackNetworkManifest = StackNetworkManifest()
    ) {
        self.id = id
        self.name = name
        self.width = width
        self.height = height
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.script = script
        self.defaultFont = defaultFont
        self.networkManifest = networkManifest
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        width = try c.decodeIfPresent(Int.self, forKey: .width) ?? 800
        height = try c.decodeIfPresent(Int.self, forKey: .height) ?? 600
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? Date()
        script = try c.decodeIfPresent(String.self, forKey: .script) ?? ""
        defaultFont = try c.decodeIfPresent(String.self, forKey: .defaultFont) ?? "Apple Braille"
        networkManifest = try c.decodeIfPresent(StackNetworkManifest.self, forKey: .networkManifest) ?? StackNetworkManifest()
    }
}
