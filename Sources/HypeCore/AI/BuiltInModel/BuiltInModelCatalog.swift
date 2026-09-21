import Foundation

/// Memory tier a Built-in model variant is sized for.
///
/// The Built-in model is Hype's on-device authoring AI: open weights that run
/// in-process (no Ollama, no server, no API key). Two tiers ship because the
/// best model that fits a 32 GB Mac is not the best model a 128 GB Mac can run.
public enum BuiltInModelTier: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Sized for Macs with 32 GB of unified memory.
    case standard
    /// Sized for Macs with 96 GB or more (tuned on a 128 GB M5 Max).
    case max

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .standard: return "Standard (32 GB Macs)"
        case .max: return "Max (96 GB+ Macs)"
        }
    }
}

/// One file of a Built-in model's weight package, pinned by size and SHA-256.
public struct BuiltInModelFile: Codable, Sendable, Equatable {
    /// Path relative to the model repository root.
    public let path: String
    public let size: Int64
    /// Lowercase hex SHA-256 of the file contents.
    public let sha256: String

    public init(path: String, size: Int64, sha256: String) {
        self.path = path
        self.size = size
        self.sha256 = sha256
    }
}

/// How a Built-in model turns its reasoning ("thinking") mode off.
///
/// Interactive authoring runs non-thinking: a 40-round tool loop cannot afford
/// a reasoning trace per round.
public enum BuiltInThinkingControl: Codable, Sendable, Equatable {
    /// The model has no reasoning mode.
    case none
    /// A boolean chat-template variable (e.g. `enable_thinking`).
    case templateFlag(String)
}

/// The markup a Built-in model wraps its tool calls in.
///
/// The engine can infer it for the model families its runtime knows by name;
/// a variant states it when the runtime's inference is wrong for the artifact.
public enum BuiltInToolCallSyntax: String, Codable, Sendable, Equatable {
    /// Let the engine infer it from the model's architecture.
    case inferred
    /// `<tool_call><function=name><parameter=key>value</parameter></function></tool_call>`
    /// (Qwen3-Coder, Qwen3.5+, Granite 4.2).
    case xmlFunction
}

/// A downloadable, pinned Built-in model.
public struct BuiltInModelVariant: Codable, Sendable, Equatable, Identifiable {
    /// Stable identifier, also reported as the client's `modelName`.
    ///
    /// Must NOT start with `hypetalk-`: that prefix marks a *tuned* model whose
    /// weights already contain the HypeTalk guide, and switches the chat panel
    /// to the slim system prompt. These variants are untuned.
    public let id: String
    public let displayName: String
    public let summary: String
    public let tier: BuiltInModelTier

    /// Hugging Face repository (`owner/name`) and pinned commit.
    public let huggingFaceRepo: String
    public let revision: String
    public let files: [BuiltInModelFile]

    public let license: String
    public let licenseURL: String

    /// Growing attention KV-cache cost per token at 16-bit precision.
    public let kvBytesPerToken: Int
    /// Context-independent memory: recurrent state, activations, scratch.
    public let fixedOverheadBytes: Int64
    public let nativeContextTokens: Int

    /// Below this the variant is refused outright.
    public let minimumPhysicalMemoryGB: Int
    /// From this size up the variant is the automatic choice for its tier.
    public let recommendedPhysicalMemoryGB: Int

    public let supportsVision: Bool
    public let thinkingControl: BuiltInThinkingControl
    public let toolCallSyntax: BuiltInToolCallSyntax

    public init(
        id: String,
        displayName: String,
        summary: String,
        tier: BuiltInModelTier,
        huggingFaceRepo: String,
        revision: String,
        files: [BuiltInModelFile],
        license: String,
        licenseURL: String,
        kvBytesPerToken: Int,
        fixedOverheadBytes: Int64,
        nativeContextTokens: Int,
        minimumPhysicalMemoryGB: Int,
        recommendedPhysicalMemoryGB: Int,
        supportsVision: Bool,
        thinkingControl: BuiltInThinkingControl,
        toolCallSyntax: BuiltInToolCallSyntax = .inferred
    ) {
        self.id = id
        self.displayName = displayName
        self.summary = summary
        self.tier = tier
        self.huggingFaceRepo = huggingFaceRepo
        self.revision = revision
        self.files = files
        self.license = license
        self.licenseURL = licenseURL
        self.kvBytesPerToken = kvBytesPerToken
        self.fixedOverheadBytes = fixedOverheadBytes
        self.nativeContextTokens = nativeContextTokens
        self.minimumPhysicalMemoryGB = minimumPhysicalMemoryGB
        self.recommendedPhysicalMemoryGB = recommendedPhysicalMemoryGB
        self.supportsVision = supportsVision
        self.thinkingControl = thinkingControl
        self.toolCallSyntax = toolCallSyntax
    }

    /// Total bytes on disk (and to download).
    public var totalBytes: Int64 {
        files.reduce(0) { $0 + $1.size }
    }

    /// Bytes of weight tensors that stay resident while the model is loaded.
    public var weightBytes: Int64 {
        files.filter { $0.path.hasSuffix(".safetensors") }.reduce(0) { $0 + $1.size }
    }

    /// Download URL for one file, pinned to `revision`.
    public func downloadURL(for file: BuiltInModelFile) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "huggingface.co"
        components.path = "/\(huggingFaceRepo)/resolve/\(revision)/\(file.path)"
        return components.url
    }
}

/// The Built-in models Hype knows how to install.
public enum BuiltInModelCatalog {
    /// Settings value meaning "pick the variant for this Mac".
    public static let automaticVariantID = "auto"

    public static var variants: [BuiltInModelVariant] {
        [BuiltInModelManifests.standard, BuiltInModelManifests.max]
    }

    public static func variant(id: String) -> BuiltInModelVariant? {
        variants.first { $0.id == id }
    }

    public static func variant(tier: BuiltInModelTier) -> BuiltInModelVariant? {
        variants.first { $0.tier == tier }
    }
}
