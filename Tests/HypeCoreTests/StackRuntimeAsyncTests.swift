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

private func freeLoopbackPort() -> Int {
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
    clock: RuntimeClock = SystemRuntimeClock()
) -> StackRuntimeConfiguration {
    StackRuntimeConfiguration(
        aiProvider: aiProvider,
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

@Suite("StackRuntime async + networking")
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
            configuration: runtimeConfiguration(aiProvider: provider)
        )
        _ = await runtime.dispatchAndWait("mouseUp", params: [], targetId: buttonId, currentCardId: cardId)

        let completed = await waitUntil {
            let updated = await runtime.currentDocument()
            return outputText(from: updated, fieldID: fieldID) == "mission briefing"
        }

        let updated = await runtime.currentDocument()
        await StackRuntimeRegistry.shared.shutdown(stackID: doc.stack.id)
        #expect(completed)
        #expect(outputText(from: updated, fieldID: fieldID) == "mission briefing")
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
        let (doc, _, _, fieldID) = makeRuntimeDocument(
            stackScript: """
            on socketEvent connectionId, eventName
              if eventName is "data" then
                put the body of connection connectionId into field "output"
                send "pong" to connection connectionId
                close connection connectionId
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
