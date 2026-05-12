import Foundation

// MARK: - Image-to-3D request types

/// POST `/openapi/v1/image-to-3d` request body.
///
/// Meshy's image-to-3D endpoint requires `image_url` (either an HTTPS URL
/// OR a `data:<mime>;base64,<bytes>` URI) or `input_task_id`. There is
/// no `image_data` field — Meshy returns a 400 if you send one. Hype
/// ALWAYS sends a data URI so source-image bytes go directly to
/// api.meshy.ai with no intermediate public URL. `input_task_id` is
/// intentionally absent from this struct — the codec cannot emit it.
///
/// The Swift property is still named `imageData` for compatibility with
/// existing call sites; the JSON `CodingKey` maps it to `image_url`.
public struct MeshyImageTo3DRequest: Codable, Sendable, Equatable {
    /// `"data:image/<jpeg|png>;base64,<...>"` — the sniffed MIME type
    /// drives the prefix, not a caller-supplied claim. Meshy supports
    /// `.jpg`, `.jpeg`, `.png` for this endpoint.
    public var imageData: String
    public var aiModel: MeshyAIModel
    public var shouldRemesh: Bool
    public var targetPolycount: Int?
    /// Always `true` in Phase 2 for content safety.
    public var moderation: Bool
    public var enablePbr: Bool?

    private enum CodingKeys: String, CodingKey {
        case imageData       = "image_url"
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
/// Meshy's multi-image endpoint expects an `image_urls` array (plural).
/// Each entry may be an HTTPS URL or a `data:<mime>;base64,<bytes>` URI.
/// Hype always sends data URIs. The first image is treated by Meshy as
/// the canonical front view; subsequent images are alternate views.
///
/// The Swift property is still named `imageData` for compatibility with
/// existing call sites; the JSON `CodingKey` maps it to `image_urls`.
/// The codec does NOT enforce the array-length constraint — `MeshyAIClient.
/// createMultiImageTo3DTask` does, before encoding.
public struct MeshyMultiImageTo3DRequest: Codable, Sendable, Equatable {
    /// 2..4 entries, each a `"data:image/<jpeg|png>;base64,<...>"` URI.
    public var imageData: [String]
    public var aiModel: MeshyAIModel
    public var shouldRemesh: Bool
    public var targetPolycount: Int?
    /// Always `true` in Phase 2 for content safety.
    public var moderation: Bool
    public var enablePbr: Bool?

    private enum CodingKeys: String, CodingKey {
        case imageData       = "image_urls"
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
