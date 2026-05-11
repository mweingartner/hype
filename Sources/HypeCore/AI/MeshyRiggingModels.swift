import Foundation

// MARK: - Rigging request type

/// POST `/openapi/v1/rigging` request body.
///
/// Meshy's rigging endpoint accepts EITHER `input_task_id` (a previously-
/// completed text-to-3D / image-to-3D task) OR `model_url` (a publicly-
/// fetchable GLB). Phase 3 always uses `input_task_id` so model bytes
/// never leave the user's machine via a third-party URL.
///
/// **Security (H2):** `model_url` and `textureImageUrl` are intentionally
/// absent from this struct — the codec cannot emit either field.
/// This removes two SSRF vectors from the wire format.
public struct MeshyRiggingRequest: Codable, Sendable, Equatable {
    /// The task id of a prior successful Meshy 3D-generation task whose
    /// output is a humanoid GLB.
    public var inputTaskId: String
    /// Optional character height in meters, for scaling. Meshy's default
    /// is 1.7 m when nil.
    public var heightMeters: Double?

    private enum CodingKeys: String, CodingKey {
        case inputTaskId  = "input_task_id"
        case heightMeters = "height_meters"
    }

    public init(
        inputTaskId: String,
        heightMeters: Double? = nil
    ) {
        self.inputTaskId = inputTaskId
        self.heightMeters = heightMeters
    }
}

// MARK: - Rigging task response

/// GET `/openapi/v1/rigging/<id>` response.
///
/// The response shape diverges from text-to-3D's `model_urls` object.
/// Meshy uses explicitly-named top-level fields for the rigged GLB/FBX
/// URLs plus a `basic_animations` substructure for bundled walk/run clips.
public struct MeshyRiggingTaskResponse: Codable, Sendable, Equatable {
    public let id: String
    public let status: MeshyTaskStatus
    public let progress: Int?
    public let createdAt: Int?
    public let startedAt: Int?
    public let finishedAt: Int?
    /// Final rigged-character GLB URL. Present when `status == .succeeded`.
    public let riggedCharacterGlbUrl: URL?
    /// Final rigged-character FBX URL. Present when `status == .succeeded`.
    public let riggedCharacterFbxUrl: URL?
    /// Optional walking/running animations bundled with the rig. Shape:
    /// `{ walking: { glb, fbx }, running: { glb, fbx } }`.
    public let basicAnimations: MeshyBasicAnimations?
    /// Populated when `status == .failed`.
    public let taskError: MeshyErrorEnvelope?

    private enum CodingKeys: String, CodingKey {
        case id, status, progress
        case createdAt             = "created_at"
        case startedAt             = "started_at"
        case finishedAt            = "finished_at"
        case riggedCharacterGlbUrl = "rigged_character_glb_url"
        case riggedCharacterFbxUrl = "rigged_character_fbx_url"
        case basicAnimations       = "basic_animations"
        case taskError             = "task_error"
    }
}

// MARK: - Basic animations sub-types

/// `basic_animations` substructure from a rigging task response.
public struct MeshyBasicAnimations: Codable, Sendable, Equatable {
    public let walking: MeshyAnimationFormats?
    public let running: MeshyAnimationFormats?
}

/// Per-format URL pair for a single basic animation (walking or running).
public struct MeshyAnimationFormats: Codable, Sendable, Equatable {
    public let glb: URL?
    public let fbx: URL?
}
