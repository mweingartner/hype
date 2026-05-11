import Foundation

/// Decoder for a Meshy webhook POST body.
///
/// Meshy's webhook delivers a JSON object identical in shape to the GET
/// response for the task that completed. Phase 4 ships this decoder so a
/// user-authored `listen for http` recipe can extract the few fields a
/// script cares about: `task_id`, `status`, `type`, primary GLB URL.
///
/// **Security (C13):** this is a pure value-type decoder. It performs no I/O
/// and no URL dereferencing. The caller (a HypeTalk handler) is responsible
/// for downloading the asset via a separate, allowlisted code path —
/// typically by triggering a Meshy3DAssetImporter run with the task id.
///
/// **No HMAC verification (C18):** per design doc §11, Meshy webhooks are not
/// signed. The webhook URL itself is the shared secret. Authors choosing
/// to wire this recipe MUST use a tunnel they control. See HypeTalkGuide
/// for the security notes. The decoder doc comment, HypeTalkGuide, and the
/// Preferences disclosure all document this acknowledged design decision.
public struct MeshyWebhookPayload: Sendable, Equatable {
    /// The Meshy task id.
    public let id: String
    /// The task type — one of "text_to_3d", "image_to_3d",
    /// "multi_image_to_3d", "rigging", "animation", "remesh", "retexture".
    /// Used by handlers to decide what to do next.
    public let type: String?
    /// Task status. The webhook fires on terminal states (`SUCCEEDED`,
    /// `FAILED`, `CANCELED`) and may also fire for transitional updates
    /// depending on Meshy account config.
    public let status: MeshyTaskStatus
    /// Primary GLB URL when present, sanitized via `MeshyPolledFact.sanitizedMeshyURL`.
    /// Non-Meshy URLs are set to nil (C4).
    public let glbUrl: URL?
    /// Error message when status is FAILED.
    public let errorMessage: String?

    // MARK: - Public API

    /// Parse a webhook body. Returns nil on shape mismatch.
    ///
    /// **Security (C13):** pure-function decoder — String in, struct out.
    /// No I/O, no network, no FileManager. All URL fields are sanitized via
    /// `MeshyPolledFact.sanitizedMeshyURL` (C4).
    ///
    /// - Parameter jsonBody: Raw HTTP request body as a `String`.
    /// - Returns: `MeshyWebhookPayload` on success, `nil` on any decode failure.
    public static func parse(jsonBody: String) -> MeshyWebhookPayload? {
        guard let data = jsonBody.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MeshyWebhookPayload.self, from: data)
    }

    /// Produce a comma-separated `task_id,status,glb_url` string suitable
    /// for returning to a HypeTalk script. Empty URL field if absent.
    ///
    /// **Security (Phase 4 F1):** the `id` field arrives from untrusted
    /// webhook JSON. Without HMAC verification, an attacker who knows the
    /// user's webhook URL can submit an `id` containing commas, which
    /// would inject extra fields when a HypeTalk handler splits the
    /// result by `,` (e.g. `id="abc,SUCCEEDED,https://evil.com"` would
    /// produce a CSV whose third field is the attacker's URL). Strip
    /// commas from the id before splicing; `status.rawValue` is a fixed
    /// enum (safe), and `glbUrl` was already host-validated through
    /// `sanitizedMeshyURL` at decode time (safe).
    public func toCSV() -> String {
        let safeId = id.replacingOccurrences(of: ",", with: "")
        let urlPart = glbUrl?.absoluteString ?? ""
        return "\(safeId),\(status.rawValue),\(urlPart)"
    }
}

// MARK: - Codable conformance

extension MeshyWebhookPayload: Codable {

    private enum CodingKeys: String, CodingKey {
        case id, type, status
        case modelUrls          = "model_urls"
        case taskError          = "task_error"
        case riggedCharacterGlbUrl = "rigged_character_glb_url"
        case result
        case animationGlbUrl    = "animation_glb_url"
    }

    /// Sub-container for animation webhook results.
    private struct InnerResult: Decodable {
        let animationGlbUrl: URL?
        private enum CodingKeys: String, CodingKey {
            case animationGlbUrl = "animation_glb_url"
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id     = try c.decode(String.self, forKey: .id)
        type   = try c.decodeIfPresent(String.self, forKey: .type)
        status = try c.decode(MeshyTaskStatus.self, forKey: .status)

        // Determine primary GLB URL — priority: model_urls.glb → rigged_character_glb_url
        // → result.animation_glb_url. All URLs flow through sanitizedMeshyURL (C4).
        if let modelUrls = try c.decodeIfPresent(MeshyModelURLs.self, forKey: .modelUrls),
           let rawGlb = modelUrls.glb {
            glbUrl = MeshyPolledFact.sanitizedMeshyURL(rawGlb)
        } else if let rawRigged = try c.decodeIfPresent(URL.self, forKey: .riggedCharacterGlbUrl) {
            glbUrl = MeshyPolledFact.sanitizedMeshyURL(rawRigged)
        } else if let inner = try c.decodeIfPresent(InnerResult.self, forKey: .result),
                  let rawAnim = inner.animationGlbUrl {
            glbUrl = MeshyPolledFact.sanitizedMeshyURL(rawAnim)
        } else {
            glbUrl = nil
        }

        // Error message from task_error envelope, truncated to 200 chars.
        if let envelope = try c.decodeIfPresent(MeshyErrorEnvelope.self, forKey: .taskError) {
            let msg = envelope.message ?? envelope.error
            errorMessage = msg.map { String($0.prefix(200)) }
        } else {
            errorMessage = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(type, forKey: .type)
        try c.encode(status, forKey: .status)
        // Encode glbUrl into model_urls.glb for round-trip fidelity.
        if let url = glbUrl {
            let urls = MeshyModelURLs(glb: url, fbx: nil, usdz: nil, obj: nil, mtl: nil)
            try c.encode(urls, forKey: .modelUrls)
        }
        if let msg = errorMessage {
            try c.encode(MeshyErrorEnvelope(error: nil, message: msg), forKey: .taskError)
        }
    }
}
