import Foundation

/// User-facing settings for the Built-in model.
public enum BuiltInModelSettings {
    /// `"auto"` or a `BuiltInModelVariant.id`.
    public static let variantKey = "hype.builtIn.variant"
    public static let thinkingKey = "hype.builtIn.thinking"
    /// Optional user override of the computed context cap, in tokens.
    public static let contextLimitKey = "hype.builtIn.contextLimit"
    /// Prefix of per-variant keys pointing at a user-supplied model directory.
    public static let modelDirectoryKeyPrefix = "hype.builtIn.modelDirectory."

    public static let defaultMaxTokens = 4096
    public static let defaultTemperature = 0.2
    public static let defaultTopP = 0.95

    /// Hype's authoring system prompt ends with this per-turn block; everything
    /// before it (tool schemas, rules, the HypeTalk guide) is static.
    public static let promptCacheBoundaryMarkers = ["CURRENT STATE:"]

    public static func selectedVariantID(defaults: UserDefaults = .standard) -> String {
        HypeAIConfiguration.normalized(defaults.string(forKey: variantKey))
            ?? BuiltInModelCatalog.automaticVariantID
    }

    public static func thinkingEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: thinkingKey)
    }

    public static func contextLimitOverride(defaults: UserDefaults = .standard) -> Int? {
        let value = defaults.integer(forKey: contextLimitKey)
        return value > 0 ? value : nil
    }

    public static func modelDirectoryOverride(
        variantID: String,
        defaults: UserDefaults = .standard
    ) -> URL? {
        guard let path = HypeAIConfiguration.normalized(
            defaults.string(forKey: modelDirectoryKeyPrefix + variantID)
        ) else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }
}

/// How a Built-in model variant fits this Mac.
public struct BuiltInMemoryFit: Sendable, Equatable {
    public enum Verdict: String, Sendable, Equatable {
        /// Fits with room for the author's other apps.
        case comfortable
        /// Fits, but the context cap is small or other apps will feel it.
        case tight
        /// Must not be loaded on this Mac.
        case insufficient
    }

    public var verdict: Verdict
    /// Bytes the model may occupy (weights + KV + overhead).
    public var budgetBytes: Int64
    /// Prompt + generation token cap that keeps the model inside the budget.
    public var contextTokenLimit: Int
    /// KV-cache quantization the engine may fall back to in order to reach that
    /// cap (nil = the whole cap fits at 16-bit).
    public var kvCacheBits: Int?
    /// The KV cache stays 16-bit — measurably faster: ~1.6x decode, ~1.9x
    /// prefill on a 27B hybrid — until a conversation grows past this many
    /// tokens; only then is it quantized to `kvCacheBits`.
    public var kvQuantizationStartTokens: Int

    public init(
        verdict: Verdict,
        budgetBytes: Int64,
        contextTokenLimit: Int,
        kvCacheBits: Int?,
        kvQuantizationStartTokens: Int = 0
    ) {
        self.verdict = verdict
        self.budgetBytes = budgetBytes
        self.contextTokenLimit = contextTokenLimit
        self.kvCacheBits = kvCacheBits
        self.kvQuantizationStartTokens = kvQuantizationStartTokens
    }
}

/// Decides which Built-in model a Mac can run, and with how much context.
///
/// The rules come from measurement, not from a fixed percentage:
/// - Metal's recommended working set is 74–84% of RAM depending on the machine;
///   query it, never assume it.
/// - macOS has an unfixed IOGPU kernel-panic class when GPU wired memory runs
///   at that ceiling, so the model never gets more than `ceilingFraction` of it.
/// - An authoring app runs next to a browser and Xcode; `reservedForSystemBytes`
///   is never handed to the model.
public enum BuiltInMemoryFitPolicy {
    /// Share of Metal's recommended working set the model may use.
    public static let ceilingFraction = 0.85
    /// Fallback when the engine cannot report the recommended working set.
    public static let fallbackWorkingSetFraction = 0.75
    /// Memory never given to the model: macOS, Hype, a browser, Xcode.
    public static let reservedForSystemBytes: Int64 = 10 << 30
    /// Hype's untuned authoring request is ~50–60K prompt tokens.
    public static let comfortableContextTokens = 65_536
    /// Below this even a short authoring request does not fit.
    public static let minimumUsefulContextTokens = 24_576
    /// Never plan for more context than this, however much memory there is.
    public static let maximumContextTokens = 131_072
    /// Share of the 16-bit KV capacity used before falling back to 8-bit.
    public static let kvQuantizationStartFraction = 0.9
    /// Tokens that can still land in a 16-bit cache after the last quantization
    /// check: the engine only quantizes between prefill chunks, never while it
    /// decodes, so one full reply plus one prefill chunk must always fit.
    public static let kvQuantizationHeadroomTokens = BuiltInModelSettings.defaultMaxTokens + 2048

    public static func budgetBytes(
        physicalMemoryBytes: Int64,
        recommendedWorkingSetBytes: Int64?
    ) -> Int64 {
        let workingSet = recommendedWorkingSetBytes
            ?? Int64(Double(physicalMemoryBytes) * fallbackWorkingSetFraction)
        let belowCeiling = Int64(Double(workingSet) * ceilingFraction)
        let afterReserve = physicalMemoryBytes - reservedForSystemBytes
        return max(0, min(belowCeiling, afterReserve))
    }

    public static func evaluate(
        variant: BuiltInModelVariant,
        physicalMemoryBytes: Int64,
        recommendedWorkingSetBytes: Int64?,
        contextLimitOverride: Int? = nil
    ) -> BuiltInMemoryFit {
        let budget = budgetBytes(
            physicalMemoryBytes: physicalMemoryBytes,
            recommendedWorkingSetBytes: recommendedWorkingSetBytes
        )
        let physicalGB = Int((Double(physicalMemoryBytes) / Double(1 << 30)).rounded())
        let forKV = budget - variant.weightBytes - variant.fixedOverheadBytes

        guard physicalGB >= variant.minimumPhysicalMemoryGB, forKV > 0 else {
            return BuiltInMemoryFit(verdict: .insufficient, budgetBytes: budget, contextTokenLimit: 0, kvCacheBits: nil)
        }

        let ceiling = min(variant.nativeContextTokens, maximumContextTokens)
        let bytesPerToken = Int64(max(variant.kvBytesPerToken, 1))
        var kvBits: Int?
        var quantizationStart = 0
        var tokens = Int(forKV / bytesPerToken)
        if tokens < comfortableContextTokens {
            // 8-bit KV halves the growing cache (recurrent state is untouched),
            // but quantized attention is much slower — so stay at 16-bit for as
            // long as that fits, with a margin for the tokens one reply can add.
            quantizationStart = max(0, min(
                Int(Double(tokens) * kvQuantizationStartFraction),
                tokens - kvQuantizationHeadroomTokens))
            kvBits = 8
            tokens = Int(forKV / max(bytesPerToken / 2, 1))
        }
        tokens = min(tokens, ceiling)
        if let override = contextLimitOverride {
            tokens = min(tokens, max(override, 0))
        }

        guard tokens >= minimumUsefulContextTokens else {
            return BuiltInMemoryFit(
                verdict: .insufficient, budgetBytes: budget, contextTokenLimit: tokens,
                kvCacheBits: kvBits, kvQuantizationStartTokens: quantizationStart)
        }
        let comfortable = tokens >= comfortableContextTokens
            && physicalGB >= variant.recommendedPhysicalMemoryGB
        return BuiltInMemoryFit(
            verdict: comfortable ? .comfortable : .tight,
            budgetBytes: budget,
            contextTokenLimit: tokens,
            kvCacheBits: kvBits,
            kvQuantizationStartTokens: quantizationStart
        )
    }

    /// The variant "Automatic" resolves to: the largest tier that is comfortable
    /// here, else the largest that fits at all.
    public static func automaticVariant(
        among variants: [BuiltInModelVariant] = BuiltInModelCatalog.variants,
        physicalMemoryBytes: Int64,
        recommendedWorkingSetBytes: Int64?
    ) -> BuiltInModelVariant? {
        let ranked = variants.sorted { $0.weightBytes > $1.weightBytes }
        let fits = ranked.map { variant in
            (variant, evaluate(
                variant: variant,
                physicalMemoryBytes: physicalMemoryBytes,
                recommendedWorkingSetBytes: recommendedWorkingSetBytes
            ))
        }
        return fits.first { $0.1.verdict == .comfortable }?.0
            ?? fits.first { $0.1.verdict == .tight }?.0
    }
}
