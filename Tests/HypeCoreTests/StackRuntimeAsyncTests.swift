import Testing
import Foundation
@testable import HypeCore
#if canImport(Network)
import Network
#endif
#if canImport(Darwin)
import Darwin
#endif

private actor RecordingClock: RuntimeClock {
    private(set) var sleeps: [TimeInterval] = []

    func sleep(seconds: TimeInterval) async throws {
        sleeps.append(seconds)
    }
}

private actor GatedClock: RuntimeClock {
    private(set) var sleeps: [TimeInterval] = []
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func sleep(seconds: TimeInterval) async throws {
        sleeps.append(seconds)
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func releaseAll() {
        let pending = continuations
        continuations.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}

private final class RuntimeDocumentPublishProbe: @unchecked Sendable {
    private let stackId: UUID
    private let fieldId: UUID
    private let lock = NSLock()
    private var observer: NSObjectProtocol?
    private var observedTexts: [String] = []

    init(stackId: UUID, fieldId: UUID) {
        self.stackId = stackId
        self.fieldId = fieldId
        observer = NotificationCenter.default.addObserver(
            forName: .stackRuntimeDocumentDidChange,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.record(notification)
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func texts() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return observedTexts
    }

    private func record(_ notification: Notification) {
        guard let stackId = notification.userInfo?["stackId"] as? UUID,
              stackId == self.stackId,
              let document = notification.userInfo?["document"] as? HypeDocument,
              let text = document.parts.first(where: { $0.id == fieldId })?.textContent else { return }
        lock.lock()
        observedTexts.append(text)
        lock.unlock()
    }
}

private struct FixedAIProvider: AIScriptingProvider {
    let model: String
    let models: [String]
    let generated: String

    init(model: String = "llama3.2", models: [String] = ["llama3.2"], generated: String = "generated response") {
        self.model = model
        self.models = models
        self.generated = generated
    }

    func currentModel() -> String { model }
    func availableModels() async throws -> [String] { models }
    func generate(prompt: String, model: String?) async throws -> String { generated }
}

private actor RuntimeSpeechRecorder: SpeechOutputProvider {
    private(set) var spoken: [(text: String, source: String)] = []

    func speakAIResponse(_ text: String, source: String) async {
        spoken.append((text, source))
    }

    func speakScriptText(_ text: String, source: String) async {
        spoken.append((text, source))
    }

    func texts() -> [String] {
        spoken.map(\.text)
    }
}

private actor RuntimeSpeechListenerProbe: SpeechListenerProvider {
    private var callback: (@Sendable (String) async -> Void)?
    private(set) var transitions: [Bool] = []

    func startSpeechListener(onTranscript: @escaping @Sendable (String) async -> Void) async throws {
        transitions.append(true)
        callback = onTranscript
    }

    func stopSpeechListener() async {
        transitions.append(false)
        callback = nil
    }

    func emit(_ transcript: String) async {
        await callback?(transcript)
    }

    func states() -> [Bool] {
        transitions
    }
}

#if canImport(Network)
private final class LoopbackHTTPServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "LoopbackHTTPServer")
    private let handler: @Sendable (String) -> (status: Int, headers: [String: String], body: String)

    init(
        port: Int,
        handler: @escaping @Sendable (String) -> (status: Int, headers: [String: String], body: String)
    ) throws {
        self.listener = try NWListener(
            using: .tcp,
            on: NWEndpoint.Port(rawValue: UInt16(port))!
        )
        self.handler = handler
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
    }

    deinit {
        listener.cancel()
    }

    func stop() {
        listener.cancel()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [handler] data, _, _, _ in
            let request = String(decoding: data ?? Data(), as: UTF8.self)
            let response = handler(request)
            var merged = response.headers
            merged["Content-Length"] = String(response.body.utf8.count)
            merged["Content-Type"] = merged["Content-Type"] ?? "text/plain; charset=utf-8"
            let headerLines = merged.map { "\($0.key): \($0.value)" }.joined(separator: "\r\n")
            let payload = Data("HTTP/1.1 \(response.status) OK\r\n\(headerLines)\r\n\r\n\(response.body)".utf8)
            connection.send(content: payload, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}
#endif

/// Serialization gate so two concurrent test threads can't pick the
/// same loopback port and race the OS into giving them the same
/// number after their probe sockets close. The lock is held just
/// long enough to ask the kernel for a port and read its number;
/// once we return the port number the listener still has to bind to
/// it, but at least we don't have multiple tests probing in lockstep.
private let _freeLoopbackPortLock = NSLock()

/// Ask the kernel for an available loopback port by binding a probe
/// socket to port 0, then returning the auto-assigned number. The
/// probe socket is closed immediately, so callers should bind the
/// returned port quickly to minimize the TOCTOU window where another
/// process could grab it. The serialization lock above prevents
/// concurrent test threads from racing each other; it does NOT
/// prevent races against unrelated processes on the host.
private func freeLoopbackPort() -> Int {
    _freeLoopbackPortLock.lock()
    defer { _freeLoopbackPortLock.unlock() }

    let fd = socket(AF_INET, SOCK_STREAM, 0)
    precondition(fd >= 0, "socket() failed")
    defer { close(fd) }

    var value: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &value, socklen_t(MemoryLayout<Int32>.size))

    var addr = sockaddr_in()
    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = in_port_t(0).bigEndian
    addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

    let bindResult = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
            bind(fd, ptr, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    precondition(bindResult == 0, "bind() failed")

    var bound = sockaddr_in()
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let nameResult = withUnsafeMutablePointer(to: &bound) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
            getsockname(fd, ptr, &length)
        }
    }
    precondition(nameResult == 0, "getsockname() failed")
    return Int(UInt16(bigEndian: bound.sin_port))
}

private func makeRuntimeDocument(
    buttonScript: String = "",
    stackScript: String = "",
    outboundRules: [OutboundHostRule] = [],
    savedListeners: [SavedNetworkListener] = []
) -> (HypeDocument, UUID, UUID, UUID) {
    var doc = HypeDocument.newDocument()
    let cardId = doc.cards[0].id
    doc.stack.networkManifest = StackNetworkManifest(
        outboundHostRules: outboundRules,
        savedListeners: savedListeners
    )
    doc.stack.script = stackScript

    var button = Part(partType: .button, cardId: cardId, name: "Runner")
    button.script = buttonScript
    doc.addPart(button)

    let field = Part(partType: .field, cardId: cardId, name: "output")
    doc.addPart(field)

    return (doc, cardId, button.id, field.id)
}

private func runtimeConfiguration(
    aiProvider: any AIScriptingProvider = StubAIScriptingProvider(),
    speechOutputProvider: SpeechOutputProvider = StubSpeechOutputProvider(),
    speechListenerProvider: SpeechListenerProvider = StubSpeechListenerProvider(),
    clock: RuntimeClock = SystemRuntimeClock()
) -> StackRuntimeConfiguration {
    StackRuntimeConfiguration(
        aiProvider: aiProvider,
        speechOutputProvider: speechOutputProvider,
        speechListenerProvider: speechListenerProvider,
        permissionStore: UserDefaultsNetworkPermissionStore(defaults: UserDefaults(suiteName: "StackRuntimeAsyncTests.\(UUID().uuidString)")!),
        clock: clock
    )
}

private func outputText(from document: HypeDocument, fieldID: UUID) -> String {
    document.parts.first(where: { $0.id == fieldID })?.textContent ?? ""
}

private func waitUntil(
    timeout: TimeInterval = 2,
    condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    return false
}

/// `.serialized` because the networking subset of these tests opens
/// loopback TCP/HTTP listeners on auto-assigned ports. Even with the
/// `_freeLoopbackPortLock` gate, running multiple listener tests in
/// parallel widens the TOCTOU window between port discovery and the
/// listener actually binding — under enough load, two tests could
/// each get a "free" port and one's listener loses the race. The
/// non-network tests in this suite are cheap, so paying the cost of
/// serialization for all of them is acceptable.
@Suite("StackRuntime async + networking", .serialized)
struct StackRuntimeAsyncTests {
    @Test("wait uses the runtime clock instead of blocking the thread")
    func waitUsesRuntimeClock() async {
        let clock = RecordingClock()
        let (doc, cardId, buttonId, fieldID) = makeRuntimeDocument(buttonScript: """
        on mouseUp
          wait 2 seconds
          put "done" into field "output"
        end mouseUp
        """)

        let runtime = await StackRuntimeRegistry.shared.runtime(
            for: doc,
            configuration: runtimeConfiguration(clock: clock)
        )
        let result = await runtime.dispatchAndWait("mouseUp", params: [], targetId: buttonId, currentCardId: cardId)
        let updated = result.modifiedDocument ?? doc
        await StackRuntimeRegistry.shared.shutdown(stackID: doc.stack.id)

        #expect(result.status == .completed)
        #expect(await clock.sleeps == [2])
        #expect(outputText(from: updated, fieldID: fieldID) == "done")
    }

    @Test("wait duration defaults to HyperCard ticks")
    func waitDurationDefaultsToTicks() async {
        let clock = RecordingClock()
        let (doc, cardId, buttonId, fieldID) = makeRuntimeDocument(buttonScript: """
        on mouseUp
          wait 120
          wait for 30 ticks
          wait 1 second
          put "done" into field "output"
        end mouseUp
        """)

        let runtime = await StackRuntimeRegistry.shared.runtime(
            for: doc,
            configuration: runtimeConfiguration(clock: clock)
        )
        let result = await runtime.dispatchAndWait("mouseUp", params: [], targetId: buttonId, currentCardId: cardId)
        let updated = result.modifiedDocument ?? doc
        await StackRuntimeRegistry.shared.shutdown(stackID: doc.stack.id)

        #expect(result.status == .completed)
        #expect(await clock.sleeps == [2, 0.5, 1])
        #expect(outputText(from: updated, fieldID: fieldID) == "done")
    }

    @Test("bare wait 30 sleeps for half a second")
    func bareWaitThirtySleepsForHalfSecond() async {
        let clock = RecordingClock()
        let (doc, cardId, buttonId, fieldID) = makeRuntimeDocument(buttonScript: """
        on mouseUp
          wait 30
          put "done" into field "output"
        end mouseUp
        """)

        let runtime = await StackRuntimeRegistry.shared.runtime(
            for: doc,
            configuration: runtimeConfiguration(clock: clock)
        )
        let result = await runtime.dispatchAndWait("mouseUp", params: [], targetId: buttonId, currentCardId: cardId)
        let updated = result.modifiedDocument ?? doc
        await StackRuntimeRegistry.shared.shutdown(stackID: doc.stack.id)

        #expect(result.status == .completed)
        #expect(await clock.sleeps == [0.5])
        #expect(outputText(from: updated, fieldID: fieldID) == "done")
    }

    @Test("script publishes document changes while suspended in wait")
    func scriptPublishesDocumentChangesWhileSuspendedInWait() async {
        let clock = GatedClock()
        let (doc, cardId, buttonId, fieldID) = makeRuntimeDocument(buttonScript: """
        on mouseUp
          put "before wait" into field "output"
          wait 1 second
          put "after wait" into field "output"
        end mouseUp
        """)
        let probe = RuntimeDocumentPublishProbe(stackId: doc.stack.id, fieldId: fieldID)

        let runtime = await StackRuntimeRegistry.shared.runtime(
            for: doc,
            configuration: runtimeConfiguration(clock: clock)
        )
        let task = Task {
            await runtime.dispatchAndWait("mouseUp", params: [], targetId: buttonId, currentCardId: cardId)
        }

        let sawBeforeWait = await waitUntil {
            probe.texts().contains("before wait")
        }
        #expect(sawBeforeWait)
        #expect(await clock.sleeps == [1])
        #expect(!probe.texts().contains("after wait"))

        await clock.releaseAll()
        let result = await task.value
        let updated = result.modifiedDocument ?? doc
        await StackRuntimeRegistry.shared.shutdown(stackID: doc.stack.id)

        #expect(result.status == .completed)
        #expect(outputText(from: updated, fieldID: fieldID) == "after wait")
        #expect(probe.texts().contains("after wait"))
    }

    @Test("classic nextCard aliases navigate to the next card")
    func classicNextCardAliasesNavigate() async {
        var doc = HypeDocument.newDocument(name: "Classic Nav Test")
        let _ = doc.addCard()
        let sorted = doc.sortedCards
        let card1 = sorted[0]
        let card2 = sorted[1]
        var button = Part(partType: .button, cardId: card1.id, name: "Next")
        button.script = """
        on mouseUp
          nextCard
        end mouseUp
        """
        doc.addPart(button)

        let runtime = await StackRuntimeRegistry.shared.runtime(
            for: doc,
            configuration: runtimeConfiguration()
        )
        let result = await runtime.dispatchAndWait("mouseUp", params: [], targetId: button.id, currentCardId: card1.id)
        await StackRuntimeRegistry.shared.shutdown(stackID: doc.stack.id)

        #expect(result.status == .completed)
        #expect(result.navigationTarget == card2.id)
    }

    @Test("repeated go next advances from the last navigation target")
    func repeatedGoNextAdvancesFromLastNavigationTarget() async {
        var doc = HypeDocument.newDocument(name: "Repeated Nav Test")
        let _ = doc.addCard()
        let _ = doc.addCard()
        let sorted = doc.sortedCards
        let card1 = sorted[0]
        let card3 = sorted[2]
        var button = Part(partType: .button, cardId: card1.id, name: "Next Twice")
        button.script = """
        on mouseUp
          go next
          go next
        end mouseUp
        """
        doc.addPart(button)

        let runtime = await StackRuntimeRegistry.shared.runtime(
            for: doc,
            configuration: runtimeConfiguration()
        )
        let result = await runtime.dispatchAndWait("mouseUp", params: [], targetId: button.id, currentCardId: card1.id)
        await StackRuntimeRegistry.shared.shutdown(stackID: doc.stack.id)

        #expect(result.status == .completed)
        #expect(result.navigationTarget == card3.id)
    }

    @Test("wait while exits when condition is false")
    func waitWhileFalseCompletesWithoutSleeping() async {
        let clock = RecordingClock()
        let (doc, cardId, buttonId, fieldID) = makeRuntimeDocument(buttonScript: """
        on mouseUp
          wait while false
          put "done" into field "output"
        end mouseUp
        """)

        let runtime = await StackRuntimeRegistry.shared.runtime(
            for: doc,
            configuration: runtimeConfiguration(clock: clock)
        )
        let result = await runtime.dispatchAndWait("mouseUp", params: [], targetId: buttonId, currentCardId: cardId)
        let updated = result.modifiedDocument ?? doc
        await StackRuntimeRegistry.shared.shutdown(stackID: doc.stack.id)

        #expect(result.status == .completed)
        #expect(await clock.sleeps == [])
        #expect(outputText(from: updated, fieldID: fieldID) == "done")
    }

    @Test("wait followed by send to me is queued instead of nesting synchronously")
    func waitThenSendToMeQueuesTimerLoop() async {
        let clock = RecordingClock()
        let (doc, cardId, buttonId, fieldID) = makeRuntimeDocument(buttonScript: """
        on mouseUp
          global tickCount
          put 0 into tickCount
          put 0 into field "output"
          send "tick" to me
        end mouseUp

        on tick
          global tickCount
          add 1 to tickCount
          put tickCount into field "output"
          if tickCount < 2 then
            wait 0.01 seconds
            send "tick" to me
          end if
        end tick
        """)

        let runtime = await StackRuntimeRegistry.shared.runtime(
            for: doc,
            configuration: runtimeConfiguration(clock: clock)
        )
        let result = await runtime.dispatchAndWait("mouseUp", params: [], targetId: buttonId, currentCardId: cardId)
        let completed = await waitUntil {
            let updated = await runtime.currentDocument()
            return outputText(from: updated, fieldID: fieldID) == "2"
        }
        let updated = await runtime.currentDocument()
        await StackRuntimeRegistry.shared.shutdown(stackID: doc.stack.id)

        #expect(result.status == .completed)
        #expect(completed)
        #expect(outputText(from: updated, fieldID: fieldID) == "2")
        #expect(await clock.sleeps == [0.01])
    }

    @Test("await ollama expression uses the async AI provider")
    func awaitOllamaExpression() async {
        let provider = FixedAIProvider(generated: "scene summary")
        let (doc, cardId, buttonId, fieldID) = makeRuntimeDocument(buttonScript: """
        on mouseUp
          put await ollama("Summarize this card") into field "output"
        end mouseUp
        """)

        let runtime = await StackRuntimeRegistry.shared.runtime(
            for: doc,
            configuration: runtimeConfiguration(aiProvider: provider)
        )
        let result = await runtime.dispatchAndWait("mouseUp", params: [], targetId: buttonId, currentCardId: cardId)
        let updated = result.modifiedDocument ?? doc
        await StackRuntimeRegistry.shared.shutdown(stackID: doc.stack.id)

        #expect(result.status == .completed)
        #expect(outputText(from: updated, fieldID: fieldID) == "scene summary")
    }

    @Test("ask ai with message enqueues a callback that can read the request body")
    func askAICallback() async {
        let provider = FixedAIProvider(generated: "mission briefing")
        let speechRecorder = RuntimeSpeechRecorder()
        let (doc, cardId, buttonId, fieldID) = makeRuntimeDocument(buttonScript: """
        on mouseUp
          ask ai "Write a mission briefing" with message "aiFinished"
        end mouseUp

        on aiFinished requestId, eventName
          if eventName is "completed" then
            put the body of request requestId into field "output"
          end if
        end aiFinished
        """)

        let runtime = await StackRuntimeRegistry.shared.runtime(
            for: doc,
            configuration: runtimeConfiguration(aiProvider: provider, speechOutputProvider: speechRecorder)
        )
        _ = await runtime.dispatchAndWait("mouseUp", params: [], targetId: buttonId, currentCardId: cardId)

        let completed = await waitUntil {
            let updated = await runtime.currentDocument()
            let spokenTexts = await speechRecorder.texts()
            return outputText(from: updated, fieldID: fieldID) == "mission briefing"
                && spokenTexts == ["mission briefing"]
        }

        let updated = await runtime.currentDocument()
        await StackRuntimeRegistry.shared.shutdown(stackID: doc.stack.id)
        #expect(completed)
        #expect(outputText(from: updated, fieldID: fieldID) == "mission briefing")
        #expect(await speechRecorder.texts() == ["mission briefing"])
    }

    @Test("say command uses the script speech provider in stack runtime")
    func sayCommandUsesRuntimeSpeechProvider() async {
        let speechRecorder = RuntimeSpeechRecorder()
        let (doc, cardId, buttonId, _) = makeRuntimeDocument(buttonScript: """
        on mouseUp
          say "runtime speech"
        end mouseUp
        """)

        let runtime = await StackRuntimeRegistry.shared.runtime(
            for: doc,
            configuration: runtimeConfiguration(speechOutputProvider: speechRecorder)
        )
        let result = await runtime.dispatchAndWait("mouseUp", params: [], targetId: buttonId, currentCardId: cardId)
        await StackRuntimeRegistry.shared.shutdown(stackID: doc.stack.id)

        #expect(result.status == .completed)
        #expect(await speechRecorder.texts() == ["runtime speech"])
    }

    @Test("activateListener dispatches listen through card background and stack")
    func activateListenerDispatchesListenThroughHierarchy() async {
        let listenerProbe = RuntimeSpeechListenerProbe()
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let backgroundId = doc.cards[0].backgroundId

        doc.cards[0].script = """
        on listen spokenText
          put "card:" & spokenText into field "output"
          pass listen
        end listen
        """
        if let bgIndex = doc.backgrounds.firstIndex(where: { $0.id == backgroundId }) {
            doc.backgrounds[bgIndex].script = """
            on listen spokenText
              put "|background:" & spokenText after field "output"
              pass listen
            end listen
            """
        }
        doc.stack.script = """
        on listen spokenText
          put "|stack:" & spokenText after field "output"
        end listen
        """

        var button = Part(partType: .button, cardId: cardId, name: "Runner")
        button.script = """
        on mouseUp
          set activateListener to true
          put the activateListener into field "output"
        end mouseUp
        """
        doc.addPart(button)
        let field = Part(partType: .field, cardId: cardId, name: "output")
        doc.addPart(field)

        let runtime = await StackRuntimeRegistry.shared.runtime(
            for: doc,
            configuration: runtimeConfiguration(speechListenerProvider: listenerProbe)
        )
        let startResult = await runtime.dispatchAndWait("mouseUp", params: [], targetId: button.id, currentCardId: cardId)
        #expect(startResult.status == .completed)
        #expect(await runtime.isSpeechListenerActive())
        #expect(await listenerProbe.states() == [true])

        await listenerProbe.emit("open the pod bay doors")
        var updated = await runtime.currentDocument()
        #expect(outputText(from: updated, fieldID: field.id) == "card:open the pod bay doors|background:open the pod bay doors|stack:open the pod bay doors")

        updated.updatePart(id: button.id) { part in
            part.script = """
            on mouseUp
              set activateListener to false
            end mouseUp
            """
        }
        await runtime.syncDocument(updated)
        let stopResult = await runtime.dispatchAndWait("mouseUp", params: [], targetId: button.id, currentCardId: cardId)
        await StackRuntimeRegistry.shared.shutdown(stackID: doc.stack.id)

        #expect(stopResult.status == .completed)
        #expect(await listenerProbe.states() == [true, false])
    }

    #if canImport(Network)
    @Test("request performs an outbound HTTP call and exposes the response body")
    func outboundHTTPRequest() async throws {
        let port = freeLoopbackPort()
        let server = try LoopbackHTTPServer(port: port) { request in
            #expect(request.contains("GET /score HTTP/1.1"))
            return (200, [:], "42")
        }
        defer { server.stop() }

        let rule = OutboundHostRule(hostPattern: "127.0.0.1", allowedSchemes: ["http"], allowedPorts: [port])
        let (doc, cardId, buttonId, fieldID) = makeRuntimeDocument(
            buttonScript: """
            on mouseUp
              request "http://127.0.0.1:\(port)/score"
              put the body of request it into field "output"
            end mouseUp
            """,
            outboundRules: [rule]
        )

        let runtime = await StackRuntimeRegistry.shared.runtime(
            for: doc,
            configuration: runtimeConfiguration()
        )
        let result = await runtime.dispatchAndWait("mouseUp", params: [], targetId: buttonId, currentCardId: cardId)
        let updated = result.modifiedDocument ?? doc
        await StackRuntimeRegistry.shared.shutdown(stackID: doc.stack.id)

        #expect(result.status == .completed)
        #expect(outputText(from: updated, fieldID: fieldID) == "42")
    }

    @Test("auto-start HTTP listeners accept requests and reply through callback scripts")
    func inboundHTTPListener() async throws {
        let port = freeLoopbackPort()
        let listener = SavedNetworkListener(
            name: "Local HTTP",
            transport: .http,
            port: port,
            host: "127.0.0.1",
            callbackMessage: "networkRequest",
            autoStart: true
        )
        let (doc, _, _, fieldID) = makeRuntimeDocument(
            stackScript: """
            on networkRequest requestId, eventName
              if eventName is "request" then
                put the body of request requestId into field "output"
                reply to request requestId with status 201 body "ack"
              end if
            end networkRequest
            """,
            savedListeners: [listener]
        )

        let runtime = await StackRuntimeRegistry.shared.runtime(
            for: doc,
            configuration: runtimeConfiguration()
        )
        await runtime.syncDocument(doc)

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/hook")!)
        request.httpMethod = "POST"
        request.httpBody = Data("payload".utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let completed = await waitUntil {
            let updated = await runtime.currentDocument()
            return outputText(from: updated, fieldID: fieldID) == "payload"
        }
        let updated = await runtime.currentDocument()
        await StackRuntimeRegistry.shared.shutdown(stackID: doc.stack.id)

        #expect((response as? HTTPURLResponse)?.statusCode == 201)
        #expect(String(decoding: data, as: UTF8.self) == "ack")
        #expect(completed)
        #expect(outputText(from: updated, fieldID: fieldID) == "payload")
    }

    @Test("TCP listeners receive data and can respond to clients")
    func inboundTCPListener() async throws {
        let port = freeLoopbackPort()
        let listener = SavedNetworkListener(
            name: "Local TCP",
            transport: .tcp,
            port: port,
            host: "127.0.0.1",
            callbackMessage: "socketEvent",
            autoStart: true
        )
        // Note: the handler intentionally does NOT call
        // `close connection` after sending the response. Closing the
        // connection from inside HypeTalk races the kernel's TCP send
        // buffer — the FIN packet can land before the "pong" payload
        // flushes, causing the client's receive() to observe EOF with
        // empty data. The test cancels the client side at the end,
        // which is enough to let the runtime tear the connection down
        // cleanly via NWConnection state changes.
        let (doc, _, _, fieldID) = makeRuntimeDocument(
            stackScript: """
            on socketEvent connectionId, eventName
              if eventName is "data" then
                put the body of connection connectionId into field "output"
                send "pong" to connection connectionId
              end if
            end socketEvent
            """,
            savedListeners: [listener]
        )

        let runtime = await StackRuntimeRegistry.shared.runtime(
            for: doc,
            configuration: runtimeConfiguration()
        )
        await runtime.syncDocument(doc)

        let client = NWConnection(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: UInt16(port))!,
            using: .tcp
        )
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            client.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    client.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    client.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            client.start(queue: .global())
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            client.send(content: Data("ping".utf8), completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }

        let pong = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            client.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: String(decoding: data ?? Data(), as: UTF8.self))
                }
            }
        }

        let completed = await waitUntil {
            let updated = await runtime.currentDocument()
            return outputText(from: updated, fieldID: fieldID) == "ping"
        }

        let updated = await runtime.currentDocument()
        client.cancel()
        await StackRuntimeRegistry.shared.shutdown(stackID: doc.stack.id)

        #expect(completed)
        #expect(pong == "pong")
        #expect(outputText(from: updated, fieldID: fieldID) == "ping")
    }
    #endif
}
