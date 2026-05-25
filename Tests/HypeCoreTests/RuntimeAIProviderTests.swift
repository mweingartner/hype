import Foundation
import Testing
@testable import HypeCore

private struct RuntimeAIBaseProbeProvider: AIScriptingProvider {
    var model: String = "authoring-model"
    var response: String = "authoring response"

    func currentModel() -> String { model }
    func availableModels() async throws -> [String] { [model] }
    func generate(prompt: String, model: String?) async throws -> String { response }
}

@Suite("Runtime AI provider routing")
struct RuntimeAIProviderTests {
    @Test("runtime AI settings default to automatic with safe tools disabled")
    func runtimeAISettingsDefaultSafely() {
        let settings = RuntimeAISettings.defaultRuntime
        #expect(settings.providerPolicy == .automatic)
        #expect(!settings.allowRuntimeSideEffectTools)
        #expect(RuntimeAIToolCatalog.tools(for: settings).allSatisfy { $0.sideEffect == .readOnly })
    }

    @Test("runtime tool catalog only exposes side-effect tools when explicitly allowlisted")
    func runtimeToolCatalogRequiresAllowlistForSideEffects() {
        let disabled = RuntimeAISettings()
        #expect(!RuntimeAIToolCatalog.tools(for: disabled).contains { $0.name == "set_runtime_variable" })

        let enabled = RuntimeAISettings(
            allowRuntimeSideEffectTools: true,
            allowedToolNames: ["set_runtime_variable"]
        )
        #expect(RuntimeAIToolCatalog.tools(for: enabled).contains { $0.name == "set_runtime_variable" })
    }

    @Test("runtime provider resolver maps iPhone and iPad to Apple and tvOS to unavailable")
    func resolverMapsTargets() async {
        let resolver = RuntimeAIProviderResolver()
        let settings = RuntimeAISettings.defaultRuntime

        let iPhone = resolver.runtimeProvider(for: .iPhone, settings: settings)
        #expect(iPhone.providerName == "Apple Foundation Models")

        let iPad = resolver.runtimeProvider(for: .iPad, settings: settings)
        #expect(iPad.providerName == "Apple Foundation Models")

        let tvOS = resolver.runtimeProvider(for: .tvOS, settings: settings)
        #expect(tvOS.providerName == "Unavailable Runtime AI")
        #expect(!(await tvOS.availability).isAvailable)
    }

    @Test("runtime-aware provider keeps macOS on the authoring provider")
    func macOSUsesAuthoringProvider() async throws {
        var document = HypeDocument.newDocument(name: "Mac Runtime")
        document.stack.runtimeModeEnabled = true
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [.macOS],
            primaryPlatform: .macOS,
            selectionPromptAcknowledged: true
        )

        let provider = RuntimeAwareAIScriptingProvider(
            baseProvider: RuntimeAIBaseProbeProvider(),
            document: document
        )
        #expect(provider.currentModel() == "authoring-model")
        #expect(try await provider.generate(prompt: "hello", model: nil) == "authoring response")
    }

    @Test("runtime-aware provider switches non-macOS runtime away from authoring provider")
    func nonMacOSRuntimeUsesRuntimeProvider() {
        var document = HypeDocument.newDocument(name: "iPad Runtime")
        document.stack.runtimeModeEnabled = true
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [.iPad],
            primaryPlatform: .iPad,
            selectionPromptAcknowledged: true
        )

        let provider = RuntimeAwareAIScriptingProvider(
            baseProvider: RuntimeAIBaseProbeProvider(),
            document: document
        )
        #expect(provider.currentModel() == "SystemLanguageModel.default")
    }

    @Test("fake runtime provider adapter generates deterministic text")
    func fakeRuntimeProviderAdapterGenerates() async throws {
        let adapter = RuntimeAIScriptingProviderAdapter(
            runtimeProvider: FakeRuntimeAIProvider(responseText: "hello from runtime"),
            targetPlatform: .iPad
        )
        #expect(adapter.currentModel() == "fake-runtime-model")
        #expect(try await adapter.generate(prompt: "hello", model: nil) == "hello from runtime")
    }

    @Test("runtime tool executor reports target profile and can set transient runtime variable")
    func runtimeToolExecutorWorks() throws {
        var document = HypeDocument.newDocument(name: "Runtime Tools")
        let cardId = try #require(document.cards.first?.id)
        let executor = RuntimeAIToolExecutor()

        let profile = executor.execute(
            RuntimeAIToolCall(name: "target_profile"),
            document: &document,
            currentCardId: cardId,
            targetPlatform: .iPad
        )
        #expect(profile.output.contains("iPad Portrait"))

        let setVariable = executor.execute(
            RuntimeAIToolCall(name: "set_runtime_variable", arguments: ["name": "hint", "value": "go north"]),
            document: &document,
            currentCardId: cardId,
            targetPlatform: .iPad
        )
        #expect(setVariable.mutatedRuntimeState)
        #expect(document.scriptGlobals["hint"] == "go north")
    }
}
