import Foundation
import Testing
@testable import HypeCore

/// Pins the MCP transport masking of secure (password) field text.
///
/// The curated AI/HypeTalk read surfaces (`get_part_property`,
/// `formatAllProperties`, HypeTalk `the text of field …`) mask secure-field
/// text — see `SecurityRegressionTests.swift`. This suite pins the same
/// guarantee for the MCP object/document tools, which serialize whole
/// `Part`/`HypeDocument` values and therefore need their own masking layer
/// (`HypeMCPDocumentBackend.maskedForTransport`). See
/// `openspec/changes/mask-mcp-object-tools/design.md` for the full rule.
@Suite("MCP secure-field masking")
@MainActor
struct MCPMaskingTests {

    private static let secureFieldMask = "(masked)"

    /// The field-body-text rule's MASKED set (design.md Decision 1): every
    /// `Part` `String` stored property that is settable with no
    /// `fieldStyle` guard and can plausibly hold the field's bound value.
    private static let maskedProperties: Set<String> = ["textContent", "htmlContent", "searchText"]

    /// Every other current `Part` `String` stored property, classified
    /// EXEMPT under the rule (chrome/config/code — see design.md Decision 1
    /// for the per-property rationale). This is the single audit point:
    /// a new `Part` `String` property must be added to one of these two
    /// sets, or `structuralClassificationCompleteness` (S1) fails.
    private static let exemptProperties: Set<String> = [
        "name", "sortKey", "textFont", "textStyle", "fontColor", "helpText", "popupItems",
        "fillColor", "strokeColor", "url", "videoURL", "chartData", "sceneSpec",
        "selectedDate", "selectedTime", "displayMonth", "minDate", "maxDate", "calendarStyle",
        "imageFilter", "pdfURL", "pdfDisplayMode", "mapType", "mapAnnotationsJSON", "mapLocation",
        "colorWellHex", "segmentItems", "audioOutputPath", "audioFormat",
        "musicPatternName", "musicInstrumentName", "musicTrackData", "musicSourceKind",
        "musicSourceID", "musicSourceType", "musicSourceTitle", "musicSourceArtist",
        "musicSourceAlbum", "musicArtworkURL", "musicQueueData", "musicSearchTerm", "musicSearchScope",
        "progressLabel", "progressTint", "gaugeStyle", "gaugeTint", "gaugeLabel", "gaugeMinLabel",
        "gaugeMaxLabel", "menuItems", "menuTitle", "searchPrompt", "dividerOrientation", "dividerColor",
        "scene3DURL", "scene3DBackground", "scene3DAntialiasing", "scene3DSourceURL", "script"
    ]

    // MARK: - Fixtures

    private func makeSecureFieldPart(
        cardId: UUID,
        name: String = "pwd",
        textContent: String = "s3cr3t",
        htmlContent: String = "<b>h1dden</b>",
        searchText: String = "f1ndme"
    ) -> Part {
        var part = Part(partType: .field, cardId: cardId, name: name, left: 10, top: 20, width: 200, height: 30)
        part.fieldStyle = .secure
        part.textContent = textContent
        part.htmlContent = htmlContent
        part.searchText = searchText
        return part
    }

    private func makeDocumentAndCardId() throws -> (HypeDocument, UUID) {
        let document = HypeDocument.newDocument(name: "MCP Masking")
        let cardId = try #require(document.sortedCards.first?.id)
        return (document, cardId)
    }

    /// Nudges every currently-known `Part` `Int`/`Double` property that
    /// defaults to exactly `0` or `1` away from that value.
    ///
    /// This is a test-only workaround for a pre-existing, unrelated
    /// Foundation bridging defect discovered while writing this suite (out
    /// of scope for this change — see the file whitelist in design.md's
    /// Conditions for Builder; `HypeMCPTypes.swift` is not touched by this
    /// change): `HypeMCPJSONValue.init(any:)` (used by `codableJSONValue`)
    /// checks `case let value as Bool` before `Int`/`Double`, and
    /// `JSONSerialization`-produced `NSNumber(0)` / `NSNumber(1)` satisfy an
    /// `as? Bool` cast, so ANY `Part` numeric property valued exactly `0`
    /// or `1` — which most numeric properties are, by default — round-trips
    /// through the real MCP object-read response as a JSON boolean instead
    /// of a JSON number. A strict `JSONDecoder().decode(Part.self, from:)`
    /// of that real response then throws a type mismatch. This affects
    /// every MCP object read regardless of `fieldStyle` and is unrelated to
    /// secure-field masking; it should be flagged to Security/Test as a
    /// separate, pre-existing defect. It is worked around here, confined to
    /// this test file, only so the masking + round-trip-guard behavior
    /// this suite targets can be observed via a genuine GET-then-decode
    /// round trip.
    private func avoidingKnownZeroOrOneNumericBridgingDefaults(_ part: Part) -> Part {
        var patched = part
        patched.rotation = 12
        patched.family = 2
        patched.strokeWidth = 2
        patched.videoCurrentTime = 5
        patched.videoDuration = 5
        patched.videoPlayRate = 2
        patched.videoVolume = 0.5
        patched.pdfCurrentPage = 2
        patched.controlValue = 5
        patched.controlMin = 5
        patched.controlStep = 2
        patched.audioDuration = 5
        patched.musicVolume = 0.5
        patched.musicPosition = 5
        patched.musicDuration = 5
        patched.progressValue = 0.5
        patched.progressTotal = 5
        patched.progressDecimals = 2
        patched.gaugeValue = 5
        patched.gaugeMin = 5
        patched.gaugeMax = 10
        patched.gaugeDecimals = 2
        patched.dividerThickness = 2
        return patched
    }

    // MARK: - 1: hype_get_object masks all three secure properties

    @Test("1: hype_get_object masks textContent, htmlContent, and searchText on a secure field")
    func getObjectMasksAllThreeSecureProperties() async throws {
        var (document, cardId) = try makeDocumentAndCardId()
        let secure = makeSecureFieldPart(cardId: cardId)
        document.addPart(secure)
        let backend = HypeMCPDocumentBackend(document: document, currentCardId: cardId)

        let result = await backend.callTool(
            name: "hype_get_object",
            arguments: ["object_type": .string("part"), "id_or_name": .string("pwd")]
        )

        let object = try #require(result.object?["object"]?.object)
        #expect(object["textContent"]?.string == Self.secureFieldMask)
        #expect(object["htmlContent"]?.string == Self.secureFieldMask)
        #expect(object["searchText"]?.string == Self.secureFieldMask)

        let blob = result.jsonString(pretty: false)
        #expect(!blob.contains(secure.textContent))
        #expect(!blob.contains(secure.htmlContent))
        #expect(!blob.contains(secure.searchText))
    }

    // MARK: - 2: non-secure fields unaffected

    @Test("2: hype_get_object returns plaintext for a non-secure (rectangle) field")
    func getObjectRectangleFieldReturnsPlaintext() async throws {
        var (document, cardId) = try makeDocumentAndCardId()
        var plain = Part(partType: .field, cardId: cardId, name: "notes", left: 0, top: 0, width: 200, height: 30)
        plain.fieldStyle = .rectangle
        plain.textContent = "hello world"
        plain.htmlContent = "<p>hello world</p>"
        plain.searchText = "hello search"
        document.addPart(plain)
        let backend = HypeMCPDocumentBackend(document: document, currentCardId: cardId)

        let result = await backend.callTool(
            name: "hype_get_object",
            arguments: ["object_type": .string("part"), "id_or_name": .string("notes")]
        )

        let object = try #require(result.object?["object"]?.object)
        #expect(object["textContent"]?.string == "hello world")
        #expect(object["htmlContent"]?.string == "<p>hello world</p>")
        #expect(object["searchText"]?.string == "hello search")
    }

    // MARK: - 3: hype_get_stack_document masks every secure field

    @Test("3: hype_get_stack_document masks the secure part and leaves the non-secure sibling verbatim")
    func getStackDocumentMasksSecurePartLeavesSiblingVerbatim() async throws {
        var (document, cardId) = try makeDocumentAndCardId()
        let secure = makeSecureFieldPart(cardId: cardId)
        var sibling = Part(partType: .field, cardId: cardId, name: "notes", left: 0, top: 60, width: 200, height: 30)
        sibling.textContent = "public note"
        document.addPart(secure)
        document.addPart(sibling)
        let backend = HypeMCPDocumentBackend(document: document, currentCardId: cardId)

        let result = await backend.callTool(name: "hype_get_stack_document", arguments: [:])
        let parts = try #require(result.object?["document"]?.object?["parts"]?.array)
        let securePartJSON = try #require(parts.first { $0.object?["id"]?.string == secure.id.uuidString }?.object)
        let siblingPartJSON = try #require(parts.first { $0.object?["id"]?.string == sibling.id.uuidString }?.object)

        #expect(securePartJSON["textContent"]?.string == Self.secureFieldMask)
        #expect(securePartJSON["htmlContent"]?.string == Self.secureFieldMask)
        #expect(securePartJSON["searchText"]?.string == Self.secureFieldMask)
        #expect(siblingPartJSON["textContent"]?.string == "public note")

        let blob = result.jsonString(pretty: false)
        #expect(!blob.contains(secure.textContent))
        #expect(!blob.contains(secure.htmlContent))
        #expect(!blob.contains(secure.searchText))
    }

    // MARK: - 4: readResource document — distinct entry point, same assertions

    @Test("4: readResource hype://stack/{id}/document masks the same as hype_get_stack_document")
    func readResourceDocumentMasksSecurePart() async throws {
        var (document, cardId) = try makeDocumentAndCardId()
        let secure = makeSecureFieldPart(cardId: cardId)
        document.addPart(secure)
        let backend = HypeMCPDocumentBackend(document: document, currentCardId: cardId)
        let stackId = backend.document.stack.id.uuidString

        let result = await backend.readResource(uri: "hype://stack/\(stackId)/document")
        let parts = try #require(result.object?["document"]?.object?["parts"]?.array)
        let securePartJSON = try #require(parts.first { $0.object?["id"]?.string == secure.id.uuidString }?.object)

        #expect(securePartJSON["textContent"]?.string == Self.secureFieldMask)
        #expect(securePartJSON["htmlContent"]?.string == Self.secureFieldMask)
        #expect(securePartJSON["searchText"]?.string == Self.secureFieldMask)

        let blob = result.jsonString(pretty: false)
        #expect(!blob.contains(secure.textContent))
        #expect(!blob.contains(secure.htmlContent))
        #expect(!blob.contains(secure.searchText))
    }

    // MARK: - 5: readResource part/{id}/full

    @Test("5: readResource hype://stack/{id}/part/{partId}/full masks the secure part")
    func readResourcePartFullMasksSecurePart() async throws {
        var (document, cardId) = try makeDocumentAndCardId()
        let secure = makeSecureFieldPart(cardId: cardId)
        document.addPart(secure)
        let backend = HypeMCPDocumentBackend(document: document, currentCardId: cardId)
        let stackId = backend.document.stack.id.uuidString

        let result = await backend.readResource(uri: "hype://stack/\(stackId)/part/\(secure.id.uuidString)/full")
        let object = try #require(result.object?["object"]?.object)
        #expect(object["textContent"]?.string == Self.secureFieldMask)
        #expect(object["htmlContent"]?.string == Self.secureFieldMask)
        #expect(object["searchText"]?.string == Self.secureFieldMask)

        let blob = result.jsonString(pretty: false)
        #expect(!blob.contains(secure.textContent))
        #expect(!blob.contains(secure.htmlContent))
        #expect(!blob.contains(secure.searchText))
    }

    // MARK: - 6: hype_set_script echo masked, stored plaintext + new script

    @Test("6: hype_set_script on a secure field echoes masked but stores plaintext and the new script")
    func setScriptOnSecureFieldEchoesMasked() async throws {
        var (document, cardId) = try makeDocumentAndCardId()
        let secure = makeSecureFieldPart(cardId: cardId)
        document.addPart(secure)
        let backend = HypeMCPDocumentBackend(document: document, currentCardId: cardId)

        let result = await backend.callTool(
            name: "hype_set_script",
            arguments: [
                "object_type": .string("part"),
                "id_or_name": .string("pwd"),
                "script": .string("on mouseUp\n  play \"boing\"\nend mouseUp")
            ]
        )

        let object = try #require(result.object?["object"]?.object)
        #expect(object["textContent"]?.string == Self.secureFieldMask)
        #expect(object["htmlContent"]?.string == Self.secureFieldMask)
        #expect(object["searchText"]?.string == Self.secureFieldMask)

        let stored = try #require(backend.document.parts.first { $0.id == secure.id })
        #expect(stored.textContent == secure.textContent)
        #expect(stored.htmlContent == secure.htmlContent)
        #expect(stored.searchText == secure.searchText)
        #expect(stored.script.contains("play \"boing\""))
    }

    // MARK: - 7: GET -> edit geometry -> REPLACE preserves all three secrets

    @Test("7: GET then edit geometry then hype_replace_part preserves all three stored secrets")
    func replacePartRoundTripPreservesAllThreeSecrets() async throws {
        var (document, cardId) = try makeDocumentAndCardId()
        let original = avoidingKnownZeroOrOneNumericBridgingDefaults(makeSecureFieldPart(cardId: cardId))
        document.addPart(original)
        let backend = HypeMCPDocumentBackend(document: document, currentCardId: cardId)

        let getResult = await backend.callTool(
            name: "hype_get_object",
            arguments: ["object_type": .string("part"), "id_or_name": .string(original.id.uuidString)]
        )
        let maskedObjectValue = try #require(getResult.object?["object"])
        var edited = try JSONDecoder().decode(Part.self, from: JSONEncoder().encode(maskedObjectValue))
        edited.left = 321
        edited.top = 654

        let replaceData = try JSONEncoder().encode(edited)
        let replaceJSON = try #require(String(data: replaceData, encoding: .utf8))
        let replaceResult = await backend.callTool(
            name: "hype_replace_part",
            arguments: ["part_json": .string(replaceJSON)]
        )

        #expect(replaceResult.object?["preservedSecureText"]?.bool == true)
        #expect(replaceResult.object?["result"]?.string?.contains("Preserved stored secure-field text") == true)
        let echoed = try #require(replaceResult.object?["object"]?.object)
        #expect(echoed["textContent"]?.string == Self.secureFieldMask)
        #expect(echoed["htmlContent"]?.string == Self.secureFieldMask)
        #expect(echoed["searchText"]?.string == Self.secureFieldMask)

        let stored = try #require(backend.document.parts.first { $0.id == original.id })
        #expect(stored.textContent == original.textContent)
        #expect(stored.htmlContent == original.htmlContent)
        #expect(stored.searchText == original.searchText)
        #expect(stored.left == 321)
        #expect(stored.top == 654)
    }

    // MARK: - 7b: independent-sentinel round-trip

    @Test("7b: a sentinel in exactly one property never clobbers the other two")
    func independentSentinelPreservesOnlyMatchingProperty() async throws {
        for maskedProperty in ["textContent", "htmlContent", "searchText"] {
            var (document, cardId) = try makeDocumentAndCardId()
            let original = makeSecureFieldPart(
                cardId: cardId,
                textContent: "secret-text-\(maskedProperty)",
                htmlContent: "secret-html-\(maskedProperty)",
                searchText: "secret-search-\(maskedProperty)"
            )
            document.addPart(original)
            let backend = HypeMCPDocumentBackend(document: document, currentCardId: cardId)

            let newTextContent = "new-text-\(maskedProperty)"
            let newHtmlContent = "new-html-\(maskedProperty)"
            let newSearchText = "new-search-\(maskedProperty)"
            var replacement = original
            replacement.textContent = maskedProperty == "textContent" ? Self.secureFieldMask : newTextContent
            replacement.htmlContent = maskedProperty == "htmlContent" ? Self.secureFieldMask : newHtmlContent
            replacement.searchText = maskedProperty == "searchText" ? Self.secureFieldMask : newSearchText

            let data = try JSONEncoder().encode(replacement)
            let json = try #require(String(data: data, encoding: .utf8))
            let result = await backend.callTool(name: "hype_replace_part", arguments: ["part_json": .string(json)])

            #expect(result.object?["preservedSecureText"]?.bool == true, "property under test: \(maskedProperty)")
            let stored = try #require(backend.document.parts.first { $0.id == original.id })
            #expect(stored.textContent == (maskedProperty == "textContent" ? original.textContent : newTextContent))
            #expect(stored.htmlContent == (maskedProperty == "htmlContent" ? original.htmlContent : newHtmlContent))
            #expect(stored.searchText == (maskedProperty == "searchText" ? original.searchText : newSearchText))
        }
    }

    // MARK: - 7c: two-of-three-sentinel round-trip

    @Test("7c: a sentinel in exactly two properties preserves both independently while the third's real new value writes through")
    func twoOfThreeSentinelsPreserveIndependently() async throws {
        let allProperties = ["textContent", "htmlContent", "searchText"]
        for unmaskedProperty in allProperties {
            var (document, cardId) = try makeDocumentAndCardId()
            let original = makeSecureFieldPart(
                cardId: cardId,
                textContent: "secret-text-\(unmaskedProperty)",
                htmlContent: "secret-html-\(unmaskedProperty)",
                searchText: "secret-search-\(unmaskedProperty)"
            )
            document.addPart(original)
            let backend = HypeMCPDocumentBackend(document: document, currentCardId: cardId)

            let newValueForUnmasked = "new-\(unmaskedProperty)-value"
            var replacement = original
            replacement.textContent = unmaskedProperty == "textContent" ? newValueForUnmasked : Self.secureFieldMask
            replacement.htmlContent = unmaskedProperty == "htmlContent" ? newValueForUnmasked : Self.secureFieldMask
            replacement.searchText = unmaskedProperty == "searchText" ? newValueForUnmasked : Self.secureFieldMask

            let data = try JSONEncoder().encode(replacement)
            let json = try #require(String(data: data, encoding: .utf8))
            let result = await backend.callTool(name: "hype_replace_part", arguments: ["part_json": .string(json)])

            #expect(result.object?["preservedSecureText"]?.bool == true, "unmasked property under test: \(unmaskedProperty)")
            let stored = try #require(backend.document.parts.first { $0.id == original.id })
            #expect(stored.textContent == (unmaskedProperty == "textContent" ? newValueForUnmasked : original.textContent))
            #expect(stored.htmlContent == (unmaskedProperty == "htmlContent" ? newValueForUnmasked : original.htmlContent))
            #expect(stored.searchText == (unmaskedProperty == "searchText" ? newValueForUnmasked : original.searchText))
        }
    }

    // MARK: - 7d: empty secure field masks and round-trips to empty, never the sentinel

    @Test("7d: an empty secure field is masked on GET and round-trips back to empty strings, not the literal sentinel")
    func emptySecureFieldMasksAndRoundTripsToEmptyStrings() async throws {
        var (document, cardId) = try makeDocumentAndCardId()
        let original = makeSecureFieldPart(cardId: cardId, textContent: "", htmlContent: "", searchText: "")
        document.addPart(original)
        let backend = HypeMCPDocumentBackend(document: document, currentCardId: cardId)

        let getResult = await backend.callTool(
            name: "hype_get_object",
            arguments: ["object_type": .string("part"), "id_or_name": .string(original.id.uuidString)]
        )
        let object = try #require(getResult.object?["object"]?.object)
        #expect(object["textContent"]?.string == Self.secureFieldMask)
        #expect(object["htmlContent"]?.string == Self.secureFieldMask)
        #expect(object["searchText"]?.string == Self.secureFieldMask)

        var replacement = original
        replacement.textContent = Self.secureFieldMask
        replacement.htmlContent = Self.secureFieldMask
        replacement.searchText = Self.secureFieldMask
        replacement.left = 99 // a trivial edit alongside the sentinel round trip
        let data = try JSONEncoder().encode(replacement)
        let json = try #require(String(data: data, encoding: .utf8))
        let replaceResult = await backend.callTool(name: "hype_replace_part", arguments: ["part_json": .string(json)])

        #expect(replaceResult.object?["preservedSecureText"]?.bool == true)
        let stored = try #require(backend.document.parts.first { $0.id == original.id })
        #expect(stored.textContent == "")
        #expect(stored.htmlContent == "")
        #expect(stored.searchText == "")
        #expect(stored.left == 99)
    }

    // MARK: - 8: explicit new plaintext writes through

    @Test("8: a new plaintext value on a secure field writes through with no preservedSecureText")
    func explicitPlaintextWritesThroughOnSecureField() async throws {
        var (document, cardId) = try makeDocumentAndCardId()
        let original = makeSecureFieldPart(cardId: cardId)
        document.addPart(original)
        let backend = HypeMCPDocumentBackend(document: document, currentCardId: cardId)

        var replacement = original
        replacement.textContent = "newSecret"
        let data = try JSONEncoder().encode(replacement)
        let json = try #require(String(data: data, encoding: .utf8))
        let result = await backend.callTool(name: "hype_replace_part", arguments: ["part_json": .string(json)])

        #expect(result.object?["preservedSecureText"] == nil)
        #expect(backend.document.parts.first { $0.id == original.id }?.textContent == "newSecret")
    }

    // MARK: - 9: literal sentinel on a plain field writes through

    @Test("9: a literal (masked) value on a rectangle field writes through verbatim")
    func literalSentinelOnPlainFieldWritesThrough() async throws {
        var (document, cardId) = try makeDocumentAndCardId()
        var original = Part(partType: .field, cardId: cardId, name: "notes", left: 0, top: 0, width: 200, height: 30)
        original.fieldStyle = .rectangle
        original.textContent = "hello world"
        document.addPart(original)
        let backend = HypeMCPDocumentBackend(document: document, currentCardId: cardId)

        var replacement = original
        replacement.textContent = Self.secureFieldMask
        let data = try JSONEncoder().encode(replacement)
        let json = try #require(String(data: data, encoding: .utf8))
        let result = await backend.callTool(name: "hype_replace_part", arguments: ["part_json": .string(json)])

        #expect(result.object?["preservedSecureText"] == nil)
        #expect(backend.document.parts.first { $0.id == original.id }?.textContent == Self.secureFieldMask)
    }

    // MARK: - 10: within-field style flip with sentinel (accepted declassification)

    @Test("10: fieldStyle flip to non-secure with sentinel, still a field, preserves text and applies the style")
    func styleFlipWithSentinelStillFieldPreservesText() async throws {
        var (document, cardId) = try makeDocumentAndCardId()
        let original = makeSecureFieldPart(cardId: cardId)
        document.addPart(original)
        let backend = HypeMCPDocumentBackend(document: document, currentCardId: cardId)

        var replacement = original
        replacement.fieldStyle = .rectangle
        replacement.textContent = Self.secureFieldMask
        replacement.htmlContent = Self.secureFieldMask
        replacement.searchText = Self.secureFieldMask
        let data = try JSONEncoder().encode(replacement)
        let json = try #require(String(data: data, encoding: .utf8))
        let result = await backend.callTool(name: "hype_replace_part", arguments: ["part_json": .string(json)])

        #expect(result.object?["preservedSecureText"]?.bool == true)
        let stored = try #require(backend.document.parts.first { $0.id == original.id })
        #expect(stored.fieldStyle == .rectangle)
        #expect(stored.textContent == original.textContent)
        #expect(stored.htmlContent == original.htmlContent)
        #expect(stored.searchText == original.searchText)

        // The next GET returns plaintext — the accepted within-field
        // declassification, already reachable via curated
        // `set_part_property fieldStyle` + `get_part_property text`.
        let getResult = await backend.callTool(
            name: "hype_get_object",
            arguments: ["object_type": .string("part"), "id_or_name": .string(original.id.uuidString)]
        )
        #expect(getResult.object?["object"]?.object?["textContent"]?.string == original.textContent)
    }

    // MARK: - 10b: partType change away from .field fails closed

    @Test("10b: converting a secure field to a button does not restore the secret (fail closed)")
    func partTypeChangeToButtonFailsClosed() async throws {
        var (document, cardId) = try makeDocumentAndCardId()
        let original = makeSecureFieldPart(cardId: cardId)
        document.addPart(original)
        let backend = HypeMCPDocumentBackend(document: document, currentCardId: cardId)

        var replacement = original
        replacement.partType = .button
        replacement.textContent = Self.secureFieldMask
        let data = try JSONEncoder().encode(replacement)
        let json = try #require(String(data: data, encoding: .utf8))
        let result = await backend.callTool(name: "hype_replace_part", arguments: ["part_json": .string(json)])

        #expect(result.object?["preservedSecureText"] == nil)
        let stored = try #require(backend.document.parts.first { $0.id == original.id })
        #expect(stored.partType == .button)
        #expect(stored.textContent == Self.secureFieldMask)
        #expect(stored.textContent != original.textContent)

        let documentData = try JSONEncoder().encode(backend.document)
        let documentText = try #require(String(data: documentData, encoding: .utf8))
        #expect(!documentText.contains(original.textContent))

        let getResult = await backend.callTool(
            name: "hype_get_object",
            arguments: ["object_type": .string("part"), "id_or_name": .string(original.id.uuidString)]
        )
        #expect(getResult.object?["object"]?.object?["textContent"]?.string == Self.secureFieldMask)
        #expect(getResult.jsonString(pretty: false).contains(original.textContent) == false)
    }

    // MARK: - 11: masking never mutates the stored document

    @Test("11: masking never mutates the stored document across every read path")
    func maskingNeverMutatesStoredDocument() async throws {
        var (document, cardId) = try makeDocumentAndCardId()
        let original = makeSecureFieldPart(cardId: cardId)
        document.addPart(original)
        let backend = HypeMCPDocumentBackend(document: document, currentCardId: cardId)
        let stackId = backend.document.stack.id.uuidString

        _ = await backend.callTool(
            name: "hype_get_object",
            arguments: ["object_type": .string("part"), "id_or_name": .string(original.id.uuidString)]
        )
        _ = await backend.callTool(name: "hype_get_stack_document", arguments: [:])
        _ = await backend.readResource(uri: "hype://stack/\(stackId)/document")
        _ = await backend.readResource(uri: "hype://stack/\(stackId)/part/\(original.id.uuidString)/full")

        let stored = try #require(backend.document.parts.first { $0.id == original.id })
        #expect(stored.textContent == original.textContent)
        #expect(stored.htmlContent == original.htmlContent)
        #expect(stored.searchText == original.searchText)
    }

    // MARK: - No-op round-trip (unedited masked JSON restores the original exactly)

    @Test("no-op round-trip: replace with the unedited masked JSON preserves the original part exactly")
    func noOpRoundTripPreservesOriginalPartExactly() async throws {
        var (document, cardId) = try makeDocumentAndCardId()
        let original = avoidingKnownZeroOrOneNumericBridgingDefaults(makeSecureFieldPart(cardId: cardId))
        document.addPart(original)
        let backend = HypeMCPDocumentBackend(document: document, currentCardId: cardId)

        let getResult = await backend.callTool(
            name: "hype_get_object",
            arguments: ["object_type": .string("part"), "id_or_name": .string(original.id.uuidString)]
        )
        let maskedObjectValue = try #require(getResult.object?["object"])
        let maskedData = try JSONEncoder().encode(maskedObjectValue)
        let maskedJSON = try #require(String(data: maskedData, encoding: .utf8))

        let replaceResult = await backend.callTool(
            name: "hype_replace_part",
            arguments: ["part_json": .string(maskedJSON)]
        )
        #expect(replaceResult.object?["preservedSecureText"]?.bool == true)

        let canonicalEncoder = JSONEncoder()
        canonicalEncoder.outputFormatting = [.sortedKeys]
        let originalCanonicalJSON = try canonicalEncoder.encode(original)
        let stored = try #require(backend.document.parts.first { $0.id == original.id })
        let storedCanonicalJSON = try canonicalEncoder.encode(stored)
        #expect(originalCanonicalJSON == storedCanonicalJSON)

        // Idempotence: reading the now-stored part back out is stable.
        let secondGetResult = await backend.callTool(
            name: "hype_get_object",
            arguments: ["object_type": .string("part"), "id_or_name": .string(original.id.uuidString)]
        )
        #expect(secondGetResult.jsonString(pretty: false) == getResult.jsonString(pretty: false))
    }

    // MARK: - S1: classification completeness

    @Test("S1: every Part String stored property is classified MASKED or EXEMPT")
    func structuralClassificationCompleteness() {
        let part = Part(partType: .field, name: "s1-probe")
        let discovered = Self.stringPropertyNames(of: part)
        let classified = Self.maskedProperties.union(Self.exemptProperties)

        #expect(discovered == classified)
        #expect(Self.maskedProperties.isDisjoint(with: Self.exemptProperties))
    }

    // MARK: - S1 hardening: nil-defaulted `String?` future properties (Security (code) advisory #3)

    /// `Part` has no optional-`String` property today, so this probe struct
    /// stands in for a hypothetical future one to pin `stringPropertyNames`'s
    /// hardened detection directly, independent of `Part`'s actual shape.
    private struct OptionalStringProbe {
        var plainString: String = "already-detected-before-hardening"
        var optionalStringNilDefault: String?
        var optionalStringPopulatedDefault: String? = "populated"
        var plainInt: Int = 0
        var optionalInt: Int?
    }

    @Test("S1 hardening: a nil-defaulted String? stored property is detected, not silently skipped")
    func nilDefaultedOptionalStringPropertyIsDetected() {
        let probe = OptionalStringProbe()

        // Sanity: pin the exact gap being hardened against. A direct
        // `is String` cast on the boxed child value sees straight through a
        // *non-nil* `String?` (Swift's `Any`-cast machinery auto-unwraps one
        // Optional level) but has nothing to unwrap for a `nil` one, so the
        // naive check alone would have silently dropped
        // `optionalStringNilDefault` from S1's discovered set — the exact
        // shape Security flagged.
        let naiveDiscovered = Set(Mirror(reflecting: probe).children.compactMap { child -> String? in
            child.value is String ? child.label : nil
        })
        #expect(naiveDiscovered.contains("optionalStringPopulatedDefault"))
        #expect(!naiveDiscovered.contains("optionalStringNilDefault"))

        let hardened = Self.stringPropertyNames(of: probe)
        #expect(hardened.contains("plainString"))
        #expect(hardened.contains("optionalStringNilDefault"), "a future nil-defaulted Part String? must be force-classified, not silently skipped")
        #expect(hardened.contains("optionalStringPopulatedDefault"))
        #expect(!hardened.contains("plainInt"))
        #expect(!hardened.contains("optionalInt"))
        #expect(hardened == ["plainString", "optionalStringNilDefault", "optionalStringPopulatedDefault"])
    }

    // MARK: - S2: structural leak sweep

    @Test("S2: a nonce seeded into every String property leaks only through EXEMPT properties")
    func structuralLeakSweep() async throws {
        var (document, cardId) = try makeDocumentAndCardId()

        // (a) Build a secure part and encode/deserialize to a mutable dictionary.
        let seedPart = makeSecureFieldPart(cardId: cardId)
        let discovered = Self.stringPropertyNames(of: seedPart)
        var dict = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(seedPart)) as? [String: Any]
        )

        // (b) Seed a pairwise-distinct nonce into every discovered String
        // property; reserialize and decode back to Part through the
        // tolerant decoder. Property names make every nonce pairwise
        // distinct and non-substring of another by construction.
        var expectedNonce: [String: String] = [:]
        for propertyName in discovered {
            let nonce = "leak-\(propertyName)-c0ffee1"
            dict[propertyName] = nonce
            expectedNonce[propertyName] = nonce
        }
        let mutatedData = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(Part.self, from: mutatedData)
        #expect(decoded.partType == .field)
        #expect(decoded.fieldStyle == .secure)

        // (c) Ground truth: re-read every String property from the DECODED
        // part via Mirror, so the sweep can never silently lose its teeth
        // if a decode-time sanitizer altered a value.
        let decodedValues = Self.stringPropertyValues(of: decoded)
        for maskedProperty in Self.maskedProperties {
            let nonce = try #require(expectedNonce[maskedProperty])
            #expect(decodedValues[maskedProperty]?.contains(nonce) == true)
        }

        // (d) Install the seeded part and sweep every covered read path.
        document.addPart(decoded)
        let backend = HypeMCPDocumentBackend(document: document, currentCardId: cardId)

        let getObjectResult = await backend.callTool(
            name: "hype_get_object",
            arguments: ["object_type": .string("part"), "id_or_name": .string(decoded.id.uuidString)]
        )
        let getStackDocumentResult = await backend.callTool(name: "hype_get_stack_document", arguments: [:])

        for response in [getObjectResult, getStackDocumentResult] {
            let blob = response.jsonString(pretty: false)

            // (i) Every MASKED property's post-decode value is absent.
            for maskedProperty in Self.maskedProperties {
                let nonce = try #require(expectedNonce[maskedProperty])
                #expect(!blob.contains(nonce), "MASKED nonce for \(maskedProperty) leaked")
            }

            // (ii) The sentinel appears at least three times (once per
            // masked property).
            #expect(Self.occurrenceCount(of: Self.secureFieldMask, in: blob) >= 3)

            // (iii) Every EXEMPT property whose post-decode value still
            // carries its nonce is present verbatim — no over-masking.
            for exemptProperty in Self.exemptProperties {
                guard let value = decodedValues[exemptProperty], value.contains("leak-") else { continue }
                #expect(blob.contains(value), "EXEMPT property \(exemptProperty) was over-masked")
            }
        }
    }

    // MARK: - Property test (Tester's pass): generated multi-part leak sweep

    /// Metamorphic/property pass called out in design.md's "Invariants and
    /// metamorphic relations" section (the structural S1/S2 tests above
    /// cover ONE seeded part; this covers many, across every `FieldStyle`).
    /// Builds a deterministic, seeded (index-derived, no `Date`/randomness —
    /// reproducible on every run) 30-part document mixing every
    /// `FieldStyle`: non-secure parts each carry unique verbatim text in all
    /// three field-body properties, secure parts each carry unique nonces in
    /// all three MASKED properties. Sweeps every part-bearing read path —
    /// per-part `hype_get_object` for every generated part, plus the two
    /// full-document paths (`hype_get_stack_document` and `readResource`
    /// `.../document`) — and asserts the invariant holds across the whole
    /// set: no secure nonce (from ANY of the three masked properties, on ANY
    /// secure part) ever leaks; every non-secure part's text survives
    /// verbatim (no over-masking); `(masked)` occurs at least 3× the secure
    /// part count on the full-document paths.
    @Test("property: a generated multi-part document leaks no secure nonce, across every FieldStyle, on every masked read path")
    func generatedMultiPartDocumentLeakSweep() async throws {
        var (document, cardId) = try makeDocumentAndCardId()

        let styles = FieldStyle.allCases
        let partCount = 30
        var parts: [Part] = []
        var secureNonces: [String] = []
        var nonSecureTexts: [String] = []

        for index in 0..<partCount {
            let style = styles[index % styles.count]
            var part = Part(
                partType: .field,
                cardId: cardId,
                name: "gen-part-\(index)-\(style.rawValue)",
                left: Double(index) * 10,
                top: Double(index) * 6,
                width: 150,
                height: 24
            )
            part.fieldStyle = style
            if style == .secure {
                let textNonce = "secret-text-\(index)-c0ffee2"
                let htmlNonce = "secret-html-\(index)-c0ffee2"
                let searchNonce = "secret-search-\(index)-c0ffee2"
                part.textContent = textNonce
                part.htmlContent = htmlNonce
                part.searchText = searchNonce
                secureNonces.append(contentsOf: [textNonce, htmlNonce, searchNonce])
            } else {
                // Deliberately slash-free: Foundation's JSONEncoder escapes
                // "/" as "\/", so raw-blob substring search (below) for a
                // string containing "/" would spuriously fail against the
                // serialized-and-escaped form — a JSON-encoding quirk
                // unrelated to masking. Matches the slash-free nonce style
                // S2 already uses for the same reason.
                let publicText = "public-text-\(index)-\(style.rawValue)"
                let publicHTML = "public-html-\(index)-\(style.rawValue)"
                let publicSearch = "public-search-\(index)-\(style.rawValue)"
                part.textContent = publicText
                part.htmlContent = publicHTML
                part.searchText = publicSearch
                nonSecureTexts.append(contentsOf: [publicText, publicHTML, publicSearch])
            }
            parts.append(part)
        }
        for part in parts { document.addPart(part) }

        let secureCount = parts.filter { $0.fieldStyle == .secure }.count
        #expect(secureCount > 0)
        #expect(secureCount < parts.count, "sanity: the generator must mix secure and non-secure styles")

        let backend = HypeMCPDocumentBackend(document: document, currentCardId: cardId)

        // Sweep every part-bearing read path: per-part hype_get_object for
        // each generated part, plus the two full-document paths.
        var perPartBlobs: [String] = []
        for part in parts {
            let result = await backend.callTool(
                name: "hype_get_object",
                arguments: ["object_type": .string("part"), "id_or_name": .string(part.id.uuidString)]
            )
            perPartBlobs.append(result.jsonString(pretty: false))
        }
        let stackId = backend.document.stack.id.uuidString
        let stackDocumentBlob = await backend.callTool(name: "hype_get_stack_document", arguments: [:]).jsonString(pretty: false)
        let resourceDocumentBlob = await backend.readResource(uri: "hype://stack/\(stackId)/document").jsonString(pretty: false)
        let fullDocumentBlobs = [stackDocumentBlob, resourceDocumentBlob]

        // (i) No secure nonce leaks through ANY read path, single-part or
        // whole-document.
        for blob in perPartBlobs + fullDocumentBlobs {
            for nonce in secureNonces {
                #expect(!blob.contains(nonce), "secure nonce leaked: \(nonce)")
            }
        }

        // (ii) Every non-secure part's verbatim text survives on the
        // full-document paths — no over-masking across the mixed-style set.
        for blob in fullDocumentBlobs {
            for text in nonSecureTexts {
                #expect(blob.contains(text), "non-secure text missing (over-masked?): \(text)")
            }
            #expect(Self.occurrenceCount(of: Self.secureFieldMask, in: blob) >= 3 * secureCount)
        }
    }

    // MARK: - Mirror-based structural helpers (the single audit point, alongside the sets above)

    /// Discovers `Part`'s `String` stored properties via reflection, not a
    /// hand-maintained inventory. `Part` is a struct of stored `var`s with
    /// no explicit `CodingKeys` and no custom `encode(to:)`, so Mirror
    /// labels equal the synthesized JSON keys.
    ///
    /// Hardened (Security (code) advisory #3) to also detect `String?`
    /// (optional) stored properties regardless of whether their current
    /// instance value is `nil`: Swift's `as? String` cast on a boxed `Any`
    /// happens to auto-unwrap one level of a *non-nil* `Optional<String>`
    /// (so `child.value is String` already reports `true` for those), but a
    /// `nil` optional has nothing to unwrap and is invisible to that direct
    /// check alone. A future `Part` property declared `var foo: String?`
    /// would very likely default to `nil` — the idiomatic default for an
    /// optional — so without the fallback below it could silently miss S1's
    /// classification gate entirely instead of failing it until classified.
    /// The fallback takes a `Mirror` of the child's own boxed value and
    /// checks its `displayStyle`/`subjectType` for exactly
    /// `Optional<String>`. See `nilDefaultedOptionalStringPropertyIsDetected`
    /// for a pinned demonstration against a local probe struct (`Part` has
    /// no optional-`String` property today to exercise this against
    /// directly).
    private static func stringPropertyNames(of value: Any) -> Set<String> {
        Set(Mirror(reflecting: value).children.compactMap { child -> String? in
            guard let label = child.label else { return nil }
            if child.value is String { return label }
            let childMirror = Mirror(reflecting: child.value)
            if childMirror.displayStyle == .optional, "\(childMirror.subjectType)" == "Optional<String>" {
                return label
            }
            return nil
        })
    }

    /// Reads back every `String` stored property's current value via Mirror.
    private static func stringPropertyValues(of part: Part) -> [String: String] {
        var values: [String: String] = [:]
        for child in Mirror(reflecting: part).children {
            guard let label = child.label, let value = child.value as? String else { continue }
            values[label] = value
        }
        return values
    }

    private static func occurrenceCount(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let range = haystack.range(of: needle, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<haystack.endIndex
        }
        return count
    }
}

private extension HypeMCPJSONValue {
    var object: [String: HypeMCPJSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    var array: [HypeMCPJSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }
}
