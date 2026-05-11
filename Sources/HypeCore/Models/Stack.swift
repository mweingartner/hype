import Foundation

/// A Hype stack — the top-level document containing backgrounds and cards.
public struct Stack: Identifiable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var width: Int
    public var height: Int
    public var createdAt: Date
    public var modifiedAt: Date
    public var script: String
    /// The default font applied to every newly created button and
    /// field. Settable at runtime via HypeTalk:
    ///   `set the defaultFont of stack to "Helvetica"`
    ///   `put the defaultFont of stack into f`
    /// The value is written into `Part.textFont` at part-creation
    /// time in both the UI tool-drop path and the AI tool-call
    /// path. Existing parts are not retroactively changed —
    /// only new parts pick up the default.
    public var defaultFont: String
    public var networkManifest: StackNetworkManifest
    /// Whether the AI web-asset search feature is allowed for this stack.
    /// Defaults to `false` for all stacks, including those created before
    /// the web-asset feature was introduced (backward-compatible decode).
    /// Toggle in Preferences → Web Asset Search → Current Stack.
    public var webAssetsAllowed: Bool

    /// Whether stack-scoped AI Context Library snippets may be sent to cloud
    /// model providers such as OpenAI. Local Ollama models can use context
    /// without this flag; cloud use is opt-in because attached files may contain
    /// private project rules, source text, or customer assets.
    public var aiContextCloudSharingAllowed: Bool

    /// The stack-level theme name. NEVER nil — the cascade
    /// (card → background → stack) needs a guaranteed terminating
    /// reference, so newly-created stacks default to
    /// `BuiltInThemes.fallbackName` ("System"). When a user deletes
    /// a theme that the stack was using, this resets to "System"
    /// rather than going nil. See ThemeResolver.swift for the full
    /// cascade contract.
    public var themeName: String

    private enum CodingKeys: String, CodingKey {
        case id, name, width, height, createdAt, modifiedAt, script
        case defaultFont, networkManifest
        case webAssetsAllowed
        case aiContextCloudSharingAllowed
        case themeName
    }

    public init(
        id: UUID = UUID(),
        name: String = "Untitled",
        width: Int = 800,
        height: Int = 600,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        script: String = "",
        defaultFont: String = "Apple Braille",
        networkManifest: StackNetworkManifest = StackNetworkManifest(),
        webAssetsAllowed: Bool = false,
        aiContextCloudSharingAllowed: Bool = false,
        themeName: String = "System"
    ) {
        self.id = id
        self.name = name
        self.width = width
        self.height = height
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.script = script
        self.defaultFont = defaultFont
        self.networkManifest = networkManifest
        self.webAssetsAllowed = webAssetsAllowed
        self.aiContextCloudSharingAllowed = aiContextCloudSharingAllowed
        self.themeName = themeName
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        width = try c.decodeIfPresent(Int.self, forKey: .width) ?? 800
        height = try c.decodeIfPresent(Int.self, forKey: .height) ?? 600
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? Date()
        script = try c.decodeIfPresent(String.self, forKey: .script) ?? ""
        defaultFont = try c.decodeIfPresent(String.self, forKey: .defaultFont) ?? "Apple Braille"
        networkManifest = try c.decodeIfPresent(StackNetworkManifest.self, forKey: .networkManifest) ?? StackNetworkManifest()
        // Backward-compatible: pre-v2 stacks have no webAssetsAllowed field.
        webAssetsAllowed = try c.decodeIfPresent(Bool.self, forKey: .webAssetsAllowed) ?? false
        aiContextCloudSharingAllowed = try c.decodeIfPresent(Bool.self, forKey: .aiContextCloudSharingAllowed) ?? false
        // Backward-compatible: pre-theme stacks default to "System".
        themeName = try c.decodeIfPresent(String.self, forKey: .themeName) ?? "System"
    }
}
