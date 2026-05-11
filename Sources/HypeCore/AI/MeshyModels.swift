import Foundation

// MARK: - Request enums

/// Generation mode for `/openapi/v2/text-to-3d`. Phase 1 supports `preview`
/// only; `refine` is plumbed in the types so Phase 2 (texturing) doesn't
/// require a new schema.
public enum MeshyGenerationMode: String, Codable, Sendable {
    case preview, refine
}

/// The `ai_model` parameter accepted by Meshy. Defaults match Meshy's
/// per-model defaults for `should_remesh`: meshy-6 = false, older = true.
/// The picker in `Generate3DSheet` reads `defaultRemesh` to seed the toggle
/// when the model selection changes.
public enum MeshyAIModel: String, Codable, Sendable, CaseIterable, Identifiable {
    case meshy6 = "meshy-6"
    case meshy5 = "meshy-5"
    case meshy4 = "meshy-4"
    case latest = "latest"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .meshy6: return "Meshy 6 (recommended)"
        case .meshy5: return "Meshy 5"
        case .meshy4: return "Meshy 4"
        case .latest: return "Latest"
        }
    }

    /// Whether re-meshing should be enabled by default for this model.
    public var defaultRemesh: Bool { self == .meshy6 ? false : true }
}

/// Meshy's `art_style` parameter. Phase 1 surfaces "realistic" and
/// "sculpture" only; those are the documented stable values.
public enum MeshyArtStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case realistic, sculpture

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .realistic: return "Realistic"
        case .sculpture: return "Sculpture"
        }
    }
}

/// Output format the Generate-3D sheet asks Meshy to deliver. GLB is always
/// the primary; USDZ / FBX are optional additional downloads.
public enum MeshyOutputFormat: String, Codable, Sendable, CaseIterable, Identifiable {
    case glb, usdz, fbx

    public var id: String { rawValue }

    /// MIME type for the format.
    public var mimeType: String {
        switch self {
        case .glb: return "model/gltf-binary"
        case .usdz: return "model/vnd.usdz+zip"
        case .fbx: return "model/fbx"
        }
    }

    public var fileExtension: String { rawValue }
}

// MARK: - Task status

/// Polling state — mirrors the Meshy `status` enum but adds client-side
/// `.timedOut` and `.cancelled`.
public enum MeshyTaskStatus: String, Codable, Sendable {
    case pending = "PENDING"
    case inProgress = "IN_PROGRESS"
    case succeeded = "SUCCEEDED"
    case failed = "FAILED"
    /// Meshy uses US-English spelling "CANCELED".
    case cancelled = "CANCELED"
}

// MARK: - Request / response types

/// POST `/openapi/v2/text-to-3d` request body. Encodes to JSON with
/// snake_case keys via custom `CodingKeys` to match the Meshy API verbatim.
public struct MeshyTextTo3DRequest: Codable, Sendable, Equatable {
    public var mode: MeshyGenerationMode
    /// Required when `mode == .preview`.
    public var prompt: String?
    public var artStyle: MeshyArtStyle?
    public var aiModel: MeshyAIModel
    public var shouldRemesh: Bool
    /// 100…300_000.
    public var targetPolycount: Int?
    /// "quad" or "triangle". Phase 1 omits, Phase 2 may set.
    public var topology: String?
    /// "off" / "auto" / "on".
    public var symmetryMode: String?
    /// Always `true` in Phase 1 for content safety.
    public var moderation: Bool
    /// Ignored in Phase 1 preview.
    public var enablePbr: Bool?
    /// Required when `mode == .refine`.
    public var previewTaskId: String?

    private enum CodingKeys: String, CodingKey {
        case mode
        case prompt
        case artStyle        = "art_style"
        case aiModel         = "ai_model"
        case shouldRemesh    = "should_remesh"
        case targetPolycount = "target_polycount"
        case topology
        case symmetryMode    = "symmetry_mode"
        case moderation
        case enablePbr       = "enable_pbr"
        case previewTaskId   = "preview_task_id"
    }

    public init(
        mode: MeshyGenerationMode = .preview,
        prompt: String? = nil,
        artStyle: MeshyArtStyle? = nil,
        aiModel: MeshyAIModel = .meshy6,
        shouldRemesh: Bool = false,
        targetPolycount: Int? = nil,
        topology: String? = nil,
        symmetryMode: String? = nil,
        moderation: Bool = true,
        enablePbr: Bool? = nil,
        previewTaskId: String? = nil
    ) {
        self.mode = mode
        self.prompt = prompt
        self.artStyle = artStyle
        self.aiModel = aiModel
        self.shouldRemesh = shouldRemesh
        self.targetPolycount = targetPolycount
        self.topology = topology
        self.symmetryMode = symmetryMode
        self.moderation = moderation
        self.enablePbr = enablePbr
        self.previewTaskId = previewTaskId
    }
}

/// POST response — Meshy returns just the task id wrapped in a `result` key.
public struct MeshyCreateTaskResponse: Codable, Sendable, Equatable {
    /// Task id, typically ~32 hex characters.
    public let result: String
}

/// Map of format → download URL returned by GET when `status == .succeeded`.
/// All fields are `decodeIfPresent` → optional — Meshy returns only the
/// formats it actually produced.
public struct MeshyModelURLs: Codable, Sendable, Equatable {
    public let glb: URL?
    public let fbx: URL?
    public let usdz: URL?
    public let obj: URL?
    public let mtl: URL?
}

/// Error envelope from Meshy. Used in two places: failed-task bodies and
/// HTTP-level error responses.
public struct MeshyErrorEnvelope: Codable, Sendable, Equatable {
    public let error: String?
    public let message: String?
}

/// GET `/openapi/v2/text-to-3d/:id` response. Every field except `id` and
/// `status` is `decodeIfPresent` — a freshly-created task has only id +
/// status; intermediate polls add progress; success adds `model_urls`.
public struct MeshyTaskResponse: Codable, Sendable, Equatable {
    public let id: String
    public let status: MeshyTaskStatus
    /// 0…100. Defaults to 0 when absent.
    public let progress: Int?
    public let createdAt: Int?
    public let startedAt: Int?
    public let finishedAt: Int?
    public let modelUrls: MeshyModelURLs?
    /// Populated when `status == .failed`.
    public let taskError: MeshyErrorEnvelope?
    /// Phase 1 ignores; Phase 2 may use.
    public let textureUrls: [MeshyTextureURL]?
    /// `true` when this was a preview task.
    public let preview: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, status, progress
        case createdAt   = "created_at"
        case startedAt   = "started_at"
        case finishedAt  = "finished_at"
        case modelUrls   = "model_urls"
        case taskError   = "task_error"
        case textureUrls = "texture_urls"
        case preview
    }
}

/// PBR texture URL set for a single texture layer. Phase 1 ignores this.
public struct MeshyTextureURL: Codable, Sendable, Equatable {
    public let baseColor: URL?
    public let metallic: URL?
    public let normal: URL?
    public let roughness: URL?

    private enum CodingKeys: String, CodingKey {
        case baseColor  = "base_color"
        case metallic, normal, roughness
    }
}

/// GET `/openapi/v1/balance` response.
public struct MeshyBalanceResponse: Codable, Sendable, Equatable {
    public let balance: Int
    /// Typically "credits".
    public let currency: String?
}

// MARK: - Internal result type

/// Distilled successful-task fact passed from monitor → importer.
/// Holds the resolved download URL, NOT bytes, so the importer can
/// stream-download independently.
public struct MeshyTaskResult: Sendable, Equatable {
    public let taskId: String
    /// The GLB download URL (always required).
    public let modelURL: URL
    public let format: MeshyOutputFormat
    /// Optional USDZ download URL when the user opted in.
    public let alsoUSDZ: URL?
    /// Optional FBX download URL when the user opted in.
    public let alsoFBX: URL?
    /// The original prompt the user submitted.
    public let prompt: String
    public let aiModel: MeshyAIModel

    public init(
        taskId: String,
        modelURL: URL,
        format: MeshyOutputFormat = .glb,
        alsoUSDZ: URL? = nil,
        alsoFBX: URL? = nil,
        prompt: String,
        aiModel: MeshyAIModel
    ) {
        self.taskId = taskId
        self.modelURL = modelURL
        self.format = format
        self.alsoUSDZ = alsoUSDZ
        self.alsoFBX = alsoFBX
        self.prompt = prompt
        self.aiModel = aiModel
    }
}
