import Foundation

// MARK: - StackScriptAttributionSync

/// Manages the auto-generated web-asset attribution block inside `Stack.script`.
///
/// The attribution block is delimited by two sentinel strings and is fully
/// regenerated on every call to `sync(stackScript:webAssets:)`. Any text the
/// user types inside the sentinel lines is silently overwritten — only
/// `Asset.provenance` is the source of truth.
///
/// **Callers** invoke `sync` in three places:
/// 1. After `import_web_asset` or `find_and_import_sprite` succeed (inside `HypeToolExecutor`).
/// 2. When an asset is removed from the `AssetRepository` via the UI.
/// 3. NOT from `SceneAuthoringAssistant.resolveMissingAssets` — that path goes through the
///    executor branches which already call sync.
public enum StackScriptAttributionSync {

    // MARK: - Sentinels

    static let beginSentinel = "-- BEGIN HYPE WEB ASSET ATTRIBUTIONS (auto-generated, do not edit this block)"
    static let endSentinel   = "-- END HYPE WEB ASSET ATTRIBUTIONS"

    // MARK: - Public API

    /// Rewrite `stackScript`, replacing the attribution sentinel block with a freshly
    /// generated block built from `webAssets`.
    ///
    /// - Parameters:
    ///   - stackScript: The current value of `Stack.script`.
    ///   - webAssets: ALL assets in the asset repository (not pre-filtered). The function
    ///     filters to `origin == .webSearch` internally.
    /// - Returns: The updated script string.
    public static func sync(
        stackScript: String,
        webAssets: [Asset]
    ) -> String {
        // Step 1: Compute userBody (everything outside the sentinel block).
        let userBody = extractUserBody(from: stackScript)

        // Step 2: Build the attribution block.
        let block = buildBlock(from: webAssets)

        // Step 3: Compose.
        if block.isEmpty {
            return userBody
        }
        if userBody.isEmpty {
            return block
        }
        return block + "\n\n" + userBody
    }

    // MARK: - Field sanitizer (public for tests)

    /// Produce a single-line, safe-to-embed string from AI-provided or provider-provided input.
    ///
    /// Transforms applied in order:
    /// 1. CR+LF pairs collapsed to a single space (before single-char replacements).
    /// 2. Individual LF, CR, U+2028, U+2029, U+000B, U+000C replaced with space.
    /// 3. Double-dash (`--`) replaced with em-dash (U+2014).
    /// 4. Bidi override characters (U+202A–U+202E, U+2066–U+2069) stripped.
    /// 5. Zero-width characters (U+200B–U+200F, U+FEFF) stripped.
    /// 6. Trim leading/trailing whitespace.
    ///
    /// Implementation uses Swift `unicodeScalars` iteration to operate on actual
    /// Unicode scalar values, NOT on two-character escape literals.
    static func sanitizeField(_ raw: String) -> String {
        // Step 1: Collapse \r\n pairs first, then individual terminators.
        // We work on scalars after an initial string pass for the two-char pair.
        let s = raw.replacingOccurrences(of: "\r\n", with: " ")

        // Now rebuild via scalar iteration for single-char cases.
        var result = ""
        result.reserveCapacity(s.unicodeScalars.count)

        var prevWasHyphen = false

        for scalar in s.unicodeScalars {
            switch scalar.value {

            // Step 1 (single-char line terminators → space)
            case 0x000A,   // LF
                 0x000D,   // CR (any remaining after the \r\n pass above)
                 0x2028,   // LINE SEPARATOR
                 0x2029,   // PARAGRAPH SEPARATOR
                 0x000B,   // VERTICAL TAB
                 0x000C:   // FORM FEED
                // Flush a pending hyphen before appending the space
                if prevWasHyphen {
                    result.append("-")
                    prevWasHyphen = false
                }
                result.append(" ")

            // Step 4: Bidi override strip (U+202A–U+202E, U+2066–U+2069)
            case 0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
                 0x2066, 0x2067, 0x2068, 0x2069:
                // Strip: do not append, do not affect hyphen state
                break

            // Step 5: Zero-width strip (U+200B–U+200F, U+FEFF)
            case 0x200B, 0x200C, 0x200D, 0x200E, 0x200F,
                 0xFEFF:
                // Strip: do not append
                break

            case 0x002D:  // ASCII hyphen-minus
                if prevWasHyphen {
                    // We have seen "--": replace with em-dash (Step 3).
                    result.append("\u{2014}")
                    prevWasHyphen = false
                } else {
                    prevWasHyphen = true
                }

            default:
                if prevWasHyphen {
                    // Single hyphen followed by a non-hyphen: emit the hyphen.
                    result.append("-")
                    prevWasHyphen = false
                }
                result.unicodeScalars.append(scalar)
            }
        }

        // Flush trailing hyphen (if the string ended with exactly one hyphen).
        if prevWasHyphen {
            result.append("-")
        }

        // Step 6: Trim leading/trailing whitespace.
        return result.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Private helpers

    /// Extract the portion of `stackScript` that lies outside the sentinel block.
    ///
    /// Rules:
    /// - Both sentinels found: strip lines [begin, end] inclusive; consume one trailing blank line.
    /// - Begin found, end missing: everything from begin to EOF is treated as the block body;
    ///   `userBody` is everything before begin.
    /// - End found but begin missing: leave the script unchanged (orphan end sentinel).
    /// - Neither found: return the script unchanged.
    private static func extractUserBody(from script: String) -> String {
        let lines = script.components(separatedBy: "\n")

        // Find begin line (prefix match)
        let beginIndex = lines.firstIndex(where: { $0.hasPrefix("-- BEGIN HYPE WEB ASSET ATTRIBUTIONS ") })

        // Find end line (exact prefix match, after begin)
        var endIndex: Int? = nil
        if let bi = beginIndex {
            endIndex = lines[(bi + 1)...].firstIndex(where: { $0.hasPrefix("-- END HYPE WEB ASSET ATTRIBUTIONS") })
        }

        if let bi = beginIndex, let ei = endIndex {
            // Both found: remove [begin, end] inclusive + one optional blank line after.
            var kept: [String] = []
            kept.append(contentsOf: lines[0..<bi])
            var afterEnd = ei + 1
            // Consume one trailing blank line
            if afterEnd < lines.count && lines[afterEnd].trimmingCharacters(in: .whitespaces).isEmpty {
                afterEnd += 1
            }
            kept.append(contentsOf: lines[afterEnd...])
            let joined = kept.joined(separator: "\n")
            // Strip leading newline if it now starts with one
            var body = joined
            if body.hasPrefix("\n") {
                body = String(body.dropFirst())
            }
            return body

        } else if let bi = beginIndex {
            // Begin found, end missing: strip from begin to EOF.
            let kept = Array(lines[0..<bi])
            return kept.joined(separator: "\n")

        } else {
            // Neither found (or only orphan end): return unchanged.
            return script
        }
    }

    /// Build the sentinel-delimited attribution block from the repository assets.
    ///
    /// - Returns: The full block string (including sentinels), or an empty string
    ///   if there are no web-asset entries.
    private static func buildBlock(from webAssets: [Asset]) -> String {
        // Filter to web-search origin only.
        let filtered = webAssets.filter { $0.provenance?.origin == .webSearch }
        guard !filtered.isEmpty else { return "" }

        // Sort ascending by asset name (case-insensitive).
        let sorted = filtered.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        let lines = sorted.map { attributionLine(for: $0) }

        return beginSentinel + "\n"
            + lines.joined(separator: "\n") + "\n"
            + endSentinel
    }

    /// Format a single attribution line for `asset`.
    ///
    /// Format (per Section 9.1, Finding 10 — no `query:` suffix):
    /// ```
    /// -- "<asset.name>" — by <creator or "Unknown"> on <sourceName or "Unknown Provider"> — <license.identifier or "Unknown License"> — <attribution.sourceURL or "n/a">
    /// ```
    ///
    /// Em-dashes are U+2014. Every field value is run through `sanitizeField(_:)`.
    private static func attributionLine(for asset: Asset) -> String {
        guard let prov = asset.provenance else {
            return "-- \"\(sanitizeField(asset.name))\" \u{2014} by Unknown on Unknown Provider \u{2014} Unknown License \u{2014} n/a"
        }
        let name       = sanitizeField(asset.name)
        let creator    = sanitizeField(prov.attribution.creator).isEmpty
                             ? "Unknown"
                             : sanitizeField(prov.attribution.creator)
        let provider   = sanitizeField(prov.attribution.providerName).isEmpty
                             ? "Unknown Provider"
                             : sanitizeField(prov.attribution.providerName)
        let licenseId  = sanitizeField(prov.license.identifier).isEmpty
                             ? "Unknown License"
                             : sanitizeField(prov.license.identifier).uppercased()
        let sourceURL  = sanitizeField(prov.attribution.sourceURL).isEmpty
                             ? "n/a"
                             : sanitizeField(prov.attribution.sourceURL)

        return "-- \"\(name)\" \u{2014} by \(creator) on \(provider) \u{2014} \(licenseId) \u{2014} \(sourceURL)"
    }
}
