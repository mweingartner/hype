import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

public enum RuntimeAIUnavailableReason: String, Codable, Sendable, Equatable {
    case available
    case disabled
    case unsupportedTarget
    case frameworkUnavailable
    case appleIntelligenceUnavailable
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unknown
}

public struct RuntimeAIAvailability: Codable, Sendable, Equatable {
    public var isAvailable: Bool
    public var reason: RuntimeAIUnavailableReason
    public var message: String

    public init(isAvailable: Bool, reason: RuntimeAIUnavailableReason, message: String) {
        self.isAvailable = isAvailable
        self.reason = reason
        self.message = message
    }

    public static func available(_ message: String = "AI is available.") -> RuntimeAIAvailability {
        RuntimeAIAvailability(isAvailable: true, reason: .available, message: message)
    }

    public static func unavailable(
        _ reason: RuntimeAIUnavailableReason,
        message: String
    ) -> RuntimeAIAvailability {
        RuntimeAIAvailability(isAvailable: false, reason: reason, message: message)
    }
}

public enum RuntimeAICapability: String, Codable, CaseIterable, Sendable, Equatable {
    case textGeneration
    case streamingText
    case structuredGeneration
    case runtimeSafeTools
    case appIntents
}

public struct RuntimeAIRequest: Sendable, Equatable {
    public var prompt: String
    public var instructions: String
    public var targetPlatform: HypeTargetPlatform
    public var capabilities: [RuntimeAICapability]
    public var toolCatalog: [RuntimeAIToolDescriptor]

    public init(
        prompt: String,
        instructions: String = RuntimeAIRequest.defaultInstructions,
        targetPlatform: HypeTargetPlatform,
        capabilities: [RuntimeAICapability] = [.textGeneration],
        toolCatalog: [RuntimeAIToolDescriptor] = []
    ) {
        self.prompt = prompt
        self.instructions = instructions
        self.targetPlatform = targetPlatform
        self.capabilities = capabilities
        self.toolCatalog = toolCatalog
    }

    public static let defaultInstructions = """
    You are responding inside a deployed Hype runtime. Answer the user's script request directly.
    Do not describe authoring steps, edit the stack structure, reveal secrets, or assume network access.
    """
}

public struct RuntimeAIResponse: Sendable, Equatable {
    public var text: String
    public var providerName: String
    public var modelName: String

    public init(text: String, providerName: String, modelName: String) {
        self.text = text
        self.providerName = providerName
        self.modelName = modelName
    }
}

public enum RuntimeAIStreamEvent: Sendable, Equatable {
    case text(String)
    case completed(RuntimeAIResponse)
}

public protocol HypeRuntimeAIProvider: Sendable {
    var providerName: String { get }
    var modelName: String { get }
    var capabilities: [RuntimeAICapability] { get }
    var availability: RuntimeAIAvailability { get async }

    func generateText(_ request: RuntimeAIRequest) async throws -> RuntimeAIResponse
    func streamText(_ request: RuntimeAIRequest) -> AsyncThrowingStream<RuntimeAIStreamEvent, Error>
    func generateStructured<Response: Decodable & Sendable>(
        _ request: RuntimeAIRequest,
        as type: Response.Type
    ) async throws -> Response
}

public struct UnavailableRuntimeAIProvider: HypeRuntimeAIProvider {
    public var providerName: String
    public var modelName: String
    public var capabilities: [RuntimeAICapability]
    private let storedAvailability: RuntimeAIAvailability

    public init(
        providerName: String = "Unavailable Runtime AI",
        modelName: String = "none",
        availability: RuntimeAIAvailability
    ) {
        self.providerName = providerName
        self.modelName = modelName
        self.capabilities = []
        self.storedAvailability = availability
    }

    public var availability: RuntimeAIAvailability { get async { storedAvailability } }

    public func generateText(_ request: RuntimeAIRequest) async throws -> RuntimeAIResponse {
        throw AIScriptingProviderError.providerUnavailable(storedAvailability.message)
    }

    public func streamText(_ request: RuntimeAIRequest) -> AsyncThrowingStream<RuntimeAIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: AIScriptingProviderError.providerUnavailable(storedAvailability.message))
        }
    }

    public func generateStructured<Response: Decodable & Sendable>(
        _ request: RuntimeAIRequest,
        as type: Response.Type
    ) async throws -> Response {
        throw AIScriptingProviderError.providerUnavailable(storedAvailability.message)
    }
}

public struct FakeRuntimeAIProvider: HypeRuntimeAIProvider {
    public var providerName: String
    public var modelName: String
    public var capabilities: [RuntimeAICapability]
    public var responseText: String
    public var storedAvailability: RuntimeAIAvailability

    public init(
        providerName: String = "Fake Runtime AI",
        modelName: String = "fake-runtime-model",
        capabilities: [RuntimeAICapability] = [.textGeneration, .structuredGeneration],
        responseText: String = "runtime response",
        availability: RuntimeAIAvailability = .available("Fake runtime AI is available.")
    ) {
        self.providerName = providerName
        self.modelName = modelName
        self.capabilities = capabilities
        self.responseText = responseText
        self.storedAvailability = availability
    }

    public var availability: RuntimeAIAvailability { get async { storedAvailability } }

    public func generateText(_ request: RuntimeAIRequest) async throws -> RuntimeAIResponse {
        RuntimeAIResponse(text: responseText, providerName: providerName, modelName: modelName)
    }

    public func streamText(_ request: RuntimeAIRequest) -> AsyncThrowingStream<RuntimeAIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.text(responseText))
            continuation.yield(.completed(RuntimeAIResponse(text: responseText, providerName: providerName, modelName: modelName)))
            continuation.finish()
        }
    }

    public func generateStructured<Response: Decodable & Sendable>(
        _ request: RuntimeAIRequest,
        as type: Response.Type
    ) async throws -> Response {
        let data = Data(responseText.utf8)
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

public struct AppleFoundationModelsRuntimeProvider: HypeRuntimeAIProvider {
    public let providerName = "Apple Foundation Models"
    public let modelName = "SystemLanguageModel.default"
    public let capabilities: [RuntimeAICapability] = [.textGeneration, .streamingText, .structuredGeneration, .runtimeSafeTools]
    private let targetPlatform: HypeTargetPlatform

    public init(targetPlatform: HypeTargetPlatform) {
        self.targetPlatform = targetPlatform
    }

    public var availability: RuntimeAIAvailability {
        get async {
            guard Self.isAppleFoundationModelsTarget(targetPlatform) else {
                return .unavailable(.unsupportedTarget, message: "Apple Foundation Models are not available for \(targetPlatform.displayName) runtime.")
            }
            return Self.foundationModelsAvailability()
        }
    }

    public func generateText(_ request: RuntimeAIRequest) async throws -> RuntimeAIResponse {
        let currentAvailability = await availability
        guard currentAvailability.isAvailable else {
            throw AIScriptingProviderError.providerUnavailable(currentAvailability.message)
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
            let response = try await generateWithFoundationModels(request)
            return RuntimeAIResponse(text: response, providerName: providerName, modelName: modelName)
        }
        #endif

        throw AIScriptingProviderError.providerUnavailable("FoundationModels.framework is not available in this build.")
    }

    public func streamText(_ request: RuntimeAIRequest) -> AsyncThrowingStream<RuntimeAIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let response = try await generateText(request)
                    continuation.yield(.text(response.text))
                    continuation.yield(.completed(response))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func generateStructured<Response: Decodable & Sendable>(
        _ request: RuntimeAIRequest,
        as type: Response.Type
    ) async throws -> Response {
        let response = try await generateText(request)
        guard let data = response.text.data(using: .utf8) else {
            throw AIScriptingProviderError.providerUnavailable("Apple Foundation Models returned non-UTF8 structured output.")
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    public static func isAppleFoundationModelsTarget(_ targetPlatform: HypeTargetPlatform) -> Bool {
        switch targetPlatform {
        case .iPhone, .iPad:
            return true
        case .macOS, .tvOS:
            return false
        }
    }

    public static func foundationModelsAvailability() -> RuntimeAIAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                return .available("Apple Foundation Models are available.")
            case .unavailable(let reason):
                let description = String(describing: reason)
                if description.contains("deviceNotEligible") {
                    return .unavailable(.deviceNotEligible, message: "This device is not eligible for Apple Intelligence.")
                }
                if description.contains("appleIntelligenceNotEnabled") {
                    return .unavailable(.appleIntelligenceNotEnabled, message: "Apple Intelligence is not enabled.")
                }
                if description.contains("modelNotReady") {
                    return .unavailable(.modelNotReady, message: "The Apple on-device model is not ready yet.")
                }
                return .unavailable(.appleIntelligenceUnavailable, message: "Apple Foundation Models are unavailable: \(description).")
            @unknown default:
                return .unavailable(.unknown, message: "Apple Foundation Models availability is unknown.")
            }
        }
        #endif

        return .unavailable(.frameworkUnavailable, message: "FoundationModels.framework is not available in this build.")
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    private func generateWithFoundationModels(_ request: RuntimeAIRequest) async throws -> String {
        let session = LanguageModelSession(instructions: request.instructions)
        let response = try await session.respond(to: request.prompt)
        return response.content
    }
    #endif
}

public struct RuntimeAIProviderResolver: Sendable {
    public init() {}

    public func runtimeProvider(
        for platform: HypeTargetPlatform,
        settings: RuntimeAISettings
    ) -> any HypeRuntimeAIProvider {
        var normalized = settings
        normalized.normalize()

        guard normalized.providerPolicy != .disabled else {
            return UnavailableRuntimeAIProvider(
                availability: .unavailable(.disabled, message: normalized.unavailableFallbackText)
            )
        }

        switch platform {
        case .macOS:
            return UnavailableRuntimeAIProvider(
                availability: .unavailable(.unsupportedTarget, message: "macOS uses Hype's selected authoring AI provider.")
            )
        case .iPhone, .iPad:
            return AppleFoundationModelsRuntimeProvider(targetPlatform: platform)
        case .tvOS:
            return UnavailableRuntimeAIProvider(
                availability: .unavailable(.unsupportedTarget, message: "Apple Foundation Models are not currently available for tvOS runtime.")
            )
        }
    }
}

public struct RuntimeAIScriptingProviderAdapter: AIScriptingProvider, Sendable {
    public var runtimeProvider: any HypeRuntimeAIProvider
    public var targetPlatform: HypeTargetPlatform
    public var toolCatalog: [RuntimeAIToolDescriptor]

    public init(
        runtimeProvider: any HypeRuntimeAIProvider,
        targetPlatform: HypeTargetPlatform,
        toolCatalog: [RuntimeAIToolDescriptor] = []
    ) {
        self.runtimeProvider = runtimeProvider
        self.targetPlatform = targetPlatform
        self.toolCatalog = toolCatalog
    }

    public func currentModel() -> String {
        runtimeProvider.modelName
    }

    public func availableModels() async throws -> [String] {
        let availability = await runtimeProvider.availability
        return availability.isAvailable ? [runtimeProvider.modelName] : []
    }

    public func generate(prompt: String, model: String?) async throws -> String {
        let request = RuntimeAIRequest(
            prompt: prompt,
            targetPlatform: targetPlatform,
            toolCatalog: toolCatalog
        )
        return try await runtimeProvider.generateText(request).text
    }
}

public struct RuntimeAwareAIScriptingProvider: AIScriptingProvider, Sendable {
    public var baseProvider: any AIScriptingProvider
    public var document: HypeDocument
    public var targetPlatform: HypeTargetPlatform

    public init(
        baseProvider: any AIScriptingProvider,
        document: HypeDocument,
        targetPlatform: HypeTargetPlatform? = nil
    ) {
        self.baseProvider = baseProvider
        self.document = document
        self.targetPlatform = targetPlatform ?? document.stack.deploymentTargets.primaryPlatform
    }

    public func currentModel() -> String {
        guard Self.shouldUseRuntimeProvider(document: document, targetPlatform: targetPlatform) else {
            return baseProvider.currentModel()
        }
        let provider = RuntimeAIProviderResolver().runtimeProvider(
            for: targetPlatform,
            settings: document.stack.runtimeAISettings
        )
        return provider.modelName
    }

    public func availableModels() async throws -> [String] {
        guard Self.shouldUseRuntimeProvider(document: document, targetPlatform: targetPlatform) else {
            return try await baseProvider.availableModels()
        }
        return try await RuntimeAIScriptingProviderAdapter(
            runtimeProvider: RuntimeAIProviderResolver().runtimeProvider(
                for: targetPlatform,
                settings: document.stack.runtimeAISettings
            ),
            targetPlatform: targetPlatform,
            toolCatalog: RuntimeAIToolCatalog.tools(for: document.stack.runtimeAISettings)
        ).availableModels()
    }

    public func generate(prompt: String, model: String?) async throws -> String {
        guard Self.shouldUseRuntimeProvider(document: document, targetPlatform: targetPlatform) else {
            return try await baseProvider.generate(prompt: prompt, model: model)
        }
        return try await RuntimeAIScriptingProviderAdapter(
            runtimeProvider: RuntimeAIProviderResolver().runtimeProvider(
                for: targetPlatform,
                settings: document.stack.runtimeAISettings
            ),
            targetPlatform: targetPlatform,
            toolCatalog: RuntimeAIToolCatalog.tools(for: document.stack.runtimeAISettings)
        ).generate(prompt: prompt, model: nil)
    }

    public static func shouldUseRuntimeProvider(
        document: HypeDocument,
        targetPlatform: HypeTargetPlatform? = nil
    ) -> Bool {
        guard document.stack.runtimeModeEnabled else { return false }
        let platform = targetPlatform ?? document.stack.deploymentTargets.primaryPlatform
        return platform != .macOS
    }
}

public struct RuntimeAIStatus: Sendable, Equatable {
    public var providerName: String
    public var modelName: String
    public var availability: RuntimeAIAvailability
    public var capabilities: [RuntimeAICapability]
}

public enum RuntimeAIStatusResolver {
    public static func status(
        baseProvider: any AIScriptingProvider,
        document: HypeDocument,
        targetPlatform: HypeTargetPlatform? = nil
    ) async -> RuntimeAIStatus {
        let platform = targetPlatform ?? document.stack.deploymentTargets.primaryPlatform
        guard RuntimeAwareAIScriptingProvider.shouldUseRuntimeProvider(document: document, targetPlatform: platform) else {
            return RuntimeAIStatus(
                providerName: "Authoring Provider",
                modelName: baseProvider.currentModel(),
                availability: .available("Using Hype's selected authoring AI provider."),
                capabilities: [.textGeneration]
            )
        }
        let provider = RuntimeAIProviderResolver().runtimeProvider(
            for: platform,
            settings: document.stack.runtimeAISettings
        )
        return RuntimeAIStatus(
            providerName: provider.providerName,
            modelName: provider.modelName,
            availability: await provider.availability,
            capabilities: provider.capabilities
        )
    }
}
