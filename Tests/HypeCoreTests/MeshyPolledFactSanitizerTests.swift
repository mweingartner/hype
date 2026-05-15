import Foundation
import Testing
@testable import HypeCore

/// Tests for `MeshyPolledFact.sanitizedMeshyURL` (H3 defense-in-depth).
///
/// `fromRigging` and `fromAnimation` must reject non-Meshy URLs even if
/// Meshy's API ever returns an unexpected host in a wire response.
@Suite("MeshyPolledFact — URL sanitizer (security H3)")
struct MeshyPolledFactSanitizerTests {

    @Test("fromTextOrImageTo3D sanitizes model_urls host")
    func textImageFactorySanitizesModelUrls() throws {
        let resp = MeshyTaskResponse(
            id: "txt_001",
            status: .succeeded,
            progress: 100,
            createdAt: nil,
            startedAt: nil,
            finishedAt: nil,
            modelUrls: MeshyModelURLs(
                glb: URL(string: "https://evil.example.com/model.glb")!,
                fbx: URL(string: "https://assets.meshy.ai/model.fbx")!,
                usdz: URL(string: "http://assets.meshy.ai/model.usdz")!,
                obj: nil,
                mtl: nil
            ),
            taskError: nil,
            textureUrls: nil,
            preview: nil
        )
        let fact = MeshyPolledFact.fromTextOrImageTo3D(resp, kind: .textTo3D)

        #expect(fact.primaryModelUrl == nil)
        #expect(fact.fbxUrl?.host == "assets.meshy.ai")
        #expect(fact.usdzUrl == nil)
    }

    // MARK: - fromRigging

    @Test("fromRigging accepts valid https://assets.meshy.ai GLB URL")
    func riggingAcceptsValidMeshyUrl() throws {
        let glbUrl = URL(string: "https://assets.meshy.ai/rigs/rig_001.glb")!
        let resp = MeshyRiggingTaskResponse(
            id: "rig_001",
            status: .succeeded,
            progress: 100,
            createdAt: nil,
            startedAt: nil,
            finishedAt: nil,
            riggedCharacterGlbUrl: glbUrl,
            riggedCharacterFbxUrl: nil,
            basicAnimations: nil,
            taskError: nil
        )
        let fact = MeshyPolledFact.fromRigging(resp)
        #expect(fact.primaryModelUrl == glbUrl)
    }

    @Test("fromRigging rejects attacker.com basicWalkUrl — becomes nil (security H3)")
    func riggingRejectsAttackerBasicWalkUrl() throws {
        let attackerWalkUrl = URL(string: "https://attacker.com/walk.glb")!
        let legitimateGlbUrl = URL(string: "https://assets.meshy.ai/rigs/rig_002.glb")!
        let resp = MeshyRiggingTaskResponse(
            id: "rig_002",
            status: .succeeded,
            progress: 100,
            createdAt: nil,
            startedAt: nil,
            finishedAt: nil,
            riggedCharacterGlbUrl: legitimateGlbUrl,
            riggedCharacterFbxUrl: nil,
            basicAnimations: MeshyBasicAnimations(
                walking: MeshyAnimationFormats(glb: attackerWalkUrl, fbx: nil),
                running: nil
            ),
            taskError: nil
        )
        let fact = MeshyPolledFact.fromRigging(resp)

        // Primary GLB is valid — kept.
        #expect(fact.primaryModelUrl == legitimateGlbUrl)
        // Attacker URL in basicWalkUrl is sanitized away.
        #expect(fact.basicWalkUrl == nil, "Non-meshy.ai walk URL must be filtered out by sanitizer H3")
    }

    @Test("fromRigging rejects http (non-https) GLB URL")
    func riggingRejectsHttpGlbUrl() throws {
        let httpUrl = URL(string: "http://assets.meshy.ai/rigs/rig_003.glb")!
        let resp = MeshyRiggingTaskResponse(
            id: "rig_003",
            status: .succeeded,
            progress: 100,
            createdAt: nil,
            startedAt: nil,
            finishedAt: nil,
            riggedCharacterGlbUrl: httpUrl,
            riggedCharacterFbxUrl: nil,
            basicAnimations: nil,
            taskError: nil
        )
        let fact = MeshyPolledFact.fromRigging(resp)
        #expect(fact.primaryModelUrl == nil, "http (non-https) URL must be rejected by sanitizer")
    }

    // MARK: - fromAnimation

    @Test("fromAnimation accepts valid https://assets.meshy.ai animation GLB URL")
    func animationAcceptsValidMeshyUrl() throws {
        let glbUrl = URL(string: "https://assets.meshy.ai/anims/anim_001.glb")!
        let resp = MeshyAnimationTaskResponse(
            id: "anim_001",
            status: .succeeded,
            progress: 100,
            createdAt: nil,
            startedAt: nil,
            finishedAt: nil,
            consumedCredits: nil,
            result: MeshyAnimationTaskResult(
                animationGlbUrl: glbUrl,
                animationFbxUrl: nil,
                processedUsdzUrl: nil,
                processedArmatureFbxUrl: nil,
                processedAnimationFpsFbxUrl: nil
            ),
            taskError: nil
        )
        let fact = MeshyPolledFact.fromAnimation(resp)
        #expect(fact.primaryModelUrl == glbUrl)
    }

    @Test("fromAnimation rejects attacker.com animation GLB URL — becomes nil (security H3)")
    func animationRejectsAttackerGlbUrl() throws {
        let attackerUrl = URL(string: "https://evil.example.com/payload.glb")!
        let resp = MeshyAnimationTaskResponse(
            id: "anim_002",
            status: .succeeded,
            progress: 100,
            createdAt: nil,
            startedAt: nil,
            finishedAt: nil,
            consumedCredits: nil,
            result: MeshyAnimationTaskResult(
                animationGlbUrl: attackerUrl,
                animationFbxUrl: nil,
                processedUsdzUrl: nil,
                processedArmatureFbxUrl: nil,
                processedAnimationFpsFbxUrl: nil
            ),
            taskError: nil
        )
        let fact = MeshyPolledFact.fromAnimation(resp)
        #expect(fact.primaryModelUrl == nil, "Non-meshy.ai animation GLB URL must be filtered (H3)")
    }
}
