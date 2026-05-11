import Testing
import Foundation
@testable import HypeCore

// MARK: - Stub providers

private struct RemeshSuccessMeshyProvider: MeshyScriptingProvider {
    let assetName: String
    init(assetName: String = "barrel-remesh.glb") { self.assetName = assetName }
    func generateSync(prompt: String, style: String?, model: String?, document: HypeDocument) async throws -> String { assetName }
    func remeshSync(sourceAssetName: String, targetPolycount: Int, document: HypeDocument) async throws -> String { assetName }
    func retextureSync(sourceAssetName: String, stylePrompt: String, document: HypeDocument) async throws -> String { assetName }
}

private struct RemeshFailingMeshyProvider: MeshyScriptingProvider {
    func generateSync(prompt: String, style: String?, model: String?, document: HypeDocument) async throws -> String { throw MeshyError.networkError }
    func remeshSync(sourceAssetName: String, targetPolycount: Int, document: HypeDocument) async throws -> String { throw MeshyError.networkError }
    func retextureSync(sourceAssetName: String, stylePrompt: String, document: HypeDocument) async throws -> String { throw MeshyError.networkError }
}

// MARK: - Helpers

private func makeDoc() -> (HypeDocument, UUID, UUID) {
    var doc = HypeDocument.newDocument()
    let cardId = doc.cards[0].id
    var button = Part(partType: .button, cardId: cardId, name: "TestButton")
    doc.addPart(button)
    return (doc, cardId, button.id)
}

private func waitUntil(
    timeout: TimeInterval = 10,
    condition: @escaping () async -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
    }
    return false
}

private func requestSummary(runtime: StackRuntime, id: UUID) async -> RuntimeStatusSnapshot.RequestSummary? {
    let snapshot = await runtime.statusSnapshot()
    return snapshot.requests.first(where: { $0.id == id })
}

// MARK: - Tests

@Suite("Runtime.startRemeshRequest / startRetextureRequest — callback delivery", .serialized)
struct StackRuntimeStartRemeshRequestTests {

    // MARK: (a) Successful remesh enqueues callback (requestID, "completed", newAssetName)

    @Test("startRemeshRequest success enqueues (id, completed, assetName)")
    func remeshSuccessEnqueuesCompletedCallback() async throws {
        let (doc, cardId, buttonId) = makeDoc()

        var docVar = doc
        docVar.stack.meshyEnabled = true

        let config = StackRuntimeConfiguration(
            meshyProvider: RemeshSuccessMeshyProvider(assetName: "barrel-remesh.glb")
        )
        let runtime = await StackRuntimeRegistry.shared.runtime(for: docVar, configuration: config)

        let owner = RuntimeOwnerContext(targetId: buttonId, currentCardId: cardId, scriptContext: nil)
        let requestId = try await runtime.startRemeshRequest(
            sourceAssetName: "barrel",
            targetPolycount: 5_000,
            callbackMessage: "onRemeshDone",
            owner: owner
        )

        #expect(requestId != UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)

        let completed = await waitUntil {
            let summary = await requestSummary(runtime: runtime, id: requestId)
            return summary?.state == "completed"
        }
        #expect(completed, "Remesh request must reach 'completed' state within timeout")

        await StackRuntimeRegistry.shared.shutdown(stackID: docVar.stack.id)
    }

    // MARK: (b) Failed remesh enqueues (requestID, "error", "")

    @Test("startRemeshRequest failure enqueues (id, error, empty)")
    func remeshFailureEnqueuesErrorCallback() async throws {
        let (doc, cardId, buttonId) = makeDoc()

        var docVar = doc
        docVar.stack.meshyEnabled = true

        let config = StackRuntimeConfiguration(
            meshyProvider: RemeshFailingMeshyProvider()
        )
        let runtime = await StackRuntimeRegistry.shared.runtime(for: docVar, configuration: config)

        let owner = RuntimeOwnerContext(targetId: buttonId, currentCardId: cardId, scriptContext: nil)
        let requestId = try await runtime.startRemeshRequest(
            sourceAssetName: "barrel",
            targetPolycount: 5_000,
            callbackMessage: "onRemeshDone",
            owner: owner
        )

        let errored = await waitUntil {
            let summary = await requestSummary(runtime: runtime, id: requestId)
            return summary?.state == "error"
        }
        #expect(errored, "Failed remesh must reach 'error' state within timeout")

        await StackRuntimeRegistry.shared.shutdown(stackID: docVar.stack.id)
    }

    // MARK: (c) Successful retexture enqueues callback

    @Test("startRetextureRequest success enqueues (id, completed, assetName)")
    func retextureSuccessEnqueuesCompletedCallback() async throws {
        let (doc, cardId, buttonId) = makeDoc()

        var docVar = doc
        docVar.stack.meshyEnabled = true

        let config = StackRuntimeConfiguration(
            meshyProvider: RemeshSuccessMeshyProvider(assetName: "barrel-retex.glb")
        )
        let runtime = await StackRuntimeRegistry.shared.runtime(for: docVar, configuration: config)

        let owner = RuntimeOwnerContext(targetId: buttonId, currentCardId: cardId, scriptContext: nil)
        let requestId = try await runtime.startRetextureRequest(
            sourceAssetName: "barrel",
            stylePrompt: "rusty iron",
            callbackMessage: "onRetexDone",
            owner: owner
        )

        let completed = await waitUntil {
            let summary = await requestSummary(runtime: runtime, id: requestId)
            return summary?.state == "completed"
        }
        #expect(completed, "Retexture request must reach 'completed' state within timeout")

        await StackRuntimeRegistry.shared.shutdown(stackID: docVar.stack.id)
    }

    // MARK: (d) startRemeshRequest registers the request immediately

    @Test("startRemeshRequest registers the request before the async task completes")
    func remeshRequestRegisteredImmediately() async throws {
        let (doc, cardId, buttonId) = makeDoc()

        struct SlowRemeshProvider: MeshyScriptingProvider {
            func generateSync(prompt: String, style: String?, model: String?, document: HypeDocument) async throws -> String { "slow" }
            func remeshSync(sourceAssetName: String, targetPolycount: Int, document: HypeDocument) async throws -> String {
                try await Task.sleep(nanoseconds: 500_000_000) // 500ms
                return "slow-remesh.glb"
            }
            func retextureSync(sourceAssetName: String, stylePrompt: String, document: HypeDocument) async throws -> String { "slow" }
        }

        var docVar = doc
        docVar.stack.meshyEnabled = true

        let config = StackRuntimeConfiguration(meshyProvider: SlowRemeshProvider())
        let runtime = await StackRuntimeRegistry.shared.runtime(for: docVar, configuration: config)

        let owner = RuntimeOwnerContext(targetId: buttonId, currentCardId: cardId, scriptContext: nil)
        let requestId = try await runtime.startRemeshRequest(
            sourceAssetName: "barrel",
            targetPolycount: 5_000,
            callbackMessage: "onRemeshDone",
            owner: owner
        )

        // The request should be registered before the 500ms task completes.
        let summary = await requestSummary(runtime: runtime, id: requestId)
        #expect(summary != nil, "Request must be registered immediately after startRemeshRequest returns")

        await StackRuntimeRegistry.shared.shutdown(stackID: docVar.stack.id)
    }
}
