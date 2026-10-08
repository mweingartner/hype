#if os(macOS)
import Foundation
import Darwin

/// Blocking child I/O stays on a Dispatch worker, never the main actor or a
/// cooperative executor. Cancellation and the deadline terminate only this proxy.
final class MCPBridgeProcess: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private var cancelled = false
    private var timedOut = false

    func execute(executableURL: URL, input: Data, timeout: TimeInterval) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async { [self] in
                    let deadline = DispatchWorkItem { [weak self] in self?.cancel(timeout: true) }
                    defer { deadline.cancel() }
                    do {
                        let stdin = Pipe(), stdout = Pipe()
                        guard fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
                            throw ScriptSpeechError.unavailable("Cannot configure the local Chatter connection.")
                        }
                        process.executableURL = executableURL
                        process.standardInput = stdin
                        process.standardOutput = stdout
                        process.standardError = FileHandle.nullDevice
                        // This integration is local. Chatter resolves its own
                        // port and private token; don't inherit remote overrides.
                        process.environment = ProcessInfo.processInfo.environment.filter {
                            !["CHATTER_URL", "CHATTER_TOKEN", "CHATTER_TOKEN_FILE", "CHATTER_TLS_SHA256", "CHATTER_DATA_ROOT"].contains($0.key)
                        }
                        try lock.withLock {
                            guard !cancelled else { throw CancellationError() }
                            try process.run()
                        }
                        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
                        guard let firstLineEnd = input.firstIndex(of: 10) else {
                            throw ScriptSpeechError.failed("Missing MCP initialization request.")
                        }
                        try stdin.fileHandleForWriting.write(contentsOf: input[...firstLineEnd])
                        var output = Data()
                        // Establish the connection before sending a speech call.
                        // A failed handshake must never still queue the speech.
                        var buffer = Data()
                        var initialized = false
                        while !initialized {
                            while !buffer.contains(10) {
                                // A larger read can wait for EOF while the child
                                // waits for the next request. Read this small
                                // handshake line without filling a large buffer.
                                guard let chunk = try stdout.fileHandleForReading.read(upToCount: 1), !chunk.isEmpty else {
                                    throw ScriptSpeechError.failed("Chatter returned no MCP initialization reply.")
                                }
                                guard output.count + buffer.count + chunk.count <= 4 * 1024 * 1024 else {
                                    throw ScriptSpeechError.failed("Chatter returned too much data.")
                                }
                                buffer.append(chunk)
                            }
                            let end = buffer.firstIndex(of: 10)!
                            let line = Data(buffer[..<end])
                            output.append(contentsOf: buffer[...end])
                            buffer.removeSubrange(...end)
                            guard let reply = try? JSONDecoder().decode(HypeMCPJSONValue.self, from: line),
                                  let object = reply.objectValue, object["jsonrpc"] == .string("2.0") else {
                                throw ScriptSpeechError.failed("Chatter returned invalid MCP initialization JSON.")
                            }
                            if object["id"] == nil, object["method"] != nil { continue }
                            if let error = object["error"]?.objectValue {
                                throw ScriptSpeechError.failed(error["message"]?.stringValue ?? "Chatter initialization failed.")
                            }
                            guard object["id"] == .string("init"), object["result"]?.objectValue?["protocolVersion"]?.stringValue != nil else {
                                throw ScriptSpeechError.failed("Chatter did not initialize MCP.")
                            }
                            initialized = true
                        }
                        try lock.withLock {
                            if timedOut { throw ScriptSpeechError.unavailable("Chatter connection timed out.") }
                            if cancelled { throw CancellationError() }
                        }
                        try stdin.fileHandleForWriting.write(contentsOf: input[input.index(after: firstLineEnd)...])
                        try stdin.fileHandleForWriting.close()
                        output.append(buffer)
                        while let chunk = try stdout.fileHandleForReading.read(upToCount: 64 * 1024), !chunk.isEmpty {
                            guard output.count + chunk.count <= 4 * 1024 * 1024 else {
                                throw ScriptSpeechError.failed("Chatter returned too much data.")
                            }
                            output.append(chunk)
                        }
                        process.waitUntilExit()
                        try lock.withLock {
                            if timedOut { throw ScriptSpeechError.unavailable("Chatter connection timed out. Check that Chatter is running.") }
                            if cancelled { throw CancellationError() }
                        }
                        guard process.terminationStatus == 0 else { throw ScriptSpeechError.unavailable("Chatter's local bridge exited. Check the installed Chatter app and connection settings.") }
                        continuation.resume(returning: output)
                    } catch {
                        let wasCancelled = lock.withLock { cancelled }
                        cancel(timeout: false)
                        if lock.withLock({ timedOut }) {
                            continuation.resume(throwing: ScriptSpeechError.unavailable("Chatter connection timed out. Check that Chatter is running."))
                        } else if wasCancelled || error is CancellationError {
                            continuation.resume(throwing: CancellationError())
                        } else if error is ScriptSpeechError {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(throwing: ScriptSpeechError.unavailable("Cannot connect to the installed Chatter bridge. Open /Applications/Chatter.app and retry."))
                        }
                    }
                }
            }
        } onCancel: { self.cancel(timeout: false) }
    }

    private func cancel(timeout: Bool) {
        lock.withLock {
            cancelled = true
            timedOut = timedOut || timeout
            if process.isRunning { process.terminate() }
        }
    }
}
#endif
