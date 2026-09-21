#if canImport(MLXLMCommon)
import Foundation
import MLX
import MLXLMCommon

/// The Built-in model's prompt cache: one working KV cache plus two checkpoints.
///
/// Hype's untuned authoring prompt is ~50–60K tokens (tool schemas + rules + the
/// HypeTalk guide), followed by a per-message `CURRENT STATE:` block and the
/// conversation. Prefilling that on every round of a 40-round tool loop would
/// take minutes, so the engine keeps:
///
/// - a **static checkpoint** just before the first per-turn section, reused by
///   every message in every chat until the tool set or guide changes;
/// - a **turn checkpoint** at the end of the last rendered message, reused by
///   the next round of the same tool loop.
///
/// Hybrid models (Gated-DeltaNet, Mamba) carry recurrent state that cannot be
/// rewound, so a checkpoint stores *copies* of those layers only. Attention
/// layers are append-only and are rewound in place with `trim`, which keeps a
/// checkpoint at a few hundred megabytes instead of a second full KV cache.
///
/// Not thread-safe: only ever touched inside `ModelContainer.perform`.
final class PromptCacheSession: @unchecked Sendable {
    struct Checkpoint {
        let tokens: [Int]
        /// Copies of the layers that cannot be trimmed, keyed by layer index.
        let recurrent: [Int: any KVCache]
    }

    /// Running count of prefilled tokens for one request's progress readout.
    struct PrefillProgress {
        var total = 0
        private(set) var processed = 0
        let report: ((_ processed: Int, _ total: Int) -> Void)?

        init(report: ((_ processed: Int, _ total: Int) -> Void)?) {
            self.report = report
        }

        mutating func advance(by count: Int) {
            processed += count
            report?(processed, total)
        }
    }

    struct KVQuantization {
        let bits: Int
        let startTokens: Int
    }

    struct Preparation {
        /// Prompt tokens served from a checkpoint instead of being prefilled.
        let reusedTokens: Int
        /// Tokens still to feed through the token iterator (never empty).
        let remaining: [Int]
    }

    private(set) var cache: [any KVCache] = []
    private(set) var staticCheckpoint: Checkpoint?
    private(set) var turnCheckpoint: Checkpoint?
    /// The prompt tokens the working cache is known to start with, kept current
    /// chunk by chunk — so it stays true when a prefill is cancelled half-way.
    /// (Generated tokens follow them in the cache; nothing ever rewinds into those.)
    private(set) var liveTokens: [Int] = []
    /// Generation-prompt length per thinking mode, learned on first use.
    var generationPromptLength: [Bool: Int] = [:]
    /// Whether this model's chat template renders tool schemas after the system
    /// text (learned on first use); see `ChatRendering.relocatingPerTurnBlock`.
    var toolsFollowSystemText: Bool?

    func reset() {
        cache = []
        staticCheckpoint = nil
        turnCheckpoint = nil
        liveTokens = []
    }

    /// Brings the working cache to `turnBoundary`, reusing the longest checkpoint
    /// that is an exact prefix of `tokens`, and refreshes both checkpoints.
    func prepare(
        tokens: [Int],
        staticBoundary: Int?,
        turnBoundary: Int,
        model: any LanguageModel,
        parameters: GenerateParameters,
        kvCacheBits: Int?,
        kvQuantizationStart: Int = 0,
        diskCache: PromptPrefixDiskCache? = nil,
        onPrefillProgress: ((_ processed: Int, _ total: Int) -> Void)? = nil
    ) throws -> Preparation {
        precondition(turnBoundary >= 0 && turnBoundary < tokens.count, "at least one token must remain to generate from")

        var position = 0
        let quantization = kvCacheBits.map { KVQuantization(bits: $0, startTokens: kvQuantizationStart) }
        let reusable = reusablePrefix(of: tokens, upTo: turnBoundary)
        if let reusable, rewindLeavesQuantizedLayers(to: reusable, quantization: quantization) {
            // A longer conversation pushed the working cache to 8-bit. Going back
            // under the threshold must also go back to 16-bit attention, or every
            // later chat would stay on the slow path until the model is unloaded.
            let layerCount = cache.count
            if let boundary = staticBoundary, boundary < turnBoundary,
               let diskCache, diskCache.contains(tokens: Array(tokens[..<boundary])) {
                // Exact: the 16-bit prefix a previous prefill persisted. Free the
                // 8-bit cache first so the two never sit in memory together.
                reset()
                if let stored = diskCache.load(tokens: Array(tokens[..<boundary]), expectedLayers: layerCount) {
                    cache = stored
                    position = boundary
                    liveTokens = Array(tokens[..<boundary])
                    staticCheckpoint = snapshot(tokens: liveTokens)
                } else {
                    cache = model.newCache(parameters: parameters)
                }
            } else if restore(reusable) {
                // Approximate (values went through 8-bit) but no minute-long prefill.
                dequantizeAttentionLayers()
                position = reusable.tokens.count
            } else {
                reset()
                cache = model.newCache(parameters: parameters)
            }
        } else if let reusable, restore(reusable) {
            position = reusable.tokens.count
        } else {
            reset()
            cache = model.newCache(parameters: parameters)
        }
        // From here on the cache is rewritten past `position`: a longer turn
        // checkpoint no longer describes it, even if this prefill is cancelled.
        if let turn = turnCheckpoint, turn.tokens.count > position {
            turnCheckpoint = nil
        }
        var reused = position
        var progress = PrefillProgress(report: onPrefillProgress)

        if let staticCheckpoint, !tokens.starts(with: staticCheckpoint.tokens) {
            self.staticCheckpoint = nil
        }
        if let boundary = staticBoundary, boundary > position, boundary < turnBoundary {
            let prefix = Array(tokens[..<boundary])
            if position == 0, let stored = diskCache?.load(tokens: prefix, expectedLayers: cache.count) {
                // A previous launch already paid for this prefix.
                cache = stored
                liveTokens = prefix
                reused = boundary
            } else {
                progress.total = turnBoundary - position
                try prefill(tokens[position..<boundary], model: model, parameters: parameters, quantization: quantization, progress: &progress)
                if position == 0 {
                    diskCache?.save(cache, tokens: prefix)
                }
            }
            position = boundary
            staticCheckpoint = snapshot(tokens: prefix)
        }

        if turnBoundary > position {
            if progress.total == 0 { progress.total = turnBoundary - position }
            try prefill(tokens[position..<turnBoundary], model: model, parameters: parameters, quantization: quantization, progress: &progress)
            position = turnBoundary
        }
        turnCheckpoint = snapshot(tokens: Array(tokens[..<turnBoundary]))

        return Preparation(reusedTokens: reused, remaining: Array(tokens[turnBoundary...]))
    }

    // MARK: - Internals

    /// The longest stretch of `tokens` the working cache can be rewound to.
    ///
    /// A hybrid model can only go back to a checkpoint (its recurrent layers do
    /// not rewind). A cache made only of append-only attention layers — a dense
    /// model — can go back to any token, so the whole common prefix with what it
    /// holds is reusable: that matters for models whose chat template renders
    /// the tool schemas *after* the system text, where the static checkpoint
    /// covers less than half the prompt.
    private func reusablePrefix(of tokens: [Int], upTo turnBoundary: Int) -> Checkpoint? {
        if !cache.isEmpty, cache.allSatisfy(Self.rewindsInPlace) {
            let common = Self.commonPrefixLength(liveTokens, tokens, limit: turnBoundary)
            return common > 0 ? Checkpoint(tokens: Array(tokens[..<common]), recurrent: [:]) : nil
        }
        return [turnCheckpoint, staticCheckpoint]
            .compactMap { $0 }
            .sorted { $0.tokens.count > $1.tokens.count }
            .first { checkpoint in
                checkpoint.tokens.count <= turnBoundary
                    && tokens.starts(with: checkpoint.tokens)
                    // The attention layers must still hold exactly these tokens.
                    && Self.commonPrefixLength(liveTokens, checkpoint.tokens, limit: checkpoint.tokens.count)
                        == checkpoint.tokens.count
            }
    }

    static func commonPrefixLength(_ lhs: [Int], _ rhs: [Int], limit: Int) -> Int {
        let bound = max(0, min(lhs.count, rhs.count, limit))
        var index = 0
        while index < bound, lhs[index] == rhs[index] { index += 1 }
        return index
    }

    private static func rewindsInPlace(_ layer: any KVCache) -> Bool {
        // Append-only attention caches. Rotating (sliding-window) caches stop
        // being trimmable once they wrap, so they are copied like recurrent state.
        (layer is KVCacheSimple || layer is QuantizedKVCache) && layer.isTrimmable
    }

    /// True when rewinding to `checkpoint` would leave 8-bit attention layers
    /// holding fewer tokens than the quantization threshold.
    private func rewindLeavesQuantizedLayers(to checkpoint: Checkpoint, quantization: KVQuantization?) -> Bool {
        guard let quantization, checkpoint.tokens.count <= quantization.startTokens else { return false }
        return cache.contains { $0 is QuantizedKVCache }
    }

    private func dequantizeAttentionLayers() {
        for (index, layer) in cache.enumerated() {
            if let quantized = layer as? QuantizedKVCache {
                cache[index] = quantized.toUnquantized()
            }
        }
        eval(cache)
    }

    private func snapshot(tokens: [Int]) -> Checkpoint {
        var recurrent: [Int: any KVCache] = [:]
        for (index, layer) in cache.enumerated() where !Self.rewindsInPlace(layer) {
            recurrent[index] = layer.copy()
        }
        return Checkpoint(tokens: tokens, recurrent: recurrent)
    }

    private func restore(_ checkpoint: Checkpoint) -> Bool {
        guard !cache.isEmpty else { return false }
        var restored = cache
        for (index, layer) in cache.enumerated() {
            if let saved = checkpoint.recurrent[index] {
                restored[index] = saved.copy()
            } else if Self.rewindsInPlace(layer), layer.offset >= checkpoint.tokens.count {
                layer.trim(layer.offset - checkpoint.tokens.count)
            } else {
                return false
            }
        }
        cache = restored
        liveTokens = checkpoint.tokens
        return true
    }

    private func prefill(
        _ segment: ArraySlice<Int>,
        model: any LanguageModel,
        parameters: GenerateParameters,
        quantization: KVQuantization?,
        progress: inout PrefillProgress
    ) throws {
        guard !segment.isEmpty else { return }
        let step = max(parameters.prefillStepSize, 1)
        var start = segment.startIndex
        while start < segment.endIndex {
            try Task.checkCancellation()
            let end = min(start + step, segment.endIndex)
            let chunk = LMInput.Text(tokens: MLXArray(segment[start..<end].map(Int32.init)))
            _ = model(chunk[text: .newAxis], cache: cache.isEmpty ? nil : cache, state: nil)
            eval(cache)
            if let quantization {
                // Converts a layer only once it holds `startTokens`: short
                // conversations keep the faster 16-bit attention path. This is
                // the ONLY place the cache is quantized. Never hand `kvBits` to
                // the token iterator: it would swap layers in its own copy of
                // this array and leave the session holding stale ones.
                maybeQuantizeKVCache(
                    cache: &cache, kvBits: quantization.bits, quantizedKVStart: quantization.startTokens)
            }
            liveTokens.append(contentsOf: segment[start..<end])
            progress.advance(by: end - start)
            start = end
        }
    }
}
#endif
