import Foundation

public struct ChatterSpeechClient: Sendable {
    public typealias ToolCall = @Sendable (String, [String: HypeMCPJSONValue]) async throws -> HypeMCPJSONValue
    private let toolCall: ToolCall
    private let defaults: @Sendable () throws -> ChatterLocalDefaults
    private let pollingDelay: Duration
    private let deadline: Duration
    private let validateWAV: @Sendable (String) throws -> Bool

    public init(toolCall: @escaping ToolCall, defaults: @escaping @Sendable () throws -> ChatterLocalDefaults = { try .current() }, pollingDelay: Duration = .seconds(1), deadline: Duration = .seconds(3600), validateWAV: @escaping @Sendable (String) throws -> Bool = ChatterSpeechClient.isWAV) {
        self.toolCall = toolCall; self.defaults = defaults; self.pollingDelay = pollingDelay
        self.deadline = deadline; self.validateWAV = validateWAV
    }

    public func voices() async throws -> [ScriptSpeechVoice] {
        let result = try await toolCall("chatter_voices", [:])
        guard let list = result.objectValue?["voices"]?.arrayValue else { throw ScriptSpeechError.failed("Chatter did not return a voice list.") }
        return try list.map { value in
            guard let object = value.objectValue, let id = object["id"]?.stringValue, let name = object["name"]?.stringValue else { throw ScriptSpeechError.failed("Chatter returned an invalid voice.") }
            return ScriptSpeechVoice(id: id, name: name, isDefault: object["isDefault"] == .bool(true), ready: object["ready"] == .bool(true), supportsTone: object["supportsInstructions"] == .bool(true))
        }
    }

    public func speak(_ request: ScriptSpeechRequest) async throws -> ScriptSpeechResult {
        try request.validate()
        try Task.checkCancellation()
        let localDefaults = request.tone == nil || request.pace == nil ? try defaults() : ChatterLocalDefaults()
        let voice: String
        if let selected = request.voice { voice = selected }
        else {
            guard let selected = try await voices().first(where: \.isDefault) else { throw ScriptSpeechError.invalid("Choose a default voice in Chatter, or pass a voice to speak.") }
            voice = selected.id
        }
        var arguments: [String: HypeMCPJSONValue] = ["text": .string(request.text), "voice": .string(voice), "requestID": .string(UUID().uuidString)]
        if let tone = request.tone ?? localDefaults.studioTone { arguments["tone"] = .string(tone) }
        if let pace = request.pace ?? localDefaults.defaultPace { arguments["pace"] = .number(pace) }
        if let quality = request.quality { arguments["quality"] = .string(quality.lowercased()) }
        if let output = request.output { arguments["mode"] = .string(output.lowercased() == "wav" ? "save" : "play") }
        let receipt = try await toolCall("chatter_speak", arguments)
        guard let id = receipt.objectValue?["id"]?.stringValue else { throw ScriptSpeechError.failed("Chatter did not return a speech job ID.") }
        let start = ContinuousClock.now
        var job = receipt
        do {
            while true {
                try Task.checkCancellation()
                switch job.objectValue?["state"]?.stringValue {
                case "completed":
                    let value: String
                    if request.output?.lowercased() == "wav" {
                        guard let path = job.objectValue?["path"]?.stringValue, path.hasPrefix("/"), try validateWAV(path) else { throw ScriptSpeechError.failed("Chatter completed the job but did not provide a readable WAV file.") }
                        value = path
                    } else { value = id }
                    return ScriptSpeechResult(value: value, warnings: job.objectValue?["warnings"]?.arrayValue?.compactMap(\.stringValue) ?? [])
                case "failed": throw ScriptSpeechError.failed(job.objectValue?["message"]?.stringValue ?? "Chatter speech failed.")
                case "cancelled": throw ScriptSpeechError.failed("Chatter speech job was cancelled.")
                case "queued", "running", "preparing", "generating", "playing", "processing", "synthesizing", "saving": break
                default:
                    // Nonterminal state names can evolve; an absent state is invalid.
                    guard job.objectValue?["state"]?.stringValue != nil else { throw ScriptSpeechError.failed("Chatter omitted the speech job state.") }
                }
                guard start.duration(to: .now) < deadline else { throw ScriptSpeechError.failed("Chatter speech is still pending (job \(id)). Check Chatter's job history before retrying.") }
                try await Task.sleep(for: pollingDelay)
                job = try await toolCall("chatter_job", ["id": .string(id)])
            }
        } catch {
            if Task.isCancelled {
                // Cancellation means stop this caller's own accepted job, never
                // cancel other clients or stop the speech service.
                let cancel = toolCall
                _ = await Task.detached { try? await cancel("chatter_cancel", ["id": .string(id)]) }.value
                throw CancellationError()
            }
            throw error
        }
    }

    public static func isWAV(_ path: String) throws -> Bool {
        guard let file = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? file.close() }
        let header = try file.read(upToCount: 12) ?? Data()
        return header.count == 12 && String(data: header.prefix(4), encoding: .ascii) == "RIFF" && String(data: header.suffix(4), encoding: .ascii) == "WAVE"
    }
}
