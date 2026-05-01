import Testing
import Foundation
@testable import HypeCore

/// Unit tests for the host-side `HypeTalkScriptValidator`.
///
/// These tests cover every validation stage and confirm the priority ordering
/// of failures, the empty-draft fast-path, and the whitelist for HypeTalk pronouns.
@Suite("HypeTalkScriptValidator — host-side draft gate")
struct HypeTalkScriptValidatorTests {

    // MARK: - Test setup helpers

    private func makeDoc() -> (HypeDocument, UUID) {
        let doc = HypeDocument.newDocument(name: "Validator Test")
        return (doc, doc.cards[0].id)
    }

    private func makeDocWithField(named name: String) -> (HypeDocument, UUID) {
        var doc = HypeDocument.newDocument(name: "Validator Test")
        let cardId = doc.cards[0].id
        let field = Part(
            partType: .field,
            cardId: cardId,
            name: name,
            left: 10, top: 10, width: 200, height: 30
        )
        doc.parts.append(field)
        return (doc, cardId)
    }

    private func context(for doc: HypeDocument, cardId: UUID, description: String = "test") -> ScriptDraftContext {
        ScriptDraftContext(targetDescription: description, document: doc, currentCardId: cardId)
    }

    private func validate(raw: String, in doc: HypeDocument, cardId: UUID) -> ValidationResult {
        let validator = HypeTalkScriptValidator()
        var lexer = Lexer(source: raw)
        let _ = lexer.tokenize()
        // Use wrapScript logic inline: the validator takes both raw and wrapped.
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let wrapped: String
        if lower.hasPrefix("on ") || lower.hasPrefix("function ") || trimmed.isEmpty {
            wrapped = trimmed
        } else {
            wrapped = "on mouseUp\n  \(trimmed)\nend mouseUp"
        }
        return validator.validate(
            rawScript: raw,
            wrappedScript: wrapped,
            context: context(for: doc, cardId: cardId)
        )
    }

    // MARK: - Passed cases

    @Test("simple mouseUp handler passes validation")
    func passed_simpleMouseUp() {
        let (doc, cardId) = makeDoc()
        let result = validate(raw: "on mouseUp\nput 1 into x\nend mouseUp", in: doc, cardId: cardId)
        if case .passed(let count, let names) = result {
            #expect(count == 1)
            #expect(names.contains("mouseup"))
        } else {
            Issue.record("Expected .passed but got \(result)")
        }
    }

    @Test("empty draft returns passed with zero handlers")
    func passed_emptyDraft() {
        let (doc, cardId) = makeDoc()
        let validator = HypeTalkScriptValidator()
        let result = validator.validate(
            rawScript: "",
            wrappedScript: "",
            context: context(for: doc, cardId: cardId)
        )
        if case .passed(let count, let names) = result {
            #expect(count == 0)
            #expect(names.isEmpty)
        } else {
            Issue.record("Expected .passed(0, []) for empty script but got \(result)")
        }
    }

    @Test("whitespace-only draft is treated as empty and passes")
    func passed_whitespaceDraft() {
        let (doc, cardId) = makeDoc()
        let validator = HypeTalkScriptValidator()
        let result = validator.validate(
            rawScript: "   \n\t  ",
            wrappedScript: "   \n\t  ",
            context: context(for: doc, cardId: cardId)
        )
        if case .passed = result {
            // OK
        } else {
            Issue.record("Expected .passed for whitespace-only script but got \(result)")
        }
    }

    @Test("pronoun whitelist: 'put me into it' does not report unresolved references")
    func passed_pronounWhitelist() {
        let (doc, cardId) = makeDoc()
        let result = validate(raw: "on mouseUp\nput me into it\nend mouseUp", in: doc, cardId: cardId)
        if case .passed = result {
            // OK
        } else {
            Issue.record("Expected .passed (me/it are whitelisted) but got \(result)")
        }
    }

    @Test("resolved field reference passes")
    func passed_resolvedFieldReference() {
        let (doc, cardId) = makeDocWithField(named: "Score")
        let result = validate(raw: "on mouseUp\nput 100 into field \"Score\"\nend mouseUp", in: doc, cardId: cardId)
        if case .passed = result {
            // OK
        } else {
            Issue.record("Expected .passed with existing field but got \(result)")
        }
    }

    // MARK: - Failed: syntax

    @Test("missing 'end mouseUp' returns syntax failure")
    func failed_syntaxMissingEnd() {
        let (doc, cardId) = makeDoc()
        let validator = HypeTalkScriptValidator()
        let wrapped = "on mouseUp\nput 1 into x\n"  // no end mouseUp
        let result = validator.validate(
            rawScript: "put 1 into x",
            wrappedScript: wrapped,
            context: context(for: doc, cardId: cardId)
        )
        if case .failed(let reasons) = result {
            #expect(reasons.contains(where: { $0.kind == .syntax }))
        } else {
            Issue.record("Expected .failed(.syntax) but got \(result)")
        }
    }

    // MARK: - Failed: nonHypeTalk

    @Test("var/let/const pattern returns nonHypeTalk failure")
    func failed_nonHypeTalkLetVar() {
        let (doc, cardId) = makeDoc()
        let result = validate(raw: "let x = 5;\nconst y = 10;\nvar z = x + y;", in: doc, cardId: cardId)
        if case .failed(let reasons) = result {
            #expect(reasons.contains(where: { $0.kind == .nonHypeTalk }))
        } else {
            Issue.record("Expected .failed(.nonHypeTalk) but got \(result)")
        }
    }

    // MARK: - Failed: forbiddenPattern

    @Test("markdown code fence in script returns forbiddenPattern failure")
    func failed_markdownFence() {
        let (doc, cardId) = makeDoc()
        let raw = "```\non mouseUp\nput 1 into x\nend mouseUp\n```"
        let result = validate(raw: raw, in: doc, cardId: cardId)
        if case .failed(let reasons) = result {
            #expect(reasons.contains(where: { $0.kind == .forbiddenPattern }))
        } else {
            Issue.record("Expected .failed(.forbiddenPattern) for markdown fences but got \(result)")
        }
    }

    @Test("Gemma turn token <start_of_turn> returns forbiddenPattern failure")
    func failed_leakedTurnToken_gemma() {
        let (doc, cardId) = makeDoc()
        let raw = "<start_of_turn>user\non mouseUp\nput 1 into x\nend mouseUp\n<end_of_turn>"
        let validator = HypeTalkScriptValidator()
        let result = validator.validate(
            rawScript: raw,
            wrappedScript: raw,
            context: context(for: doc, cardId: cardId)
        )
        if case .failed(let reasons) = result {
            #expect(reasons.contains(where: { $0.kind == .forbiddenPattern }))
        } else {
            Issue.record("Expected .failed(.forbiddenPattern) for Gemma token but got \(result)")
        }
    }

    @Test("ChatML/Qwen3 token <|im_start|> returns forbiddenPattern failure")
    func failed_leakedTurnToken_qwen3() {
        let (doc, cardId) = makeDoc()
        let raw = "<|im_start|>user\non mouseUp\nput 1 into x\nend mouseUp\n<|im_end|>"
        let validator = HypeTalkScriptValidator()
        let result = validator.validate(
            rawScript: raw,
            wrappedScript: raw,
            context: context(for: doc, cardId: cardId)
        )
        if case .failed(let reasons) = result {
            #expect(reasons.contains(where: { $0.kind == .forbiddenPattern }))
        } else {
            Issue.record("Expected .failed(.forbiddenPattern) for ChatML token but got \(result)")
        }
    }

    @Test("Llama 3.x token <|begin_of_text|> returns forbiddenPattern failure")
    func failed_leakedTurnToken_llama() {
        let (doc, cardId) = makeDoc()
        let raw = "<|begin_of_text|>on mouseUp\nput 1 into x\nend mouseUp"
        let validator = HypeTalkScriptValidator()
        let result = validator.validate(
            rawScript: raw,
            wrappedScript: raw,
            context: context(for: doc, cardId: cardId)
        )
        if case .failed(let reasons) = result {
            #expect(reasons.contains(where: { $0.kind == .forbiddenPattern }))
        } else {
            Issue.record("Expected .failed(.forbiddenPattern) for Llama token but got \(result)")
        }
    }

    @Test("DeepSeek token returns forbiddenPattern failure")
    func failed_leakedTurnToken_deepseek() {
        let (doc, cardId) = makeDoc()
        let raw = "<｜begin▁of▁sentence｜>on mouseUp\nput 1 into x\nend mouseUp"
        let validator = HypeTalkScriptValidator()
        let result = validator.validate(
            rawScript: raw,
            wrappedScript: raw,
            context: context(for: doc, cardId: cardId)
        )
        if case .failed(let reasons) = result {
            #expect(reasons.contains(where: { $0.kind == .forbiddenPattern }))
        } else {
            Issue.record("Expected .failed(.forbiddenPattern) for DeepSeek token but got \(result)")
        }
    }

    // MARK: - Failed: unresolvedReference

    @Test("put into nonexistent field returns unresolvedReference failure")
    func failed_unresolvedFieldReference() {
        let (doc, cardId) = makeDoc()  // no fields in this doc
        let result = validate(
            raw: "on mouseUp\nput 1 into field \"ghost\"\nend mouseUp",
            in: doc, cardId: cardId
        )
        if case .failed(let reasons) = result {
            #expect(reasons.contains(where: { $0.kind == .unresolvedReference }))
        } else {
            Issue.record("Expected .failed(.unresolvedReference) for missing field but got \(result)")
        }
    }

    // MARK: - Failure priority ordering

    @Test("multi-failure script returns failures in priority order (syntax > forbidden > nonHypeTalk > unresolvedReference)")
    func failure_orderingIsStable() {
        let (doc, cardId) = makeDoc()
        // This script has a syntax error (missing end) AND a forbidden token AND a non-HypeTalk signal.
        let raw = "```\nvar x = 5;\n"
        let wrapped = "on mouseUp\n```\nvar x = 5;\n"  // no end mouseUp — syntax fails
        let validator = HypeTalkScriptValidator()
        let result = validator.validate(
            rawScript: raw,
            wrappedScript: wrapped,
            context: context(for: doc, cardId: cardId)
        )
        if case .failed(let reasons) = result, reasons.count > 1 {
            // First failure should be syntax (highest priority) or forbidden
            let firstKind = reasons.first?.kind
            #expect(firstKind == .syntax || firstKind == .forbiddenPattern)
            // Verify no unresolvedReference appears before syntax/forbidden
            if let unresolvedIdx = reasons.firstIndex(where: { $0.kind == .unresolvedReference }),
               let syntaxIdx = reasons.firstIndex(where: { $0.kind == .syntax || $0.kind == .forbiddenPattern }) {
                #expect(syntaxIdx < unresolvedIdx)
            }
        }
    }
}
