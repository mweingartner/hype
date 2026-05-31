import Darwin
import AppKit
import Foundation
import HypeCore

private let hypeDebugMaxRequestBytes = 1_048_576
private let hypeDebugSocketTimeoutSeconds = 30

private final class HypeDebugResponseBox: @unchecked Sendable {
    var response: [String: Any]

    init(_ response: [String: Any]) {
        self.response = response
    }
}

extension Notification.Name {
    static let hypeDebugConnectionStatusDidChange = Notification.Name("hypeDebugConnectionStatusDidChange")
}

struct HypeDebugServerStatus: Equatable {
    var isRunning: Bool
    var instanceId: String
    var socketPath: String
    var descriptorPath: String
    var discoveryDirectory: String
    var activeConnectionCount: Int

    var instanceLink: String {
        "hype://debug/instances/\(instanceId)"
    }
}

final class HypeDebugServer: @unchecked Sendable {
    @MainActor
    static let shared = HypeDebugServer()

    private let instanceId = UUID().uuidString
    private let queue = DispatchQueue(label: "hype.debug.server")
    private let webAssetSession = WebAssetSession()
    private let startedAt = Date()
    private let startedAtString: String
    private var transactions: [UUID: AIEditTransaction] = [:]
    private var listenSocket: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var socketPath = ""
    private var descriptorPath = ""
    private let connectionLock = NSLock()
    private var connectionCount = 0

    private init() {
        startedAtString = ISO8601DateFormatter().string(from: startedAt)
    }

    @MainActor
    func start() {
        guard listenSocket == -1 else { return }
        do {
            let directory = try HypeDebugDirectory.socketDirectory()
            socketPath = directory.appendingPathComponent("\(getpid()).sock").path
            descriptorPath = directory.appendingPathComponent("\(instanceId).json").path
            HypeLogger.shared.info("Debug bridge using socket directory: \(directory.path)", source: "DebugBridge")
            try? FileManager.default.removeItem(atPath: socketPath)

            let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else {
                throw DebugServerError.posix("socket", errno)
            }
            let flags = Darwin.fcntl(fd, F_GETFL, 0)
            guard flags >= 0, Darwin.fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else {
                let error = errno
                Darwin.close(fd)
                throw DebugServerError.posix("fcntl", error)
            }

            var address = sockaddr_un()
            address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
            address.sun_family = sa_family_t(AF_UNIX)
            let pathBytes = socketPath.utf8CString
            guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
                HypeLogger.shared.error("Debug socket path too long (\(pathBytes.count) bytes): \(socketPath)", source: "DebugBridge")
                Darwin.close(fd)
                throw DebugServerError.message("debug socket path is too long")
            }
            withUnsafeMutableBytes(of: &address.sun_path) { rawBuffer in
                rawBuffer.copyBytes(from: pathBytes.map { UInt8(bitPattern: $0) })
            }

            let bindStatus = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bindStatus == 0 else {
                let error = errno
                HypeLogger.shared.error("Debug bridge bind failed (\(bindStatus)) for path \(socketPath): \(String(cString: strerror(error)))", source: "DebugBridge")
                Darwin.close(fd)
                throw DebugServerError.posix("bind", error)
            }
            guard Darwin.listen(fd, 16) == 0 else {
                let error = errno
                HypeLogger.shared.error("Debug bridge listen failed for \(socketPath): \(String(cString: strerror(error)))", source: "DebugBridge")
                Darwin.close(fd)
                throw DebugServerError.posix("listen", error)
            }

            listenSocket = fd
            try writeDescriptor()
            HypeLogger.shared.info("Debug bridge wrote descriptor: \(descriptorPath)", source: "DebugBridge")
            let source = makeAcceptSource(fileDescriptor: fd)
            acceptSource = source
            source.resume()
            HypeLogger.shared.info("Debug bridge listening on \(socketPath)", source: "DebugBridge")
        } catch {
            HypeLogger.shared.error("Failed to start debug bridge: \(error.localizedDescription)", source: "DebugBridge")
            stop()
        }
    }

    @MainActor
    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        if listenSocket != -1 {
            listenSocket = -1
        }
        if !socketPath.isEmpty {
            try? FileManager.default.removeItem(atPath: socketPath)
            try? FileManager.default.removeItem(atPath: descriptorPath)
            socketPath = ""
            descriptorPath = ""
        }
        resetConnectionCount()
    }

    nonisolated var activeConnectionCount: Int {
        connectionLock.lock()
        defer { connectionLock.unlock() }
        return connectionCount
    }

    @MainActor
    var status: HypeDebugServerStatus {
        HypeDebugServerStatus(
            isRunning: listenSocket != -1,
            instanceId: instanceId,
            socketPath: socketPath,
            descriptorPath: descriptorPath,
            discoveryDirectory: descriptorPath.isEmpty ? "" : (descriptorPath as NSString).deletingLastPathComponent,
            activeConnectionCount: activeConnectionCount
        )
    }

    @MainActor
    private func writeDescriptor() throws {
        let data = try JSONSerialization.data(withJSONObject: descriptor(), options: [.prettyPrinted, .sortedKeys])
        let url = URL(fileURLWithPath: descriptorPath)
        let tempURL = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).tmp")
        try data.write(to: tempURL, options: .atomic)
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: tempURL, to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    @MainActor
    private func descriptor() -> [String: Any] {
        let document = HypeDocumentMutationCoordinator.shared.activeDocumentBinding?.wrappedValue.document
        let bundle = Bundle.main
        return [
            "protocolVersion": 1,
            "instanceId": instanceId,
            "pid": Int(getpid()),
            "socketPath": socketPath,
            "descriptorPath": descriptorPath,
            "discoveryDirectory": (descriptorPath as NSString).deletingLastPathComponent,
            "startedAt": startedAtString,
            "bundlePath": bundle.bundlePath,
            "bundleIdentifier": bundle.bundleIdentifier ?? NSNull(),
            "appVersion": bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? NSNull(),
            "appBuild": bundle.infoDictionary?["CFBundleVersion"] as? String ?? NSNull(),
            "activeDocumentName": document?.stack.name ?? NSNull(),
            "activeDocumentId": document?.stack.id.uuidString ?? NSNull(),
            "activeDocumentPath": {
                guard let doc = document else { return NSNull() }
                return URL(fileURLWithPath: doc.stack.name).absoluteString as NSString
            }(),
        ]
    }

    private nonisolated func makeAcceptSource(fileDescriptor fd: Int32) -> DispatchSourceRead {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self, fd] in
            self?.acceptPendingConnections(on: fd)
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        return source
    }

    private nonisolated func acceptPendingConnections(on listenSocket: Int32) {
        while true {
            let client = Darwin.accept(listenSocket, nil, nil)
            if client < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                return
            }
            configureAcceptedClientSocket(client)
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handle(clientSocket: client)
            }
        }
    }

    private nonisolated func configureAcceptedClientSocket(_ client: Int32) {
        var timeout = timeval(tv_sec: hypeDebugSocketTimeoutSeconds, tv_usec: 0)
        withUnsafePointer(to: &timeout) { pointer in
            pointer.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<timeval>.size) {
                _ = Darwin.setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
            }
        }
        let flags = Darwin.fcntl(client, F_GETFL, 0)
        if flags >= 0 {
            _ = Darwin.fcntl(client, F_SETFL, flags & ~O_NONBLOCK)
        }
    }

    private nonisolated func handle(clientSocket: Int32) {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        noteClientConnected()
        defer {
            noteClientDisconnected()
            Darwin.close(clientSocket)
        }

        while true {
            let readCount = Darwin.recv(clientSocket, &chunk, chunk.count, 0)
            if readCount == 0 { return }
            if readCount < 0 {
                if errno == EINTR { continue }
                return
            }

            buffer.append(chunk, count: readCount)
            if buffer.count > hypeDebugMaxRequestBytes {
                write(response: jsonRPCError(id: nil, code: -32600, message: "Invalid Request"), to: clientSocket)
                return
            }

            while let newline = buffer.firstIndex(of: 0x0A) {
                let requestData = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                let response = handleRequestSynchronously(requestData)
                write(response: response, to: clientSocket)
            }
        }
    }

    private nonisolated func handleRequestSynchronously(_ data: Data) -> [String: Any] {
        if let keepalive = handleDedicatedServerRequest(data) {
            return keepalive
        }

        let semaphore = DispatchSemaphore(value: 0)
        let responseBox = HypeDebugResponseBox(jsonRPCError(id: nil, code: -32603, message: "Debug request timed out"))
        Task { @MainActor in
            responseBox.response = await self.handleRequest(data)
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + .seconds(hypeDebugSocketTimeoutSeconds))
        return responseBox.response
    }

    private nonisolated func handleDedicatedServerRequest(_ data: Data) -> [String: Any]? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let request = object as? [String: Any],
              let method = request["method"] as? String,
              method == "debug/keepalive" else {
            return nil
        }

        return jsonRPCResult(id: request["id"], result: [
            "ok": true,
            "pid": Int(getpid()),
            "instanceId": instanceId,
            "socketPath": socketPath,
            "startedAt": startedAtString,
        ])
    }

    private nonisolated func noteClientConnected() {
        connectionLock.lock()
        connectionCount += 1
        let count = connectionCount
        connectionLock.unlock()
        postConnectionStatus(count: count)
    }

    private nonisolated func noteClientDisconnected() {
        connectionLock.lock()
        connectionCount = max(0, connectionCount - 1)
        let count = connectionCount
        connectionLock.unlock()
        postConnectionStatus(count: count)
    }

    private nonisolated func resetConnectionCount() {
        connectionLock.lock()
        connectionCount = 0
        connectionLock.unlock()
        postConnectionStatus(count: 0)
    }

    private nonisolated func postConnectionStatus(count: Int) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .hypeDebugConnectionStatusDidChange,
                object: nil,
                userInfo: ["connectionCount": count]
            )
        }
    }

    private nonisolated func write(response: [String: Any], to clientSocket: Int32) {
        guard let data = try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]) else { return }
        var output = data
        output.append(0x0A)
        output.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var sent = 0
            while sent < output.count {
                let count = Darwin.send(clientSocket, base.advanced(by: sent), output.count - sent, 0)
                if count <= 0 { return }
                sent += count
            }
        }
    }

    @MainActor
    private func handleRequest(_ data: Data) async -> [String: Any] {
        do {
            let object = try JSONSerialization.jsonObject(with: data)
            guard let request = object as? [String: Any],
                  let method = request["method"] as? String else {
                return jsonRPCError(id: nil, code: -32600, message: "Invalid Request")
            }
            let id = request["id"]
            let params = request["params"] as? [String: Any] ?? [:]

            switch method {
            case "debug/keepalive":
                return jsonRPCResult(id: id, result: [
                    "ok": true,
                    "pid": Int(getpid()),
                    "instanceId": instanceId,
                    "socketPath": socketPath,
                    "startedAt": startedAtString,
                ])
            case "debug/importHyperCardStack":
                guard let path = params["path"] as? String, !path.isEmpty else {
                    return jsonRPCError(id: id, code: -32602, message: "debug/importHyperCardStack requires params.path")
                }
                return await importHyperCardStack(path: path, params: params, id: id)
            case "debug/clickButton":
                let cardReference = params["card"] as? String
                guard let buttonName = params["button"] as? String, !buttonName.isEmpty else {
                    return jsonRPCError(id: id, code: -32602, message: "debug/clickButton requires params.button")
                }
                return await clickButton(named: buttonName, onCard: cardReference, id: id)
            case "debug/getScriptState":
                return jsonRPCResult(id: id, result: scriptState(params: params))
            case "debug/hello", "debug/getState":
                try? writeDescriptor()
                return jsonRPCResult(id: id, result: descriptor())
            case "debug/listTools":
                return jsonRPCResult(id: id, result: ["tools": debugTools()])
            case "debug/listResources":
                return jsonRPCResult(id: id, result: ["resources": await debugResources()])
            case "debug/readResource":
                guard let uri = params["uri"] as? String, !uri.isEmpty else {
                    return jsonRPCError(id: id, code: -32602, message: "debug/readResource requires params.uri")
                }
                return jsonRPCResult(id: id, result: ["uri": uri, "mimeType": "application/json", "value": await debugResource(uri: uri)])
            case "debug/listPrompts":
                return jsonRPCResult(id: id, result: ["prompts": await debugPrompts()])
            case "debug/getPrompt":
                guard let name = params["name"] as? String, !name.isEmpty else {
                    return jsonRPCError(id: id, code: -32602, message: "debug/getPrompt requires params.name")
                }
                let arguments = mcpArguments(from: params["arguments"] as? [String: Any] ?? [:])
                return jsonRPCResult(id: id, result: ["value": await debugPrompt(name: name, arguments: arguments)])
            case "debug/callTool":
                guard let name = params["name"] as? String else {
                    return jsonRPCError(id: id, code: -32602, message: "debug/callTool requires params.name")
                }
                let rawArguments = params["arguments"] as? [String: Any] ?? [:]
                let result: (text: String, isError: Bool)
                if HypeMCPToolBridge.mcpControlToolNames.contains(name) {
                    result = await callControlTool(name: name, arguments: mcpArguments(from: rawArguments))
                } else {
                    result = await callTool(name: name, arguments: stringifyArguments(rawArguments))
                }
                return jsonRPCResult(id: id, result: ["text": result.text, "isError": result.isError])
            default:
                return jsonRPCError(id: id, code: -32601, message: "Method not found")
            }
        } catch {
            return jsonRPCError(id: nil, code: -32700, message: "Parse error")
        }
    }

    @MainActor
    private func importHyperCardStack(path: String, params: [String: Any], id: Any?) async -> [String: Any] {
        do {
            let url = URL(fileURLWithPath: path)
            let result = try StackImportCImporter(options: importOptions(from: params)).importStack(at: url)
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-debug-imported.hype")
            try? FileManager.default.removeItem(at: outputURL)
            try HypeSQLiteStackStore().save(result.document, toPackageAt: outputURL)
            let openError = await openImportedDocument(at: outputURL)
            if let openError {
                return jsonRPCError(id: id, code: -32002, message: openError.localizedDescription)
            }
            return jsonRPCResult(id: id, result: [
                "stackName": result.document.stack.name,
                "cardCount": result.document.cards.count,
                "backgroundCount": result.document.backgrounds.count,
                "partCount": result.document.parts.count,
                "assetCount": result.document.assetRepository.assets.count,
                "documentPath": outputURL.path,
                "targetPlatforms": result.document.stack.deploymentTargets.selectedPlatforms.map(\.rawValue),
                "primaryTargetPlatform": result.document.stack.deploymentTargets.primaryPlatform.rawValue,
                "warnings": result.report.warnings,
            ])
        } catch {
            return jsonRPCError(id: id, code: -32001, message: error.localizedDescription)
        }
    }

    @MainActor
    private func openImportedDocument(at url: URL) async -> Error? {
        await withCheckedContinuation { continuation in
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                continuation.resume(returning: error)
            }
        }
    }

    @MainActor
    private func clickButton(named buttonName: String, onCard cardReference: String?, id: Any?) async -> [String: Any] {
        guard let binding = HypeDocumentMutationCoordinator.shared.activeDocumentBinding else {
            return jsonRPCError(id: id, code: -32000, message: "No active Hype document.")
        }

        let document = binding.wrappedValue.document
        guard let card = resolveCard(reference: cardReference, in: document) else {
            return jsonRPCError(id: id, code: -32002, message: "Card not found.")
        }
        guard let button = resolveButton(named: buttonName, on: card, in: document) else {
            return jsonRPCError(id: id, code: -32003, message: "Button not found.")
        }

        HypeLogger.shared.info(
            "debug click button \"\(button.name)\" on card \"\(card.name)\" (script chars=\(button.script.count))",
            source: "DebugBridge"
        )
        let started = Date()
        let result = await MessageDispatcher().dispatchAsync(
            message: "mouseUp",
            params: [],
            targetId: button.id,
            document: document,
            currentCardId: card.id,
            mouseX: Double(button.left),
            mouseY: Double(button.top)
        )
        let elapsedMS = Int(Date().timeIntervalSince(started) * 1000)
        var updated = result.modifiedDocument ?? document
        var navigatedTo: UUID?
        if let navTarget = result.navigationTarget {
            navigatedTo = navTarget
            HypeDocumentMutationCoordinator.shared.activeCardId = navTarget
        } else {
            HypeDocumentMutationCoordinator.shared.activeCardId = card.id
        }
        HypeDocumentMutationCoordinator.shared.applyDocument(
            updated,
            to: binding,
            undoManager: nil,
            actionName: "Debug Click Button"
        )
        if let navTarget = navigatedTo, !updated.cards.contains(where: { $0.id == navTarget }) {
            updated = binding.wrappedValue.document
        }
        let activeId = HypeDocumentMutationCoordinator.shared.activeCardId ?? card.id
        let activeCard = updated.cards.first(where: { $0.id == activeId })

        return jsonRPCResult(id: id, result: [
            "status": String(describing: result.status),
            "elapsedMS": elapsedMS,
            "buttonName": button.name,
            "buttonScriptChars": button.script.count,
            "sourceCardName": card.name,
            "sourceCardNumber": cardNumber(card.id, in: document) ?? NSNull(),
            "navigationTarget": navigatedTo?.uuidString ?? NSNull(),
            "activeCardName": activeCard?.name ?? NSNull(),
            "activeCardNumber": cardNumber(activeId, in: updated) ?? NSNull(),
            "error": result.error?.message ?? NSNull(),
        ])
    }

    @MainActor
    private func scriptState(params: [String: Any]) -> [String: Any] {
        guard let binding = HypeDocumentMutationCoordinator.shared.activeDocumentBinding else {
            return ["error": "No active Hype document."]
        }

        let document = binding.wrappedValue.document
        let card = resolveCard(reference: params["card"] as? String, in: document)
            ?? HypeDocumentMutationCoordinator.shared.activeCardId.flatMap { id in
                document.cards.first(where: { $0.id == id })
            }
            ?? document.sortedCards.first
        guard let card else {
            return ["error": "No card available."]
        }
        let buttonName = params["button"] as? String
        let button = buttonName.flatMap { resolveButton(named: $0, on: card, in: document) }
        let background = document.backgrounds.first(where: { $0.id == card.backgroundId })
        let cardParts = document.parts.filter { $0.cardId == card.id }
        let backgroundParts = document.parts.filter { $0.backgroundId == card.backgroundId }

        return [
            "stackName": document.stack.name,
            "cardName": card.name,
            "cardNumber": cardNumber(card.id, in: document) ?? NSNull(),
            "cardId": card.id.uuidString,
            "cardScriptChars": card.script.count,
            "backgroundName": background?.name ?? NSNull(),
            "backgroundScriptChars": background?.script.count ?? 0,
            "stackScriptChars": document.stack.script.count,
            "cardPartCount": cardParts.count,
            "backgroundPartCount": backgroundParts.count,
            "buttonName": button?.name ?? NSNull(),
            "buttonId": button?.id.uuidString ?? NSNull(),
            "buttonScriptChars": button?.script.count ?? 0,
            "buttonScript": button?.script ?? "",
        ]
    }

    @MainActor
    private func resolveCard(reference: String?, in document: HypeDocument) -> Card? {
        let cards = document.sortedCards
        guard let reference = reference?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reference.isEmpty else {
            if let active = HypeDocumentMutationCoordinator.shared.activeCardId {
                return document.cards.first(where: { $0.id == active })
            }
            return cards.first
        }

        let lower = reference.lowercased()
        if lower.hasPrefix("card "),
           let number = Int(lower.dropFirst("card ".count).trimmingCharacters(in: .whitespacesAndNewlines)),
           number > 0,
           number <= cards.count {
            return cards[number - 1]
        }
        if let number = Int(reference), number > 0, number <= cards.count {
            return cards[number - 1]
        }
        if let id = UUID(uuidString: reference),
           let card = document.cards.first(where: { $0.id == id }) {
            return card
        }
        return document.cards.first { $0.name.caseInsensitiveCompare(reference) == .orderedSame }
    }

    private func resolveButton(named name: String, on card: Card, in document: HypeDocument) -> Part? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cardButtons = document.parts.filter { $0.cardId == card.id && $0.partType == .button }
        if let button = cardButtons.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return button
        }
        let backgroundButtons = document.parts.filter { $0.backgroundId == card.backgroundId && $0.partType == .button }
        if let button = backgroundButtons.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return button
        }
        if let number = Int(trimmed.split(separator: " ").last ?? ""),
           number > 0 {
            let allButtons = cardButtons + backgroundButtons
            if number <= allButtons.count {
                return allButtons[number - 1]
            }
        }
        return nil
    }

    private func cardNumber(_ cardId: UUID, in document: HypeDocument) -> Int? {
        document.sortedCards.firstIndex(where: { $0.id == cardId }).map { $0 + 1 }
    }

    @MainActor
    private func debugTools() -> [[String: Any]] {
        let authoringTools = availableTools().map { tool in
            [
                "name": tool.function.name,
                "description": tool.function.description,
                "inputSchema": inputSchema(for: tool),
            ]
        }
        let controlTools = HypeMCPToolBridge.allTools
            .filter { HypeMCPToolBridge.mcpControlToolNames.contains($0.name) }
            .map(mcpToolJSON)
        return controlTools + authoringTools
    }

    @MainActor
    private func debugResources() async -> [[String: Any]] {
        guard let backend = documentBackend() else {
            return [
                [
                    "uri": "hype://app/state",
                    "name": "App State",
                    "description": "Current Hype app and active debug-session state.",
                    "mimeType": "application/json",
                ]
            ]
        }
        return await backend.listResources().map(mcpResourceJSON)
    }

    @MainActor
    private func debugResource(uri: String) async -> Any {
        guard let backend = documentBackend() else {
            if uri == "hype://app/state" {
                return [
                    "activeStackId": NSNull(),
                    "openStacks": [],
                    "debug": descriptor(),
                ] as [String: Any]
            }
            return ["error": "No active Hype document."] as [String: Any]
        }
        return (await backend.readResource(uri: uri)).jsonObject
    }

    @MainActor
    private func debugPrompts() async -> [[String: Any]] {
        guard let backend = documentBackend() else { return [] }
        return await backend.listPrompts().map(mcpPromptJSON)
    }

    @MainActor
    private func debugPrompt(name: String, arguments: [String: HypeMCPJSONValue]) async -> Any {
        guard let backend = documentBackend() else {
            return ["error": "No active Hype document."] as [String: Any]
        }
        return (await backend.getPrompt(name: name, arguments: arguments)).jsonObject
    }

    @MainActor
    private func documentBackend() -> HypeMCPDocumentBackend? {
        guard let document = HypeDocumentMutationCoordinator.shared.activeDocumentBinding?.wrappedValue.document else {
            return nil
        }
        let currentCardId = HypeDocumentMutationCoordinator.shared.activeCardId
            ?? document.sortedCards.first?.id
        return HypeMCPDocumentBackend(
            document: document,
            currentCardId: currentCardId,
            allowMutations: allowMCPMutations()
        )
    }

    private func mcpToolJSON(_ tool: HypeMCPTool) -> [String: Any] {
        [
            "name": tool.name,
            "description": tool.description,
            "inputSchema": tool.inputSchema.jsonObject,
        ]
    }

    private func mcpResourceJSON(_ resource: HypeMCPResource) -> [String: Any] {
        [
            "uri": resource.uri,
            "name": resource.name,
            "description": resource.description,
            "mimeType": resource.mimeType,
        ]
    }

    private func mcpPromptJSON(_ prompt: HypeMCPPrompt) -> [String: Any] {
        [
            "name": prompt.name,
            "description": prompt.description,
            "arguments": prompt.arguments.map {
                [
                    "name": $0.name,
                    "description": $0.description,
                    "required": $0.required,
                ] as [String: Any]
            },
        ]
    }

    @MainActor
    private func availableTools() -> [OllamaTool] {
        let document = HypeDocumentMutationCoordinator.shared.activeDocumentBinding?.wrappedValue.document
        let withWebAssets = HypeToolDefinitions.withWebAssetTools(
            HypeToolDefinitions.allTools,
            enabled: document?.stack.webAssetsAllowed == true
        )
        let hasContext = !(document?.aiContextLibrary.items.isEmpty ?? true)
        return HypeToolDefinitions.withAIContextTools(withWebAssets, enabled: hasContext)
    }

    private func inputSchema(for tool: OllamaTool) -> [String: Any] {
        var properties: [String: Any] = [:]
        for (name, property) in tool.function.parameters.properties {
            var schema: [String: Any] = [
                "type": property.type,
                "description": property.description,
            ]
            if let values = property.enum {
                schema["enum"] = values
            }
            properties[name] = schema
        }
        return [
            "type": tool.function.parameters.type,
            "properties": properties,
            "required": tool.function.parameters.required,
        ]
    }

    @MainActor
    private func callControlTool(name: String, arguments: [String: HypeMCPJSONValue]) async -> (text: String, isError: Bool) {
        switch name {
        case "hype_get_app_state", "hype_list_open_stacks":
            return (debugJSONText(await debugResource(uri: "hype://app/state")), false)
        case "hype_get_preferences":
            return (debugJSONText(HypeMCPPreferenceStore.snapshot().jsonObject), false)
        case "hype_set_preference":
            guard allowMCPMutations() else { return ("MCP mutations are disabled.", true) }
            let result = HypeMCPPreferenceStore.setPreference(
                name: arguments["name"]?.flattenedString ?? "",
                value: arguments["value"]?.flattenedString ?? ""
            )
            return (debugJSONText(["result": result, "preferences": HypeMCPPreferenceStore.snapshot().jsonObject]), false)
        case "hype_set_secret":
            guard allowMCPMutations() else { return ("MCP mutations are disabled.", true) }
            let result = HypeMCPPreferenceStore.setSecret(
                name: arguments["name"]?.flattenedString ?? "",
                value: arguments["value"]?.flattenedString ?? ""
            )
            return (debugJSONText(["result": result, "preferences": HypeMCPPreferenceStore.snapshot().jsonObject]), false)
        case "hype_delete_secret":
            guard allowMCPMutations() else { return ("MCP mutations are disabled.", true) }
            let result = HypeMCPPreferenceStore.deleteSecret(name: arguments["name"]?.flattenedString ?? "")
            return (debugJSONText(["result": result, "preferences": HypeMCPPreferenceStore.snapshot().jsonObject]), false)
        case "hype_run_existing_tool":
            guard allowMCPMutations() else { return ("MCP mutations are disabled.", true) }
            let toolName = arguments["tool_name"]?.flattenedString ?? ""
            let toolArguments = HypeMCPToolBridge.parseArgumentsJSON(arguments["arguments_json"]?.flattenedString ?? "{}")
            return await callTool(name: toolName, arguments: toolArguments)
        case "hype_preview_transaction":
            guard allowMCPMutations() else { return ("MCP mutations are disabled.", true) }
            return await previewTransaction(arguments: arguments)
        case "hype_apply_transaction":
            guard allowMCPMutations() else { return ("MCP mutations are disabled.", true) }
            return await applyTransaction(idText: arguments["transaction_id"]?.flattenedString ?? "")
        case "hype_rollback_transaction":
            return rollbackTransaction(idText: arguments["transaction_id"]?.flattenedString ?? "")
        case "hype_create_test_stack":
            guard allowMCPMutations() else { return ("MCP mutations are disabled.", true) }
            return createTestStack(arguments: arguments)
        default:
            return ("Unknown MCP control tool \(name)", true)
        }
    }

    @MainActor
    private func previewTransaction(arguments: [String: HypeMCPJSONValue]) async -> (text: String, isError: Bool) {
        guard let binding = HypeDocumentMutationCoordinator.shared.activeDocumentBinding else {
            return ("No active Hype document. Open or focus a stack window before previewing transactions.", true)
        }
        let current = binding.wrappedValue.document
        let currentCardId = HypeDocumentMutationCoordinator.shared.activeCardId
            ?? current.sortedCards.first?.id
            ?? UUID()
        let calls = transactionCalls(from: arguments)
        guard !calls.isEmpty else {
            return ("hype_preview_transaction requires tool_calls_json or tool_name.", true)
        }
        let transaction = await AIEditTransactionRunner(executor: makeExecutor(for: current)).preview(
            toolCalls: calls,
            document: current,
            currentCardId: currentCardId,
            prompt: arguments["prompt"]?.flattenedString ?? "MCP transaction",
            providerName: "debug-mcp"
        )
        transactions[transaction.id] = transaction
        return (debugJSONText(transactionSummary(transaction)), false)
    }

    @MainActor
    private func applyTransaction(idText: String) async -> (text: String, isError: Bool) {
        guard let id = UUID(uuidString: idText), var transaction = transactions[id] else {
            return ("Unknown transaction \(idText)", true)
        }
        guard let binding = HypeDocumentMutationCoordinator.shared.activeDocumentBinding else {
            return ("No active Hype document. Open or focus a stack window before applying transactions.", true)
        }
        var document = binding.wrappedValue.document
        let currentCardId = HypeDocumentMutationCoordinator.shared.activeCardId
            ?? document.sortedCards.first?.id
            ?? UUID()
        let applied = await AIEditTransactionRunner(executor: makeExecutor(for: document)).apply(
            &transaction,
            to: &document,
            currentCardId: currentCardId
        )
        transactions[id] = applied
        HypeDocumentMutationCoordinator.shared.applyDocument(
            document,
            to: binding,
            undoManager: nil,
            actionName: "Debug MCP Transaction"
        )
        return (debugJSONText(transactionSummary(applied)), false)
    }

    @MainActor
    private func rollbackTransaction(idText: String) -> (text: String, isError: Bool) {
        guard let id = UUID(uuidString: idText), var transaction = transactions[id] else {
            return ("Unknown transaction \(idText)", true)
        }
        guard let binding = HypeDocumentMutationCoordinator.shared.activeDocumentBinding else {
            return ("No active Hype document. Open or focus a stack window before rolling back transactions.", true)
        }
        var document = binding.wrappedValue.document
        let rolledBack = AIEditTransactionRunner(executor: makeExecutor(for: document)).rollback(&transaction, to: &document)
        transactions[id] = rolledBack
        HypeDocumentMutationCoordinator.shared.applyDocument(
            document,
            to: binding,
            undoManager: nil,
            actionName: "Debug MCP Transaction Rollback"
        )
        return (debugJSONText(transactionSummary(rolledBack)), false)
    }

    @MainActor
    private func createTestStack(arguments: [String: HypeMCPJSONValue]) -> (text: String, isError: Bool) {
        guard let binding = HypeDocumentMutationCoordinator.shared.activeDocumentBinding else {
            return ("No active Hype document. Open or focus a stack window before creating a test stack.", true)
        }
        let name = arguments["name"]?.flattenedString.nonEmpty ?? "MCP Test Stack"
        let document: HypeDocument
        do {
            var draft = HypeDocument.newDocument(name: name)
            draft.stack.deploymentTargets = try deploymentTargets(
                targetPlatforms: arguments["target_platforms"]?.flattenedString
                    ?? arguments["targetPlatforms"]?.flattenedString
                    ?? arguments["target_platform"]?.flattenedString
                    ?? arguments["targetPlatform"]?.flattenedString,
                primaryTargetPlatform: arguments["primary_target_platform"]?.flattenedString
                    ?? arguments["primaryTargetPlatform"]?.flattenedString
            )
            document = draft
        } catch {
            return (error.localizedDescription, true)
        }
        HypeDocumentMutationCoordinator.shared.activeCardId = document.sortedCards.first?.id
        HypeDocumentMutationCoordinator.shared.applyDocument(
            document,
            to: binding,
            undoManager: nil,
            actionName: "Debug MCP Test Stack"
        )
        transactions.removeAll()
        return (debugJSONText([
            "result": "Created test stack",
            "state": [
                "activeStackId": document.stack.id.uuidString,
                "targetPlatforms": document.stack.deploymentTargets.selectedPlatforms.map(\.rawValue),
                "primaryTargetPlatform": document.stack.deploymentTargets.primaryPlatform.rawValue,
            ],
        ]), false)
    }

    private func importOptions(from params: [String: Any]) throws -> HyperCardImportOptions {
        let targets = try deploymentTargets(
            targetPlatforms: params["targetPlatforms"] as? String
                ?? params["target_platforms"] as? String
                ?? params["targetPlatform"] as? String
                ?? params["target_platform"] as? String,
            primaryTargetPlatform: params["primaryTargetPlatform"] as? String
                ?? params["primary_target_platform"] as? String
        )
        return HyperCardImportOptions(deploymentTargets: targets)
    }

    private func deploymentTargets(
        targetPlatforms: String?,
        primaryTargetPlatform: String?
    ) throws -> StackDeploymentTargets {
        let selected = try parseTargetPlatforms(targetPlatforms)
        let primary = try parsePrimaryTargetPlatform(primaryTargetPlatform, selectedPlatforms: selected)
        return StackDeploymentTargets(
            selectedPlatforms: selected,
            primaryPlatform: primary,
            selectionPromptAcknowledged: true
        )
    }

    private func parseTargetPlatforms(_ raw: String?) throws -> [HypeTargetPlatform] {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return [.macOS]
        }
        guard let platforms = HypeTargetPlatform.parseList(raw), !platforms.isEmpty else {
            throw DebugServerError.message("Invalid target platform '\(raw)' (expected macOS, iPhone, iPad, or tvOS)")
        }
        return platforms
    }

    private func parsePrimaryTargetPlatform(
        _ raw: String?,
        selectedPlatforms: [HypeTargetPlatform]
    ) throws -> HypeTargetPlatform {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return selectedPlatforms.first ?? .macOS
        }
        guard let platform = HypeTargetPlatform.parse(raw) else {
            throw DebugServerError.message("Invalid primary target platform '\(raw)' (expected macOS, iPhone, iPad, or tvOS)")
        }
        guard selectedPlatforms.contains(platform) else {
            throw DebugServerError.message("Primary target platform '\(platform.rawValue)' is not included in target platforms")
        }
        return platform
    }

    private func transactionCalls(from arguments: [String: HypeMCPJSONValue]) -> [OllamaToolCall] {
        if let json = arguments["tool_calls_json"]?.flattenedString,
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(HypeMCPJSONValue.self, from: data),
           let array = decoded.arrayValue {
            return array.compactMap { item in
                guard let object = item.objectValue,
                      let name = object["tool_name"]?.flattenedString.nonEmpty ?? object["name"]?.flattenedString.nonEmpty else {
                    return nil
                }
                let args = HypeMCPToolBridge.stringArguments(from: object["arguments"])
                return OllamaToolCall(function: OllamaToolCallFunction(name: name, arguments: args))
            }
        }

        guard let name = arguments["tool_name"]?.flattenedString.nonEmpty else { return [] }
        let args = HypeMCPToolBridge.parseArgumentsJSON(arguments["arguments_json"]?.flattenedString ?? "{}")
        return [OllamaToolCall(function: OllamaToolCallFunction(name: name, arguments: args))]
    }

    private func transactionSummary(_ transaction: AIEditTransaction) -> Any {
        [
            "transactionId": transaction.id.uuidString,
            "state": transaction.state.rawValue,
            "operationCount": transaction.operations.count,
            "diagnostics": transaction.diagnostics,
            "operations": transaction.operations.map { operation in
                [
                    "toolName": operation.toolName,
                    "result": operation.result,
                    "phase": operation.phase.rawValue,
                    "delta": [
                        "createdPartIds": operation.delta.createdPartIds.map(\.uuidString),
                        "deletedPartIds": operation.delta.deletedPartIds.map(\.uuidString),
                        "changedPartIds": operation.delta.changedPartIds.map(\.uuidString),
                        "createdCardIds": operation.delta.createdCardIds.map(\.uuidString),
                        "changedCardIds": operation.delta.changedCardIds.map(\.uuidString),
                        "stackChanged": operation.delta.stackChanged,
                    ] as [String: Any],
                ] as [String: Any]
            },
        ] as [String: Any]
    }

    private func allowMCPMutations() -> Bool {
        if UserDefaults.standard.object(forKey: HypeMCPConfiguration.allowMutationsKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: HypeMCPConfiguration.allowMutationsKey)
    }

    private func mcpArguments(from arguments: [String: Any]) -> [String: HypeMCPJSONValue] {
        arguments.mapValues(HypeMCPJSONValue.init(any:))
    }

    @MainActor
    private func callTool(name: String, arguments: [String: String]) async -> (text: String, isError: Bool) {
        guard let binding = HypeDocumentMutationCoordinator.shared.activeDocumentBinding else {
            return ("No active Hype document. Open or focus a stack window before calling Hype debug tools.", true)
        }

        let current = binding.wrappedValue.document
        let currentCardId = HypeDocumentMutationCoordinator.shared.activeCardId
            ?? current.sortedCards.first?.id
            ?? UUID()

        let executor = makeExecutor(for: current)
        var updated = current
        let result = await executor.execute(
            toolName: name,
            arguments: arguments,
            document: &updated,
            currentCardId: currentCardId
        )

        if let createdId = createdCardId(from: result) {
            HypeDocumentMutationCoordinator.shared.activeCardId = createdId
        } else if let destination = navigationDestination(from: result),
                  let resolved = resolveCard(destination: destination, document: updated, currentCardId: currentCardId) {
            HypeDocumentMutationCoordinator.shared.activeCardId = resolved
        }

        HypeDocumentMutationCoordinator.shared.applyDocument(
            updated,
            to: binding,
            undoManager: nil,
            actionName: "Debug Tool: \(name)"
        )
        return (result, result.hasPrefix("Unknown tool:"))
    }

    @MainActor
    private func makeExecutor(for document: HypeDocument) -> HypeToolExecutor {
        let webAssetClient: (any WebAssetSearchClient)? = document.stack.webAssetsAllowed
            ? WebAssetSearchClientFactory.make(
                provider: WebAssetSearchProvider(rawValue: UserDefaults.standard.string(forKey: "hype.webAssets.provider") ?? "openverse") ?? .openverse
            )
            : nil
        let webAssetPipeline: WebAssetImportPipeline? = document.stack.webAssetsAllowed ? WebAssetImportPipeline() : nil
        let imageGenerationClient: (any HypeImageGenerating)? = try? HypeAIConfiguration.makeImageGenerationClient()
        let meshyClientFactory: (@Sendable () throws -> MeshyClient)? = {
            @Sendable in
            let key = try KeychainStore.getSecret(account: KeychainStore.meshyAPIKeyAccount)
            return MeshyAIClient(apiKey: key)
        }

        return HypeToolExecutor(
            webAssetSession: document.stack.webAssetsAllowed ? webAssetSession : nil,
            webAssetClient: webAssetClient,
            webAssetPipeline: webAssetPipeline,
            imageGenerationClient: imageGenerationClient,
            meshyClientFactory: meshyClientFactory
        )
    }

    private func stringifyArguments(_ arguments: [String: Any]) -> [String: String] {
        arguments.reduce(into: [:]) { result, pair in
            switch pair.value {
            case let value as String:
                result[pair.key] = value
            case let value as NSNumber:
                result[pair.key] = value.stringValue
            case _ as NSNull:
                result[pair.key] = ""
            default:
                if JSONSerialization.isValidJSONObject(pair.value),
                   let data = try? JSONSerialization.data(withJSONObject: pair.value),
                   let json = String(data: data, encoding: .utf8) {
                    result[pair.key] = json
                } else {
                    result[pair.key] = String(describing: pair.value)
                }
            }
        }
    }

    private func createdCardId(from result: String) -> UUID? {
        guard result.hasPrefix("CREATED_CARD:") else { return nil }
        return UUID(uuidString: String(result.dropFirst("CREATED_CARD:".count)))
    }

    private func navigationDestination(from result: String) -> String? {
        guard result.hasPrefix("NAVIGATE:") else { return nil }
        return String(result.dropFirst("NAVIGATE:".count))
    }

    private func resolveCard(destination: String, document: HypeDocument, currentCardId: UUID) -> UUID? {
        switch destination.lowercased() {
        case "next":
            return CardNavigator.navigate(direction: .next, currentCardId: currentCardId, document: document)
        case "previous", "prev":
            return CardNavigator.navigate(direction: .previous, currentCardId: currentCardId, document: document)
        case "first":
            return document.sortedCards.first?.id
        case "last":
            return document.sortedCards.last?.id
        default:
            if let number = Int(destination), number > 0, number <= document.sortedCards.count {
                return document.sortedCards[number - 1].id
            }
            return document.cards.first { $0.name.caseInsensitiveCompare(destination) == .orderedSame }?.id
        }
    }

    private func jsonRPCResult(id: Any?, result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result]
    }

    private nonisolated func jsonRPCError(id: Any?, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }
}

private extension HypeMCPJSONValue {
    var jsonObject: Any {
        switch self {
        case .null:
            return NSNull()
        case .bool(let value):
            return value
        case .number(let value):
            return value
        case .string(let value):
            return value
        case .array(let values):
            return values.map(\.jsonObject)
        case .object(let values):
            return values.mapValues(\.jsonObject)
        }
    }
}

private func debugJSONText(_ value: Any) -> String {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
        return String(describing: value)
    }
    return text
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

private enum DebugServerError: LocalizedError {
    case posix(String, Int32)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .posix(let operation, let code):
            return "\(operation) failed: \(String(cString: strerror(code)))"
        case .message(let message):
            return message
        }
    }
}
