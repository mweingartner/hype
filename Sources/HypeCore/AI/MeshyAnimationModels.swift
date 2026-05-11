import Foundation

// MARK: - MeshyActionId

/// A typed Meshy animation action id. Wrapping in a struct prevents callers
/// from accidentally passing a generic `Int` (e.g. an asset count or array
/// index) where an action id is expected.
///
/// **Security (M1):** `init(from:)` rejects values outside 0…1000.
/// The live catalog has ~587 entries; 1000 gives headroom for future additions.
public struct MeshyActionId: Hashable, Codable, Sendable, ExpressibleByIntegerLiteral {
    public let value: Int

    /// - Throws: `MeshyError.validationFailed` if `value` is outside 0…1000.
    public init(_ value: Int) throws {
        guard value >= 0 && value <= 1000 else {
            throw MeshyError.validationFailed(
                field: "action_id",
                reason: "Action id must be between 0 and 1000 (got \(value))."
            )
        }
        self.value = value
    }

    /// For test literals only — fatal if out of range.
    public init(integerLiteral value: Int) {
        precondition(value >= 0 && value <= 1000, "MeshyActionId integer literal out of range 0…1000: \(value)")
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(Int.self)
        guard raw >= 0 && raw <= 1000 else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "MeshyActionId value \(raw) out of range 0…1000"
            ))
        }
        self.value = raw
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

// MARK: - Animation request

/// POST `/openapi/v1/animations` request body.
public struct MeshyAnimationRequest: Codable, Sendable, Equatable {
    /// The id of a previously-completed rigging task.
    public var rigTaskId: String
    /// The numeric id of the animation action to apply.
    public var actionId: MeshyActionId
    /// Optional post-process options. Phase 3 omits — Meshy's defaults
    /// produce a ready-to-use GLB.
    public var postProcess: MeshyAnimationPostProcess?

    private enum CodingKeys: String, CodingKey {
        case rigTaskId   = "rig_task_id"
        case actionId    = "action_id"
        case postProcess = "post_process"
    }

    public init(
        rigTaskId: String,
        actionId: MeshyActionId,
        postProcess: MeshyAnimationPostProcess? = nil
    ) {
        self.rigTaskId = rigTaskId
        self.actionId = actionId
        self.postProcess = postProcess
    }
}

/// Optional post-processing step requested with an animation job.
public struct MeshyAnimationPostProcess: Codable, Sendable, Equatable {
    /// `"change_fps"` | `"fbx2usdz"` | `"extract_armature"`
    public let operationType: String
    /// Frame rate for `"change_fps"` operation: 24 | 25 | 30 | 60.
    public let fps: Int?

    private enum CodingKeys: String, CodingKey {
        case operationType = "operation_type"
        case fps
    }
}

// MARK: - Animation task response

/// GET `/openapi/v1/animations/<id>` response.
public struct MeshyAnimationTaskResponse: Codable, Sendable, Equatable {
    public let id: String
    public let status: MeshyTaskStatus
    public let progress: Int?
    public let createdAt: Int?
    public let startedAt: Int?
    public let finishedAt: Int?
    public let consumedCredits: Int?
    public let result: MeshyAnimationTaskResult?
    /// Populated when `status == .failed`.
    public let taskError: MeshyErrorEnvelope?

    private enum CodingKeys: String, CodingKey {
        case id, status, progress, result
        case createdAt       = "created_at"
        case startedAt       = "started_at"
        case finishedAt      = "finished_at"
        case consumedCredits = "consumed_credits"
        case taskError       = "task_error"
    }
}

/// Result body within a succeeded animation task response.
public struct MeshyAnimationTaskResult: Codable, Sendable, Equatable {
    public let animationGlbUrl: URL?
    public let animationFbxUrl: URL?
    public let processedUsdzUrl: URL?
    public let processedArmatureFbxUrl: URL?
    public let processedAnimationFpsFbxUrl: URL?

    private enum CodingKeys: String, CodingKey {
        case animationGlbUrl             = "animation_glb_url"
        case animationFbxUrl             = "animation_fbx_url"
        case processedUsdzUrl            = "processed_usdz_url"
        case processedArmatureFbxUrl     = "processed_armature_fbx_url"
        case processedAnimationFpsFbxUrl = "processed_animation_fps_fbx_url"
    }
}

// MARK: - Animation catalog entry

/// One row in the Meshy Animation Library reference table.
///
/// The table is curated by Meshy and shipped as a static JSON resource
/// (see `MeshyAnimationCatalog`) because Meshy provides NO API endpoint
/// to list animations (confirmed against `docs.meshy.ai/en/api/animation-library`
/// on 2026-05-11). There are ~587 entries; ids range from 0 to 586 with gaps.
public struct MeshyAnimationEntry: Codable, Sendable, Hashable, Identifiable {
    /// Numeric action id used with the animation API.
    public let id: MeshyActionId
    /// Animation name (e.g. "Idle", "Walking_Woman", "Boxing_Practice").
    /// Underscores in the name are preserved from Meshy's reference table;
    /// the UI replaces them with spaces for display.
    public let name: String
    /// Broad category (e.g. "DailyActions", "Fighting", "Dancing").
    public let category: String
    /// Specific subcategory (e.g. "Idle", "Walking", "Punching").
    public let subCategory: String
    /// Optional preview URL — Phase 3 stores the URL but does NOT fetch
    /// the GIF in-app. Network egress for previews is explicit future work
    /// (Phase 4 candidate). UI shows a placeholder.
    public let previewUrl: String?

    /// Display-friendly version of `name` with underscores → spaces.
    public var displayName: String {
        name.replacingOccurrences(of: "_", with: " ")
    }
}
