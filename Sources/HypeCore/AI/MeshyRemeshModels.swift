import Foundation

// MARK: - Remesh request type

/// POST `/openapi/v1/remesh` request body.
///
/// Phase 4 always uses `input_task_id` (never `model_url`) so model bytes
/// stay private to the user's account. `model_url` is intentionally absent
/// from this struct — the codec cannot emit it.
///
/// **Security (C2):** The absence of `model_url` from `CodingKeys` ensures
/// the encoder can never emit that field, removing an SSRF vector.
public struct MeshyRemeshRequest: Codable, Sendable, Equatable {
    /// The task id of a prior successful Meshy 3D-generation, rigging, or
    /// retexture task.
    public var inputTaskId: String
    /// Target polygon count. Range 100…300_000 (validated at multiple layers).
    public var targetPolycount: Int
    /// Topology — "quad" or "triangle". Defaults to "triangle" when nil.
    public var topology: String?
    /// 1…4 — adaptive decimation level (per Meshy docs).
    public var decimationMode: Int?
    /// Target height in meters. 0 means "no resize".
    public var resizeHeight: Double?
    /// AI-estimated sizing toggle. Defaults to false.
    public var autoSize: Bool?
    /// "bottom" or "center". Defaults to "bottom".
    public var originAt: String?
    /// When true, performs format conversion only (no remesh).
    public var convertFormatOnly: Bool?

    private enum CodingKeys: String, CodingKey {
        case inputTaskId        = "input_task_id"
        case targetPolycount    = "target_polycount"
        case topology
        case decimationMode     = "decimation_mode"
        case resizeHeight       = "resize_height"
        case autoSize           = "auto_size"
        case originAt           = "origin_at"
        case convertFormatOnly  = "convert_format_only"
    }

    public init(
        inputTaskId: String,
        targetPolycount: Int,
        topology: String? = nil,
        decimationMode: Int? = nil,
        resizeHeight: Double? = nil,
        autoSize: Bool? = nil,
        originAt: String? = nil,
        convertFormatOnly: Bool? = nil
    ) {
        self.inputTaskId = inputTaskId
        self.targetPolycount = targetPolycount
        self.topology = topology
        self.decimationMode = decimationMode
        self.resizeHeight = resizeHeight
        self.autoSize = autoSize
        self.originAt = originAt
        self.convertFormatOnly = convertFormatOnly
    }
}

// MARK: - Remesh task response

/// GET `/openapi/v1/remesh/<id>` response.
///
/// Same shape as text-to-3D's `MeshyTaskResponse` (`model_urls` + `status` +
/// timestamps + `task_error`). The wire response also carries `type: "remesh"`
/// and an optional `preceding_tasks` queue position — both ignored by Hype.
public struct MeshyRemeshTaskResponse: Codable, Sendable, Equatable {
    public let id: String
    public let status: MeshyTaskStatus
    /// 0…100. Defaults to 0 when absent.
    public let progress: Int?
    public let createdAt: Int?
    public let startedAt: Int?
    public let finishedAt: Int?
    /// Present when `status == .succeeded`.
    public let modelUrls: MeshyModelURLs?
    /// Populated when `status == .failed`.
    public let taskError: MeshyErrorEnvelope?
    /// Credits consumed by this task. Phase 4 logs but doesn't enforce.
    public let consumedCredits: Int?

    private enum CodingKeys: String, CodingKey {
        case id, status, progress
        case createdAt        = "created_at"
        case startedAt        = "started_at"
        case finishedAt       = "finished_at"
        case modelUrls        = "model_urls"
        case taskError        = "task_error"
        case consumedCredits  = "consumed_credits"
    }
}
