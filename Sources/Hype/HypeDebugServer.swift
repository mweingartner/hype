import Darwin
import Foundation
import HypeCore

private let hypeDebugMaxRequestBytes = 1_048_576

@MainActor
final class HypeDebugServer {
    static let shared = HypeDebugServer()

    private let instanceId = UUID().uuidString
    private let queue = DispatchQueue(label: "hype.debug.server")
    private let webAssetSession = WebAssetSession()
    private let startedAt = Date()
    private var listenSocket: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var socketPath = ""
    private var descriptorPath = ""

    private init() {}

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
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self, fd] in
                self?.acceptPendingConnections(on: fd)
            }
            source.setCancelHandler {
                Darwin.close(fd)
            }
            acceptSource = source
            source.resume()
            HypeLogger.shared.info("Debug bridge listening on \(socketPath)", source: "DebugBridge")
        } catch {
            HypeLogger.shared.error("Failed to start debug bridge: \(error.localizedDescription)", source: "DebugBridge")
            stop()
        }
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        if listenSocket != -1 {
            listenSocket = -1
        }
        if !socketPath.isEmpty {
            try? FileManager.default.removeItem(atPath: socketPath)
            socketPath = ""
        }
        if !descriptorPath.isEmpty {
            try? FileManager.default.removeItem(atPath: descriptorPath)
            descriptorPath = ""
        }
    }

    private func writeDescriptor() throws {
        let data = try JSONSerialization.data(withJSONObject: descriptor(), options: [.prettyPrinted, .sortedKeys])
        let url = URL(fileURLWithPath: descriptorPath)
        let tempURL = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).tmp")
        try data.write(to: tempURL, options: .atomic)
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: tempURL, to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

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
            "startedAt": ISO8601DateFormatter().string(from: startedAt),
            "bundlePath": bundle.bundlePath,
            "bundleIdentifier": bundle.bundleIdentifier ?? NSNull(),
            "appVersion": bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? NSNull(),
            "appBuild": bundle.infoDictionary?["CFBundleVersion"] as? String ?? NSNull(),
            "activeDocumentName": document?.stack.name ?? NSNull(),
            "activeDocumentId": document?.stack.id.uuidString ?? NSNull(),
            "activeDocumentPath": {
                guard let doc = document, let stackName = doc.stack.name else { return NSNull() }
                return URL(fileURLWithPath: stackName).absoluteString as NSString
            }(),
        ]
    }

    private nonisolated func acceptPendingConnections(on listenSocket: Int32) {
        while true {
            let client = Darwin.accept(listenSocket, nil, nil)
            if client < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                return
            }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handle(clientSocket: client)
            }
        }
    }

    private nonisolated func handle(clientSocket: Int32) {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while buffer.count <= hypeDebugMaxRequestBytes {
            let readCount = Darwin.recv(clientSocket, &chunk, chunk.count, 0)
            if readCount <= 0 { break }
            buffer.append(chunk, count: readCount)
            if buffer.contains(0x0A) { break }
        }

        guard buffer.count <= hypeDebugMaxRequestBytes,
              let newline = buffer.firstIndex(of: 0x0A) else {
            write(response: jsonRPCError(id: nil, code: -32600, message: "Invalid Request"), to: clientSocket)
            Darwin.close(clientSocket)
            return
        }

        let requestData = buffer[..<newline]
        Task { @MainActor in
            let responseObject = await self.handleRequest(Data(requestData))
            self.write(response: responseObject, to: clientSocket)
            Darwin.close(clientSocket)
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
            case "debug/hello", "debug/getState":
                try? writeDescriptor()
                return jsonRPCResult(id: id, result: descriptor())
            case "debug/listTools":
                return jsonRPCResult(id: id, result: ["tools": debugTools()])
            case "debug/callTool":
                guard let name = params["name"] as? String else {
                    return jsonRPCError(id: id, code: -32602, message: "debug/callTool requires params.name")
                }
                let arguments = stringifyArguments(params["arguments"] as? [String: Any] ?? [:])
                let result = await callTool(name: name, arguments: arguments)
                return jsonRPCResult(id: id, result: ["text": result.text, "isError": result.isError])
            default:
                return jsonRPCError(id: id, code: -32601, message: "Method not found")
            }
        } catch {
            return jsonRPCError(id: nil, code: -32700, message: "Parse error")
        }
    }

    private func debugTools() -> [[String: Any]] {
        availableTools().map { tool in
            [
                "name": tool.function.name,
                "description": tool.function.description,
                "inputSchema": inputSchema(for: tool),
            ]
        }
    }

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
