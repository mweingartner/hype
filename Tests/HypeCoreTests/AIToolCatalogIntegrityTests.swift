import Testing
import Foundation
@testable import HypeCore

/// Catalog-integrity and execution-gate tests for `HypeToolDefinitions` and
/// the `set_card_property` / `set_background_property` executor branches.
///
/// These tests verify two invariants:
///
/// 1. **Uniqueness** — every tool name in `allTools` (and in the combined
///    `allTools + webAssetTools` surface) appears exactly once.  Duplicate
///    definitions silently shadow each other and send contradictory schemas
///    to the model on every provider request.
///
/// 2. **Gate parity** — `set_card_property(property:"script")` and
///    `set_background_property(property:"script")` go through the same
///    `refusalForInvalidDraft` gate as the dedicated `set_card_script` /
///    `set_background_script` tools.  Malformed or non-HypeTalk drafts must
///    return the `__HYPE_INTERNAL_DRAFT_REFUSED_v1:` sentinel (driving the
///    `ScriptDraftCoordinator` retry loop) and leave the document unchanged.
@Suite("AI tool catalog integrity and script-storage gate parity")
struct AIToolCatalogIntegrityTests {

    // MARK: - Helpers

    private func makeDoc() -> (HypeDocument, UUID) {
        let doc = HypeDocument.newDocument(name: "Catalog Integrity Test")
        return (doc, doc.cards[0].id)
    }

    private func isSentinel(_ result: String) -> Bool {
        result.hasPrefix(ScriptDraftRefusal.sentinelPrefix)
    }

    // MARK: - Catalog uniqueness

    @Test("allTools contains no duplicate tool names")
    func allTools_noDuplicateNames() {
        let names = HypeToolDefinitions.allTools.map { $0.function.name }
        let uniqueCount = Set(names).count
        #expect(
            uniqueCount == names.count,
            "Expected \(names.count) unique names but found only \(uniqueCount). Duplicates: \(findDuplicates(names))"
        )
    }

    @Test("allTools combined with webAssetTools contains no duplicate tool names")
    func allToolsPlusWebAssets_noDuplicateNames() {
        let combined = HypeToolDefinitions.allTools + HypeToolDefinitions.webAssetTools
        let names = combined.map { $0.function.name }
        let uniqueCount = Set(names).count
        #expect(
            uniqueCount == names.count,
            "Expected \(names.count) unique names but found only \(uniqueCount). Duplicates: \(findDuplicates(names))"
        )
    }

    @Test("set_card_property appears exactly once in allTools")
    func setCardProperty_appearsExactlyOnce() {
        let count = HypeToolDefinitions.allTools.filter {
            $0.function.name == "set_card_property"
        }.count
        #expect(count == 1, "set_card_property should appear exactly once; found \(count)")
    }

    @Test("set_background_property appears exactly once in allTools")
    func setBackgroundProperty_appearsExactlyOnce() {
        let count = HypeToolDefinitions.allTools.filter {
            $0.function.name == "set_background_property"
        }.count
        #expect(count == 1, "set_background_property should appear exactly once; found \(count)")
    }

    @Test("set_card_property description and property parameter mention 'script'")
    func setCardProperty_schemaTeachesScriptProperty() {
        guard let tool = HypeToolDefinitions.allTools.first(where: { $0.function.name == "set_card_property" }) else {
            Issue.record("set_card_property not found in allTools")
            return
        }
        let descriptionMentionsScript = tool.function.description.localizedCaseInsensitiveContains("script")
        let propertyParamMentionsScript = tool.function.parameters.properties["property"]?.description
            .localizedCaseInsensitiveContains("script") ?? false
        #expect(descriptionMentionsScript || propertyParamMentionsScript,
                "set_card_property schema should mention 'script' so the model knows it accepts this property")
    }

    @Test("set_background_property description and property parameter mention 'script'")
    func setBackgroundProperty_schemaTeachesScriptProperty() {
        guard let tool = HypeToolDefinitions.allTools.first(where: { $0.function.name == "set_background_property" }) else {
            Issue.record("set_background_property not found in allTools")
            return
        }
        let descriptionMentionsScript = tool.function.description.localizedCaseInsensitiveContains("script")
        let propertyParamMentionsScript = tool.function.parameters.properties["property"]?.description
            .localizedCaseInsensitiveContains("script") ?? false
        #expect(descriptionMentionsScript || propertyParamMentionsScript,
                "set_background_property schema should mention 'script' so the model knows it accepts this property")
    }

    // MARK: - set_card_property script gate

    @Test("set_card_property(script: malformed) returns sentinel and leaves card script unchanged")
    func setCardProperty_malformedScript_returnsSentinelUnchanged() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        // Missing `end mouseUp` — parser rejects an unterminated handler.
        // (A dangling `put ... into` is tolerated by the parser's leniency,
        // so it is not a usable malformed sample here.)
        let badScript = "on mouseUp\n  put \"x\" into x"
        let result = await executor.execute(
            toolName: "set_card_property",
            arguments: ["property": "script", "value": badScript],
            document: &doc,
            currentCardId: cardId
        )
        #expect(isSentinel(result), "Malformed script via set_card_property should return the refusal sentinel")
        #expect(doc.cards[0].script.isEmpty, "Card script should be unchanged after a refused draft")
    }

    @Test("set_card_property(script: valid handler) stores script and returns success")
    func setCardProperty_validScript_storesAndReturnsSuccess() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let validScript = "on mouseUp\n  go next\nend mouseUp"
        let result = await executor.execute(
            toolName: "set_card_property",
            arguments: ["property": "script", "value": validScript],
            document: &doc,
            currentCardId: cardId
        )
        #expect(!isSentinel(result), "Valid script via set_card_property should return a normal (non-sentinel) result")
        #expect(doc.cards[0].script.contains("go next"), "Card script should contain the stored handler body")
    }

    @Test("set_card_property(script: JS arrow function) returns sentinel — forbidden pattern caught")
    func setCardProperty_jsArrowFunction_returnsSentinel() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        // `=>` is a forbidden pattern caught by HypeTalkScriptValidator
        let jsScript = "const handler = () => { console.log('hi'); };"
        let result = await executor.execute(
            toolName: "set_card_property",
            arguments: ["property": "script", "value": jsScript],
            document: &doc,
            currentCardId: cardId
        )
        #expect(isSentinel(result), "JS arrow function via set_card_property should return the refusal sentinel")
        #expect(doc.cards[0].script.isEmpty, "Card script should be unchanged after a refused JS draft")
    }

    @Test("set_card_property(script: addEventListener) returns sentinel — forbidden pattern caught")
    func setCardProperty_addEventListener_returnsSentinel() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let jsScript = "on mouseUp\n  addEventListener('click', handler)\nend mouseUp"
        let result = await executor.execute(
            toolName: "set_card_property",
            arguments: ["property": "script", "value": jsScript],
            document: &doc,
            currentCardId: cardId
        )
        #expect(isSentinel(result), "addEventListener usage via set_card_property should return the refusal sentinel")
        #expect(doc.cards[0].script.isEmpty, "Card script should be unchanged after a refused draft")
    }

    @Test("set_card_property(name: X) renames card and returns success — non-script path unaffected")
    func setCardProperty_renameCard_success() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "set_card_property",
            arguments: ["property": "name", "value": "MyRenamedCard"],
            document: &doc,
            currentCardId: cardId
        )
        #expect(!isSentinel(result), "Renaming a card via set_card_property should succeed without a sentinel")
        #expect(doc.cards[0].name == "MyRenamedCard", "Card name should be updated")
    }

    // MARK: - set_background_property script gate

    @Test("set_background_property(script: malformed) returns sentinel and leaves background script unchanged")
    func setBackgroundProperty_malformedScript_returnsSentinelUnchanged() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        // Missing `end mouseUp` — parser should reject
        let badScript = "on mouseUp\n  put \"hello\" into x"
        let result = await executor.execute(
            toolName: "set_background_property",
            arguments: ["property": "script", "value": badScript],
            document: &doc,
            currentCardId: cardId
        )
        #expect(isSentinel(result), "Malformed script via set_background_property should return the refusal sentinel")
        #expect(doc.backgrounds[0].script.isEmpty, "Background script should be unchanged after a refused draft")
    }

    @Test("set_background_property(script: valid handler) stores script and returns success")
    func setBackgroundProperty_validScript_storesAndReturnsSuccess() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let validScript = "on openBackground\n  put \"ready\" into x\nend openBackground"
        let result = await executor.execute(
            toolName: "set_background_property",
            arguments: ["property": "script", "value": validScript],
            document: &doc,
            currentCardId: cardId
        )
        #expect(!isSentinel(result), "Valid script via set_background_property should return a normal (non-sentinel) result")
        #expect(doc.backgrounds[0].script.contains("openBackground"), "Background script should contain the stored handler")
    }

    @Test("set_background_property(script: JS arrow function) returns sentinel — forbidden pattern caught")
    func setBackgroundProperty_jsArrowFunction_returnsSentinel() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let jsScript = "const fn = () => { return 42; };"
        let result = await executor.execute(
            toolName: "set_background_property",
            arguments: ["property": "script", "value": jsScript],
            document: &doc,
            currentCardId: cardId
        )
        #expect(isSentinel(result), "JS arrow function via set_background_property should return the refusal sentinel")
        #expect(doc.backgrounds[0].script.isEmpty, "Background script should be unchanged after a refused JS draft")
    }

    @Test("set_background_property(script: addEventListener) returns sentinel — forbidden pattern caught")
    func setBackgroundProperty_addEventListener_returnsSentinel() async {
        var (doc, cardId) = makeDoc()
        let executor = HypeToolExecutor()
        let jsScript = "on openBackground\n  window.addEventListener('load', fn)\nend openBackground"
        let result = await executor.execute(
            toolName: "set_background_property",
            arguments: ["property": "script", "value": jsScript],
            document: &doc,
            currentCardId: cardId
        )
        #expect(isSentinel(result), "addEventListener usage via set_background_property should return the refusal sentinel")
        #expect(doc.backgrounds[0].script.isEmpty, "Background script should be unchanged after a refused draft")
    }

    // MARK: - Private helpers

    /// Returns tool names that appear more than once in `names`.
    private func findDuplicates(_ names: [String]) -> [String] {
        var seen: [String: Int] = [:]
        for name in names { seen[name, default: 0] += 1 }
        return seen.filter { $0.value > 1 }.map { $0.key }.sorted()
    }
}
