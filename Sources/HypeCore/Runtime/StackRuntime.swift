import Foundation
#if canImport(Network)
import Network
#endif

public struct NetworkAccessRequest: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case outboundRequest
        case outboundConnection
        case inboundListener
    }

    public var kind: Kind
    public var description: String
    public var host: String
    public var port: Int
    public var scheme: String
    public var stackID: UUID

    public init(kind: Kind, description: String, host: String, port: Int, scheme: String, stackID: UUID) {
        self.kind = kind
        self.description = description
        self.host = host
        self.port = port
        self.scheme = scheme
        self.stackID = stackID
    }
}

public protocol NetworkPermissionPrompting: Sendable {
    func requestApproval(for access: NetworkAccessRequest) async -> Bool
}

public protocol RuntimeClock: Sendable {
    func sleep(seconds: TimeInterval) async throws
}

public struct SystemRuntimeClock: RuntimeClock, Sendable {
    public init() {}

    public func sleep(seconds: TimeInterval) async throws {
        guard seconds > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

public final class UserDefaultsNetworkPermissionStore: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func isApproved(_ access: NetworkAccessRequest) -> Bool {
        defaults.bool(forKey: key(for: access))
    }

    public func approve(_ access: NetworkAccessRequest) {
        defaults.set(true, forKey: key(for: access))
    }

    private func key(for access: NetworkAccessRequest) -> String {
        "hype.network.approval.\(access.stackID.uuidString).\(access.kind.rawValue).\(access.scheme).\(access.host).\(access.port)"
    }
}

public struct RuntimeStatusSnapshot: Sendable, Equatable {
    public struct RequestSummary: Identifiable, Sendable, Equatable {
        public var id: UUID
        public var state: String
        public var method: String
        public var url: String
        public var statusCode: Int?
        public var error: String?
    }

    public struct ListenerSummary: Identifiable, Sendable, Equatable {
        public var id: UUID
        public var transport: String
        public var host: String
        public var port: Int
        public var state: String
        public var callbackMessage: String
    }

    public struct ConnectionSummary: Identifiable, Sendable, Equatable {
        public var id: UUID
        public var host: String
        public var port: Int
        public var state: String
        public var lastDataPreview: String
        public var error: String?
    }

    public var requests: [RequestSummary]
    public var listeners: [ListenerSummary]
    public var connections: [ConnectionSummary]

    public init(
        requests: [RequestSummary],
        listeners: [ListenerSummary],
        connections: [ConnectionSummary]
    ) {
        self.requests = requests
        self.listeners = listeners
        self.connections = connections
    }
}

public struct RuntimeOwnerContext: Sendable {
    public var targetId: UUID
    public var currentCardId: UUID
    public var scriptContext: ScriptDispatchContext?

    public init(targetId: UUID, currentCardId: UUID, scriptContext: ScriptDispatchContext?) {
        self.targetId = targetId
        self.currentCardId = currentCardId
        self.scriptContext = scriptContext
    }
}

public struct OutboundHTTPRequestSpec: Sendable {
    public var url: String
    public var method: String
    public var headersText: String
    public var body: String
    public var username: String?
    public var password: String?
    public var callbackMessage: String?

    public init(
        url: String,
        method: String = "GET",
        headersText: String = "",
        body: String = "",
        username: String? = nil,
        password: String? = nil,
        callbackMessage: String? = nil
    ) {
        self.url = url
        self.method = method
        self.headersText = headersText
        self.body = body
        self.username = username
        self.password = password
        self.callbackMessage = callbackMessage
    }
}

public struct ListenerSpec: Sendable {
    public var transport: NetworkTransportKind
    public var host: String
    public var port: Int
    public var bindScope: NetworkBindScope
    public var callbackMessage: String
    public var httpMethod: String?
    public var httpPath: String?

    public init(
        transport: NetworkTransportKind,
        host: String,
        port: Int,
        bindScope: NetworkBindScope = .loopback,
        callbackMessage: String,
        httpMethod: String? = nil,
        httpPath: String? = nil
    ) {
        self.transport = transport
        self.host = host
        self.port = port
        self.bindScope = bindScope
        self.callbackMessage = callbackMessage
        self.httpMethod = httpMethod
        self.httpPath = httpPath
    }
}

public struct TCPConnectionSpec: Sendable {
    public var host: String
    public var port: Int
    public var tls: Bool
    public var callbackMessage: String

    public init(host: String, port: Int, tls: Bool = false, callbackMessage: String) {
        self.host = host
        self.port = port
        self.tls = tls
        self.callbackMessage = callbackMessage
    }
}

public protocol ScriptRuntimeProviding: Sendable {
    func sleep(seconds: TimeInterval) async throws
    func navigateToCard(_ cardId: UUID) async
    func publishDocument(_ document: HypeDocument) async
    func enqueueMessage(
        _ message: String,
        params: [Value],
        targetId: UUID,
        currentCardId: UUID,
        mouseX: Double,
        mouseY: Double,
        scriptContext: ScriptDispatchContext?
    ) async
    func startAIRequest(prompt: String, model: String?, callbackMessage: String, owner: RuntimeOwnerContext) async throws -> UUID
    /// Phase 3: kick off a Meshy text-to-3D generation asynchronously.
    ///
    /// Same async-callback pattern as `startAIRequest`. Returns a request UUID
    /// immediately; when generation completes (or fails), dispatches
    /// `callbackMessage` with parameters `(requestID, status, assetName)` where
    /// `status` is one of `"completed"` | `"error"` | `"cancelled"`.
    func startMeshyRequest(
        prompt: String,
        style: String?,
        model: String?,
        callbackMessage: String,
        owner: RuntimeOwnerContext
    ) async throws -> UUID
    /// Phase 4: kick off a Meshy remesh asynchronously. Same async-callback
    /// pattern as `startMeshyRequest`. Returns request UUID; callback fires with
    /// `(requestID, status, assetName)`.
    func startRemeshRequest(
        sourceAssetName: String,
        targetPolycount: Int,
        callbackMessage: String,
        owner: RuntimeOwnerContext
    ) async throws -> UUID
    /// Phase 4: kick off a Meshy retexture asynchronously. Same async-callback
    /// pattern. Returns request UUID; callback fires with `(requestID, status, assetName)`.
    func startRetextureRequest(
        sourceAssetName: String,
        stylePrompt: String,
        callbackMessage: String,
        owner: RuntimeOwnerContext
    ) async throws -> UUID
    func setSpeechListenerActive(_ active: Bool, owner: RuntimeOwnerContext) async throws
    func isSpeechListenerActive() async -> Bool
    func startHTTPRequest(_ spec: OutboundHTTPRequestSpec, owner: RuntimeOwnerContext) async throws -> UUID
    func reply(to requestID: UUID, status: Int, headersText: String, body: String) async throws
    func startListener(_ spec: ListenerSpec, owner: RuntimeOwnerContext) async throws -> UUID
    func connectTCP(_ spec: TCPConnectionSpec, owner: RuntimeOwnerContext) async throws -> UUID
    func send(_ data: String, toConnection id: UUID) async throws
    func closeConnection(_ id: UUID) async
    func stopListener(_ id: UUID) async
    func runtimeProperty(objectType: String, id: UUID, property: String, argument: String?) async -> String
}

public struct StackRuntimeConfiguration: Sendable {
    public var dialogProvider: DialogProvider
    public var drawingProvider: DrawingProvider
    public var systemProvider: SystemProvider
    public var aiProvider: any AIScriptingProvider
    /// Phase 3: Meshy scripting provider for `ask meshy` async-callback generation.
    public var meshyProvider: any MeshyScriptingProvider
    public var speechOutputProvider: SpeechOutputProvider
    public var speechListenerProvider: SpeechListenerProvider
    public var appScript: String
    public var approvalPrompter: any NetworkPermissionPrompting
    public var permissionStore: UserDefaultsNetworkPermissionStore
    public var clock: RuntimeClock

    public init(
        dialogProvider: DialogProvider = StubDialogProvider(),
        drawingProvider: DrawingProvider = StubDrawingProvider(),
        systemProvider: SystemProvider = StubSystemProvider(),
        aiProvider: any AIScriptingProvider = StubAIScriptingProvider(),
        meshyProvider: any MeshyScriptingProvider = StubMeshyScriptingProvider(),
        speechOutputProvider: SpeechOutputProvider = StubSpeechOutputProvider(),
        speechListenerProvider: SpeechListenerProvider = StubSpeechListenerProvider(),
        appScript: String = "",
        approvalPrompter: any NetworkPermissionPrompting = AllowAllNetworkPermissionPrompter(),
        permissionStore: UserDefaultsNetworkPermissionStore = UserDefaultsNetworkPermissionStore(),
        clock: RuntimeClock = SystemRuntimeClock()
    ) {
        self.dialogProvider = dialogProvider
        self.drawingProvider = drawingProvider
        self.systemProvider = systemProvider
        self.aiProvider = aiProvider
        self.meshyProvider = meshyProvider
        self.speechOutputProvider = speechOutputProvider
        self.speechListenerProvider = speechListenerProvider
        self.appScript = appScript
        self.approvalPrompter = approvalPrompter
        self.permissionStore = permissionStore
        self.clock = clock
    }
}

public struct AllowAllNetworkPermissionPrompter: NetworkPermissionPrompting, Sendable {
    public init() {}
    public func requestApproval(for access: NetworkAccessRequest) async -> Bool { true }
}

public extension Notification.Name {
    static let stackRuntimeDocumentDidChange = Notification.Name("stackRuntimeDocumentDidChange")
    static let stackRuntimeStatusDidChange = Notification.Name("stackRuntimeStatusDidChange")
}

public actor StackRuntimeRegistry {
    public static let shared = StackRuntimeRegistry()

    private var runtimes: [UUID: StackRuntime] = [:]

    public func runtime(
        for document: HypeDocument,
        configuration: StackRuntimeConfiguration
    ) async -> StackRuntime {
        if let existing = runtimes[document.stack.id] {
            await existing.configure(configuration)
            await existing.syncDocument(document)
            return existing
        }
        let runtime = StackRuntime(document: document, configuration: configuration)
        runtimes[document.stack.id] = runtime
        return runtime
    }

    public func shutdown(stackID: UUID) async {
        guard let runtime = runtimes.removeValue(forKey: stackID) else { return }
        await runtime.shutdown()
    }
}

public actor StackRuntime: ScriptRuntimeProviding {
    private struct QueuedDispatch {
        var message: String
        var params: [Value]
        var targetId: UUID
        var currentCardId: UUID
        var mouseX: Double
        var mouseY: Double
        var scriptContext: ScriptDispatchContext?
        var completion: CheckedContinuation<ExecutionResult, Never>?
    }

    private enum RequestKind: String {
        case outboundHTTP
        case inboundHTTP
        case ai
        case meshy      // Phase 3
        case remesh     // Phase 4
        case retexture  // Phase 4
    }

    private struct RequestState {
        var id: UUID
        var kind: RequestKind
        var state: String
        var method: String
        var url: String
        var headers: [String: String]
        var body: String
        var statusCode: Int?
        var error: String?
    }

    private struct ListenerState {
        var id: UUID
        var transport: NetworkTransportKind
        var host: String
        var port: Int
        var callbackMessage: String
        var owner: RuntimeOwnerContext
        var state: String
    }

    private struct ConnectionState {
        var id: UUID
        var host: String
        var port: Int
        var callbackMessage: String
        var owner: RuntimeOwnerContext
        var state: String
        var lastData: String
        var error: String?
    }

    #if canImport(Network)
    private final class ListenerBox: @unchecked Sendable {
        let listener: NWListener
        init(listener: NWListener) { self.listener = listener }
    }

    private final class ConnectionBox: @unchecked Sendable {
        let connection: NWConnection
        init(connection: NWConnection) { self.connection = connection }
    }
    #endif

    private let dispatcher = MessageDispatcher()
    private var configuration: StackRuntimeConfiguration
    private var document: HypeDocument
    private var queue: [QueuedDispatch] = []
    private var isProcessing = false
    private var requests: [UUID: RequestState] = [:]
    private var listeners: [UUID: ListenerState] = [:]
    private var connections: [UUID: ConnectionState] = [:]
    private var savedListenerRuntimeIDs: [UUID: UUID] = [:]
    private var speechListenerActive = false
    #if canImport(Network)
    private var listenerBoxes: [UUID: ListenerBox] = [:]
    private var connectionBoxes: [UUID: ConnectionBox] = [:]
    #endif
    private let networkQueue = DispatchQueue(label: "com.hype.network.runtime")

    public init(document: HypeDocument, configuration: StackRuntimeConfiguration) {
        self.document = document
        self.configuration = configuration
    }

    public func configure(_ configuration: StackRuntimeConfiguration) {
        self.configuration = configuration
    }

    public func syncDocument(_ document: HypeDocument) async {
        self.document = document
        await reconcileSavedListeners()
    }

    public func currentDocument() -> HypeDocument {
        document
    }

    public func isSavedListenerActive(_ definitionID: UUID) -> Bool {
        savedListenerRuntimeIDs[definitionID] != nil
    }

    public func startSavedListener(definitionID: UUID) async throws -> UUID {
        if let runtimeID = savedListenerRuntimeIDs[definitionID] {
            return runtimeID
        }
        guard let saved = document.stack.networkManifest.savedListeners.first(where: { $0.id == definitionID }) else {
            throw RuntimeNetworkError.unknownListener
        }
        let runtimeID = try await startListener(listenerSpec(from: saved), owner: defaultSavedListenerOwner())
        savedListenerRuntimeIDs[definitionID] = runtimeID
        return runtimeID
    }

    public func stopSavedListener(definitionID: UUID) async {
        guard let runtimeID = savedListenerRuntimeIDs.removeValue(forKey: definitionID) else { return }
        await stopListener(runtimeID)
    }

    public func enqueueMessage(
        _ message: String,
        params: [Value],
        targetId: UUID,
        currentCardId: UUID,
        mouseX: Double = 0,
        mouseY: Double = 0,
        scriptContext: ScriptDispatchContext? = nil
    ) async {
        queue.append(
            QueuedDispatch(
                message: message,
                params: params,
                targetId: targetId,
                currentCardId: currentCardId,
                mouseX: mouseX,
                mouseY: mouseY,
                scriptContext: scriptContext,
                completion: nil
            )
        )
        if !isProcessing {
            await processQueue()
        }
    }

    public func dispatchAndWait(
        _ message: String,
        params: [Value],
        targetId: UUID,
        currentCardId: UUID,
        mouseX: Double = 0,
        mouseY: Double = 0,
        scriptContext: ScriptDispatchContext? = nil
    ) async -> ExecutionResult {
        await withCheckedContinuation { continuation in
            queue.append(
                QueuedDispatch(
                    message: message,
                    params: params,
                    targetId: targetId,
                    currentCardId: currentCardId,
                    mouseX: mouseX,
                    mouseY: mouseY,
                    scriptContext: scriptContext,
                    completion: continuation
                )
            )
            if !isProcessing {
                Task {
                    await self.processQueue()
                }
            }
        }
    }

    public func dispatchIdleBurst(
        cardTargetID: UUID,
        partTargetIDs: [UUID],
        currentCardId: UUID,
        includeCardTarget: Bool = true
    ) async {
        guard !isProcessing, queue.isEmpty else { return }
        if includeCardTarget {
            queue.append(
                QueuedDispatch(
                    message: "idle",
                    params: [],
                    targetId: cardTargetID,
                    currentCardId: currentCardId,
                    mouseX: 0,
                    mouseY: 0,
                    scriptContext: nil,
                    completion: nil
                )
            )
        }
        for partID in partTargetIDs {
            queue.append(
                QueuedDispatch(
                    message: "idle",
                    params: [],
                    targetId: partID,
                    currentCardId: currentCardId,
                    mouseX: 0,
                    mouseY: 0,
                    scriptContext: nil,
                    completion: nil
                )
            )
        }
        await processQueue()
    }

    public func statusSnapshot() -> RuntimeStatusSnapshot {
        RuntimeStatusSnapshot(
            requests: requests.values.sorted { $0.id.uuidString < $1.id.uuidString }.map {
                .init(id: $0.id, state: $0.state, method: $0.method, url: $0.url, statusCode: $0.statusCode, error: $0.error)
            },
            listeners: listeners.values.sorted { $0.id.uuidString < $1.id.uuidString }.map {
                .init(id: $0.id, transport: $0.transport.rawValue, host: $0.host, port: $0.port, state: $0.state, callbackMessage: $0.callbackMessage)
            },
            connections: connections.values.sorted { $0.id.uuidString < $1.id.uuidString }.map {
                .init(id: $0.id, host: $0.host, port: $0.port, state: $0.state, lastDataPreview: String($0.lastData.prefix(120)), error: $0.error)
            }
        )
    }

    public func shutdown() async {
        if speechListenerActive {
            speechListenerActive = false
            await configuration.speechListenerProvider.stopSpeechListener()
        }
        let listenerIDs = Array(listeners.keys)
        for id in listenerIDs {
            await stopListener(id)
        }
        let connectionIDs = Array(connections.keys)
        for id in connectionIDs {
            await closeConnection(id)
        }
    }

    public func sleep(seconds: TimeInterval) async throws {
        try await configuration.clock.sleep(seconds: seconds)
    }

    public func navigateToCard(_ cardId: UUID) async {
        await MainActor.run {
            NotificationCenter.default.post(name: Notification.Name("navigateToCard"), object: cardId)
        }
        // Give SwiftUI/AppKit a frame boundary to commit and paint
        // the card change before a long-running script emits another
        // navigation. Without this, many `go` commands in one handler
        // can coalesce into a single visible update.
        try? await Task.sleep(nanoseconds: 16_666_667)
    }

    public func publishDocument(_ updatedDocument: HypeDocument) async {
        document = updatedDocument
        let stackId = updatedDocument.stack.id
        await MainActor.run {
            NotificationCenter.default.post(
                name: .stackRuntimeDocumentDidChange,
                object: nil,
                userInfo: [
                    "stackId": stackId,
                    "document": updatedDocument,
                ]
            )
        }
        try? await Task.sleep(nanoseconds: 16_666_667)
    }

    public func setSpeechListenerActive(_ active: Bool, owner: RuntimeOwnerContext) async throws {
        if active {
            speechListenerActive = true
            let cardOwner = RuntimeOwnerContext(
                targetId: owner.currentCardId,
                currentCardId: owner.currentCardId,
                scriptContext: nil
            )
            try await configuration.speechListenerProvider.startSpeechListener { transcript in
                await self.enqueueSpeechListen(transcript, owner: cardOwner)
            }
        } else {
            speechListenerActive = false
            await configuration.speechListenerProvider.stopSpeechListener()
        }
        postStatusChange()
    }

    public func isSpeechListenerActive() async -> Bool {
        speechListenerActive
    }

    public func startAIRequest(prompt: String, model: String?, callbackMessage: String, owner: RuntimeOwnerContext) async throws -> UUID {
        let id = UUID()
        let aiProvider = RuntimeAwareAIScriptingProvider(
            baseProvider: configuration.aiProvider,
            document: document
        )
        requests[id] = RequestState(
            id: id,
            kind: .ai,
            state: "pending",
            method: "AI",
            url: model ?? aiProvider.currentModel(),
            headers: [:],
            body: "",
            statusCode: nil,
            error: nil
        )
        postStatusChange()
        let speechOutputProvider = configuration.speechOutputProvider
        Task {
            do {
                let response = try await aiProvider.generate(prompt: prompt, model: model)
                await speechOutputProvider.speakAIResponse(response, source: "HypeTalk AI")
                if var request = self.requests[id] {
                    request.state = "completed"
                    request.body = response
                    self.setRequestState(request)
                }
                await self.enqueueCallback(message: callbackMessage, owner: owner, params: [id.uuidString, "completed"])
            } catch {
                if var request = self.requests[id] {
                    request.state = "error"
                    request.error = error.localizedDescription
                    self.setRequestState(request)
                }
                await self.enqueueCallback(message: callbackMessage, owner: owner, params: [id.uuidString, "error"])
            }
        }
        return id
    }

    /// Phase 3: start an async Meshy text-to-3D generation.
    ///
    /// Registers the request in `requests`, fires a child Task that calls
    /// `configuration.meshyProvider.generateSync`, then enqueues the callback
    /// with three parameters: `(requestID, status, assetName)`.
    ///
    /// **Security (OQ-C3):** `generateSync` is responsible for installing the
    /// asset into the document via `HypeDocumentMutationCoordinator`. This method
    /// does NOT perform a second mutation — exactly one mutation per generation.
    public func startMeshyRequest(
        prompt: String,
        style: String?,
        model: String?,
        callbackMessage: String,
        owner: RuntimeOwnerContext
    ) async throws -> UUID {
        let id = UUID()
        requests[id] = RequestState(
            id: id,
            kind: .meshy,
            state: "pending",
            method: "MESHY",
            url: "/openapi/v2/text-to-3d",
            headers: [:],
            body: "",
            statusCode: nil,
            error: nil
        )
        postStatusChange()

        let meshyProvider = configuration.meshyProvider
        let docSnapshot = document

        Task {
            do {
                let assetName = try await meshyProvider.generateSync(
                    prompt: prompt,
                    style: style,
                    model: model,
                    document: docSnapshot
                )
                if var request = self.requests[id] {
                    request.state = "completed"
                    request.body = assetName
                    self.setRequestState(request)
                }
                await self.enqueueCallback(
                    message: callbackMessage,
                    owner: owner,
                    params: [id.uuidString, "completed", assetName]
                )
            } catch {
                if var request = self.requests[id] {
                    request.state = "error"
                    request.error = error.localizedDescription
                    self.setRequestState(request)
                }
                await self.enqueueCallback(
                    message: callbackMessage,
                    owner: owner,
                    params: [id.uuidString, "error", ""]
                )
            }
        }
        return id
    }

    /// Kick off a Meshy remesh asynchronously. Returns a request UUID immediately;
    /// when remesh completes (or fails), dispatches `callbackMessage` with
    /// parameters `(requestID, status, assetName)`.
    ///
    /// **Security (C8):** `remeshSync` is responsible for installing the asset
    /// via `HypeDocumentMutationCoordinator`. This method does NOT perform a
    /// second mutation — exactly one mutation per generation.
    public func startRemeshRequest(
        sourceAssetName: String,
        targetPolycount: Int,
        callbackMessage: String,
        owner: RuntimeOwnerContext
    ) async throws -> UUID {
        let id = UUID()
        requests[id] = RequestState(
            id: id,
            kind: .remesh,
            state: "pending",
            method: "POST",
            url: "/openapi/v1/remesh",
            headers: [:],
            body: "",
            statusCode: nil,
            error: nil
        )
        postStatusChange()

        let meshyProvider = configuration.meshyProvider
        let docSnapshot = document

        Task {
            do {
                let assetName = try await meshyProvider.remeshSync(
                    sourceAssetName: sourceAssetName,
                    targetPolycount: targetPolycount,
                    document: docSnapshot
                )
                if var request = self.requests[id] {
                    request.state = "completed"
                    request.body = assetName
                    self.setRequestState(request)
                }
                await self.enqueueCallback(
                    message: callbackMessage,
                    owner: owner,
                    params: [id.uuidString, "completed", assetName]
                )
            } catch {
                if var request = self.requests[id] {
                    request.state = "error"
                    request.error = error.localizedDescription
                    self.setRequestState(request)
                }
                await self.enqueueCallback(
                    message: callbackMessage,
                    owner: owner,
                    params: [id.uuidString, "error", ""]
                )
            }
        }
        return id
    }

    /// Kick off a Meshy retexture asynchronously. Returns a request UUID immediately;
    /// when retexture completes (or fails), dispatches `callbackMessage` with
    /// parameters `(requestID, status, assetName)`.
    ///
    /// **Security (C8):** `retextureSync` is responsible for installing the asset.
    /// This method does NOT perform a second mutation.
    public func startRetextureRequest(
        sourceAssetName: String,
        stylePrompt: String,
        callbackMessage: String,
        owner: RuntimeOwnerContext
    ) async throws -> UUID {
        let id = UUID()
        requests[id] = RequestState(
            id: id,
            kind: .retexture,
            state: "pending",
            method: "POST",
            url: "/openapi/v1/retexture",
            headers: [:],
            body: "",
            statusCode: nil,
            error: nil
        )
        postStatusChange()

        let meshyProvider = configuration.meshyProvider
        let docSnapshot = document

        Task {
            do {
                let assetName = try await meshyProvider.retextureSync(
                    sourceAssetName: sourceAssetName,
                    stylePrompt: stylePrompt,
                    document: docSnapshot
                )
                if var request = self.requests[id] {
                    request.state = "completed"
                    request.body = assetName
                    self.setRequestState(request)
                }
                await self.enqueueCallback(
                    message: callbackMessage,
                    owner: owner,
                    params: [id.uuidString, "completed", assetName]
                )
            } catch {
                if var request = self.requests[id] {
                    request.state = "error"
                    request.error = error.localizedDescription
                    self.setRequestState(request)
                }
                await self.enqueueCallback(
                    message: callbackMessage,
                    owner: owner,
                    params: [id.uuidString, "error", ""]
                )
            }
        }
        return id
    }

    public func startHTTPRequest(_ spec: OutboundHTTPRequestSpec, owner: RuntimeOwnerContext) async throws -> UUID {
        let url = try validatedURL(from: spec.url)
        let access = NetworkAccessRequest(
            kind: .outboundRequest,
            description: "HTTP request to \(url.host ?? spec.url):\(url.port ?? defaultPort(for: url.scheme ?? "https"))",
            host: url.host ?? "",
            port: url.port ?? defaultPort(for: url.scheme ?? "https"),
            scheme: url.scheme ?? "https",
            stackID: document.stack.id
        )
        try await ensureAccessPermitted(access, url: url)

        let id = UUID()
        requests[id] = RequestState(
            id: id,
            kind: .outboundHTTP,
            state: "pending",
            method: spec.method.uppercased(),
            url: url.absoluteString,
            headers: parseHeaders(spec.headersText),
            body: "",
            statusCode: nil,
            error: nil
        )
        postStatusChange()

        if let callback = normalized(spec.callbackMessage) {
            Task {
                await self.performHTTPRequest(id: id, url: url, spec: spec, callbackMessage: callback, owner: owner)
            }
            return id
        }

        await performHTTPRequest(id: id, url: url, spec: spec, callbackMessage: nil, owner: owner)
        return id
    }

    public func reply(to requestID: UUID, status: Int, headersText: String, body: String) async throws {
        guard var record = requests[requestID], record.kind == .inboundHTTP else {
            throw RuntimeNetworkError.unknownRequest
        }
        record.state = "replied"
        record.statusCode = status
        record.body = body
        record.headers = parseHeaders(headersText)
        requests[requestID] = record
        postStatusChange()
        #if canImport(Network)
        if let connectionBox = connectionBoxes[requestID] {
            let payload = makeHTTPResponse(status: status, headers: record.headers, body: body)
            connectionBox.connection.send(content: payload, completion: .contentProcessed { _ in
                connectionBox.connection.cancel()
            })
        }
        #endif
    }

    public func startListener(_ spec: ListenerSpec, owner: RuntimeOwnerContext) async throws -> UUID {
        let access = NetworkAccessRequest(
            kind: .inboundListener,
            description: "\(spec.transport.rawValue.uppercased()) listener on \(spec.host):\(spec.port)",
            host: spec.host,
            port: spec.port,
            scheme: spec.transport.rawValue,
            stackID: document.stack.id
        )
        try await ensureListenerPermitted(access, spec: spec)

        #if canImport(Network)
        let parameters: NWParameters = spec.transport == .tcp ? .tcp : .tcp
        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: NWEndpoint.Port.IntegerLiteralType(spec.port)))
        let id = UUID()
        listeners[id] = ListenerState(
            id: id,
            transport: spec.transport,
            host: spec.host,
            port: spec.port,
            callbackMessage: spec.callbackMessage,
            owner: owner,
            state: "starting"
        )
        listenerBoxes[id] = ListenerBox(listener: listener)
        listener.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            Task {
                await self.handleListenerStateChange(id: id, state: newState)
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task {
                await self.handleAcceptedConnection(connection, listenerID: id, spec: spec, owner: owner)
            }
        }
        listener.start(queue: networkQueue)
        postStatusChange()
        return id
        #else
        throw RuntimeNetworkError.networkFrameworkUnavailable
        #endif
    }

    public func connectTCP(_ spec: TCPConnectionSpec, owner: RuntimeOwnerContext) async throws -> UUID {
        let scheme = spec.tls ? "tls" : "tcp"
        let access = NetworkAccessRequest(
            kind: .outboundConnection,
            description: "TCP connection to \(spec.host):\(spec.port)",
            host: spec.host,
            port: spec.port,
            scheme: scheme,
            stackID: document.stack.id
        )
        try await ensureOutboundConnectionPermitted(access)
        #if canImport(Network)
        let host = NWEndpoint.Host(spec.host)
        let port = NWEndpoint.Port(integerLiteral: NWEndpoint.Port.IntegerLiteralType(spec.port))
        let parameters = spec.tls ? NWParameters(tls: .init(), tcp: .init()) : .tcp
        let connection = NWConnection(host: host, port: port, using: parameters)
        let id = UUID()
        connections[id] = ConnectionState(
            id: id,
            host: spec.host,
            port: spec.port,
            callbackMessage: spec.callbackMessage,
            owner: owner,
            state: "connecting",
            lastData: "",
            error: nil
        )
        connectionBoxes[id] = ConnectionBox(connection: connection)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task {
                await self.handleConnectionStateChange(id: id, state: state)
            }
        }
        connection.start(queue: networkQueue)
        startConnectionReceiveLoop(id: id)
        postStatusChange()
        return id
        #else
        throw RuntimeNetworkError.networkFrameworkUnavailable
        #endif
    }

    public func send(_ data: String, toConnection id: UUID) async throws {
        #if canImport(Network)
        guard let connection = connectionBoxes[id]?.connection else {
            throw RuntimeNetworkError.unknownConnection
        }
        connection.send(content: data.data(using: .utf8), completion: .contentProcessed { _ in })
        #else
        throw RuntimeNetworkError.networkFrameworkUnavailable
        #endif
    }

    public func closeConnection(_ id: UUID) async {
        #if canImport(Network)
        connectionBoxes[id]?.connection.cancel()
        connectionBoxes[id] = nil
        #endif
        if var connection = connections[id] {
            connection.state = "closed"
            connections[id] = connection
        }
        postStatusChange()
    }

    public func stopListener(_ id: UUID) async {
        #if canImport(Network)
        listenerBoxes[id]?.listener.cancel()
        listenerBoxes[id] = nil
        #endif
        if let listener = listeners[id] {
            await enqueueCallback(
                message: listener.callbackMessage,
                owner: listener.owner,
                params: [id.uuidString, "stopped"]
            )
        }
        listeners[id] = nil
        savedListenerRuntimeIDs = savedListenerRuntimeIDs.filter { $0.value != id }
        postStatusChange()
    }

    public func runtimeProperty(objectType: String, id: UUID, property: String, argument: String?) async -> String {
        switch objectType.lowercased() {
        case "request":
            guard let request = requests[id] else { return "" }
            switch property.lowercased() {
            case "status", "state":
                return request.state
            case "method":
                return request.method
            case "url":
                return request.url
            case "body":
                return request.body
            case "error":
                return request.error ?? ""
            case "code", "statuscode":
                return request.statusCode.map(String.init) ?? ""
            case "header":
                guard let key = argument else { return "" }
                return headerValue(named: key, from: request.headers)
            default:
                return ""
            }
        case "listener":
            guard let listener = listeners[id] else { return "" }
            switch property.lowercased() {
            case "status", "state":
                return listener.state
            case "host":
                return listener.host
            case "port":
                return String(listener.port)
            case "transport":
                return listener.transport.rawValue
            case "callbackmessage":
                return listener.callbackMessage
            default:
                return ""
            }
        case "connection":
            guard let connection = connections[id] else { return "" }
            switch property.lowercased() {
            case "status", "state":
                return connection.state
            case "host", "remoteaddress":
                return connection.host
            case "port", "remoteport":
                return String(connection.port)
            case "lastdata", "body":
                return connection.lastData
            case "error":
                return connection.error ?? ""
            default:
                return ""
            }
        default:
            return ""
        }
    }

    private func processQueue() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        while !queue.isEmpty {
            let batch = queue
            queue.removeAll(keepingCapacity: true)
            var batchDocumentChanged = false
            for item in batch {
                let result = await dispatcher.dispatchAsync(
                    message: item.message,
                    params: item.params,
                    targetId: item.targetId,
                    document: document,
                    currentCardId: item.currentCardId,
                    dialogProvider: configuration.dialogProvider,
                    drawingProvider: configuration.drawingProvider,
                    systemProvider: configuration.systemProvider,
                    aiProvider: configuration.aiProvider,
                    meshyProvider: configuration.meshyProvider,
                    speechOutputProvider: configuration.speechOutputProvider,
                    appScript: configuration.appScript,
                    mouseX: item.mouseX,
                    mouseY: item.mouseY,
                    scriptContext: item.scriptContext,
                    runtimeProvider: self
                )
                batchDocumentChanged = apply(
                    result: result,
                    postsDocumentChange: batch.count == 1
                ) || batchDocumentChanged
                item.completion?.resume(returning: result)
            }
            if batch.count > 1, batchDocumentChanged {
                postDocumentChange()
            }
        }
    }

    @discardableResult
    private func apply(result: ExecutionResult, postsDocumentChange: Bool = true) -> Bool {
        var documentChanged = false
        if let modified = result.modifiedDocument {
            document = modified
            documentChanged = true
            if postsDocumentChange {
                postDocumentChange()
            }
        }
        if result.showAllCards {
            NotificationCenter.default.post(name: Notification.Name("showAllCards"), object: nil)
        }
        if let navTarget = result.navigationTarget {
            Task { @MainActor in
                NotificationCenter.default.post(name: Notification.Name("navigateToCard"), object: navTarget)
            }
        }
        if let err = result.error {
            var userInfo: [AnyHashable: Any] = [
                "line": err.line,
                "message": err.message,
                "handler": err.handler,
            ]
            if let objectId = err.objectId {
                userInfo["objectId"] = objectId
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Notification.Name("showScriptError"), object: nil, userInfo: userInfo)
            }
        }
        return documentChanged
    }

    private func postDocumentChange() {
        let stackId = document.stack.id
        let updatedDocument = document
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .stackRuntimeDocumentDidChange,
                object: nil,
                userInfo: [
                    "stackId": stackId,
                    "document": updatedDocument,
                ]
            )
        }
    }

    private func postStatusChange() {
        let stackId = document.stack.id
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .stackRuntimeStatusDidChange,
                object: nil,
                userInfo: [
                    "stackId": stackId,
                ]
            )
        }
    }

    private func enqueueCallback(message: String, owner: RuntimeOwnerContext, params: [Value]) async {
        queue.append(
            QueuedDispatch(
                message: message,
                params: params,
                targetId: owner.targetId,
                currentCardId: owner.currentCardId,
                mouseX: 0,
                mouseY: 0,
                scriptContext: owner.scriptContext,
                completion: nil
            )
        )
        if !isProcessing {
            await processQueue()
        }
    }

    private func enqueueSpeechListen(_ transcript: String, owner: RuntimeOwnerContext) async {
        let spokenText = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard speechListenerActive, !spokenText.isEmpty else { return }
        queue.append(
            QueuedDispatch(
                message: "listen",
                params: [spokenText],
                targetId: owner.targetId,
                currentCardId: owner.currentCardId,
                mouseX: 0,
                mouseY: 0,
                scriptContext: owner.scriptContext,
                completion: nil
            )
        )
        if !isProcessing {
            await processQueue()
        }
    }

    private func validatedURL(from value: String) throws -> URL {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host,
              !host.isEmpty else {
            throw RuntimeNetworkError.invalidURL
        }
        return url
    }

    private func ensureAccessPermitted(_ access: NetworkAccessRequest, url: URL) async throws {
        let manifest = document.stack.networkManifest
        let allowed = manifest.outboundHostRules.contains { rule in
            hostMatches(url.host ?? "", pattern: rule.hostPattern)
            && (rule.allowedSchemes.isEmpty || rule.allowedSchemes.contains(url.scheme?.lowercased() ?? "https"))
            && (rule.allowedPorts.isEmpty || rule.allowedPorts.contains(url.port ?? defaultPort(for: url.scheme ?? "https")))
        }
        guard allowed else {
            throw RuntimeNetworkError.notAllowedByManifest
        }
        try await ensureApproved(access)
    }

    private func ensureOutboundConnectionPermitted(_ access: NetworkAccessRequest) async throws {
        let manifest = document.stack.networkManifest
        let allowed = manifest.outboundHostRules.contains { rule in
            hostMatches(access.host, pattern: rule.hostPattern)
            && (rule.allowedSchemes.isEmpty || rule.allowedSchemes.contains(access.scheme))
            && (rule.allowedPorts.isEmpty || rule.allowedPorts.contains(access.port))
        }
        guard allowed else {
            throw RuntimeNetworkError.notAllowedByManifest
        }
        try await ensureApproved(access)
    }

    private func ensureListenerPermitted(_ access: NetworkAccessRequest, spec: ListenerSpec) async throws {
        let normalizedHost = spec.host.lowercased()
        let allowed = document.stack.networkManifest.savedListeners.contains { saved in
            saved.transport == spec.transport
            && saved.port == spec.port
            && saved.host.lowercased() == normalizedHost
        }
        guard allowed else {
            throw RuntimeNetworkError.notAllowedByManifest
        }
        try await ensureApproved(access)
    }

    private func ensureApproved(_ access: NetworkAccessRequest) async throws {
        if configuration.permissionStore.isApproved(access) {
            return
        }
        let approved = await configuration.approvalPrompter.requestApproval(for: access)
        guard approved else {
            throw RuntimeNetworkError.permissionDenied
        }
        configuration.permissionStore.approve(access)
    }

    private func performHTTPRequest(
        id: UUID,
        url: URL,
        spec: OutboundHTTPRequestSpec,
        callbackMessage: String?,
        owner: RuntimeOwnerContext
    ) async {
        do {
            var request = URLRequest(url: url)
            request.httpMethod = spec.method.uppercased()
            for (name, value) in parseHeaders(spec.headersText) {
                request.setValue(value, forHTTPHeaderField: name)
            }
            if !spec.body.isEmpty {
                request.httpBody = spec.body.data(using: .utf8)
            }
            if let username = spec.username, let password = spec.password {
                let token = Data("\(username):\(password)".utf8).base64EncodedString()
                request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            var updated = requests[id]
            updated?.body = String(decoding: data, as: UTF8.self)
            updated?.headers = (response as? HTTPURLResponse)?.allHeaderFields.reduce(into: [:], { partial, entry in
                partial[String(describing: entry.key)] = String(describing: entry.value)
            }) ?? [:]
            updated?.statusCode = (response as? HTTPURLResponse)?.statusCode
            updated?.state = "completed"
            if let updated {
                requests[id] = updated
            }
            postStatusChange()
            if let callbackMessage {
                await enqueueCallback(message: callbackMessage, owner: owner, params: [id.uuidString, "completed"])
            }
        } catch {
            if var updated = requests[id] {
                updated.state = "error"
                updated.error = error.localizedDescription
                requests[id] = updated
            }
            postStatusChange()
            if let callbackMessage {
                await enqueueCallback(message: callbackMessage, owner: owner, params: [id.uuidString, "error"])
            }
        }
    }

    #if canImport(Network)
    private func handleListenerStateChange(id: UUID, state: NWListener.State) async {
        guard var listener = listeners[id] else { return }
        switch state {
        case .ready:
            listener.state = "ready"
        case .failed(let error):
            listener.state = "error"
            listeners[id] = listener
            savedListenerRuntimeIDs = savedListenerRuntimeIDs.filter { $0.value != id }
            await enqueueCallback(message: listener.callbackMessage, owner: listener.owner, params: [id.uuidString, "error"])
            if let listener = listeners[id] {
                var summary = listener
                summary.state = error.localizedDescription
                self.listeners[id] = summary
            }
            postStatusChange()
            return
        case .cancelled:
            listener.state = "stopped"
            savedListenerRuntimeIDs = savedListenerRuntimeIDs.filter { $0.value != id }
        default:
            listener.state = String(describing: state)
        }
        listeners[id] = listener
        postStatusChange()
    }

    private func handleAcceptedConnection(
        _ connection: NWConnection,
        listenerID: UUID,
        spec: ListenerSpec,
        owner: RuntimeOwnerContext
    ) async {
        if spec.transport == .tcp {
            let connectionID = UUID()
            connections[connectionID] = ConnectionState(
                id: connectionID,
                host: spec.host,
                port: spec.port,
                callbackMessage: spec.callbackMessage,
                owner: owner,
                state: "connected",
                lastData: "",
                error: nil
            )
            connectionBoxes[connectionID] = ConnectionBox(connection: connection)
            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                Task {
                    await self.handleConnectionStateChange(id: connectionID, state: state)
                }
            }
            connection.start(queue: networkQueue)
            startConnectionReceiveLoop(id: connectionID)
            await enqueueCallback(message: spec.callbackMessage, owner: owner, params: [connectionID.uuidString, "connected"])
            postStatusChange()
            return
        }

        connection.start(queue: networkQueue)
        receiveHTTPRequest(on: connection, listenerID: listenerID, spec: spec, owner: owner)
    }

    private func receiveHTTPRequest(
        on connection: NWConnection,
        listenerID: UUID,
        spec: ListenerSpec,
        owner: RuntimeOwnerContext,
        accumulated: Data = Data()
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            let combined = accumulated + (data ?? Data())
            Task {
                let nextBuffer = await self.handleHTTPReceive(
                    listenerID: listenerID,
                    spec: spec,
                    owner: owner,
                    connection: connection,
                    data: combined,
                    isComplete: isComplete,
                    error: error
                )
                if let nextBuffer {
                    await self.receiveHTTPRequest(
                        on: connection,
                        listenerID: listenerID,
                        spec: spec,
                        owner: owner,
                        accumulated: nextBuffer
                    )
                }
            }
        }
    }

    private func handleHTTPReceive(
        listenerID: UUID,
        spec: ListenerSpec,
        owner: RuntimeOwnerContext,
        connection: NWConnection,
        data: Data?,
        isComplete: Bool,
        error: NWError?
    ) async -> Data? {
        if let error {
            await enqueueCallback(message: spec.callbackMessage, owner: owner, params: [listenerID.uuidString, "error"])
            if isComplete {
                connection.cancel()
            }
            if var state = listeners[listenerID] {
                state.state = error.localizedDescription
                listeners[listenerID] = state
            }
            postStatusChange()
            return nil
        }

        let buffered = data ?? Data()
        guard let requestData = completeHTTPRequestData(in: buffered) else {
            if isComplete {
                connection.cancel()
                return nil
            }
            return buffered
        }

        let requestID = UUID()
        let text = String(decoding: requestData, as: UTF8.self)
        guard let parsed = parseHTTPRequest(text) else {
            connection.cancel()
            return nil
        }
        if let method = spec.httpMethod?.uppercased(), method != parsed.method.uppercased() {
            connection.cancel()
            return nil
        }
        if let path = spec.httpPath, !path.isEmpty, path != parsed.path {
            connection.cancel()
            return nil
        }

        requests[requestID] = RequestState(
            id: requestID,
            kind: .inboundHTTP,
            state: "pendingReply",
            method: parsed.method,
            url: parsed.path,
            headers: parsed.headers,
            body: parsed.body,
            statusCode: nil,
            error: nil
        )
        connectionBoxes[requestID] = ConnectionBox(connection: connection)
        postStatusChange()
        await enqueueCallback(message: spec.callbackMessage, owner: owner, params: [requestID.uuidString, "request"])

        Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            await self.timeoutPendingHTTPRequest(id: requestID)
        }
        return nil
    }

    private func timeoutPendingHTTPRequest(id: UUID) async {
        guard let request = requests[id], request.kind == .inboundHTTP, request.state == "pendingReply" else { return }
        try? await reply(to: id, status: 500, headersText: "Content-Type: text/plain", body: "Hype request timed out")
    }

    private func handleConnectionStateChange(id: UUID, state: NWConnection.State) async {
        guard var connection = connections[id] else { return }
        switch state {
        case .ready:
            connection.state = "connected"
            connections[id] = connection
            await enqueueCallback(message: connection.callbackMessage, owner: connection.owner, params: [id.uuidString, "connected"])
        case .failed(let error):
            connection.state = "error"
            connection.error = error.localizedDescription
            connections[id] = connection
            await enqueueCallback(message: connection.callbackMessage, owner: connection.owner, params: [id.uuidString, "error"])
        case .cancelled:
            connection.state = "closed"
            connections[id] = connection
            await enqueueCallback(message: connection.callbackMessage, owner: connection.owner, params: [id.uuidString, "closed"])
        default:
            connection.state = String(describing: state)
            connections[id] = connection
        }
        postStatusChange()
    }

    private func startConnectionReceiveLoop(id: UUID) {
        guard let connection = connectionBoxes[id]?.connection else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            Task {
                await self.handleConnectionReceive(
                    id: id,
                    connection: connection,
                    data: data,
                    isComplete: isComplete,
                    error: error
                )
            }
        }
    }

    private func handleConnectionReceive(
        id: UUID,
        connection: NWConnection,
        data: Data?,
        isComplete: Bool,
        error: NWError?
    ) async {
        guard var state = connections[id] else { return }
        if let error {
            state.state = "error"
            state.error = error.localizedDescription
            setConnectionState(state)
            await enqueueCallback(message: state.callbackMessage, owner: state.owner, params: [id.uuidString, "error"])
            return
        }
        if let data, !data.isEmpty {
            state.lastData = String(decoding: data, as: UTF8.self)
            setConnectionState(state)
            await enqueueCallback(message: state.callbackMessage, owner: state.owner, params: [id.uuidString, "data"])
        }
        if isComplete {
            state.state = "closed"
            setConnectionState(state)
            await enqueueCallback(message: state.callbackMessage, owner: state.owner, params: [id.uuidString, "closed"])
            connection.cancel()
        } else {
            startConnectionReceiveLoop(id: id)
        }
    }
    #endif

    private func setConnectionState(_ state: ConnectionState) {
        connections[state.id] = state
        postStatusChange()
    }

    private func setRequestState(_ state: RequestState) {
        requests[state.id] = state
        postStatusChange()
    }

    private func parseHeaders(_ text: String) -> [String: String] {
        text
            .split(whereSeparator: \.isNewline)
            .reduce(into: [:]) { partial, rawLine in
                let line = String(rawLine)
                let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return }
                partial[parts[0].trimmingCharacters(in: .whitespacesAndNewlines)] = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
    }

    private func makeHTTPResponse(status: Int, headers: [String: String], body: String) -> Data {
        var merged = headers
        if merged["Content-Length"] == nil {
            merged["Content-Length"] = String(body.utf8.count)
        }
        if merged["Content-Type"] == nil {
            merged["Content-Type"] = "text/plain; charset=utf-8"
        }
        let headerLines = merged.map { "\($0.key): \($0.value)" }.joined(separator: "\r\n")
        let response = "HTTP/1.1 \(status) \(reasonPhrase(for: status))\r\n\(headerLines)\r\n\r\n\(body)"
        return Data(response.utf8)
    }

    private func parseHTTPRequest(_ raw: String) -> (method: String, path: String, headers: [String: String], body: String)? {
        let sections = raw.components(separatedBy: "\r\n\r\n")
        guard let head = sections.first else { return nil }
        let body = sections.dropFirst().joined(separator: "\r\n\r\n")
        let lines = head.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard requestParts.count >= 2 else { return nil }
        let headerText = lines.dropFirst().joined(separator: "\n")
        return (requestParts[0], requestParts[1], parseHeaders(headerText), body)
    }

    private func completeHTTPRequestData(in raw: Data) -> Data? {
        let delimiter = Data("\r\n\r\n".utf8)
        guard let headerRange = raw.range(of: delimiter) else {
            return nil
        }
        let headerData = raw[..<headerRange.lowerBound]
        let headerText = String(decoding: headerData, as: UTF8.self)
        let contentLength = parseHeaders(headerText)["Content-Length"]
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0
        let totalLength = headerRange.upperBound + contentLength
        guard raw.count >= totalLength else {
            return nil
        }
        return raw.prefix(totalLength)
    }

    private func headerValue(named key: String, from headers: [String: String]) -> String {
        if let exact = headers[key] {
            return exact
        }
        return headers.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?.value ?? ""
    }

    private func hostMatches(_ host: String, pattern: String) -> Bool {
        let normalizedPattern = pattern.lowercased()
        let normalizedHost = host.lowercased()
        if normalizedPattern == "*" {
            return true
        }
        if normalizedPattern.hasPrefix("*.") {
            let suffix = String(normalizedPattern.dropFirst(1))
            return normalizedHost.hasSuffix(suffix)
        }
        return normalizedHost == normalizedPattern
    }

    private func defaultPort(for scheme: String) -> Int {
        switch scheme.lowercased() {
        case "http": return 80
        case "https": return 443
        case "tls": return 443
        default: return 0
        }
    }

    private func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 201: return "Created"
        case 202: return "Accepted"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default: return "OK"
        }
    }

    private func listenerSpec(from saved: SavedNetworkListener) -> ListenerSpec {
        ListenerSpec(
            transport: saved.transport,
            host: saved.host,
            port: saved.port,
            bindScope: saved.bindScope,
            callbackMessage: saved.callbackMessage,
            httpMethod: saved.httpMethod,
            httpPath: saved.httpPath
        )
    }

    private func defaultSavedListenerOwner() -> RuntimeOwnerContext {
        RuntimeOwnerContext(
            targetId: document.stack.id,
            currentCardId: document.sortedCards.first?.id ?? document.stack.id,
            scriptContext: nil
        )
    }

    private func reconcileSavedListeners() async {
        let definitions = Dictionary(uniqueKeysWithValues: document.stack.networkManifest.savedListeners.map { ($0.id, $0) })

        for definitionID in Array(savedListenerRuntimeIDs.keys) where definitions[definitionID] == nil {
            await stopSavedListener(definitionID: definitionID)
        }

        for definition in document.stack.networkManifest.savedListeners {
            if definition.autoStart {
                if savedListenerRuntimeIDs[definition.id] == nil {
                    _ = try? await startSavedListener(definitionID: definition.id)
                }
            } else if savedListenerRuntimeIDs[definition.id] != nil {
                await stopSavedListener(definitionID: definition.id)
            }
        }
    }
}

public enum RuntimeNetworkError: Error, LocalizedError, Sendable {
    case invalidURL
    case permissionDenied
    case notAllowedByManifest
    case unknownRequest
    case unknownListener
    case unknownConnection
    case networkFrameworkUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .permissionDenied:
            return "Network access was denied"
        case .notAllowedByManifest:
            return "Network access is not allowed by this stack's network manifest"
        case .unknownRequest:
            return "Unknown request handle"
        case .unknownListener:
            return "Unknown listener handle"
        case .unknownConnection:
            return "Unknown connection handle"
        case .networkFrameworkUnavailable:
            return "The Network framework is unavailable on this platform"
        }
    }
}
