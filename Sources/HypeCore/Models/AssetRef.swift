import Foundation

/// A reference to a sprite asset, used within scene node specifications.
public struct AssetRef: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var variantId: UUID?
    public var mimeType: String

    public init(id: UUID = UUID(), name: String = "", variantId: UUID? = nil, mimeType: String = "image/png") {
        self.id = id
        self.name = name
        self.variantId = variantId
        self.mimeType = mimeType
    }
}
