import Foundation

/// Read only non-secret local preference fields that Chatter's current API
/// does not resolve on omission. Never read its api-token or voice recordings.
public struct ChatterLocalDefaults: Decodable, Sendable, Equatable {
    public var defaultPace: Double?
    public var studioTone: String?
    public init(defaultPace: Double? = nil, studioTone: String? = nil) { self.defaultPace = defaultPace; self.studioTone = studioTone }

    public static func current() throws -> Self {
        #if os(macOS)
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Chatter/settings.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
        do { return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url)) }
        catch { throw ScriptSpeechError.unavailable("Cannot read Chatter's speech defaults. Open Chatter Preferences and check its settings.") }
        #else
        throw ScriptSpeechError.unavailable("Local Chatter defaults are available on macOS only.")
        #endif
    }
}
