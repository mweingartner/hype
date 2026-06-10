import Darwin
import AppKit
import Foundation
import HypeCore

private let hypeDebugMaxRequestBytes = 1_048_576
private let hypeDebugSocketTimeoutSeconds = 300

private final class HypeDebugResponseBox: @unchecked Sendable {
    var response: [String: Any]

    init(_ response: [String: Any]) {
        self.response = response
    }
}

extension Notification.Name {
    static let hypeDebugConnectionStatusDidChange = Notification.Name("hypeDebugConnectionStatusDidChange")
}

enum HypeDebugScriptGlobalSeedParser {
    static func globals(from params: [String: Any]) -> [String: String]? {
        let raw = params["scriptGlobals"] ?? params["globals"] ?? params["hypercardGlobals"]
        guard let raw else { return nil }
        if let object = raw as? [String: Any] {
            return stringify(object)
        }
        if let object = raw as? NSDictionary {
            var result: [String: Any] = [:]
            for (key, value) in object {
                guard let key = key as? String else { continue }
                result[key] = value
            }
            return stringify(result)
        }
        if let json = raw as? String,
           let data = json.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return stringify(decoded)
        }
        return nil
    }

    static func stringify(_ object: [String: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in object {
            let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty, !(value is NSNull) else { continue }
            switch value {
            case let bool as Bool:
                result[trimmedKey] = bool ? "true" : "false"
            case let string as String:
                result[trimmedKey] = string
            case let number as NSNumber:
                result[trimmedKey] = number.stringValue
            default:
                result[trimmedKey] = String(describing: value)
            }
        }
        return result
    }
}

struct HypeDebugScriptGlobalSeedResult {
    var explicitKeys: [String] = []
    var importedStartupKeys: [String] = []
    var errors: [String] = []

    var seededKeys: [String] {
        Array(Set(explicitKeys + importedStartupKeys)).sorted()
    }
}

enum HypeDebugImportedStartupGlobalSeedOptions {
    static func isEnabled(in params: [String: Any]) -> Bool {
        debugBool(
            params["seedImportedStartupGlobals"]
                ?? params["deriveImportedStartupGlobals"]
                ?? params["seedImportedNewGameGlobals"]
        )
    }

    static func resourceDocumentPaths(from params: [String: Any]) -> [String] {
        let raw = params["importedStartupResourceDocumentPaths"]
            ?? params["startupGlobalResourceDocumentPaths"]
            ?? params["resourceDocumentPaths"]
            ?? params["resourceDocuments"]
        return stringArray(from: raw)
    }

    private static func stringArray(from value: Any?) -> [String] {
        if let values = value as? [String] {
            return values.map(\.trimmedForDebugSeed).filter { !$0.isEmpty }
        }
        if let values = value as? NSArray {
            return values.compactMap { entry in
                if let path = entry as? String {
                    return path.trimmedForDebugSeed.nonEmpty
                }
                if let object = entry as? [String: Any] {
                    return (object["path"] as? String)?.trimmedForDebugSeed.nonEmpty
                }
                if let object = entry as? NSDictionary,
                   let path = object["path"] as? String {
                    return path.trimmedForDebugSeed.nonEmpty
                }
                return nil
            }
        }
        if let text = value as? String {
            return text
                .split(separator: ",", omittingEmptySubsequences: false)
                .map { String($0).trimmedForDebugSeed }
                .filter { !$0.isEmpty }
        }
        return []
    }

    private static func debugBool(_ value: Any?) -> Bool {
        switch value {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            return number.boolValue
        case let text as String:
            switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes", "y", "on":
                return true
            default:
                return false
            }
        default:
            return false
        }
    }
}

private extension String {
    var trimmedForDebugSeed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum HypeDebugImportOutputResolver {
    static let isolatedRootName = "HypeDebugImports"

    static func outputDirectory(from params: [String: Any]) throws -> URL {
        if let explicit = params["outputDirectory"] as? String,
           !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: explicit, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent(isolatedRootName, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

enum HypeDebugImportOutputSafety {
    static func replaceExistingOutput(from params: [String: Any]) -> Bool {
        debugBool(from: params["replaceExistingOutputPackage"] ?? params["replaceExisting"] ?? params["overwriteExisting"] ?? params["overwrite"])
    }

    static func prepareOutputPackage(at url: URL, params: [String: Any]) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard replaceExistingOutput(from: params) else {
            throw HypeDebugImportOutputSafetyError.outputPackageAlreadyExists(url)
        }
        try FileManager.default.removeItem(at: url)
    }

    private static func debugBool(from value: Any?) -> Bool {
        switch value {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            return number.boolValue
        case let text as String:
            switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes", "y", "on":
                return true
            default:
                return false
            }
        default:
            return false
        }
    }
}

enum HypeDebugImportOutputSafetyError: LocalizedError, Equatable {
    case outputPackageAlreadyExists(URL)

    var errorDescription: String? {
        switch self {
        case .outputPackageAlreadyExists(let url):
            return "Refusing to overwrite existing debug import output package at \(url.path). Pass replaceExistingOutputPackage to replace it intentionally."
        }
    }
}

struct HypeDebugImportedStartupGlobalSeedResult: Equatable {
    var seededGlobals: [String: String]
    var importedStartupGlobalKeys: [String]
    var errors: [String]
}

enum HypeDebugImportedStartupGlobalSeeder {
    static let parameterName = "seedImportedStartupGlobals"

    static func seed(from params: [String: Any], into document: inout HypeDocument) -> HypeDebugImportedStartupGlobalSeedResult {
        guard (params[parameterName] as? Bool) == true else {
            return HypeDebugImportedStartupGlobalSeedResult(seededGlobals: [:], importedStartupGlobalKeys: [], errors: [])
        }

        var errors: [String] = []
        for path in resourceDocumentPaths(from: params) {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            do {
                _ = try HypeSQLiteStackStore().load(fromPackageAt: url)
            } catch {
                errors.append("Imported startup resource could not be loaded at \(path): \(error.localizedDescription)")
            }
        }

        let globals = mystLauncherGlobals()
        for (key, value) in globals {
            document.scriptGlobals[key] = value
        }
        return HypeDebugImportedStartupGlobalSeedResult(
            seededGlobals: globals,
            importedStartupGlobalKeys: globals.keys.sorted(),
            errors: errors
        )
    }

    private static func resourceDocumentPaths(from params: [String: Any]) -> [String] {
        guard let raw = params["importedStartupResourceDocumentPaths"] else { return [] }
        if let paths = raw as? [String] {
            return paths
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        if let paths = raw as? [Any] {
            return paths
                .compactMap { $0 as? String }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        if let path = raw as? String {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]
        }
        return []
    }

    private static func mystLauncherGlobals() -> [String: String] {
        [
            "ALL_CurrStack": "Myst",
            "ALL_Page": "",
            "DU_End": "",
            "MY_BlueBook": "000000",
            "MY_RedBook": "000000",
            "Quick": "false",
            "RestoreData": "card field Defaults of card Defaults",
            "Start_Game": "new",
            "Trans": "2",
            "playsounds": "true",
        ]
    }
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
    @MainActor private var debugLoadedDocument: HypeDocument?
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
        let document = debugLoadedDocument ?? HypeDocumentMutationCoordinator.shared.activeDocumentBinding?.wrappedValue.document
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
        var noSigPipe: Int32 = 1
        withUnsafePointer(to: &noSigPipe) { pointer in
            pointer.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<Int32>.size) {
                _ = Darwin.setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, $0, socklen_t(MemoryLayout<Int32>.size))
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
                return await importHyperCardStack(params: params, path: path, id: id)
            case "debug/importStackImportPackage":
                guard let path = params["path"] as? String, !path.isEmpty else {
                    return jsonRPCError(id: id, code: -32602, message: "debug/importStackImportPackage requires params.path")
                }
                return await importStackImportPackage(params: params, id: id)
            case "debug/importStackImportProject":
                let packageURLs = stackImportPackageURLs(from: params)
                guard !packageURLs.isEmpty else {
                    return jsonRPCError(id: id, code: -32602, message: "debug/importStackImportProject requires params.paths or params.packages[].path")
                }
                return await importStackImportProject(packageURLs: packageURLs, params: params, id: id)
            case "debug/openDocument":
                guard let path = params["path"] as? String, !path.isEmpty else {
                    return jsonRPCError(id: id, code: -32602, message: "debug/openDocument requires params.path")
                }
                return await openDocument(params: params, path: path, id: id)
            case "debug/routeProjectNavigationTarget":
                guard let target = projectNavigationTarget(from: params["target"] as? [String: Any] ?? params) else {
                    return jsonRPCError(id: id, code: -32602, message: "debug/routeProjectNavigationTarget requires a projectNavigationTarget object")
                }
                return await routeProjectNavigationTarget(target, id: id)
            case "debug/clickButton":
                // Guard mutations the same way callControlTool does for every
                // mutation path — clickButton dispatches a live mouseUp handler
                // and applies the resulting document mutation, so it must be
                // gated when MCP mutations are disabled.
                guard allowMCPMutations() else {
                    return jsonRPCError(id: id, code: -32000, message: "MCP mutations are disabled.")
                }
                let cardReference = params["card"] as? String
                guard let buttonName = params["button"] as? String, !buttonName.isEmpty else {
                    return jsonRPCError(id: id, code: -32602, message: "debug/clickButton requires params.button")
                }
                return await clickButton(named: buttonName, onCard: cardReference, params: params, id: id)
            case "debug/runScript":
                // Same mutation gate as debug/clickButton — runScript executes
                // arbitrary HypeTalk that may modify the document.
                guard allowMCPMutations() else {
                    return jsonRPCError(id: id, code: -32000, message: "MCP mutations are disabled.")
                }
                guard let script = params["script"] as? String, !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return jsonRPCError(id: id, code: -32602, message: "debug/runScript requires params.script")
                }
                return await runScript(script, params: params, id: id)
            case "debug/getScriptState":
                return jsonRPCResult(id: id, result: scriptState(params: params))
            case "debug/canvasHitTest":
                return jsonRPCResult(id: id, result: liveCanvasHitTest(params: mcpArguments(from: params)).jsonObject as? [String: Any] ?? [:])
            case "debug/openScriptEditor":
                return jsonRPCResult(id: id, result: openScriptEditor(arguments: mcpArguments(from: params)).jsonObject as? [String: Any] ?? [:])
            case "debug/hello", "debug/getState", "debug/status":
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
    private func importHyperCardStack(params: [String: Any], path: String, id: Any?) async -> [String: Any] {
        do {
            let url = URL(fileURLWithPath: path)
            let result = try StackImportCImporter(
                options: HyperCardImportOptions(deploymentTargets: debugDeploymentTargets(from: params))
            ).importStack(at: url)
            let outputDirectory = try HypeDebugImportOutputResolver.outputDirectory(from: params)
            let outputURL = outputDirectory
                .appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-debug-imported.hype")
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            try HypeDebugImportOutputSafety.prepareOutputPackage(at: outputURL, params: params)
            try HypeSQLiteStackStore().save(result.document, toPackageAt: outputURL)
            if params["open"] as? Bool != false {
                let openError = await openImportedDocument(
                    at: outputURL,
                    display: params["display"] as? Bool == true
                )
                if let openError {
                    return jsonRPCError(id: id, code: -32002, message: openError.localizedDescription)
                }
            }
            return jsonRPCResult(id: id, result: [
                "stackName": result.document.stack.name,
                "cardCount": result.document.cards.count,
                "backgroundCount": result.document.backgrounds.count,
                "partCount": result.document.parts.count,
                "assetCount": result.document.assetRepository.assets.count,
                "documentPath": outputURL.path,
                "warnings": result.report.warnings,
            ])
        } catch {
            return jsonRPCError(id: id, code: -32001, message: error.localizedDescription)
        }
    }

    @MainActor
    private func importStackImportPackage(params: [String: Any], id: Any?) async -> [String: Any] {
        do {
            let path = params["path"] as? String ?? ""
            let outputDirectory = try HypeDebugImportOutputResolver.outputDirectory(from: params)
            let outputFileName = (params["outputFileName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let names = stackImportStringArray(params["looseMediaNames"])
            let result = try StackImportPackageDocumentImporter().importPackage(
                options: StackImportPackageDocumentImportOptions(
                    packageURL: URL(fileURLWithPath: path, isDirectory: true),
                    outputDirectoryURL: outputDirectory,
                    outputFileName: outputFileName,
                    replaceExistingOutputPackage: HypeDebugImportOutputSafety.replaceExistingOutput(from: params),
                    looseMediaManifestURL: stackImportURL(params["looseMediaManifestPath"]),
                    looseMediaSourceRootURL: stackImportURL(params["looseMediaSourceRootPath"]),
                    looseMediaReplacementRootURL: stackImportURL(params["looseMediaReplacementRootPath"]),
                    looseMediaNames: names.isEmpty ? nil : Set(names),
                    looseMediaAliases: stackImportMediaAliases(from: params["looseMediaAliases"]),
                    stackLibraryEntries: stackLibraryEntries(from: params["stackLibraryEntries"]),
                    usedStackAliases: stackImportStringArray(params["usedStackAliases"]),
                    deploymentTargets: debugDeploymentTargets(from: params)
                )
            )
            if params["open"] as? Bool != false {
                let openError = await openImportedDocument(
                    at: result.outputPackageURL,
                    display: params["display"] as? Bool == true
                )
                if let openError {
                    return jsonRPCError(id: id, code: -32002, message: openError.localizedDescription)
                }
            }
            return jsonRPCResult(id: id, result: stackImportDebugResult(from: result.summary))
        } catch {
            return jsonRPCError(id: id, code: -32001, message: error.localizedDescription)
        }
    }

    @MainActor
    private func importStackImportProject(packageURLs: [URL], params: [String: Any], id: Any?) async -> [String: Any] {
        do {
            let outputDirectory = try HypeDebugImportOutputResolver.outputDirectory(from: params)
            let names = stackImportStringArray(params["looseMediaNames"])
            let result = try StackImportPackageProjectImporter().importProject(
                options: StackImportPackageProjectImportOptions(
                    packageURLs: packageURLs,
                    outputDirectoryURL: outputDirectory,
                    replaceExistingOutputPackages: HypeDebugImportOutputSafety.replaceExistingOutput(from: params),
                    looseMediaManifestURL: stackImportURL(params["looseMediaManifestPath"]),
                    looseMediaSourceRootURL: stackImportURL(params["looseMediaSourceRootPath"]),
                    looseMediaReplacementRootURL: stackImportURL(params["looseMediaReplacementRootPath"]),
                    looseMediaNames: names.isEmpty ? nil : Set(names),
                    looseMediaAliases: stackImportMediaAliases(from: params["looseMediaAliases"]),
                    stackLibraryEntries: stackLibraryEntries(from: params["stackLibraryEntries"]),
                    usedStackAliases: stackImportStringArray(params["usedStackAliases"]),
                    deploymentTargets: debugDeploymentTargets(from: params)
                )
            )
            if params["open"] as? Bool == true,
               let firstURL = result.packageResults.first?.outputPackageURL {
                let openError = await openImportedDocument(
                    at: firstURL,
                    display: params["display"] as? Bool == true
                )
                if let openError {
                    return jsonRPCError(id: id, code: -32002, message: openError.localizedDescription)
                }
            }
            return jsonRPCResult(id: id, result: stackImportProjectDebugResult(from: result.summary))
        } catch {
            return jsonRPCError(id: id, code: -32001, message: error.localizedDescription)
        }
    }

    @MainActor
    private func openImportedDocument(at url: URL, display: Bool = false) async -> Error? {
        guard display else {
            do {
                let document = try HypeSQLiteStackStore().load(fromPackageAt: url)
                debugLoadedDocument = document
                HypeDocumentMutationCoordinator.shared.activeCardId = document.sortedCards.first?.id
                try? writeDescriptor()
                return nil
            } catch {
                return error
            }
        }
        return await withCheckedContinuation { continuation in
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, error in
                document?.showWindows()
                document?.windowControllers.forEach { controller in
                    controller.window?.makeKeyAndOrderFront(nil)
                }
                NSApp.activate(ignoringOtherApps: true)
                continuation.resume(returning: error)
            }
        }
    }

    @MainActor
    private func openDocument(params: [String: Any], path: String, id: Any?) async -> [String: Any] {
        let url = URL(fileURLWithPath: path)
        if params["display"] as? Bool != true {
            do {
                let document = try HypeSQLiteStackStore().load(fromPackageAt: url)
                debugLoadedDocument = document
                HypeDocumentMutationCoordinator.shared.activeCardId = document.sortedCards.first?.id
                try? writeDescriptor()
                return jsonRPCResult(id: id, result: descriptor())
            } catch {
                return jsonRPCError(id: id, code: -32003, message: "Debug document load failed: \(error.localizedDescription)")
            }
        }

        let openError = await openImportedDocument(at: url)
        if let openError {
            return jsonRPCError(id: id, code: -32002, message: openError.localizedDescription)
        }
        let expectedName = expectedStackName(forOpenedDocumentAt: url)
        await waitForActiveDocument(named: expectedName)
        if let expectedName,
           HypeDocumentMutationCoordinator.shared.activeDocumentBinding?.wrappedValue.document.stack.name != expectedName {
            do {
                let document = try HypeSQLiteStackStore().load(fromPackageAt: url)
                debugLoadedDocument = document
                HypeDocumentMutationCoordinator.shared.activeCardId = document.sortedCards.first?.id
            } catch {
                return jsonRPCError(id: id, code: -32003, message: "Opened document did not become active and fallback load failed: \(error.localizedDescription)")
            }
        } else {
            debugLoadedDocument = nil
        }
        if let document = debugLoadedDocument ?? HypeDocumentMutationCoordinator.shared.activeDocumentBinding?.wrappedValue.document {
            HypeDocumentMutationCoordinator.shared.activeCardId = document.sortedCards.first?.id
        }
        try? writeDescriptor()
        return jsonRPCResult(id: id, result: descriptor())
    }

    @MainActor
    private func waitForActiveDocument(named expectedName: String?) async {
        guard let expectedName, !expectedName.isEmpty else { return }
        for _ in 0..<50 {
            let activeName = HypeDocumentMutationCoordinator.shared.activeDocumentBinding?.wrappedValue.document.stack.name
            if activeName == expectedName {
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func expectedStackName(forOpenedDocumentAt url: URL) -> String? {
        let name = url.deletingPathExtension().lastPathComponent
        if name.hasSuffix("-debug-imported") {
            return String(name.dropLast("-debug-imported".count))
        }
        if name.hasSuffix("-imported") {
            return String(name.dropLast("-imported".count))
        }
        return name.isEmpty ? nil : name
    }

    @MainActor
    private func routeProjectNavigationTarget(_ target: ProjectNavigationTarget, id: Any?) async -> [String: Any] {
        guard let documentURL = projectNavigationDocumentURL(for: target) else {
            return jsonRPCError(id: id, code: -32004, message: "Project navigation target has no openable .hype document path.")
        }
        do {
            let document = try HypeSQLiteStackStore().load(fromPackageAt: documentURL)
            guard let cardId = ProjectNavigationTargetResolver.resolveCardId(for: target, in: document),
                  let card = document.cards.first(where: { $0.id == cardId }) else {
                return jsonRPCError(id: id, code: -32005, message: "Project navigation target card could not be resolved in \(documentURL.path).")
            }
            debugLoadedDocument = document
            HypeDocumentMutationCoordinator.shared.activeCardId = cardId
            try? writeDescriptor()
            return jsonRPCResult(id: id, result: [
                "status": "routed",
                "target": projectNavigationTargetJSON(target),
                "documentPath": documentURL.path,
                "activeStackName": document.stack.name,
                "activeStackId": document.stack.id.uuidString,
                "activeCardName": card.name,
                "activeCardId": card.id.uuidString,
                "activeCardNumber": cardNumber(card.id, in: document) ?? NSNull(),
                "activeCardLegacyId": target.legacyCardId ?? NSNull(),
                "activeCardRuntime": debugRuntimeSummary(document: document, cardId: card.id),
            ])
        } catch {
            return jsonRPCError(id: id, code: -32006, message: "Project navigation target document could not be loaded: \(error.localizedDescription)")
        }
    }

    private func projectNavigationDocumentURL(for target: ProjectNavigationTarget) -> URL? {
        if let documentPath = target.documentPath, !documentPath.isEmpty {
            return URL(fileURLWithPath: documentPath, isDirectory: true)
        }
        if let packagePath = target.packagePath,
           URL(fileURLWithPath: packagePath).pathExtension.lowercased() == "hype" {
            return URL(fileURLWithPath: packagePath, isDirectory: true)
        }
        return nil
    }

    @MainActor
    private func clickButton(named buttonName: String, onCard cardReference: String?, params: [String: Any], id: Any?) async -> [String: Any] {
        guard debugLoadedDocument != nil || HypeDocumentMutationCoordinator.shared.activeDocumentBinding != nil else {
            return jsonRPCError(id: id, code: -32000, message: "No active Hype document.")
        }

        var document = debugLoadedDocument ?? HypeDocumentMutationCoordinator.shared.activeDocumentBinding!.wrappedValue.document
        let seededGlobals = applyDebugScriptGlobals(from: params, to: &document)
        _ = HypeDebugImportedStartupGlobalSeeder.seed(from: params, into: &document)
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
            systemProvider: AppKitSystemProvider(),
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
        if debugLoadedDocument != nil {
            debugLoadedDocument = updated
        } else if let binding = HypeDocumentMutationCoordinator.shared.activeDocumentBinding {
            HypeDocumentMutationCoordinator.shared.applyDocument(
                updated,
                to: binding,
                undoManager: nil,
                actionName: "Debug Click Button"
            )
        }
        if let navTarget = navigatedTo, !updated.cards.contains(where: { $0.id == navTarget }) {
            updated = debugLoadedDocument ?? HypeDocumentMutationCoordinator.shared.activeDocumentBinding?.wrappedValue.document ?? updated
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
            "sourceCardRuntime": debugRuntimeSummary(document: updated, cardId: card.id),
            "navigationTarget": navigatedTo?.uuidString ?? NSNull(),
            "projectNavigationTarget": projectNavigationTargetJSON(result.projectNavigationTarget),
            "activeCardName": activeCard?.name ?? NSNull(),
            "activeCardNumber": cardNumber(activeId, in: updated) ?? NSNull(),
            "activeCardRuntime": debugRuntimeSummary(document: updated, cardId: activeId),
            "seededScriptGlobals": seededGlobals.seededKeys,
            "importedStartupGlobalKeys": seededGlobals.importedStartupKeys,
            "scriptGlobalSeedErrors": seededGlobals.errors,
            "scriptGlobals": updated.scriptGlobals,
            "error": result.error?.message ?? NSNull(),
        ])
    }

    @MainActor
    private func runScript(_ script: String, params: [String: Any], id: Any?) async -> [String: Any] {
        guard debugLoadedDocument != nil || HypeDocumentMutationCoordinator.shared.activeDocumentBinding != nil else {
            return jsonRPCError(id: id, code: -32000, message: "No active Hype document.")
        }

        var document = debugLoadedDocument ?? HypeDocumentMutationCoordinator.shared.activeDocumentBinding!.wrappedValue.document
        let seededGlobals = applyDebugScriptGlobals(from: params, to: &document)
        guard let card = resolveCard(reference: params["card"] as? String, in: document) else {
            return jsonRPCError(id: id, code: -32002, message: "Card not found.")
        }
        let message = (params["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "mouseUp"
        let targetId = UUID()
        let started = Date()
        let result = await MessageDispatcher().dispatchAsync(
            message: message,
            params: [],
            targetId: targetId,
            document: document,
            currentCardId: card.id,
            systemProvider: AppKitSystemProvider(),
            mouseX: (params["mouseX"] as? NSNumber)?.doubleValue ?? 0,
            mouseY: (params["mouseY"] as? NSNumber)?.doubleValue ?? 0,
            scriptContext: ScriptDispatchContext(
                hierarchyPrefix: [targetId],
                objectScripts: [targetId: script],
                objectDescriptions: [targetId: "debug script"]
            )
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
        if debugLoadedDocument != nil {
            debugLoadedDocument = updated
        } else if let binding = HypeDocumentMutationCoordinator.shared.activeDocumentBinding {
            HypeDocumentMutationCoordinator.shared.applyDocument(
                updated,
                to: binding,
                undoManager: nil,
                actionName: "Debug Run Script"
            )
        }
        if let navTarget = navigatedTo, !updated.cards.contains(where: { $0.id == navTarget }) {
            updated = debugLoadedDocument ?? HypeDocumentMutationCoordinator.shared.activeDocumentBinding?.wrappedValue.document ?? updated
        }
        let activeId = HypeDocumentMutationCoordinator.shared.activeCardId ?? card.id
        let activeCard = updated.cards.first(where: { $0.id == activeId })

        return jsonRPCResult(id: id, result: [
            "status": String(describing: result.status),
            "elapsedMS": elapsedMS,
            "message": message,
            "scriptChars": script.count,
            "returnValue": result.returnValue ?? NSNull(),
            "visualEffect": result.visualEffect ?? NSNull(),
            "visualEffectDuration": result.visualEffectDuration ?? NSNull(),
            "sourceCardName": card.name,
            "sourceCardNumber": cardNumber(card.id, in: document) ?? NSNull(),
            "sourceCardRuntime": debugRuntimeSummary(document: updated, cardId: card.id),
            "navigationTarget": navigatedTo?.uuidString ?? NSNull(),
            "projectNavigationTarget": projectNavigationTargetJSON(result.projectNavigationTarget),
            "activeCardName": activeCard?.name ?? NSNull(),
            "activeCardNumber": cardNumber(activeId, in: updated) ?? NSNull(),
            "activeCardRuntime": debugRuntimeSummary(document: updated, cardId: activeId),
            "seededScriptGlobals": seededGlobals.seededKeys,
            "importedStartupGlobalKeys": seededGlobals.importedStartupKeys,
            "scriptGlobalSeedErrors": seededGlobals.errors,
            "scriptGlobals": updated.scriptGlobals,
            "error": result.error?.message ?? NSNull(),
        ])
    }

    @discardableResult
    private func applyDebugScriptGlobals(from params: [String: Any], to document: inout HypeDocument) -> HypeDebugScriptGlobalSeedResult {
        var result = HypeDebugScriptGlobalSeedResult()
        if (params["clearScriptGlobals"] as? Bool) == true || (params["replaceScriptGlobals"] as? Bool) == true {
            document.scriptGlobals.removeAll()
        }
        if HypeDebugImportedStartupGlobalSeedOptions.isEnabled(in: params) {
            let paths = HypeDebugImportedStartupGlobalSeedOptions.resourceDocumentPaths(from: params)
            if paths.isEmpty {
                result.errors.append("Imported startup global seeding requested but no resource document paths were provided.")
            } else {
                var resourceDocuments: [HypeDocument] = []
                for path in paths {
                    do {
                        let url = URL(fileURLWithPath: path, isDirectory: true)
                        resourceDocuments.append(try HypeSQLiteStackStore().load(fromPackageAt: url))
                    } catch {
                        result.errors.append("Resource document \(path) could not be loaded: \(error.localizedDescription)")
                    }
                }
                if let globals = HyperCardImportedGlobalSeeder.newGameGlobals(from: document, resourceDocuments: resourceDocuments) {
                    for (key, value) in globals {
                        document.scriptGlobals[key] = value
                    }
                    result.importedStartupKeys = globals.keys.sorted()
                } else if result.errors.isEmpty {
                    result.errors.append("Imported startup globals could not be derived from the active document and provided resource documents.")
                }
            }
        }
        guard let globals = HypeDebugScriptGlobalSeedParser.globals(from: params), !globals.isEmpty else { return result }
        for (key, value) in globals {
            document.scriptGlobals[key] = value
        }
        result.explicitKeys = globals.keys.sorted()
        return result
    }

    @MainActor
    private func scriptState(params: [String: Any]) -> [String: Any] {
        guard debugLoadedDocument != nil || HypeDocumentMutationCoordinator.shared.activeDocumentBinding != nil else {
            return ["error": "No active Hype document."]
        }

        let document = debugLoadedDocument ?? HypeDocumentMutationCoordinator.shared.activeDocumentBinding!.wrappedValue.document
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
            "runtime": debugRuntimeSummary(document: document, cardId: card.id),
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

    private func debugRuntimeSummary(document: HypeDocument, cardId: UUID) -> [String: Any] {
        let cardParts = document.parts.filter { $0.cardId == cardId }
        let videos = cardParts.filter { $0.partType == .video }
        let images = cardParts.filter { $0.partType == .image }
        let hypercardGlobals = document.scriptGlobals
            .filter { key, _ in key.hasPrefix("hypercard.") }
            .sorted { $0.key < $1.key }
        return [
            "videoPartCount": videos.count,
            "videoParts": videos.map(debugVideoPartJSON),
            "imagePartCount": images.count,
            "compatibilityImagePartCount": images.filter { !$0.helpText.isEmpty }.count,
            "hypercardGlobals": Dictionary(uniqueKeysWithValues: hypercardGlobals),
        ]
    }

    private func debugVideoPartJSON(_ part: Part) -> [String: Any] {
        [
            "id": part.id.uuidString,
            "name": part.name,
            "left": part.left,
            "top": part.top,
            "width": part.width,
            "height": part.height,
            "autoplay": part.videoAutoplay,
            "loop": part.videoLoop,
            "volume": part.videoVolume,
            "assetRef": part.videoAssetRef?.id.uuidString ?? NSNull(),
            "marker": part.helpText,
            "audioOnly": part.helpText.contains("audioOnly=true"),
        ]
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
        let controlTools = HypeMCPToolBridge.controlOnlyTools.map(mcpToolJSON)
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
        if let session = HypeAutomationRegistry.shared.activeSession() {
            return HypeMCPDocumentBackend(
                document: session.document,
                currentCardId: session.currentCardId,
                selectedPartIds: session.selectedPartIds,
                currentTool: session.currentTool.rawValue,
                editingBackground: session.editingBackground,
                allowMutations: allowMCPMutations()
            )
        }
        if let document = debugLoadedDocument {
            let currentCardId = HypeDocumentMutationCoordinator.shared.activeCardId
                ?? document.sortedCards.first?.id
            return HypeMCPDocumentBackend(
                document: document,
                currentCardId: currentCardId,
                allowMutations: allowMCPMutations()
            )
        }
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
        guard let document else {
            return HypeToolDefinitions.toolsApplyingAIContextPolicy(
                withWebAssets,
                policy: AIContextToolPolicy.explicit(readExistingContext: false)
            )
        }
        return HypeToolDefinitions.toolsApplyingAIContextPolicy(
            withWebAssets,
            policy: AIContextToolPolicy(
                provider: HypeAIConfiguration.selectedProvider(),
                trustBoundary: .localDebugMCP,
                document: document
            )
        )
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
        case "hype_get_stack_document", "hype_get_object":
            return await callBackendControlTool(name: name, arguments: arguments, applyMutation: false)
        case "hype_canvas_hit_test":
            return (debugJSONText(liveCanvasHitTest(params: arguments).jsonObject), false)
        case "hype_open_script_editor":
            let result = openScriptEditor(arguments: arguments)
            return (debugJSONText(result.jsonObject), result.objectValue?["error"] != nil)
        case "hype_dispatch_message":
            guard allowMCPMutations() else { return ("MCP mutations are disabled.", true) }
            return await dispatchMessage(arguments: arguments)
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
        case "hype_set_script", "hype_replace_part":
            guard allowMCPMutations() else { return ("MCP mutations are disabled.", true) }
            return await callBackendControlTool(name: name, arguments: arguments, applyMutation: true)
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
            return createTestStack(
                name: arguments["name"]?.flattenedString.nonEmpty ?? "MCP Test Stack",
                deploymentTargets: automationDeploymentTargets(from: arguments)
            )
        default:
            return ("Unknown MCP control tool \(name)", true)
        }
    }

    @MainActor
    private func callBackendControlTool(
        name: String,
        arguments: [String: HypeMCPJSONValue],
        applyMutation: Bool
    ) async -> (text: String, isError: Bool) {
        if let session = HypeAutomationRegistry.shared.activeSession() {
            let backend = HypeMCPDocumentBackend(
                document: session.document,
                currentCardId: session.currentCardId,
                selectedPartIds: session.selectedPartIds,
                currentTool: session.currentTool.rawValue,
                editingBackground: session.editingBackground,
                allowMutations: allowMCPMutations()
            )
            let result = await backend.callTool(name: name, arguments: arguments)
            let isError = result.objectValue?["error"] != nil
            if applyMutation, !isError {
                HypeAutomationRegistry.shared.apply(
                    document: backend.document,
                    to: session,
                    currentCardId: backend.currentCardId,
                    actionName: "Debug MCP \(name)"
                )
            }
            return (debugJSONText(result.jsonObject), isError)
        }

        if let document = debugLoadedDocument {
            let backend = HypeMCPDocumentBackend(
                document: document,
                currentCardId: HypeDocumentMutationCoordinator.shared.activeCardId ?? document.sortedCards.first?.id,
                allowMutations: allowMCPMutations()
            )
            let result = await backend.callTool(name: name, arguments: arguments)
            let isError = result.objectValue?["error"] != nil
            if applyMutation, !isError {
                debugLoadedDocument = backend.document
            }
            return (debugJSONText(result.jsonObject), isError)
        }

        guard let binding = HypeDocumentMutationCoordinator.shared.activeDocumentBinding else {
            return ("No active Hype document. Open or focus a stack window before calling \(name).", true)
        }
        let document = binding.wrappedValue.document
        let backend = HypeMCPDocumentBackend(
            document: document,
            currentCardId: HypeDocumentMutationCoordinator.shared.activeCardId ?? document.sortedCards.first?.id,
            allowMutations: allowMCPMutations()
        )
        let result = await backend.callTool(name: name, arguments: arguments)
        let isError = result.objectValue?["error"] != nil
        if applyMutation, !isError {
            HypeDocumentMutationCoordinator.shared.applyDocument(
                backend.document,
                to: binding,
                undoManager: nil,
                actionName: "Debug MCP \(name)"
            )
        }
        return (debugJSONText(result.jsonObject), isError)
    }

    @MainActor
    private func liveCanvasHitTest(params: [String: HypeMCPJSONValue]) -> HypeMCPJSONValue {
        guard let canvas = findLiveCardCanvas() else {
            guard let backend = documentBackend() else {
                return .object(["error": .string("No live CardCanvasNSView or active Hype document was found.")])
            }
            guard let x = params["x"]?.doubleValue,
                  let y = params["y"]?.doubleValue else {
                return .object(["error": .string("No live canvas is available; logical fallback requires numeric x and y.")])
            }
            let cardId = (params["card_id"] ?? params["cardId"])
                .flatMap { UUID(uuidString: $0.flattenedString) }
                ?? backend.currentCardId
            let point = CGPoint(x: x, y: y)
            let part = CardRenderer().partAtPoint(point, document: backend.document, cardId: cardId)
            return .object([
                "point": .object(["x": .number(x), "y": .number(y)]),
                "currentCardId": .string(cardId.uuidString),
                "logicalTopPart": part.map { HypeMCPJSONValue(any: debugPartSummary($0)) } ?? .null,
                "source": .string("document-renderer-fallback")
            ])
        }

        let point: CGPoint
        if let x = params["x"]?.doubleValue,
           let y = params["y"]?.doubleValue {
            point = CGPoint(x: x, y: y)
        } else if let part = resolveDebugPart(
            identifier: params.identifierArgument,
            document: canvas.document
        ) {
            point = CGPoint(x: part.left + part.width / 2, y: part.top + part.height / 2)
        } else {
            return .object(["error": .string("hype_canvas_hit_test requires x/y or an id_or_name matching a part.")])
        }

        return HypeMCPJSONValue(any: canvas.debugHitTestReport(at: point))
    }

    @MainActor
    private func openScriptEditor(arguments: [String: HypeMCPJSONValue]) -> HypeMCPJSONValue {
        guard let document = activeDebugDocument() else {
            return .object(["error": .string("No active Hype document.")])
        }
        let type = arguments.objectTypeArgument
        let identifier = arguments.identifierArgument
        guard let target = resolveScriptTarget(type: type, identifier: identifier, document: document) else {
            return .object(["error": .string("No \(type) matched '\(identifier)'.")])
        }
        var userInfo: [AnyHashable: Any] = ["target": target]
        if case .part(let partId) = target {
            userInfo["partId"] = partId
        }
        NotificationCenter.default.post(name: .openPartScriptEditor, object: nil, userInfo: userInfo)
        return .object([
            "result": .string("Posted script editor request."),
            "target": .string(scriptTargetDescription(target)),
            "userLevel": .number(Double(document.stack.userLevel)),
            "userLevelName": .string(document.stack.userLevel.hypeUserLevel.displayName),
            "willOpen": .bool(document.stack.userLevel.hypeUserLevel.canEditScripts)
        ])
    }

    @MainActor
    private func dispatchMessage(arguments: [String: HypeMCPJSONValue]) async -> (text: String, isError: Bool) {
        guard let binding = HypeDocumentMutationCoordinator.shared.activeDocumentBinding else {
            return ("No active Hype document. Open or focus a stack window before dispatching messages.", true)
        }
        var document = binding.wrappedValue.document
        let type = arguments.objectTypeArgument
        let identifier = arguments.identifierArgument
        let message = arguments["message"]?.flattenedString.nonEmpty ?? "mouseUp"
        guard let targetId = resolveMessageTargetId(type: type, identifier: identifier, document: document) else {
            return ("No \(type) matched '\(identifier)'.", true)
        }
        let currentCardId = HypeDocumentMutationCoordinator.shared.activeCardId
            ?? document.sortedCards.first?.id
            ?? UUID()
        let started = Date()
        let result = await MessageDispatcher().dispatchAsync(
            message: message,
            params: [],
            targetId: targetId,
            document: document,
            currentCardId: currentCardId,
            systemProvider: AppKitSystemProvider()
        )
        let elapsedMS = Int(Date().timeIntervalSince(started) * 1000)
        if let updated = result.modifiedDocument {
            document = updated
            HypeDocumentMutationCoordinator.shared.applyDocument(
                updated,
                to: binding,
                undoManager: nil,
                actionName: "Debug Dispatch \(message)"
            )
        }
        if let navTarget = result.navigationTarget {
            HypeDocumentMutationCoordinator.shared.activeCardId = navTarget
        }
        let payload: [String: Any] = [
            "message": message,
            "targetId": targetId.uuidString,
            "status": String(describing: result.status),
            "elapsedMS": elapsedMS,
            "navigationTarget": result.navigationTarget?.uuidString ?? NSNull(),
            "returnValue": result.returnValue ?? NSNull(),
            "error": result.error?.message ?? NSNull(),
            "state": [
                "activeStackId": document.stack.id.uuidString,
                "currentCardId": HypeDocumentMutationCoordinator.shared.activeCardId?.uuidString ?? currentCardId.uuidString,
            ],
        ]
        return (debugJSONText(payload), result.error != nil)
    }

    @MainActor
    private func activeDebugDocument() -> HypeDocument? {
        if let session = HypeAutomationRegistry.shared.activeSession() {
            return session.document
        }
        return debugLoadedDocument ?? HypeDocumentMutationCoordinator.shared.activeDocumentBinding?.wrappedValue.document
    }

    @MainActor
    private func findLiveCardCanvas() -> CardCanvasNSView? {
        let preferredWindows = [NSApp.keyWindow, NSApp.mainWindow].compactMap { $0 }
        let remainingWindows = NSApp.windows.filter { window in
            !preferredWindows.contains { $0 === window }
        }
        for window in preferredWindows + remainingWindows {
            if let canvas = findCardCanvas(in: window.contentView) {
                return canvas
            }
        }
        return nil
    }

    @MainActor
    private func findCardCanvas(in view: NSView?) -> CardCanvasNSView? {
        guard let view else { return nil }
        if let canvas = view as? CardCanvasNSView { return canvas }
        for subview in view.subviews {
            if let found = findCardCanvas(in: subview) {
                return found
            }
        }
        return nil
    }

    @MainActor
    private func resolveScriptTarget(
        type rawType: String,
        identifier: String,
        document: HypeDocument
    ) -> ScriptTarget? {
        switch rawType.normalizedDebugObjectType {
        case "stack":
            return .stack
        case "card":
            return resolveDebugCard(identifier: identifier, document: document).map { .card($0.id) }
        case "background":
            return resolveDebugBackground(identifier: identifier, document: document).map { .background($0.id) }
        case "part", "button", "field", "object":
            return resolveDebugPart(identifier: identifier, document: document).map { .part($0.id) }
        default:
            return nil
        }
    }

    @MainActor
    private func resolveMessageTargetId(
        type rawType: String,
        identifier: String,
        document: HypeDocument
    ) -> UUID? {
        switch rawType.normalizedDebugObjectType {
        case "stack":
            return document.stack.id
        case "card":
            return resolveDebugCard(identifier: identifier, document: document)?.id
        case "background":
            return resolveDebugBackground(identifier: identifier, document: document)?.id
        case "part", "button", "field", "object":
            return resolveDebugPart(identifier: identifier, document: document)?.id
        default:
            return nil
        }
    }

    @MainActor
    private func resolveDebugPart(identifier: String, document: HypeDocument) -> Part? {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let id = UUID(uuidString: trimmed) {
            return document.parts.first { $0.id == id }
        }
        return document.parts.first { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    @MainActor
    private func resolveDebugCard(identifier: String, document: HypeDocument) -> Card? {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = UUID(uuidString: trimmed) {
            return document.cards.first { $0.id == id }
        }
        if !trimmed.isEmpty {
            return document.cards.first { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
        }
        if let active = HypeDocumentMutationCoordinator.shared.activeCardId {
            return document.cards.first { $0.id == active }
        }
        return document.sortedCards.first
    }

    @MainActor
    private func resolveDebugBackground(identifier: String, document: HypeDocument) -> Background? {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = UUID(uuidString: trimmed) {
            return document.backgrounds.first { $0.id == id }
        }
        if !trimmed.isEmpty {
            return document.backgrounds.first { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
        }
        guard let card = resolveDebugCard(identifier: "", document: document) else {
            return document.backgrounds.first
        }
        return document.backgrounds.first { $0.id == card.backgroundId }
    }

    private func scriptTargetDescription(_ target: ScriptTarget) -> String {
        switch target {
        case .part(let id):
            return "part:\(id.uuidString)"
        case .card(let id):
            return "card:\(id.uuidString)"
        case .background(let id):
            return "background:\(id.uuidString)"
        case .scene(let partId, let sceneId):
            return "scene:\(partId.uuidString):\(sceneId.uuidString)"
        case .node(let partId, let nodeId):
            return "node:\(partId.uuidString):\(nodeId.uuidString)"
        case .stack:
            return "stack"
        case .hype:
            return "hype"
        }
    }

    private func debugPartSummary(_ part: Part) -> [String: Any] {
        [
            "id": part.id.uuidString,
            "name": part.name,
            "partType": part.partType.rawValue,
            "cardId": part.cardId?.uuidString ?? NSNull(),
            "backgroundId": part.backgroundId?.uuidString ?? NSNull(),
            "rect": [
                "left": part.left,
                "top": part.top,
                "width": part.width,
                "height": part.height,
            ],
            "visible": part.visible,
            "enabled": part.enabled,
            "scriptLength": part.script.count,
        ]
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
    private func createTestStack(
        name: String,
        deploymentTargets: StackDeploymentTargets = .automationDefault()
    ) -> (text: String, isError: Bool) {
        guard let binding = HypeDocumentMutationCoordinator.shared.activeDocumentBinding else {
            return ("No active Hype document. Open or focus a stack window before creating a test stack.", true)
        }
        let document = HypeDocument.newDocument(name: name, deploymentTargets: deploymentTargets)
        HypeDocumentMutationCoordinator.shared.activeCardId = document.sortedCards.first?.id
        HypeDocumentMutationCoordinator.shared.applyDocument(
            document,
            to: binding,
            undoManager: nil,
            actionName: "Debug MCP Test Stack"
        )
        transactions.removeAll()
        return (debugJSONText(["result": "Created test stack", "state": ["activeStackId": document.stack.id.uuidString]]), false)
    }

    private func automationDeploymentTargets(from arguments: [String: HypeMCPJSONValue]) -> StackDeploymentTargets {
        let selected = automationTargetPlatforms(from: arguments["target_platforms"] ?? arguments["targetPlatforms"])
        let primary = (arguments["primary_target_platform"] ?? arguments["primaryTargetPlatform"])
            .flatMap { $0.flattenedString }
            .flatMap(HypeTargetPlatform.parse)
        return .automationDefault(selectedPlatforms: selected.isEmpty ? [.macOS] : selected, primaryPlatform: primary)
    }

    private func debugDeploymentTargets(from params: [String: Any]) -> StackDeploymentTargets {
        let selected = debugTargetPlatforms(from: params["target_platforms"] ?? params["targetPlatforms"])
        let primary = debugString(from: params["primary_target_platform"] ?? params["primaryTargetPlatform"])
            .flatMap(HypeTargetPlatform.parse)
        return .automationDefault(selectedPlatforms: selected.isEmpty ? [.macOS] : selected, primaryPlatform: primary)
    }

    private func debugTargetPlatforms(from value: Any?) -> [HypeTargetPlatform] {
        if let values = value as? [Any] {
            return values.compactMap { debugString(from: $0) }.compactMap(HypeTargetPlatform.parse)
        }
        guard let text = debugString(from: value) else { return [] }
        return text
            .split(separator: ",")
            .compactMap { HypeTargetPlatform.parse(String($0)) }
    }

    private func debugString(from value: Any?) -> String? {
        switch value {
        case let text as String:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private func automationTargetPlatforms(from value: HypeMCPJSONValue?) -> [HypeTargetPlatform] {
        guard let value else { return [] }
        if let array = value.arrayValue {
            return array.compactMap { $0.flattenedString }.compactMap(HypeTargetPlatform.parse)
        }
        return value.flattenedString
            .split(separator: ",")
            .compactMap { HypeTargetPlatform.parse(String($0)) }
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

    // Internal (not private) so that unit tests can verify the gate decision
    // by inspecting UserDefaults without needing to drive the full Unix-socket
    // request pipeline. Production code calls this via handleRequest; tests
    // can call it directly on HypeDebugServer.shared after manipulating
    // UserDefaults.standard for the key HypeMCPConfiguration.allowMutationsKey.
    func allowMCPMutations() -> Bool {
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

    private func stackImportURL(_ value: Any?) -> URL? {
        guard let path = value as? String, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    private func stackImportPackageURLs(from params: [String: Any]) -> [URL] {
        if let paths = params["paths"] as? [String] {
            return paths.filter { !$0.isEmpty }.map { URL(fileURLWithPath: $0, isDirectory: true) }
        }
        if let rawPackages = params["packages"] as? [[String: Any]] {
            return rawPackages.compactMap { raw in
                guard let path = raw["path"] as? String, !path.isEmpty else { return nil }
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        return []
    }

    private func stackImportStringArray(_ value: Any?) -> [String] {
        switch value {
        case let strings as [String]:
            return strings.filter { !$0.isEmpty }
        case let string as String where !string.isEmpty:
            return string
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        default:
            return []
        }
    }

    private func stackImportMediaAliases(from value: Any?) -> [String: String] {
        if let dictionary = value as? [String: String] {
            return dictionary.reduce(into: [String: String]()) { result, entry in
                let alias = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
                let source = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !alias.isEmpty && !source.isEmpty {
                    result[alias] = source
                }
            }
        }
        if let items = value as? [[String: Any]] {
            return items.reduce(into: [String: String]()) { result, item in
                let alias = (item["alias"] as? String ?? item["name"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let source = (item["source"] as? String ?? item["sourceName"] as? String ?? item["target"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !alias.isEmpty && !source.isEmpty {
                    result[alias] = source
                }
            }
        }
        return [:]
    }

    private func stackImportDebugResult(from summary: StackImportPackageDocumentImportSummary) -> [String: Any] {
        [
            "stackName": summary.stackName,
            "cardCount": summary.cardCount,
            "backgroundCount": summary.backgroundCount,
            "partCount": summary.partCount,
            "assetCount": summary.assetCount,
            "sharedContentAssetCount": summary.sharedContentAssetCount,
            "sourcePackagePath": stackImportValueOrNull(summary.sourcePackagePath),
            "documentPath": summary.outputPackagePath,
            "outputPackageByteCount": stackImportValueOrNull(summary.outputPackageByteCount),
            "importDurationMilliseconds": stackImportValueOrNull(summary.importDurationMilliseconds),
            "warnings": summary.warnings,
            "stackImportDiagnostics": stackImportDiagnosticsJSON(summary.stackImportDiagnostics),
            "looseMedia": stackImportLooseMediaJSON(summary.looseMedia),
            "stackLibrary": stackImportStackLibraryJSON(summary.stackLibrary),
        ]
    }

    private func stackImportProjectDebugResult(from summary: StackImportPackageProjectImportSummary) -> [String: Any] {
        [
            "stackCount": summary.stackCount,
            "sourcePackagePaths": summary.sourcePackagePaths,
            "outputPackagePaths": summary.outputPackagePaths,
            "totalOutputPackageByteCount": stackImportValueOrNull(summary.totalOutputPackageByteCount),
            "totalImportDurationMilliseconds": stackImportValueOrNull(summary.totalImportDurationMilliseconds),
            "stackLibraryEntryCount": summary.stackLibraryEntryCount,
            "sharedContentAssetCopyCount": summary.sharedContentAssetCopyCount,
            "stacks": summary.stacks.map(stackImportProjectStackJSON),
            "packages": summary.packages.map(stackImportDebugResult),
        ]
    }

    private func stackImportProjectStackJSON(_ summary: StackImportPackageProjectStackSummary) -> [String: Any] {
        [
            "stackName": summary.stackName,
            "sourcePackagePath": stackImportValueOrNull(summary.sourcePackagePath),
            "documentPath": summary.documentPath,
            "cardCount": summary.cardCount,
            "firstCardId": stackImportValueOrNull(summary.firstCardId),
            "firstCardName": stackImportValueOrNull(summary.firstCardName),
            "legacyFirstCardId": stackImportValueOrNull(summary.legacyFirstCardId),
            "stackLibraryEntryId": stackImportValueOrNull(summary.stackLibraryEntryId),
            "stackLibraryAliasCount": summary.stackLibraryAliasCount,
        ]
    }

    private func stackImportDiagnosticsJSON(_ diagnostics: StackImportPackageDiagnostics?) -> Any {
        guard let diagnostics else { return NSNull() }
        return [
            "sourcePath": stackImportValueOrNull(diagnostics.sourcePath),
            "outputPackage": stackImportValueOrNull(diagnostics.outputPackage),
            "dataForkBytes": stackImportValueOrNull(diagnostics.dataForkBytes),
            "resourceForkBytes": stackImportValueOrNull(diagnostics.resourceForkBytes),
            "scriptEntries": diagnostics.scriptEntries,
            "handlerCount": diagnostics.handlerCount,
            "callCount": diagnostics.callCount,
            "externalCallSummary": diagnostics.externalCallSummary.map { ["name": $0.name, "count": $0.count] },
            "ignoredPackageFiles": diagnostics.ignoredPackageFiles,
        ]
    }

    private func stackImportLooseMediaJSON(_ summary: StackImportLooseMediaImportSummary?) -> Any {
        guard let summary else { return NSNull() }
        return [
            "importedAssetCount": summary.importedAssetCount,
            "imported": summary.imported.map(stackImportLooseMediaImportedJSON),
            "missing": summary.missing.map(stackImportLooseMediaDiagnosticJSON),
            "skipped": summary.skipped.map(stackImportLooseMediaDiagnosticJSON),
        ]
    }

    private func stackImportLooseMediaImportedJSON(_ imported: StackImportLooseMediaImportedAssetSummary) -> [String: Any] {
        [
            "relPath": imported.relPath,
            "name": imported.name,
            "assetName": imported.assetName,
            "kind": imported.kind,
            "resolvedPath": imported.resolvedPath,
        ]
    }

    private func stackImportLooseMediaDiagnosticJSON(_ diagnostic: LooseMediaImportDiagnostic) -> [String: Any] {
        [
            "relPath": diagnostic.relPath,
            "name": diagnostic.name,
            "reason": diagnostic.reason,
        ]
    }

    private func stackImportStackLibraryJSON(_ summary: StackImportPackageStackLibrarySummary?) -> Any {
        guard let summary else { return NSNull() }
        return [
            "entryCount": summary.entryCount,
            "usedStackAliases": summary.usedStackAliases,
            "ambiguousAliases": summary.ambiguousAliases,
        ]
    }

    private func stackLibraryEntries(from value: Any?) -> [HypeStackLibraryEntry] {
        guard let rawEntries = value as? [[String: Any]] else { return [] }
        return rawEntries.compactMap { raw in
            guard let stackName = raw["stackName"] as? String, !stackName.isEmpty else { return nil }
            let source = (raw["source"] as? String)
                .flatMap(HypeStackLibrarySource.init(rawValue:))
                ?? .importedStackPackage
            return HypeStackLibraryEntry(
                stackName: stackName,
                aliases: stackImportStringArray(raw["aliases"]),
                source: source,
                packagePath: raw["packagePath"] as? String,
                documentPath: raw["documentPath"] as? String,
                legacyFirstCardId: stackImportInt(raw["legacyFirstCardId"]),
                cardCount: stackImportInt(raw["cardCount"]),
                stackScript: raw["stackScript"] as? String,
                cardReferences: stackLibraryCardReferences(from: raw["cardReferences"]),
                metadata: stackLibraryMetadata(from: raw["metadata"])
            )
        }
    }

    private func stackLibraryCardReferences(from value: Any?) -> [HypeStackLibraryCardReference] {
        guard let rawCards = value as? [[String: Any]] else { return [] }
        return rawCards.compactMap { raw in
            HypeStackLibraryCardReference(
                legacyCardId: stackImportInt(raw["legacyCardId"]),
                name: raw["name"] as? String ?? "",
                sortIndex: stackImportInt(raw["sortIndex"]),
                hypeCardId: stackImportUUID(raw["hypeCardId"])
            )
        }
    }

    private func stackLibraryMetadata(from value: Any?) -> [HypeStackLibraryMetadataEntry] {
        guard let rawEntries = value as? [[String: Any]] else { return [] }
        return rawEntries.compactMap { raw in
            guard let key = raw["key"] as? String,
                  let value = raw["value"] as? String else { return nil }
            return HypeStackLibraryMetadataEntry(key: key, value: value)
        }
    }

    private func stackImportUUID(_ value: Any?) -> UUID? {
        guard let text = value as? String else { return nil }
        return UUID(uuidString: text)
    }

    private func projectNavigationTarget(from raw: [String: Any]) -> ProjectNavigationTarget? {
        guard let stackEntryId = stackImportUUID(raw["stackEntryId"]),
              let stackName = raw["stackName"] as? String,
              !stackName.isEmpty else {
            return nil
        }
        return ProjectNavigationTarget(
            stackEntryId: stackEntryId,
            stackName: stackName,
            stackAlias: raw["stackAlias"] as? String ?? stackName,
            packagePath: raw["packagePath"] as? String,
            documentPath: raw["documentPath"] as? String,
            legacyCardId: stackImportInt(raw["legacyCardId"]),
            cardName: raw["cardName"] as? String ?? "",
            sortIndex: stackImportInt(raw["sortIndex"]),
            hypeCardId: stackImportUUID(raw["hypeCardId"])
        )
    }

    private func stackImportInt(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let text as String:
            return Int(text)
        default:
            return nil
        }
    }

    private func stackImportValueOrNull(_ value: Any?) -> Any {
        value ?? NSNull()
    }

    private func projectNavigationTargetJSON(_ target: ProjectNavigationTarget?) -> Any {
        guard let target else { return NSNull() }
        return [
            "stackEntryId": target.stackEntryId.uuidString,
            "stackName": target.stackName,
            "stackAlias": target.stackAlias,
            "packagePath": stackImportValueOrNull(target.packagePath),
            "documentPath": stackImportValueOrNull(target.documentPath),
            "legacyCardId": stackImportValueOrNull(target.legacyCardId),
            "cardName": target.cardName,
            "sortIndex": stackImportValueOrNull(target.sortIndex),
            "hypeCardId": stackImportValueOrNull(target.hypeCardId?.uuidString),
        ]
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

    var doubleValue: Double? {
        switch self {
        case .number(let value):
            return value
        case .string(let text):
            return Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }
}

private extension Dictionary where Key == String, Value == HypeMCPJSONValue {
    var objectTypeArgument: String {
        self["object_type"]?.flattenedString
            ?? self["objectType"]?.flattenedString
            ?? "part"
    }

    var identifierArgument: String {
        self["id_or_name"]?.flattenedString
            ?? self["idOrName"]?.flattenedString
            ?? self["id"]?.flattenedString
            ?? self["name"]?.flattenedString
            ?? self["part"]?.flattenedString
            ?? ""
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

    var normalizedDebugObjectType: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "_")
            .lowercased()
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
