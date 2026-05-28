import Testing
import Foundation
@testable import HypeCore

/// Comprehensive tests for `StackScriptAttributionSync` — covers Security
/// Findings 3 and 10, plus all sentinel block management behaviors.
@Suite("StackScriptAttributionSync — sanitization and block management")
struct StackScriptAttributionSyncTests {

    // MARK: - Helpers

    private func makeAsset(
        name: String,
        creator: String = "Test Creator",
        providerName: String = "Test Provider",
        licenseId: String = "cc-by-4.0",
        sourceURL: String = "https://example.com/asset"
    ) -> Asset {
        let license = AssetLicense(
            name: licenseId.uppercased(),
            identifier: licenseId,
            url: "https://creativecommons.org/licenses/by/4.0/",
            isShareable: true
        )
        let attribution = AssetAttribution(
            creator: creator,
            title: name,
            sourceURL: sourceURL,
            downloadURL: "https://example.com/download/\(name)",
            providerName: providerName,
            providerIdentifier: providerName.lowercased()
        )
        let provenance = AssetProvenance(
            origin: .webSearch,
            searchQuery: "test query",
            license: license,
            attribution: attribution,
            importedAt: Date()
        )
        return Asset(
            id: UUID(),
            name: name,
            kind: .imageTexture,
            mimeType: "image/png",
            data: Data(),
            width: 100,
            height: 100,
            tags: [],
            slices: [],
            animationClips: [],
            tileWidth: 0,
            tileHeight: 0,
            tileColumns: 0,
            tileRows: 0,
            provenance: provenance
        )
    }

    private func makeNonWebAsset(name: String) -> Asset {
        return Asset(
            id: UUID(),
            name: name,
            kind: .imageTexture,
            mimeType: "image/png",
            data: Data(),
            width: 100,
            height: 100,
            tags: [],
            slices: [],
            animationClips: [],
            tileWidth: 0,
            tileHeight: 0,
            tileColumns: 0,
            tileRows: 0,
            provenance: AssetProvenance(origin: .userImport)
        )
    }

    // MARK: - sanitizeField: line terminator collapse

    @Test("LF collapses to space")
    func lfCollapsesToSpace() {
        let result = StackScriptAttributionSync.sanitizeField("hello\nworld")
        #expect(result == "hello world")
    }

    @Test("CR collapses to space")
    func crCollapsesToSpace() {
        let result = StackScriptAttributionSync.sanitizeField("hello\rworld")
        #expect(result == "hello world")
    }

    @Test("CRLF pair collapses to a single space")
    func crlfCollapsesToSingleSpace() {
        let result = StackScriptAttributionSync.sanitizeField("hello\r\nworld")
        #expect(result == "hello world")
    }

    @Test("U+2028 (LINE SEPARATOR) collapses to space")
    func lineSeparatorCollapsesToSpace() {
        let result = StackScriptAttributionSync.sanitizeField("hello\u{2028}world")
        #expect(result == "hello world")
    }

    @Test("U+2029 (PARAGRAPH SEPARATOR) collapses to space")
    func paragraphSeparatorCollapsesToSpace() {
        let result = StackScriptAttributionSync.sanitizeField("hello\u{2029}world")
        #expect(result == "hello world")
    }

    @Test("U+000B (VERTICAL TAB) collapses to space")
    func verticalTabCollapsesToSpace() {
        let result = StackScriptAttributionSync.sanitizeField("hello\u{000B}world")
        #expect(result == "hello world")
    }

    @Test("U+000C (FORM FEED) collapses to space")
    func formFeedCollapsesToSpace() {
        let result = StackScriptAttributionSync.sanitizeField("hello\u{000C}world")
        #expect(result == "hello world")
    }

    // MARK: - sanitizeField: em-dash replacement

    @Test("double-dash (--) is replaced with em-dash U+2014")
    func doubleDashReplacedWithEmDash() {
        let result = StackScriptAttributionSync.sanitizeField("hello--world")
        #expect(result == "hello\u{2014}world")
    }

    @Test("single hyphen is preserved")
    func singleHyphenPreserved() {
        let result = StackScriptAttributionSync.sanitizeField("self-portrait")
        #expect(result == "self-portrait")
    }

    @Test("triple dash becomes em-dash + hyphen")
    func tripleDashBecomesEmDashHyphen() {
        let result = StackScriptAttributionSync.sanitizeField("---")
        // First two dashes → em-dash, third dash → single hyphen
        #expect(result == "\u{2014}-")
    }

    // MARK: - sanitizeField: Bidi control stripping

    @Test("U+202A (LEFT-TO-RIGHT EMBEDDING) is stripped")
    func ltrEmbeddingStripped() {
        let result = StackScriptAttributionSync.sanitizeField("hello\u{202A}world")
        #expect(result == "helloworld")
    }

    @Test("U+202B (RIGHT-TO-LEFT EMBEDDING) is stripped")
    func rtlEmbeddingStripped() {
        let result = StackScriptAttributionSync.sanitizeField("hello\u{202B}world")
        #expect(result == "helloworld")
    }

    @Test("U+202C (POP DIRECTIONAL FORMATTING) is stripped")
    func popDirectionalFormattingStripped() {
        let result = StackScriptAttributionSync.sanitizeField("hello\u{202C}world")
        #expect(result == "helloworld")
    }

    @Test("U+202D (LEFT-TO-RIGHT OVERRIDE) is stripped")
    func ltrOverrideStripped() {
        let result = StackScriptAttributionSync.sanitizeField("hello\u{202D}world")
        #expect(result == "helloworld")
    }

    @Test("U+202E (RIGHT-TO-LEFT OVERRIDE) is stripped")
    func rtlOverrideStripped() {
        let result = StackScriptAttributionSync.sanitizeField("hello\u{202E}world")
        #expect(result == "helloworld")
    }

    @Test("U+2066 (LEFT-TO-RIGHT ISOLATE) is stripped")
    func ltrIsolateStripped() {
        let result = StackScriptAttributionSync.sanitizeField("hello\u{2066}world")
        #expect(result == "helloworld")
    }

    @Test("U+2069 (POP DIRECTIONAL ISOLATE) is stripped")
    func popDirectionalIsolateStripped() {
        let result = StackScriptAttributionSync.sanitizeField("hello\u{2069}world")
        #expect(result == "helloworld")
    }

    // MARK: - sanitizeField: Zero-width stripping

    @Test("U+200B (ZERO-WIDTH SPACE) is stripped")
    func zeroWidthSpaceStripped() {
        let result = StackScriptAttributionSync.sanitizeField("hello\u{200B}world")
        #expect(result == "helloworld")
    }

    @Test("U+200C (ZERO-WIDTH NON-JOINER) is stripped")
    func zeroWidthNonJoinerStripped() {
        let result = StackScriptAttributionSync.sanitizeField("hello\u{200C}world")
        #expect(result == "helloworld")
    }

    @Test("U+200D (ZERO-WIDTH JOINER) is stripped")
    func zeroWidthJoinerStripped() {
        let result = StackScriptAttributionSync.sanitizeField("hello\u{200D}world")
        #expect(result == "helloworld")
    }

    @Test("U+200E (LEFT-TO-RIGHT MARK) is stripped")
    func ltrMarkStripped() {
        let result = StackScriptAttributionSync.sanitizeField("hello\u{200E}world")
        #expect(result == "helloworld")
    }

    @Test("U+200F (RIGHT-TO-LEFT MARK) is stripped")
    func rtlMarkStripped() {
        let result = StackScriptAttributionSync.sanitizeField("hello\u{200F}world")
        #expect(result == "helloworld")
    }

    @Test("U+FEFF (BOM / ZERO-WIDTH NO-BREAK SPACE) is stripped")
    func bomStripped() {
        let result = StackScriptAttributionSync.sanitizeField("\u{FEFF}hello")
        #expect(result == "hello")
    }

    // MARK: - sanitizeField: Trim

    @Test("leading and trailing whitespace is trimmed")
    func leadingTrailingWhitespaceTrimmed() {
        let result = StackScriptAttributionSync.sanitizeField("  hello  ")
        #expect(result == "hello")
    }

    // MARK: - Attribution line format (Finding 10: no query: suffix)

    @Test("attribution line does NOT contain 'query:' suffix (Security Finding 10)")
    func attributionLineNoQuerySuffix() {
        let asset = makeAsset(name: "test_asset")
        let output = StackScriptAttributionSync.sync(stackScript: "", webAssets: [asset])
        // The query "test query" must NOT appear in the output (Finding 10)
        #expect(!output.contains("query:"))
        #expect(!output.contains("test query"))
    }

    @Test("attribution line format is: -- \"name\" — by creator on provider — LICENSE — url")
    func attributionLineFormat() {
        let asset = makeAsset(
            name: "my_asset",
            creator: "Jane Doe",
            providerName: "Openverse",
            licenseId: "cc-by-4.0",
            sourceURL: "https://openverse.org/image/123"
        )
        let output = StackScriptAttributionSync.sync(stackScript: "", webAssets: [asset])
        #expect(output.contains("\"my_asset\""))
        #expect(output.contains("Jane Doe"))
        #expect(output.contains("Openverse"))
        #expect(output.contains("CC-BY-4.0"))
        #expect(output.contains("https://openverse.org/image/123"))
        // Format uses em-dashes (U+2014)
        #expect(output.contains("\u{2014}"))
    }

    // MARK: - Sentinel block: no prior block → add

    @Test("no prior block: attribution block is prepended")
    func noPriorBlockAdded() {
        let asset = makeAsset(name: "cat")
        let result = StackScriptAttributionSync.sync(stackScript: "on mouseUp\nend mouseUp", webAssets: [asset])
        #expect(result.contains("BEGIN HYPE WEB ASSET ATTRIBUTIONS"))
        #expect(result.contains("END HYPE WEB ASSET ATTRIBUTIONS"))
        #expect(result.contains("on mouseUp"))
    }

    @Test("no web assets: sync returns the original script unchanged")
    func noWebAssetsReturnsUnchanged() {
        let userScript = "on mouseUp\n  put 1\nend mouseUp"
        let result = StackScriptAttributionSync.sync(stackScript: userScript, webAssets: [])
        #expect(result == userScript)
    }

    @Test("empty stack script with web assets: returns only the block")
    func emptyScriptWithAssetsReturnsBlock() {
        let asset = makeAsset(name: "dog")
        let result = StackScriptAttributionSync.sync(stackScript: "", webAssets: [asset])
        #expect(result.contains("BEGIN HYPE WEB ASSET ATTRIBUTIONS"))
        #expect(result.contains("dog"))
        #expect(!result.hasPrefix("\n"))  // No leading newline
    }

    // MARK: - Sentinel block: prior block → replace

    @Test("prior block is replaced wholesale on re-sync")
    func priorBlockReplaced() {
        let asset1 = makeAsset(name: "apple")
        let firstSync = StackScriptAttributionSync.sync(stackScript: "", webAssets: [asset1])

        let asset2 = makeAsset(name: "banana")
        let secondSync = StackScriptAttributionSync.sync(stackScript: firstSync, webAssets: [asset2])

        // Old asset gone, new asset present
        #expect(!secondSync.contains("apple"))
        #expect(secondSync.contains("banana"))
        // Only one sentinel block
        let beginCount = secondSync.components(separatedBy: "BEGIN HYPE WEB ASSET ATTRIBUTIONS").count - 1
        #expect(beginCount == 1)
    }

    @Test("user text after sentinels is preserved below the new block")
    func userTextAfterSentinelPreserved() {
        let asset = makeAsset(name: "tree")
        let userScript = "on mouseUp\n  put \"hi\"\nend mouseUp"

        let script = StackScriptAttributionSync.sync(stackScript: userScript, webAssets: [asset])
        // Both block and user content should be present
        #expect(script.contains("BEGIN HYPE WEB ASSET ATTRIBUTIONS"))
        #expect(script.contains("on mouseUp"))
        // User content should come after the block
        let blockEnd = script.range(of: "END HYPE WEB ASSET ATTRIBUTIONS")!.upperBound
        let remainingAfterBlock = String(script[blockEnd...])
        #expect(remainingAfterBlock.contains("on mouseUp"))
    }

    // MARK: - Malicious creator name cannot escape sentinel block

    @Test("malicious creator name containing sentinel string cannot escape the block")
    func maliciousCreatorCannotEscapeBlock() {
        let maliciousCreator = "END HYPE WEB ASSET ATTRIBUTIONS\n-- injection"
        let asset = makeAsset(name: "exploit", creator: maliciousCreator)
        let output = StackScriptAttributionSync.sync(stackScript: "", webAssets: [asset])

        // The sanitized field should collapse the newline to a space
        // so it can't produce a new line that looks like the end sentinel
        // The end sentinel must appear exactly once at the end
        let lines = output.components(separatedBy: "\n")
        let endSentinelLines = lines.filter { $0.hasPrefix("-- END HYPE WEB ASSET ATTRIBUTIONS") }
        #expect(endSentinelLines.count == 1)

        // And "injection" must not appear as its own line outside the block
        let injectionOutsideBlock = lines.dropFirst().filter { $0 == "-- injection" }
        #expect(injectionOutsideBlock.isEmpty)
    }

    // MARK: - Non-webSearch assets not listed

    @Test("assets with non-webSearch origin are not listed in the block")
    func nonWebSearchAssetsNotListed() {
        let webAsset = makeAsset(name: "cloud")
        let userAsset = makeNonWebAsset(name: "localImage")

        let output = StackScriptAttributionSync.sync(stackScript: "", webAssets: [webAsset, userAsset])
        #expect(output.contains("cloud"))
        #expect(!output.contains("localImage"))
    }

    // MARK: - Alphabetical ordering

    @Test("attribution lines are sorted alphabetically by asset name")
    func attributionLinesSortedAlphabetically() {
        let assetC = makeAsset(name: "cherry")
        let assetA = makeAsset(name: "apple")
        let assetB = makeAsset(name: "banana")

        let output = StackScriptAttributionSync.sync(stackScript: "", webAssets: [assetC, assetA, assetB])
        let appleIdx = output.range(of: "apple")!.lowerBound
        let bananaIdx = output.range(of: "banana")!.lowerBound
        let cherryIdx = output.range(of: "cherry")!.lowerBound

        #expect(appleIdx < bananaIdx)
        #expect(bananaIdx < cherryIdx)
    }

    // MARK: - Begin sentinel not found / end sentinel orphan

    @Test("orphan end sentinel (no begin): script returned unchanged")
    func orphanEndSentinelUnchanged() {
        let withOrphan = "-- END HYPE WEB ASSET ATTRIBUTIONS\non mouseUp\nend mouseUp"
        // No web assets → should return unchanged
        let result = StackScriptAttributionSync.sync(stackScript: withOrphan, webAssets: [])
        #expect(result == withOrphan)
    }

    // MARK: - Empty / nil fields fall back to "Unknown"

    @Test("empty creator falls back to 'Unknown'")
    func emptyCreatorFallsBackToUnknown() {
        let asset = makeAsset(name: "photo", creator: "")
        let output = StackScriptAttributionSync.sync(stackScript: "", webAssets: [asset])
        #expect(output.contains("Unknown"))
    }

    @Test("empty license identifier falls back to 'Unknown License'")
    func emptyLicenseFallsBackToUnknownLicense() {
        let license = AssetLicense(name: "", identifier: "", url: "", isShareable: false)
        let attribution = AssetAttribution(
            creator: "Creator",
            title: "title",
            sourceURL: "https://example.com",
            downloadURL: "https://example.com/file.png",
            providerName: "Provider",
            providerIdentifier: "provider"
        )
        let provenance = AssetProvenance(
            origin: .webSearch,
            searchQuery: "q",
            license: license,
            attribution: attribution,
            importedAt: Date()
        )
        var asset = makeAsset(name: "noLicense")
        // We need to create the asset with empty license directly
        let assetWithEmptyLicense = Asset(
            id: UUID(),
            name: "noLicense",
            kind: .imageTexture,
            mimeType: "image/png",
            data: Data(),
            width: 100,
            height: 100,
            tags: [],
            slices: [],
            animationClips: [],
            tileWidth: 0,
            tileHeight: 0,
            tileColumns: 0,
            tileRows: 0,
            provenance: provenance
        )
        let output = StackScriptAttributionSync.sync(stackScript: "", webAssets: [assetWithEmptyLicense])
        #expect(output.contains("Unknown License"))
    }
}
