import Foundation

/// Surgical pre-flight repairs for common AI-authored HypeTalk
/// mistakes. Runs BEFORE the parser so the script-draft gate
/// doesn't have to refuse-and-retry for errors that are
/// trivially mechanical to fix.
///
/// What this fixes
/// ---------------
/// 1. **Bare `end`** → `end <handlerName>`. Models trained on
///    languages with anonymous block terminators (Python, Ruby,
///    Bash) routinely emit `end` without naming the block. The
///    HypeTalk parser requires the name. We infer the name from
///    the most recent unmatched `on <name>` line at the same
///    nesting level.
///
/// 2. **`elseif x` (one word)** → `else if x` (two words). Some
///    models emit the Visual-Basic-style `elseif`. The HypeTalk
///    parser only recognizes the two-word form.
///
/// What this DOES NOT fix
/// ----------------------
/// - **`else if x then ...` chains** — these are a parse error
///   (HypeTalk has no `else if`); the *correct* rewrite is a
///   nested `if` inside the `else` branch. That's not safe to
///   do mechanically without changing the script's semantics
///   when an `end if` is missing or misplaced. The host gate
///   refuses these and the model retries with the canonical
///   nested form documented in the HypeTalkGuide.
///
/// - **JS-flavored signals** (`function(`, `addEventListener`,
///   `let`, `var`, `=>`, etc.) — these indicate the model is
///   writing the wrong language entirely. The host gate refuses
///   them so the model is forced to retry in HypeTalk; an auto
///   "fix" would silently produce nonsense.
///
/// All transforms are idempotent — running the fixer twice
/// produces the same output as running it once.
public enum ScriptAutoFixer {

    /// Apply every safe auto-repair to `script`. Returns the fixed
    /// script. Callers should pass the fixed script to the parser
    /// / validator. The original raw script is preserved upstream
    /// so the AVOID-list and hard-signal checks see the model's
    /// actual emission.
    public static func autoFix(_ script: String) -> String {
        var fixed = script
        fixed = repairBareEnds(fixed)
        fixed = splitJoinedElseIf(fixed)
        return fixed
    }

    /// Fix-up summary — telemetry/debug-friendly. Returns the
    /// fixed script plus the list of repair categories applied
    /// (one entry per category, even if the category fired
    /// multiple times). Callers can log this so we can track how
    /// often each fix-up matters.
    public static func autoFixWithReport(_ script: String) -> (fixed: String, applied: [String]) {
        var fixed = script
        var applied: [String] = []

        let endsFixed = repairBareEnds(fixed)
        if endsFixed != fixed { applied.append("bare-end-named") }
        fixed = endsFixed

        let elseFixed = splitJoinedElseIf(fixed)
        if elseFixed != fixed { applied.append("elseif-spaced") }
        fixed = elseFixed

        return (fixed, applied)
    }

    // MARK: - 1. Bare `end` → `end <handlerName>`

    /// Replace any line that is exactly `end` (whitespace allowed)
    /// with `end <name>` where `<name>` is the handler name from
    /// the most recent unmatched `on <name>` line.
    ///
    /// Approach: walk lines top-to-bottom, maintain a stack of open
    /// `on <name>` blocks. When we hit a bare `end`, pop the stack
    /// and replace the line with `end <popped>`. When we hit an
    /// `end <name>` already, just pop. When we hit a structural
    /// keyword that is also closed by `end` (`if`, `repeat`), push
    /// a sentinel marker so a bare `end` matches its OWN structural
    /// block first, not the enclosing handler. (HypeTalk uses
    /// `end if` / `end repeat` for those.)
    static func repairBareEnds(_ script: String) -> String {
        let lines = script.components(separatedBy: "\n")
        var stack: [String] = []   // "<handler-name>" or "if" / "repeat" markers
        var output: [String] = []
        output.reserveCapacity(lines.count)

        for raw in lines {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()

            // Strip a trailing line comment so it doesn't fool the
            // structural detection. Comments start with `--`.
            let commentRange = lower.range(of: "--")
            let codeOnly = commentRange.map { String(lower[..<$0.lowerBound]).trimmingCharacters(in: .whitespaces) } ?? lower

            // Push: opening keyword.
            if codeOnly.hasPrefix("on "), let name = handlerName(after: "on", in: trimmed) {
                stack.append(name)
                output.append(raw)
                continue
            }
            if codeOnly == "if" || codeOnly.hasPrefix("if ") {
                // Single-line `if x then y` doesn't need an `end if`.
                // The parser rule: a multi-line `if` keeps tokens past
                // `then` on its own line. Detect by looking for
                // `then` as the last word of the line.
                if codeOnly.hasSuffix("then") {
                    stack.append("if")
                }
                output.append(raw)
                continue
            }
            if codeOnly == "repeat" || codeOnly.hasPrefix("repeat ") {
                stack.append("repeat")
                output.append(raw)
                continue
            }

            // Pop: explicit `end <name>` — verify it matches the top
            // of the stack but DON'T rewrite. (If it doesn't match,
            // the parser will still flag it; we don't try to be
            // clever.)
            if codeOnly == "end if" || codeOnly == "end repeat" {
                if !stack.isEmpty { stack.removeLast() }
                output.append(raw)
                continue
            }
            if codeOnly.hasPrefix("end ") {
                if !stack.isEmpty { stack.removeLast() }
                output.append(raw)
                continue
            }

            // Bare `end` — REPAIR if we have an enclosing handler.
            if codeOnly == "end" {
                if let name = stack.popLast() {
                    // Preserve indentation from the original line.
                    let leading = raw.prefix(while: { $0 == " " || $0 == "\t" })
                    let suffix: String
                    if let cr = commentRange { suffix = " " + String(raw[cr.lowerBound...]) } else { suffix = "" }
                    if name == "if" || name == "repeat" {
                        output.append("\(leading)end \(name)\(suffix)")
                    } else {
                        output.append("\(leading)end \(name)\(suffix)")
                    }
                    continue
                }
                output.append(raw)  // No enclosing block — leave it for the parser to flag.
                continue
            }

            output.append(raw)
        }

        return output.joined(separator: "\n")
    }

    // MARK: - 2. `elseif` → `else if`

    /// Convert single-token `elseif` (Visual Basic / older BASIC
    /// dialects) into the two-token form HypeTalk's lexer
    /// recognizes. NOT to be confused with the (forbidden) `else if`
    /// chain — splitting `elseif` produces `else if`, which is then
    /// caught by the parser's existing "no `else if`" error if the
    /// surrounding shape is wrong. So this fix is strictly an
    /// alphabet-level repair; it does NOT introduce a syntactic
    /// pattern the parser couldn't already see.
    static func splitJoinedElseIf(_ script: String) -> String {
        // Word-boundary regex: `\belseif\b` → `else if`. Case-insensitive.
        guard let regex = try? NSRegularExpression(
            pattern: #"\belseif\b"#,
            options: [.caseInsensitive]
        ) else { return script }
        let range = NSRange(script.startIndex..., in: script)
        return regex.stringByReplacingMatches(
            in: script,
            options: [],
            range: range,
            withTemplate: "else if"
        )
    }

    // MARK: - Helpers

    /// Extract `<name>` from an `on <name>` opening line. Trim any
    /// trailing parameter list — HypeTalk handlers can declare
    /// parameters after the name, e.g. `on requestFinished requestId, eventName`.
    /// We only need the handler name for the matching `end <name>`.
    private static func handlerName(after keyword: String, in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix(keyword.lowercased() + " ") else { return nil }
        let afterKeyword = trimmed.dropFirst(keyword.count + 1)
            .trimmingCharacters(in: .whitespaces)
        // Take the first whitespace-delimited word as the name.
        let firstWord = afterKeyword
            .split(whereSeparator: { $0.isWhitespace })
            .first
            .map(String.init)
        return firstWord
    }
}
