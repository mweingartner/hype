import Foundation
import Testing
@testable import HypeCore

/// Tests for `MeshyPolledFact.sanitizedMeshyURL` (H3 defense-in-depth).
///
/// `fromRigging` and `fromAnimation` must reject non-Meshy URLs even if
/// Meshy's API ever returns an unexpected host in a wire response.
@Suite("MeshyPolledFact — URL sanitizer (security H3)")
struct MeshyPolledFactSanitizerTests {

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
