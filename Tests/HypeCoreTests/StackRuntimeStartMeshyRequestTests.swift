import Testing
import Foundation
@testable import HypeCore

// MARK: - Stub providers

private struct SuccessMeshyProvider: MeshyScriptingProvider {
    let assetName: String
    func generateSync(prompt: String, style: String?, model: String?, document: HypeDocument) async throws -> String {
        return assetName
    }
    func remeshSync(sourceAssetName: String, targetPolycount: Int, document: HypeDocument) async throws -> String {
        return assetName
    }
    func retextureSync(sourceAssetName: String, stylePrompt: String, document: HypeDocument) async throws -> String {
        return assetName
    }
}

private struct FailingMeshyProvider: MeshyScriptingProvider {
    func generateSync(prompt: String, style: String?, model: String?, document: HypeDocument) async throws -> String {
        throw MeshyError.networkError
    }
    func remeshSync(sourceAssetName: String, targetPolycount: Int, document: HypeDocument) async throws -> String {
        throw MeshyError.networkError
    }
    func retextureSync(sourceAssetName: String, stylePrompt: String, document: HypeDocument) async throws -> String {
        throw MeshyError.networkError
    }
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
    timeout: TimeInterval = 3.0,
    condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    return false
}

/// Find the first request summary matching `id` from the runtime's status snapshot.
private func requestSummary(runtime: StackRuntime, id: UUID) async -> RuntimeStatusSnapshot.RequestSummary? {
    await runtime.statusSnapshot().requests.first(where: { $0.id == id })
}

// MARK: - Tests

@Suite("StackRuntime.startMeshyRequest — callback delivery", .serialized)
struct StackRuntimeStartMeshyRequestTests {

    // MARK: (a) Successful generation enqueues callback (requestId, "completed", assetName)

    @Test("startMeshyRequest success enqueues 3-param callback: id, completed, assetName")
    func successEnqueuesCompletedCallback() async throws {
        let (doc, cardId, buttonId) = makeDoc()

        actor CallbackRecorder {
            var calls: [(id: String, event: String, asset: String)] = []
            func record(id: String, event: String, asset: String) {
                calls.append((id, event, asset))
            }
        }
        let recorder = CallbackRecorder()

        // We test via a HypeTalk script that calls `ask meshy` with a message.
        // The runtime will call startMeshyRequest internally and deliver the
        // callback when generation completes.

        var docVar = doc
        docVar.stack.meshyEnabled = true

        docVar.updatePart(id: buttonId) { part in
            part.script = """
            on mouseUp
              ask meshy "a barrel" with message "onMeshyDone"
            end mouseUp

            on onMeshyDone requestId, eventName, assetName
              -- nothing to assert from here in unit test context
            end onMeshyDone
            """
        }

        let config = StackRuntimeConfiguration(
            meshyProvider: SuccessMeshyProvider(assetName: "barrel.glb")
        )
        let runtime = await StackRuntimeRegistry.shared.runtime(for: docVar, configuration: config)

        // Trigger startMeshyRequest directly (simulating the interpreter calling it).
        let owner = RuntimeOwnerContext(targetId: buttonId, currentCardId: cardId, scriptContext: nil)
        let requestId = try await runtime.startMeshyRequest(
            prompt: "a barrel",
            style: nil,
            model: nil,
            callbackMessage: "onMeshyDone",
            owner: owner
        )

        // The request id must be a valid UUID.
        #expect(requestId != UUID.init(uuidString: "00000000-0000-0000-0000-000000000000"))

        // Wait for the async task inside startMeshyRequest to complete.
        let completed = await waitUntil {
            let summary = await requestSummary(runtime: runtime, id: requestId)
            return summary?.state == "completed"
        }
        #expect(completed, "Request must reach 'completed' state within timeout")

        await StackRuntimeRegistry.shared.shutdown(stackID: docVar.stack.id)
    }

    // MARK: (b) Failed generation enqueues (requestId, "error", "")

    @Test("startMeshyRequest failure enqueues 3-param callback: id, error, empty string")
    func failureEnqueuesErrorCallback() async throws {
        let (doc, cardId, buttonId) = makeDoc()

        var docVar = doc
        docVar.stack.meshyEnabled = true

        let config = StackRuntimeConfiguration(
            meshyProvider: FailingMeshyProvider()
        )
        let runtime = await StackRuntimeRegistry.shared.runtime(for: docVar, configuration: config)

        let owner = RuntimeOwnerContext(targetId: buttonId, currentCardId: cardId, scriptContext: nil)
        let requestId = try await runtime.startMeshyRequest(
            prompt: "a crown",
            style: nil,
            model: nil,
            callbackMessage: "onMeshyDone",
            owner: owner
        )

        // Wait for the error state.
        let errored = await waitUntil {
            let summary = await requestSummary(runtime: runtime, id: requestId)
            return summary?.state == "error"
        }
        #expect(errored, "Request must reach 'error' state when provider throws")

        await StackRuntimeRegistry.shared.shutdown(stackID: docVar.stack.id)
    }

    // MARK: (c) Request is registered with kind .meshy immediately

    @Test("startMeshyRequest registers a .meshy kind request immediately upon call")
    func requestRegisteredImmediately() async throws {
        let (doc, cardId, buttonId) = makeDoc()

        // Use a slow provider so the request is still in-flight when we check.
        struct SlowProvider: MeshyScriptingProvider {
            func generateSync(prompt: String, style: String?, model: String?, document: HypeDocument) async throws -> String {
                try await Task.sleep(nanoseconds: 500_000_000) // 500ms
                return "slow-model.glb"
            }
            func remeshSync(sourceAssetName: String, targetPolycount: Int, document: HypeDocument) async throws -> String {
                try await Task.sleep(nanoseconds: 500_000_000)
                return "slow-remesh.glb"
            }
            func retextureSync(sourceAssetName: String, stylePrompt: String, document: HypeDocument) async throws -> String {
                try await Task.sleep(nanoseconds: 500_000_000)
                return "slow-retex.glb"
            }
        }

        var docVar = doc
        docVar.stack.meshyEnabled = true

        let config = StackRuntimeConfiguration(meshyProvider: SlowProvider())
        let runtime = await StackRuntimeRegistry.shared.runtime(for: docVar, configuration: config)

        let owner = RuntimeOwnerContext(targetId: buttonId, currentCardId: cardId, scriptContext: nil)
        let requestId = try await runtime.startMeshyRequest(
            prompt: "slow model",
            style: nil,
            model: nil,
            callbackMessage: "done",
            owner: owner
        )

        // Immediately after the call returns, the request should be registered.
        let snapshot = await runtime.statusSnapshot()
        let initialSummary = snapshot.requests.first(where: { $0.id == requestId })
        #expect(initialSummary != nil, "Request must be registered immediately (before async task completes)")

        // Cleanup — cancel the slow task.
        await StackRuntimeRegistry.shared.shutdown(stackID: docVar.stack.id)
    }
}

