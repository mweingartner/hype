import Foundation

// MARK: - Image-to-3D request types

/// POST `/openapi/v1/image-to-3d` request body.
///
/// Meshy accepts either `image_url` (a publicly-fetchable URL) OR
/// `image_data` (a `data:<mime>;base64,<bytes>` URI). Phase 2 ALWAYS
/// uses `image_data` so the source image bytes never leave the user's
/// machine except as a single direct POST to api.meshy.ai. This means
/// `image_url` is intentionally absent from the Swift struct — the
/// codec cannot emit it.
public struct MeshyImageTo3DRequest: Codable, Sendable, Equatable {
    /// `"data:image/<png|jpeg|webp>;base64,<...>"` — the sniffed MIME
    /// type drives the prefix, not a caller-supplied claim.
    public var imageData: String
    public var aiModel: MeshyAIModel
    public var shouldRemesh: Bool
    public var targetPolycount: Int?
    /// Always `true` in Phase 2 for content safety.
    public var moderation: Bool
    public var enablePbr: Bool?

    private enum CodingKeys: String, CodingKey {
        case imageData       = "image_data"
        case aiModel         = "ai_model"
        case shouldRemesh    = "should_remesh"
        case targetPolycount = "target_polycount"
        case moderation
        case enablePbr       = "enable_pbr"
    }

    public init(
        imageData: String,
        aiModel: MeshyAIModel = .meshy6,
        shouldRemesh: Bool = false,
        targetPolycount: Int? = nil,
        moderation: Bool = true,
        enablePbr: Bool? = nil
    ) {
        self.imageData = imageData
        self.aiModel = aiModel
        self.shouldRemesh = shouldRemesh
        self.targetPolycount = targetPolycount
        self.moderation = moderation
        self.enablePbr = enablePbr
    }
}

/// POST `/openapi/v1/multi-image-to-3d` request body.
///
/// Same `image_data` discipline as `MeshyImageTo3DRequest`, but accepts
/// an array of 2..4 data URIs. The first image is treated by Meshy as the
/// canonical front view; subsequent images are alternate views.
///
/// The codec does NOT enforce the array-length constraint — `MeshyAIClient.
/// createMultiImageTo3DTask` does, before encoding.
public struct MeshyMultiImageTo3DRequest: Codable, Sendable, Equatable {
    /// 2..4 entries, each a `"data:image/<mime>;base64,<...>"` URI.
    public var imageData: [String]
    public var aiModel: MeshyAIModel
    public var shouldRemesh: Bool
    public var targetPolycount: Int?
    /// Always `true` in Phase 2 for content safety.
    public var moderation: Bool
    public var enablePbr: Bool?

    private enum CodingKeys: String, CodingKey {
        case imageData       = "image_data"
        case aiModel         = "ai_model"
        case shouldRemesh    = "should_remesh"
        case targetPolycount = "target_polycount"
        case moderation
        case enablePbr       = "enable_pbr"
    }

    public init(
        imageData: [String],
        aiModel: MeshyAIModel = .meshy6,
        shouldRemesh: Bool = false,
        targetPolycount: Int? = nil,
        moderation: Bool = true,
        enablePbr: Bool? = nil
    ) {
        self.imageData = imageData
        self.aiModel = aiModel
        self.shouldRemesh = shouldRemesh
        self.targetPolycount = targetPolycount
        self.moderation = moderation
        self.enablePbr = enablePbr
    }
}
