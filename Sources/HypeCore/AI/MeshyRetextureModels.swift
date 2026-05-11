import Foundation

// MARK: - Retexture request type

/// POST `/openapi/v1/retexture` request body.
///
/// Phase 4 always uses `input_task_id` + `text_style_prompt`. `model_url`
/// and `image_style_url` are intentionally absent from this struct.
///
/// **Security (C3):** The absence of `model_url` and `image_style_url` from
/// `CodingKeys` ensures the encoder can never emit either field, removing
/// two SSRF vectors.
public struct MeshyRetextureRequest: Codable, Sendable, Equatable {
    /// The task id of a prior successful Meshy task (text/image-to-3D,
    /// remesh, or earlier retexture).
    public var inputTaskId: String
    /// Texture description. Max 600 characters (Meshy limit). The
    /// `createRetextureTask` method truncates/validates before sending.
    public var textStylePrompt: String
    /// Meshy model — "meshy-6" / "meshy-5" / "latest". Defaults to "latest".
    public var aiModel: MeshyAIModel?
    /// Preserve existing UVs. Defaults to true.
    public var enableOriginalUv: Bool?
    /// Generate PBR maps. Defaults to false.
    public var enablePbr: Bool?
    /// 4K base color. meshy-6/latest only. Defaults to false.
    public var hdTexture: Bool?
    /// Clean baked lighting from textures. meshy-6/latest only.
    public var removeLighting: Bool?
    /// Output formats. Defaults to ["glb"].
    public var targetFormats: [String]?

    private enum CodingKeys: String, CodingKey {
        case inputTaskId       = "input_task_id"
        case textStylePrompt   = "text_style_prompt"
        case aiModel           = "ai_model"
        case enableOriginalUv  = "enable_original_uv"
        case enablePbr         = "enable_pbr"
        case hdTexture         = "hd_texture"
        case removeLighting    = "remove_lighting"
        case targetFormats     = "target_formats"
    }

    public init(
        inputTaskId: String,
        textStylePrompt: String,
        aiModel: MeshyAIModel? = nil,
        enableOriginalUv: Bool? = nil,
        enablePbr: Bool? = nil,
        hdTexture: Bool? = nil,
        removeLighting: Bool? = nil,
        targetFormats: [String]? = nil
    ) {
        self.inputTaskId = inputTaskId
        // Truncate to 600 chars at the encoder layer — silent per Meshy docs (C6).
        self.textStylePrompt = String(textStylePrompt.prefix(600))
        self.aiModel = aiModel
        self.enableOriginalUv = enableOriginalUv
        self.enablePbr = enablePbr
        self.hdTexture = hdTexture
        self.removeLighting = removeLighting
        self.targetFormats = targetFormats
    }
}

// MARK: - Retexture task response

/// GET `/openapi/v1/retexture/<id>` response.
public struct MeshyRetextureTaskResponse: Codable, Sendable, Equatable {
    public let id: String
    public let status: MeshyTaskStatus
    /// 0…100. Defaults to 0 when absent.
    public let progress: Int?
    public let createdAt: Int?
    public let startedAt: Int?
    public let finishedAt: Int?
    public let expiresAt: Int?
    /// Present when `status == .succeeded`.
    public let modelUrls: MeshyModelURLs?
    /// PBR texture URLs for each material layer.
    ///
    /// **Security (Phase 4 M2):** UNSANITIZED — these per-layer URLs
    /// come straight from the Meshy API response with no host
    /// allowlist check. Phase 4 has no UI consumer; if a future
    /// caller surfaces these URLs to a `WebView` or for download,
    /// it MUST pass each through `MeshyPolledFact.sanitizedMeshyURL`
    /// and drop the result if it returns nil.
    public let textureUrls: [MeshyTextureURL]?
    /// Thumbnail image URL for display in the UI.
    ///
    /// **Security (Phase 4 M2):** UNSANITIZED — see note above. Pass
    /// through `MeshyPolledFact.sanitizedMeshyURL` before navigation
    /// or display.
    public let thumbnailUrl: URL?
    /// Populated when `status == .failed`.
    public let taskError: MeshyErrorEnvelope?
    /// Credits consumed by this task.
    public let consumedCredits: Int?

    private enum CodingKeys: String, CodingKey {
        case id, status, progress
        case createdAt         = "created_at"
        case startedAt         = "started_at"
        case finishedAt        = "finished_at"
        case expiresAt         = "expires_at"
        case modelUrls         = "model_urls"
        case textureUrls       = "texture_urls"
        case thumbnailUrl      = "thumbnail_url"
        case taskError         = "task_error"
        case consumedCredits   = "consumed_credits"
    }
}
