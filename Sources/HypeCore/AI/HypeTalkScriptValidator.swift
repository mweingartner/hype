import Foundation

// MARK: - ValidationResult

/// The outcome of a host-side script draft validation pass.
///
/// A `.passed` result does NOT guarantee the script is semantically
/// correct against live state — it only guarantees the draft is
/// syntactically valid HypeTalk and free of forbidden patterns.
/// Runtime errors (referencing a sprite that was deleted, etc.) are
/// surfaced at execution time, not validation time.
public enum ValidationResult: Sendable, Equatable {
    /// Script passed all validation stages.
    /// - Parameters:
    ///   - handlerCount: Number of handler blocks found in the wrapped script (0 = empty/bare).
    ///   - handlerNames: Lowercase handler names in order.
    case passed(handlerCount: Int, handlerNames: [String])

    /// Script failed one or more stages. Failures are ordered by priority
    /// (most-actionable first): syntax → forbidden → nonHypeTalk → unresolvedReference.
    case failed(reasons: [ValidationFailure])
}

// MARK: - ValidationFailure

/// A single reason why a script draft was refused by the host gate.
public struct ValidationFailure: Sendable, Equatable, Codable {

    /// The category of failure — determines iteration priority and user messaging.
    public enum Kind: String, Sendable, Codable {
        /// HypeTalk parser rejected the script.
        case syntax
        /// Script contains non-HypeTalk patterns (JavaScript, Swift, etc.).
        case nonHypeTalk
        /// Script references a named object (button, field, card) that does not exist.
        case unresolvedReference
        /// Script contains a forbidden pattern (chat tokens, markdown fences, etc.).
        case forbiddenPattern
    }

    /// The kind of failure.
    public let kind: Kind
    /// Human-readable description of the problem.
    public let message: String
    /// Source line number, if the underlying tool can provide one.
    public let line: Int?
    /// Optional suggested fix for the model.
    public let suggestion: String?

    public init(kind: Kind, message: String, line: Int? = nil, suggestion: String? = nil) {
        self.kind = kind
        self.message = message
        self.line = line
        self.suggestion = suggestion
    }

    // MARK: Equatable (Codable-synthesized Equatable covers optionals)
    public static func == (lhs: ValidationFailure, rhs: ValidationFailure) -> Bool {
        lhs.kind == rhs.kind && lhs.message == rhs.message && lhs.line == rhs.line
    }
}

// MARK: - ScriptDraftContext

/// Context that accompanies a script draft through the validation pipeline.
///
/// The validator uses this to resolve named references (e.g. `field "Score"`)
/// against the live document so it can report unresolved references before
/// the model's tool call mutates anything.
public struct ScriptDraftContext: Sendable {
    /// Human-readable description of the target (e.g. "card 'Home'", "button 'OK'").
    public let targetDescription: String
    /// The document to resolve references against (read-only — validation never mutates).
    public let document: HypeDocument
    /// The active card's UUID — used to scope part lookups to the visible card.
    public let currentCardId: UUID

    public init(targetDescription: String, document: HypeDocument, currentCardId: UUID) {
        self.targetDescription = targetDescription
        self.document = document
        self.currentCardId = currentCardId
    }
}

// MARK: - HypeTalkScriptValidator

/// Host-side validator for AI-authored HypeTalk script drafts.
///
/// The validator runs BEFORE the executor's storage tools mutate the document.
/// It is independent of the `check_script` AI tool surface — `check_script`
/// lets the model self-validate interactively; this validator provides a
/// mandatory host-side gate that the model cannot bypass.
///
/// ## Validation stages (in priority order)
/// 1. **Syntax** — HypeTalk lexer + parser must accept the wrapped script.
/// 2. **Forbidden patterns** — chat tokens, markdown fences, etc.
/// 3. **Non-HypeTalk** — hard/soft signal detector for JavaScript/Swift.
/// 4. **Reference resolution** — named parts, cards, and backgrounds must exist.
///
/// ## Empty drafts
/// An empty `rawScript` (after trimming) is treated as `.passed(handlerCount: 0, handlerNames: [])`
/// because an empty string is a valid "no script" storage intent. This differs from
/// `check_script`'s tool-surface behavior, which returns a soft FAIL on empty to discourage
/// the model from accidentally clearing a script — the host gate has no such policy concern.
public struct HypeTalkScriptValidator: Sendable {

    public init() {}

    // MARK: - Public API

    /// Validate a script draft before it is stored.
    ///
    /// - Parameters:
    ///   - rawScript: The script text exactly as the model produced it (pre-wrap).
    ///   - wrappedScript: The same script after `wrapScript()` auto-wrapping.
    ///   - context: Document + card context for reference resolution.
    /// - Returns: `.passed` when all stages succeed; `.failed` with prioritised failures otherwise.
    ///
    /// - Note: Empty `rawScript` (after trimming whitespace) always returns `.passed(handlerCount: 0, handlerNames: [])`.
    ///   See the type-level doc comment for rationale.
    public func validate(
        rawScript: String,
        wrappedScript: String,
        context: ScriptDraftContext
    ) -> ValidationResult {
        let trimmedRaw = rawScript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRaw.isEmpty else {
            return .passed(handlerCount: 0, handlerNames: [])
        }

        // Run all stages, then sort by priority.
        var failures: [ValidationFailure] = []

        failures += validateSyntax(wrappedScript)

        // Only check forbidden / non-HypeTalk on the raw input so
        // the wrapper itself doesn't trigger false positives.
        failures += validateForbiddenPatterns(trimmedRaw)
        failures += validateNonHypeTalk(raw: trimmedRaw, wrapped: wrappedScript)

        // Reference resolution: only attempt when syntax passes, because
        // a malformed script may produce misleading AST fragments.
        if !failures.contains(where: { $0.kind == .syntax }) {
            if let parsed = parsedScript(wrappedScript) {
                failures += validateReferences(parsed: parsed, context: context)
            }
        }

        if failures.isEmpty {
            // Count handlers from the parse.
            let parsed = parsedScript(wrappedScript)
            let count = parsed?.handlers.count ?? 0
            let names = parsed?.handlers.map { $0.name.lowercased() } ?? []
            return .passed(handlerCount: count, handlerNames: names)
        }

        // Sort by priority: syntax > forbidden > nonHypeTalk > unresolvedReference.
        let priorityOrder: [ValidationFailure.Kind] = [.syntax, .forbiddenPattern, .nonHypeTalk, .unresolvedReference]
        let sorted = failures.sorted { a, b in
            let ai = priorityOrder.firstIndex(of: a.kind) ?? priorityOrder.count
            let bi = priorityOrder.firstIndex(of: b.kind) ?? priorityOrder.count
            return ai < bi
        }
        return .failed(reasons: sorted)
    }

    // MARK: - Internal stages (testable via @testable import)

    /// Check for forbidden patterns: chat tokens, markdown fences, prompt injections.
    ///
    /// Security note: these patterns cover tokens from all major LLM families
    /// (Gemma, ChatML/Qwen3, OpenAI, Llama 3.x, DeepSeek, GPT/Qwen3-MoE).
    /// A script body that contains a model's own turn boundary token almost
    /// certainly means the model leaked its context window into the script — this
    /// is a prompt-injection risk and must be rejected regardless of whether the
    /// surrounding HypeTalk parses.
    func validateForbiddenPatterns(_ raw: String) -> [ValidationFailure] {
        guard Self.forbiddenTokenRegex.numberOfMatches(
            in: raw,
            range: NSRange(raw.startIndex..., in: raw)
        ) > 0 else {
            return []
        }

        // Find which specific pattern matched for a useful error message.
        let matchedToken = Self.forbiddenTokenPatterns.first { pattern in
            if let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                return re.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)) != nil
            }
            return false
        } ?? "forbidden pattern"

        return [ValidationFailure(
            kind: .forbiddenPattern,
            message: "Script contains a forbidden token '\(matchedToken)' — possible chat-context leak or prompt injection.",
            line: nil,
            suggestion: "Remove the forbidden token and rewrite the script in plain HypeTalk with no chat formatting."
        )]
    }

    /// Check for non-HypeTalk language signals.
    ///
    /// This duplicates some logic from `SceneAuthoringAssistant.looksLikeNonHypeTalkScript`
    /// intentionally — the validator's acceptable-input surface is different from the
    /// scene assistant's: here we tolerate handler blocks unconditionally, whereas the
    /// scene assistant applies the rescue clause differently. Keeping them separate avoids
    /// unintended coupling across subsystems.
    func validateNonHypeTalk(raw: String, wrapped: String) -> [ValidationFailure] {
        let hardSignals: [String] = [
            "hype.",
            "self.", "this.",
            "function(", "function (",
            "=>",
            "skphysicsbody", "sknode", "skaction", "skspritenode", "sklabelnode",
            "skshapenode", "skscene", "skfield",
            "childnodewithname(",
            "enumeratechildrenwithnodepattern(",
            "document.", "window.",
            "addeventlistener",
            "console.log(",
            "@objc", "nonisolated",
        ]
        let softSignals: [String] = [
            "var ", "let ", "const ",
            ".foreach(", ".map(", ".filter(",
            ";",
            "{ ",
            " }",
        ]

        let lower = raw.lowercased()
        let wrappedLower = wrapped.lowercased()

        if let signal = hardSignals.first(where: { lower.contains($0) }) ?? hardSignals.first(where: { wrappedLower.contains($0) }) {
            return [ValidationFailure(
                kind: .nonHypeTalk,
                message: "Script contains non-HypeTalk token '\(signal)'.",
                line: nil,
                suggestion: "Rewrite the script in HypeTalk. Use 'on mouseUp ... end mouseUp' handler syntax."
            )]
        }

        let softHits = softSignals.filter { lower.contains($0) }.count
        if softHits >= 3 {
            // Apply the rescue clause: if there's a real HypeTalk handler block, don't fire.
            if !containsHypeTalkHandler(lower) {
                let matched = softSignals.filter { lower.contains($0) }
                return [ValidationFailure(
                    kind: .nonHypeTalk,
                    message: "Script contains multiple non-HypeTalk signals (\(matched.joined(separator: ", "))).",
                    line: nil,
                    suggestion: "Rewrite the script in HypeTalk. Remove semicolons, JavaScript arrow functions, and var/let/const declarations."
                )]
            }
        }
        return []
    }

    /// Parse the wrapped script and return syntax failures.
    func validateSyntax(_ wrapped: String) -> [ValidationFailure] {
        let trimmed = wrapped.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var lexer = Lexer(source: wrapped)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        do {
            _ = try parser.parse()
            return []
        } catch let error as ParseError {
            let description = error.errorDescription ?? String(describing: error)
            let line: Int?
            if case .unexpected(let tok, _) = error {
                line = tok.line > 0 ? tok.line : nil
            } else {
                line = nil
            }
            return [ValidationFailure(
                kind: .syntax,
                message: description,
                line: line,
                suggestion: "Fix the syntax error and call check_script to re-validate before storing."
            )]
        } catch {
            return [ValidationFailure(
                kind: .syntax,
                message: error.localizedDescription,
                line: nil,
                suggestion: "Fix the syntax error and call check_script to re-validate before storing."
            )]
        }
    }

    /// Walk the parsed AST and report named object references that cannot
    /// be resolved against the document.
    ///
    /// This is a best-effort pass. When the walker cannot determine a reference
    /// type from context, it prefers FALSE NEGATIVE (no report) over FALSE POSITIVE.
    /// A few categories of identifiers are always whitelisted (pronouns, property keywords).
    func validateReferences(parsed: Script, context: ScriptDraftContext) -> [ValidationFailure] {
        var failures: [ValidationFailure] = []

        for handler in parsed.handlers {
            failures += checkStatements(handler.body, context: context)
        }

        return failures
    }

    // MARK: - Private helpers

    /// True when the string contains at least one HypeTalk handler block opening.
    private func containsHypeTalkHandler(_ lower: String) -> Bool {
        if let onRange = lower.range(of: #"(^|\n)\s*on\s+[a-z]"#, options: .regularExpression),
           lower.range(of: #"(^|\n)\s*end\s+[a-z]"#, options: .regularExpression, range: onRange.upperBound..<lower.endIndex) != nil {
            return true
        }
        if lower.range(of: #"(^|\n)\s*function\s+[a-z]"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    /// Parse the wrapped script silently, returning nil on any failure.
    private func parsedScript(_ wrapped: String) -> Script? {
        let trimmed = wrapped.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Script(handlers: []) }
        var lexer = Lexer(source: wrapped)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        return try? parser.parse()
    }

    /// Recursively check a list of statements for unresolved references.
    private func checkStatements(_ statements: [Statement], context: ScriptDraftContext) -> [ValidationFailure] {
        var failures: [ValidationFailure] = []
        for stmt in statements {
            failures += checkStatement(stmt, context: context)
        }
        return failures
    }

    private func checkStatement(_ stmt: Statement, context: ScriptDraftContext) -> [ValidationFailure] {
        var failures: [ValidationFailure] = []
        switch stmt {
        case .put(let source, _, let target):
            failures += checkExpression(source, context: context)
            failures += checkExpression(target, context: context)
        case .get(let expr):
            failures += checkExpression(expr, context: context)
        case .set(_, let ofExpr, let to):
            if let ofExpr { failures += checkExpression(ofExpr, context: context) }
            failures += checkExpression(to, context: context)
        case .go(let dest):
            failures += checkExpression(dest, context: context)
        case .ifThenElse(let cond, let thenBlock, let elseBlock):
            failures += checkExpression(cond, context: context)
            failures += checkStatements(thenBlock, context: context)
            if let elseBlock { failures += checkStatements(elseBlock, context: context) }
        case .repeatCount(let count, let body):
            failures += checkExpression(count, context: context)
            failures += checkStatements(body, context: context)
        case .repeatWhile(let cond, let body):
            failures += checkExpression(cond, context: context)
            failures += checkStatements(body, context: context)
        case .repeatWith(_, let from, let to, let body):
            failures += checkExpression(from, context: context)
            failures += checkExpression(to, context: context)
            failures += checkStatements(body, context: context)
        case .expressionStatement(let expr):
            failures += checkExpression(expr, context: context)
        case .send(let message, let target):
            failures += checkExpression(message, context: context)
            failures += checkExpression(target, context: context)
        case .say(let expr), .activateListener(let expr):
            failures += checkExpression(expr, context: context)
        case .animateProperty(_, let target, let toValue, let duration):
            failures += checkExpression(target, context: context)
            failures += checkExpression(toValue, context: context)
            failures += checkExpression(duration, context: context)
        case .waitUntil(let expr):
            failures += checkExpression(expr, context: context)
        case .returnValue(let expr):
            failures += checkExpression(expr, context: context)
        case .setSpriteNodeProperty(_, let node, let value):
            failures += checkExpression(node, context: context)
            failures += checkExpression(value, context: context)
        case .runSpriteAction(let action, let node):
            failures += checkExpression(action, context: context)
            failures += checkExpression(node, context: context)
        default:
            break  // Other statement kinds: prefer false negative
        }
        return failures
    }

    private func checkExpression(_ expr: Expression, context: ScriptDraftContext) -> [ValidationFailure] {
        var failures: [ValidationFailure] = []
        switch expr {
        case .objectRef(let ref):
            failures += checkObjectRef(ref, context: context)
        case .binary(let lhs, _, let rhs):
            failures += checkExpression(lhs, context: context)
            failures += checkExpression(rhs, context: context)
        case .unary(_, let inner):
            failures += checkExpression(inner, context: context)
        case .functionCall(_, let args):
            for arg in args { failures += checkExpression(arg, context: context) }
        case .propertyAccess(_, let target):
            if let target { failures += checkExpression(target, context: context) }
        case .chunk(_, _, let inner):
            failures += checkExpression(inner, context: context)
        case .await(let inner):
            failures += checkExpression(inner, context: context)
        case .stringConcat(let l, let r), .spacedConcat(let l, let r),
             .contains(let l, let r), .isIn(let l, let r),
             .isNotIn(let l, let r), .isWithin(let l, let r),
             .isNotWithin(let l, let r):
            failures += checkExpression(l, context: context)
            failures += checkExpression(r, context: context)
        case .not(let inner):
            failures += checkExpression(inner, context: context)
        default:
            break  // Literals, .it, .me, .this, .empty, etc.: always OK
        }
        return failures
    }

    /// Check a single ObjectRefExpr against the document.
    ///
    /// Returns an empty array (false negative) whenever resolution is ambiguous
    /// or the object type is not tracked in the document model.
    private func checkObjectRef(_ ref: ObjectRefExpr, context: ScriptDraftContext) -> [ValidationFailure] {
        // Only check string-literal identifiers — numeric indices and
        // variable-derived names cannot be resolved statically.
        // Value is typealias Value = String, so .literal(Value) is .literal(String).
        guard case .literal(let rawName) = ref.identifier else {
            return []
        }

        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return [] }

        // Whitelist: pronouns and implicit references are never unresolved.
        let pronounWhitelist: Set<String> = [
            "me", "it", "this", "target", "the result", "params",
            "param 1", "param 2", "param 3", "param 4", "param 5",
            "param 6", "param 7", "param 8", "param 9",
            "card field", "bg field", "background field",
        ]
        if pronounWhitelist.contains(name.lowercased()) { return [] }

        let doc = context.document
        let typeLower = ref.objectType.lowercased()

        switch typeLower {
        case "button", "btn":
            let currentCard = doc.cards.first(where: { $0.id == context.currentCardId })
            let bgId = currentCard.flatMap { card in
                doc.backgrounds.first(where: { bg in
                    doc.cards.first(where: { $0.id == context.currentCardId })?.backgroundId == bg.id
                })?.id
            }
            let found = doc.parts.contains(where: { part in
                part.partType == .button &&
                part.name.lowercased() == name.lowercased() &&
                (part.cardId == context.currentCardId || (bgId != nil && part.backgroundId == bgId))
            })
            if !found {
                return [ValidationFailure(
                    kind: .unresolvedReference,
                    message: "Button '\(name)' not found on the current card or its background.",
                    line: nil,
                    suggestion: "Check the button name with list_parts or create the button first."
                )]
            }

        case "field", "fld":
            let currentCard = doc.cards.first(where: { $0.id == context.currentCardId })
            let bgId = currentCard.flatMap { _ in
                doc.backgrounds.first(where: { bg in
                    doc.cards.first(where: { $0.id == context.currentCardId })?.backgroundId == bg.id
                })?.id
            }
            let found = doc.parts.contains(where: { part in
                part.partType == .field &&
                part.name.lowercased() == name.lowercased() &&
                (part.cardId == context.currentCardId || (bgId != nil && part.backgroundId == bgId))
            })
            if !found {
                return [ValidationFailure(
                    kind: .unresolvedReference,
                    message: "Field '\(name)' not found on the current card or its background.",
                    line: nil,
                    suggestion: "Check the field name with list_parts or create the field first."
                )]
            }

        case "card":
            let found = doc.cards.contains(where: { $0.name.lowercased() == name.lowercased() })
            if !found {
                return [ValidationFailure(
                    kind: .unresolvedReference,
                    message: "Card '\(name)' not found in the stack.",
                    line: nil,
                    suggestion: "Check the card name with list_all_cards."
                )]
            }

        case "background", "bg":
            let found = doc.backgrounds.contains(where: { $0.name.lowercased() == name.lowercased() })
            if !found {
                return [ValidationFailure(
                    kind: .unresolvedReference,
                    message: "Background '\(name)' not found in the stack.",
                    line: nil,
                    suggestion: "Check the background name."
                )]
            }

        default:
            // sprite, image, video, etc. — prefer false negative
            break
        }

        return []
    }

    // MARK: - Forbidden token patterns (static, compiled once)

    /// The individual regex alternation patterns for forbidden tokens.
    /// These cover chat-context boundary tokens from all major LLM families.
    static let forbiddenTokenPatterns: [String] = [
        // Markdown code fences
        #"^\s*```"#,
        #"```\s*$"#,
        // Gemma
        #"<start_of_turn>"#,
        #"<end_of_turn>"#,
        // ChatML / Qwen3
        #"<\|im_start\|>"#,
        #"<\|im_end\|>"#,
        // Generic OpenAI special tokens
        #"<\|user\|>"#,
        #"<\|assistant\|>"#,
        #"<\|system\|>"#,
        #"<\|tool_call\|>"#,
        #"<tool_call>"#,
        #"</tool_call>"#,
        // Llama 3.x
        #"<\|begin_of_text\|>"#,
        #"<\|end_of_text\|>"#,
        #"<\|start_header_id\|>"#,
        #"<\|end_header_id\|>"#,
        #"<\|eot_id\|>"#,
        // DeepSeek (full-width vertical bars and triangular bullets)
        "<｜begin▁of▁sentence｜>",
        "<｜end▁of▁sentence｜>",
        // GPT / Qwen3-MoE
        #"<\|endoftext\|>"#,
    ]

    /// A single compiled regex that matches any forbidden token.
    /// Built once as a static let so repeated validation calls are fast.
    static let forbiddenTokenRegex: NSRegularExpression = {
        let combined = forbiddenTokenPatterns.joined(separator: "|")
        // DOTALL isn't needed here — each pattern matches a fixed string or line anchor.
        guard let re = try? NSRegularExpression(pattern: combined, options: [.caseInsensitive]) else {
            // Should never fail with the hardcoded patterns above.
            // If it does (e.g., unicode issue), return a never-matching regex.
            return try! NSRegularExpression(pattern: "(?!)")
        }
        return re
    }()
}
