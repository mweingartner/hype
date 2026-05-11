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

/// Discriminates between Meshy task kinds so `cancelTask` and `fetchTaskFact`
/// can route to the correct v1 or v2 endpoint.
///
/// - `textTo3D`: `/openapi/v2/text-to-3d/<id>` (Phase 1 default)
/// - `imageTo3D`: `/openapi/v1/image-to-3d/<id>`
/// - `multiImageTo3D`: `/openapi/v1/multi-image-to-3d/<id>`
/// - `rigging`: `/openapi/v1/rigging/<id>` (Phase 3)
/// - `animation`: `/openapi/v1/animations/<id>` (Phase 3)
public enum MeshyTaskKind: String, Sendable, Equatable {
    case textTo3D
    case imageTo3D
    case multiImageTo3D
    /// Phase 3: rigging task.
    case rigging
    /// Phase 3: animation task.
    case animation
}

/// POST response — Meshy v2 returns `{ "result": "<id>" }`;
/// Meshy v1 endpoints may return `{ "id": "<id>" }` instead.
///
/// The custom `init(from:)` tries `result` first, then falls back to `id`.
/// This is forward-compatible and avoids a smoke-test requirement against
/// the live API during development.
public struct MeshyCreateTaskResponse: Sendable, Equatable {
    /// Normalised task id — populated from `result` (v2) or `id` (v1).
    public let result: String

    private enum CodingKeys: String, CodingKey { case result, id }
}

extension MeshyCreateTaskResponse: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let r = try c.decodeIfPresent(String.self, forKey: .result), !r.isEmpty {
            self.result = r
        } else if let r = try c.decodeIfPresent(String.self, forKey: .id), !r.isEmpty {
            self.result = r
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: c.codingPath,
                debugDescription: "Neither 'result' nor 'id' present in MeshyCreateTaskResponse"
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(result, forKey: .result)
    }
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
    /// Phase 3: basic walking animation GLB URL when the task is a rigging
    /// task with `alsoBasicWalk == true`. Nil otherwise.
    public let basicWalkUrl: URL?
    /// Phase 3: basic running animation GLB URL when applicable.
    public let basicRunUrl: URL?

    public init(
        taskId: String,
        modelURL: URL,
        format: MeshyOutputFormat = .glb,
        alsoUSDZ: URL? = nil,
        alsoFBX: URL? = nil,
        prompt: String,
        aiModel: MeshyAIModel,
        basicWalkUrl: URL? = nil,
        basicRunUrl: URL? = nil
    ) {
        self.taskId = taskId
        self.modelURL = modelURL
        self.format = format
        self.alsoUSDZ = alsoUSDZ
        self.alsoFBX = alsoFBX
        self.prompt = prompt
        self.aiModel = aiModel
        self.basicWalkUrl = basicWalkUrl
        self.basicRunUrl = basicRunUrl
    }
}

// MARK: - MeshyPolledFact

/// Internal homogenised fact yielded by `MeshyClient.fetchTaskFact`.
///
/// Squashes the kind-specific wire responses (text/image/multi-image-3D,
/// rigging, animation) into one normalised view. `MeshyTaskMonitor`
/// consumes only this type; the wire types stay isolated to the client's
/// HTTP boundary.
///
/// - `primaryModelUrl` is the GLB URL appropriate for this kind:
///   - text/image/multi-image: `model_urls.glb`
///   - rigging: `rigged_character_glb_url`
///   - animation: `result.animation_glb_url`
/// - `usdzUrl` / `fbxUrl` are populated for text/image/multi-image tasks
///   when Meshy delivers them; always `nil` for rigging/animation.
/// - `basicWalkUrl` / `basicRunUrl` are populated ONLY for rigging tasks.
public struct MeshyPolledFact: Sendable, Equatable {
    public let taskId: String
    public let status: MeshyTaskStatus
    public let progress: Int?
    public let primaryModelUrl: URL?
    public let usdzUrl: URL?
    public let fbxUrl: URL?
    /// Rigging only: basic walking animation GLB bundled with the rig.
    public let basicWalkUrl: URL?
    /// Rigging only: basic running animation GLB bundled with the rig.
    public let basicRunUrl: URL?
    public let errorMessage: String?

    public init(
        taskId: String,
        status: MeshyTaskStatus,
        progress: Int? = nil,
        primaryModelUrl: URL? = nil,
        usdzUrl: URL? = nil,
        fbxUrl: URL? = nil,
        basicWalkUrl: URL? = nil,
        basicRunUrl: URL? = nil,
        errorMessage: String? = nil
    ) {
        self.taskId = taskId
        self.status = status
        self.progress = progress
        self.primaryModelUrl = primaryModelUrl
        self.usdzUrl = usdzUrl
        self.fbxUrl = fbxUrl
        self.basicWalkUrl = basicWalkUrl
        self.basicRunUrl = basicRunUrl
        self.errorMessage = errorMessage
    }

    // MARK: - Factories

    /// Construct a fact from a text-to-3D, image-to-3D, or multi-image-to-3D
    /// wire response. `kind` is recorded for logging purposes only.
    public static func fromTextOrImageTo3D(
        _ resp: MeshyTaskResponse,
        kind: MeshyTaskKind
    ) -> MeshyPolledFact {
        _ = kind  // logged at call site; not stored in the fact
        let errorMsg = resp.taskError?.message ?? resp.taskError?.error
        return MeshyPolledFact(
            taskId: resp.id,
            status: resp.status,
            progress: resp.progress,
            primaryModelUrl: resp.modelUrls?.glb,
            usdzUrl: resp.modelUrls?.usdz,
            fbxUrl: resp.modelUrls?.fbx,
            basicWalkUrl: nil,
            basicRunUrl: nil,
            errorMessage: errorMsg.map { String($0.prefix(200)) }
        )
    }

    /// Construct a fact from a rigging task wire response.
    ///
    /// **Security (H3):** every URL is passed through `sanitizedMeshyURL`.
    /// A URL that fails the host check becomes `nil` in the fact rather
    /// than propagating an untrusted URL to the downloader.
    public static func fromRigging(_ resp: MeshyRiggingTaskResponse) -> MeshyPolledFact {
        let errorMsg = resp.taskError?.message ?? resp.taskError?.error
        let glbUrl = sanitizedMeshyURL(resp.riggedCharacterGlbUrl)
        let walkUrl = sanitizedMeshyURL(resp.basicAnimations?.walking?.glb)
        let runUrl = sanitizedMeshyURL(resp.basicAnimations?.running?.glb)

        return MeshyPolledFact(
            taskId: resp.id,
            status: resp.status,
            progress: resp.progress,
            primaryModelUrl: glbUrl,
            usdzUrl: nil,
            fbxUrl: sanitizedMeshyURL(resp.riggedCharacterFbxUrl),
            basicWalkUrl: walkUrl,
            basicRunUrl: runUrl,
            errorMessage: errorMsg.map { String($0.prefix(200)) }
        )
    }

    /// Construct a fact from an animation task wire response.
    ///
    /// **Security (H3):** every URL is passed through `sanitizedMeshyURL`.
    public static func fromAnimation(_ resp: MeshyAnimationTaskResponse) -> MeshyPolledFact {
        let errorMsg = resp.taskError?.message ?? resp.taskError?.error
        let glbUrl = sanitizedMeshyURL(resp.result?.animationGlbUrl)

        return MeshyPolledFact(
            taskId: resp.id,
            status: resp.status,
            progress: resp.progress,
            primaryModelUrl: glbUrl,
            usdzUrl: nil,
            fbxUrl: sanitizedMeshyURL(resp.result?.animationFbxUrl),
            basicWalkUrl: nil,
            basicRunUrl: nil,
            errorMessage: errorMsg.map { String($0.prefix(200)) }
        )
    }

    // MARK: - H3 URL sanitizer

    /// Rejects any URL that is not HTTPS and hosted on `meshy.ai` or a
    /// subdomain. Returns `nil` for non-conforming URLs.
    ///
    /// This provides defense-in-depth at the fact-construction boundary.
    /// Even if a future Meshy response accidentally includes a non-Meshy
    /// URL, it becomes `nil` here before ever reaching the downloader.
    private static func sanitizedMeshyURL(_ url: URL?) -> URL? {
        guard let url,
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              host == "meshy.ai" || host.hasSuffix(".meshy.ai")
        else {
            if let url {
                // Log the drop without emitting the raw URL value.
                let host = url.host ?? "(no host)"
                _ = host  // available for breakpoints; not logged to prevent URL leakage
            }
            return nil
        }
        return url
    }
}
