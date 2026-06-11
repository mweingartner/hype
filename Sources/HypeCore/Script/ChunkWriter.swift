import Foundation

// MARK: - ChunkWriter

/// Pure chunk-write engine for HypeTalk container mutations.
///
/// Mirrors the read-path semantics of `evaluateChunk` in `Interpreter.swift`
/// (splits, sentinel resolution, clamping, no-ops) while remaining a pure
/// value layer: no document, no environment, no expression evaluation.
///
/// Called from `Interpreter.performChunkPut` to transform the string value
/// of a container before writing it back through the appropriate setter.
///
/// Thread-safety: all methods are pure (no mutation, no shared state);
/// safe to call from any concurrency context without isolation.
public enum ChunkWriter {

    /// Upper bound on the number of padding chars/words/items/lines a single
    /// out-of-range chunk write may synthesize. Writes that would need more
    /// padding than this are no-ops (the address is treated as unreachable,
    /// like a negative index) so a script cannot turn `put x into item N of y`
    /// into an arbitrary-size allocation.
    public static let maxPaddingCount = 65_536

    // MARK: - Resolved indices

    /// The result of resolving a `ChunkRange` to concrete array indices.
    public enum ResolvedIndices {
        /// A single 1-based index into the parts array.
        case single(Int)
        /// An inclusive 1-based range [lo, hi] into the parts array.
        case range(Int, Int)
    }

    // MARK: - Split / Join

    /// Split `text` into parts according to `chunkType`.
    ///
    /// Splitting rules mirror the read path in `evaluateChunk`:
    /// - `char` / `character`: each `Character` is one part; empty string → empty array.
    /// - `word`: split on spaces omitting empty sequences (whitespace-run collapses).
    /// - `item`: split on `itemDelimiter` (default `","`) keeping empty sequences;
    ///   items are **not** trimmed, preserving `"a, b, c"` spacing.
    /// - `line`: normalise `\r\n` and `\r` to `\n`; split on `\n` keeping empties;
    ///   empty string → empty array (mirrors `splitLines` in Interpreter).
    ///
    /// - Note: `itemDelimiter` only applies to the `.item` case; all other chunk types
    ///   are unaffected. Coordinate/rect/loc parsers in the interpreter use their own
    ///   hardcoded `","` split and are explicitly not routed through this function.
    public static func split(_ text: String, as chunkType: ChunkType, itemDelimiter: String = ",") -> [String] {
        // An empty container has ZERO chunks of every type. Swift's
        // split(omittingEmptySubsequences: false) would yield [""] for
        // item/line, which would make `last item of ""` address a phantom
        // empty part; the read path treats empty containers as chunkless,
        // and writes must agree (ordinals on empty are no-ops; positive
        // indices pad from zero).
        if text.isEmpty { return [] }
        switch chunkType {
        case .char, .character:
            return text.map(String.init)
        case .word:
            return text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        case .item:
            // Keep empty sequences so "a,,b" has 3 items.
            // Do NOT trim — preserve spacing like "a, b, c".
            let delimChar = itemDelimiter.first ?? ","
            return text.split(separator: delimChar, omittingEmptySubsequences: false).map(String.init)
        case .line:
            return splitLines(text)
        }
    }

    /// Join `parts` back into a container string with the correct delimiter.
    ///
    /// - `char` / `character`: no delimiter (parts are single characters or
    ///   replacement values; they concatenate directly).
    /// - `word`: space delimiter.
    /// - `item`: `itemDelimiter` (default `","`).
    /// - `line`: `"\n"`.
    public static func join(_ parts: [String], as chunkType: ChunkType, itemDelimiter: String = ",") -> String {
        switch chunkType {
        case .char, .character:
            return parts.joined()
        case .word:
            return parts.joined(separator: " ")
        case .item:
            return parts.joined(separator: itemDelimiter)
        case .line:
            return parts.joined(separator: "\n")
        }
    }

    // MARK: - Sentinel / index resolution

    /// Resolve a single index expression value to a concrete 1-based index,
    /// returning `nil` for sentinel values that should be a no-op.
    ///
    /// Sentinel encoding (from Parser.swift):
    /// - `-1` → `last` → `count`
    /// - `0`  → `middle` → `count / 2` (0-based middle, 1-based = `count/2`)
    /// - `-2` → `any` → random valid index
    /// - `≥1` → itself
    ///
    /// Returns `nil` when the address is out of range after resolution
    /// (e.g. `last` of an empty container, or positive index ≤ 0 after
    /// the sentinel has been resolved to something invalid).
    public static func resolveSingle(_ idx: Int, count: Int) -> Int? {
        switch idx {
        case -1:
            // "last"
            guard count > 0 else { return nil }
            return count
        case 0:
            // "middle" — mirrors evaluateChunk: parts[count/2] (0-based) = (count/2)+1 (1-based)
            guard count > 0 else { return nil }
            return (count / 2) + 1
        case -2:
            // "any"
            guard count > 0 else { return nil }
            return Int.random(in: 1...count)
        default:
            guard idx >= 1 else { return nil }
            return idx
        }
    }

    /// Resolve a range `[from, to]` to concrete 1-based `(lo, hi)` bounds,
    /// returning `nil` when the range is a no-op (reversed or entirely out
    /// of bounds before padding is needed).
    ///
    /// Mirrors the read path in `evaluateChunk`:
    /// ```
    /// let from = max(1, indexValue(fromExpr))
    /// let to   = min(parts.count, indexValue(toExpr))
    /// guard from <= to, from >= 1 else { return "" }
    /// ```
    /// For the write path we also need to pad, so we return `nil` only
    /// when `from > to` after sentinel resolution AND both are within
    /// range — callers handle the padding cases themselves.
    public static func resolveRange(from fromIdx: Int, to toIdx: Int, count: Int) -> (lo: Int, hi: Int)? {
        // Resolve sentinels to concrete indices
        let lo = resolveSentinelForRange(fromIdx, count: count, isFrom: true)
        let hi = resolveSentinelForRange(toIdx, count: count, isFrom: false)
        guard lo <= hi, lo >= 1 else { return nil }
        return (lo, hi)
    }

    // MARK: - Apply

    /// Apply a chunk write operation, returning the mutated container string.
    ///
    /// This is the main entry point. It is pure: given the current value of
    /// the container, it returns the new value. No I/O, no throws.
    ///
    /// - Parameters:
    ///   - chunkType: The chunk granularity (char, word, item, line).
    ///   - indices: The resolved address (single or range).
    ///   - preposition: `into` / `before` / `after`.
    ///   - container: The current string value of the container.
    ///   - value: The source value being written.
    ///   - itemDelimiter: The current item delimiter (default `","`). Only used for `.item` chunks.
    /// - Returns: The updated container string.  Returns `container`
    ///   unchanged for any address that is a no-op.
    public static func apply(
        chunkType: ChunkType,
        indices: ResolvedIndices,
        preposition: Preposition,
        container: String,
        value: String,
        itemDelimiter: String = ","
    ) -> String {
        switch indices {
        case .single(let idx):
            return applySingle(
                chunkType: chunkType,
                idx: idx,
                preposition: preposition,
                container: container,
                value: value,
                itemDelimiter: itemDelimiter
            )
        case .range(let lo, let hi):
            return applyRange(
                chunkType: chunkType,
                lo: lo,
                hi: hi,
                preposition: preposition,
                container: container,
                value: value,
                itemDelimiter: itemDelimiter
            )
        }
    }

    // MARK: - Private helpers

    /// Apply a single-index write.
    private static func applySingle(
        chunkType: ChunkType,
        idx: Int,
        preposition: Preposition,
        container: String,
        value: String,
        itemDelimiter: String = ","
    ) -> String {
        var parts = split(container, as: chunkType, itemDelimiter: itemDelimiter)
        let count = parts.count

        // Resolve sentinel
        guard let resolvedIdx = resolveSingle(idx, count: count) else {
            // Sentinel that can't resolve (e.g. last of empty) — no-op
            return container
        }

        if resolvedIdx <= count {
            // In-range: apply preposition to the existing element
            let zeroIdx = resolvedIdx - 1
            switch preposition {
            case .into:
                parts[zeroIdx] = value
            case .before:
                parts[zeroIdx] = value + parts[zeroIdx]
            case .after:
                parts[zeroIdx] = parts[zeroIdx] + value
            }
        } else {
            // Out-of-range (resolved index > count): pad then place
            // Only applies for positive literal indices (sentinels never
            // exceed count by design, so we would have returned above
            // for sentinel -1/-2/0).
            // Only `into` is meaningful for padding; before/after on a
            // non-existent element pads to that slot then treats the
            // new-empty element as the target.
            let target = resolvedIdx
            let paddingCount = target - count - 1
            // Padding is script-controlled (`put x into item 2000000000 of y`
            // resolves through clampedInt up to Int.max) and each padded slot
            // allocates real bytes. An unbounded String(repeating:) here is a
            // process-killing allocation — the exact crash class the rest of
            // the interpreter clamps against. Indices needing more padding
            // than any plausible HyperTalk usage are a deliberate no-op.
            guard paddingCount <= Self.maxPaddingCount else { return container }
            switch chunkType {
            case .char, .character:
                // Pad with spaces up to (target-1), then append value
                let spacePadding = String(repeating: " ", count: max(0, paddingCount))
                let appended = container + spacePadding + value
                return appended
            case .word:
                // Pad with extra spaces to reach slot, then append value
                // "a b" word 4 → "a b  Z" (two spaces between word 2 and word 4)
                let spacePadding = String(repeating: " ", count: max(0, paddingCount + 1))
                let appended = container.isEmpty ? value : container + spacePadding + value
                return appended
            case .item:
                // Append (target - count - 1) empty items then place value
                let delim = itemDelimiter
                let emptyItems = String(repeating: delim, count: paddingCount)
                let appended = container.isEmpty
                    ? emptyItems + value
                    : container + emptyItems + delim + value
                return appended
            case .line:
                // Append (target - count - 1) empty lines then place value
                let emptyLines = String(repeating: "\n", count: paddingCount)
                let appended = container.isEmpty
                    ? emptyLines + value
                    : container + emptyLines + "\n" + value
                return appended
            }
        }

        return join(parts, as: chunkType, itemDelimiter: itemDelimiter)
    }

    /// Apply a range write.
    ///
    /// `lo` and `hi` are raw sentinel-encoded values from the script (not yet resolved).
    /// We resolve sentinels first, then clamp to valid indices matching the read path.
    private static func applyRange(
        chunkType: ChunkType,
        lo: Int,
        hi: Int,
        preposition: Preposition,
        container: String,
        value: String,
        itemDelimiter: String = ","
    ) -> String {
        var parts = split(container, as: chunkType, itemDelimiter: itemDelimiter)
        let count = parts.count

        // Resolve sentinels before clamping.
        let resolvedLo = resolveSentinelForRange(lo, count: count, isFrom: true)
        let resolvedHi = resolveSentinelForRange(hi, count: count, isFrom: false)

        // Mirror read path: clamp to [1, count].
        let clampedLo = max(1, resolvedLo)
        let clampedHi = min(count, resolvedHi)

        if clampedLo > clampedHi || clampedLo < 1 {
            // The range is entirely outside the container or reversed after clamping.
            // If the original from-sentinel resolves to > count, pad to that slot
            // using the single-index padding path.
            let rawLo = (lo >= 1) ? lo : resolvedLo
            if rawLo > count && rawLo >= 1 {
                return applySingle(
                    chunkType: chunkType,
                    idx: rawLo,
                    preposition: preposition,
                    container: container,
                    value: value,
                    itemDelimiter: itemDelimiter
                )
            }
            return container
        }

        let loZ = clampedLo - 1   // 0-based
        let hiZ = clampedHi - 1   // 0-based (inclusive)

        switch preposition {
        case .into:
            // Replace the entire span with value as one part (collapse).
            let newParts: [String] = Array(parts[0..<loZ]) + [value] + Array(parts[(hiZ + 1)...])
            parts = newParts
        case .before:
            parts[loZ] = value + parts[loZ]
        case .after:
            parts[hiZ] = parts[hiZ] + value
        }

        return join(parts, as: chunkType, itemDelimiter: itemDelimiter)
    }

    /// Resolve a range-endpoint sentinel.  The `from` endpoint clamps low
    /// to 1; the `to` endpoint clamps high to count.  Matches the read path.
    private static func resolveSentinelForRange(_ idx: Int, count: Int, isFrom: Bool) -> Int {
        switch idx {
        case -1:
            return count          // "last"
        case 0:
            // "middle" — mirrors evaluateChunk: parts[count/2] (0-based) = (count/2)+1 (1-based)
            guard count > 0 else { return 0 }
            return (count / 2) + 1
        case -2:
            // "any" — random valid index
            guard count > 0 else { return 0 }
            return Int.random(in: 1...count)
        default:
            if isFrom {
                return max(1, idx)
            } else {
                return min(count, idx)
            }
        }
    }

    /// Split `source` into lines. Mirrors `splitLines` in `Interpreter.swift`:
    /// normalise `\r\n` and `\r` → `\n`, then split on `\n` keeping empties.
    /// Empty string → empty array.
    private static func splitLines(_ source: String) -> [String] {
        guard !source.isEmpty else { return [] }
        return source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }
}
