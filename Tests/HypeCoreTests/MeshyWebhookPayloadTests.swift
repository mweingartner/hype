import Foundation
import Testing
@testable import HypeCore

// MARK: - MeshyWebhookPayloadTests

@Suite("Webhook payload decoder")
struct MeshyWebhookPayloadTests {

    // MARK: (a) parse returns nil for malformed JSON

    @Test("parse(jsonBody:) returns nil for malformed JSON")
    func returnsNilForMalformedJSON() {
        let result = MeshyWebhookPayload.parse(jsonBody: "not json at all")
        #expect(result == nil)
    }

    @Test("parse(jsonBody:) returns nil for empty string")
    func returnsNilForEmptyString() {
        let result = MeshyWebhookPayload.parse(jsonBody: "")
        #expect(result == nil)
    }

    @Test("parse(jsonBody:) returns nil when id field missing")
    func returnsNilWhenIdMissing() {
        let result = MeshyWebhookPayload.parse(jsonBody: #"{"status":"SUCCEEDED"}"#)
        #expect(result == nil)
    }

    // MARK: (b) decodes a text-to-3D succeeded webhook

    @Test("parse decodes a text-to-3D SUCCEEDED webhook with model_urls.glb")
    func decodesTextTo3DSucceeded() {
        let body = """
        {
          "id": "task_text_001",
          "type": "text_to_3d",
          "status": "SUCCEEDED",
          "model_urls": {
            "glb": "https://assets.meshy.ai/models/001.glb",
            "fbx": "https://assets.meshy.ai/models/001.fbx"
          }
        }
        """
        let payload = MeshyWebhookPayload.parse(jsonBody: body)

        #expect(payload != nil)
        #expect(payload?.id == "task_text_001")
        #expect(payload?.type == "text_to_3d")
        #expect(payload?.status == .succeeded)
        #expect(payload?.glbUrl?.absoluteString == "https://assets.meshy.ai/models/001.glb")
    }

    // MARK: (c) decodes a rigging webhook using rigged_character_glb_url

    @Test("parse decodes a rigging SUCCEEDED webhook using rigged_character_glb_url")
    func decodesRiggingSucceeded() {
        let body = """
        {
          "id": "rig_task_002",
          "type": "rigging",
          "status": "SUCCEEDED",
          "rigged_character_glb_url": "https://assets.meshy.ai/rigs/002.glb"
        }
        """
        let payload = MeshyWebhookPayload.parse(jsonBody: body)

        #expect(payload?.id == "rig_task_002")
        #expect(payload?.type == "rigging")
        #expect(payload?.status == .succeeded)
        #expect(payload?.glbUrl?.absoluteString == "https://assets.meshy.ai/rigs/002.glb")
    }

    // MARK: (d) decodes an animation webhook using result.animation_glb_url

    @Test("parse decodes an animation SUCCEEDED webhook using result.animation_glb_url")
    func decodesAnimationSucceeded() {
        let body = """
        {
          "id": "anim_task_003",
          "type": "animation",
          "status": "SUCCEEDED",
          "result": {
            "animation_glb_url": "https://assets.meshy.ai/anims/003.glb"
          }
        }
        """
        let payload = MeshyWebhookPayload.parse(jsonBody: body)

        #expect(payload?.id == "anim_task_003")
        #expect(payload?.glbUrl?.absoluteString == "https://assets.meshy.ai/anims/003.glb")
    }

    // MARK: (e) attacker URL in model_urls.glb becomes nil (URL sanitization C4)

    @Test("parse sanitizes attacker GLB URL — non-meshy.ai host becomes nil (C4)")
    func sanitizesAttackerGLBUrl() {
        let body = """
        {
          "id": "task_attack_001",
          "status": "SUCCEEDED",
          "model_urls": {
            "glb": "https://evil.example.com/steal.glb"
          }
        }
        """
        let payload = MeshyWebhookPayload.parse(jsonBody: body)

        // Status decodes fine, but the attacker URL is filtered out.
        #expect(payload?.id == "task_attack_001")
        #expect(payload?.glbUrl == nil, "Non-meshy.ai GLB URL must be filtered (C4)")
    }

    // MARK: (f) decodes FAILED status with error message

    @Test("parse decodes FAILED webhook with task_error message")
    func decodesFailedWithError() {
        let body = """
        {
          "id": "task_fail_001",
          "status": "FAILED",
          "task_error": {"message": "Model topology invalid."}
        }
        """
        let payload = MeshyWebhookPayload.parse(jsonBody: body)

        #expect(payload?.status == .failed)
        #expect(payload?.errorMessage == "Model topology invalid.")
        #expect(payload?.glbUrl == nil)
    }

    // MARK: (g) toCSV() formats output correctly

    @Test("toCSV() returns task_id,status,glb_url when glbUrl is present")
    func toCsvFormatsWithUrl() {
        let body = """
        {
          "id": "csv_task_001",
          "status": "SUCCEEDED",
          "model_urls": {
            "glb": "https://assets.meshy.ai/m/001.glb"
          }
        }
        """
        let payload = MeshyWebhookPayload.parse(jsonBody: body)!
        let csv = payload.toCSV()

        #expect(csv == "csv_task_001,SUCCEEDED,https://assets.meshy.ai/m/001.glb")
    }

    @Test("toCSV() returns task_id,status, when glbUrl is absent")
    func toCsvFormatsWithoutUrl() {
        let body = """
        {
          "id": "csv_task_002",
          "status": "FAILED",
          "task_error": {"message": "Error"}
        }
        """
        let payload = MeshyWebhookPayload.parse(jsonBody: body)!
        let csv = payload.toCSV()

        #expect(csv == "csv_task_002,FAILED,")
    }

    // MARK: (g3) Phase 4 F1 — toCSV strips commas from `id` to defeat CSV injection

    @Test("toCSV() strips embedded commas from id (Phase 4 F1)")
    func toCSVStripsCommasFromId() {
        // Attacker submits an id designed to inject a fake status + URL when a
        // HypeTalk handler splits the CSV. Without sanitization, splitting by
        // comma would produce 5 fields and item 3 would be an evil URL.
        let body = """
        {
          "id": "abc,SUCCEEDED,https://evil.com",
          "status": "PENDING"
        }
        """
        let payload = MeshyWebhookPayload.parse(jsonBody: body)!
        let csv = payload.toCSV()

        // The malicious commas in `id` must be stripped before splicing —
        // splitting the output by comma MUST yield exactly 3 fields, and
        // the status + url fields MUST remain in their canonical positions.
        let parts = csv.split(separator: ",", omittingEmptySubsequences: false)
        #expect(parts.count == 3, "CSV must yield exactly 3 fields, not \(parts.count): \(csv)")
        // Second field must be the real status, not the attacker-supplied SUCCEEDED.
        #expect(String(parts[1]) == "PENDING")
        // Third field is empty (no glb_url at PENDING status). MUST NOT be the
        // attacker URL.
        #expect(String(parts[2]) == "")
        // The attacker's URL substring may legitimately remain INSIDE the id
        // field (parts[0]) — that's where the user expects untrusted content.
        // What matters is that it is NOT in the URL field (parts[2]).
        #expect(!String(parts[2]).contains("evil.com"))
    }

    // MARK: (h) decoder ignores unknown fields

    @Test("parse ignores unknown top-level JSON fields")
    func ignoresUnknownFields() {
        let body = """
        {
          "id": "task_unknown_001",
          "status": "PENDING",
          "some_future_field": "ignored",
          "another_new_field": 42
        }
        """
        let payload = MeshyWebhookPayload.parse(jsonBody: body)

        #expect(payload?.id == "task_unknown_001")
        #expect(payload?.status == .pending)
    }
}
