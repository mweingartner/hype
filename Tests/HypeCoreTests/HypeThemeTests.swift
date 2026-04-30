import Testing
import Foundation
@testable import HypeCore

@Suite("HypeTheme — model, codable, ColorRef")
struct HypeThemeTests {

    // MARK: - ColorRef

    @Test("ColorRef parses #RRGGBB")
    func colorRefParsesSixDigit() {
        let c = ColorRef.parse("#FF8800")
        #expect(c == .hex("#FF8800"))
        #expect(c.rawDescription == "#FF8800")
    }

    @Test("ColorRef parses #RRGGBBAA with alpha")
    func colorRefParsesEightDigit() {
        let c = ColorRef.parse("#0A84FF40")
        #expect(c == .hex("#0A84FF40"))
    }

    @Test("ColorRef accepts bare hex without leading #")
    func colorRefAcceptsBareHex() {
        let c = ColorRef.parse("FF8800")
        #expect(c == .hex("#FF8800"))
    }

    @Test("ColorRef parses system: prefix into systemKey")
    func colorRefParsesSystemKey() {
        let c = ColorRef.parse("system:accentColor")
        #expect(c == .systemKey("accentColor"))
    }

    @Test("ColorRef.normalizedHex uppercases and prefixes #")
    func colorRefNormalizes() {
        #expect(ColorRef.normalizedHex("ff8800") == "#FF8800")
        #expect(ColorRef.normalizedHex("#ff8800") == "#FF8800")
        #expect(ColorRef.normalizedHex("FF8800AA") == "#FF8800AA")
    }

    @Test("ColorRef falls back to black on garbage input")
    func colorRefFallsBackOnGarbage() {
        #expect(ColorRef.parse("not-a-color") == .hex("#000000"))
        #expect(ColorRef.normalizedHex("zzz") == "#000000")
    }

    @Test("ColorRef encodes to single-string JSON")
    func colorRefEncodesAsString() throws {
        let hex = ColorRef.hex("#FF8800")
        let sys = ColorRef.systemKey("accentColor")
        let hexData = try JSONEncoder().encode(hex)
        let sysData = try JSONEncoder().encode(sys)
        #expect(String(data: hexData, encoding: .utf8) == "\"#FF8800\"")
        #expect(String(data: sysData, encoding: .utf8) == "\"system:accentColor\"")
    }

    @Test("ColorRef round-trips through JSON")
    func colorRefRoundTripsThroughJSON() throws {
        for original in [ColorRef.hex("#1A2B3C"),
                         ColorRef.hex("#0A84FF40"),
                         ColorRef.systemKey("accentColor")] {
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(ColorRef.self, from: data)
            #expect(decoded == original)
        }
    }

    // MARK: - HypeTheme

    @Test("HypeTheme round-trips through JSON")
    func themeRoundTripsThroughJSON() throws {
        let original = BuiltInThemes.modernLight
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HypeTheme.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.isBuiltIn == original.isBuiltIn)
        #expect(decoded.cardBackground == original.cardBackground)
        #expect(decoded.accent == original.accent)
        #expect(decoded.cornerRadiusMedium == original.cornerRadiusMedium)
        #expect(decoded.scriptTheme.keyword == original.scriptTheme.keyword)
    }

    @Test("HypeTheme tolerates missing fields")
    func themeToleratesMissingFields() throws {
        // Minimal JSON — only id and name. Everything else should
        // hydrate from defaults.
        let json = #"{"id": "00000000-0000-0000-0000-000000000001", "name": "Sparse"}"#
        let data = json.data(using: .utf8)!
        let theme = try JSONDecoder().decode(HypeTheme.self, from: data)
        #expect(theme.name == "Sparse")
        #expect(theme.cardBackground == .hex("#FFFFFF"))
        #expect(theme.accent == .hex("#0A84FF"))
        #expect(theme.cornerRadiusMedium == 6)
        #expect(theme.scriptTheme.fontSize == 13)
    }

    @Test("HypeTheme.duplicate makes a non-built-in copy with provenance")
    func themeDuplicateMakesUserCopy() {
        let copy = BuiltInThemes.sunset.duplicate(named: "My Sunset")
        #expect(copy.id != BuiltInThemes.sunset.id)
        #expect(copy.isBuiltIn == false)
        #expect(copy.basedOn == "Sunset")
        #expect(copy.name == "My Sunset")
        // Color values are preserved by value-type copy.
        #expect(copy.cardBackground == BuiltInThemes.sunset.cardBackground)
        #expect(copy.accent == BuiltInThemes.sunset.accent)
    }

    // MARK: - BuiltInThemes catalog

    @Test("BuiltInThemes.all has all six expected themes")
    func builtInsHasSixThemes() {
        let names = BuiltInThemes.all.map(\.name)
        #expect(names.count == 6)
        #expect(names.contains("System"))
        #expect(names.contains("Classic HyperCard"))
        #expect(names.contains("Modern Light"))
        #expect(names.contains("Modern Dark"))
        #expect(names.contains("Sunset"))
        #expect(names.contains("Neon"))
    }

    @Test("Every built-in is marked isBuiltIn=true")
    func builtInsAllMarked() {
        for theme in BuiltInThemes.all {
            #expect(theme.isBuiltIn == true,
                    "\(theme.name) should be marked isBuiltIn=true")
        }
    }

    @Test("Built-in IDs are stable across calls (same UUID every invocation)")
    func builtInIDsAreStable() {
        let firstPass = BuiltInThemes.all.map(\.id)
        let secondPass = BuiltInThemes.all.map(\.id)
        #expect(firstPass == secondPass,
                "BuiltInThemes.all must produce identical IDs across invocations so .hype files round-trip")
    }

    @Test("BuiltInThemes.find is case-insensitive")
    func builtInFindIsCaseInsensitive() {
        #expect(BuiltInThemes.find(named: "system")?.name == "System")
        #expect(BuiltInThemes.find(named: "SYSTEM")?.name == "System")
        #expect(BuiltInThemes.find(named: "Modern Dark")?.name == "Modern Dark")
        #expect(BuiltInThemes.find(named: "modern dark")?.name == "Modern Dark")
    }

    @Test("BuiltInThemes.fallbackName resolves to System")
    func builtInFallbackResolves() {
        let fallback = BuiltInThemes.find(named: BuiltInThemes.fallbackName)
        #expect(fallback != nil)
        #expect(fallback?.name == "System")
    }

    // MARK: - Stack default themeName

    @Test("Stack defaults to themeName='System'")
    func stackDefaultsToSystemTheme() {
        let s = Stack()
        #expect(s.themeName == "System")
    }

    @Test("Stack JSON without themeName field decodes with default 'System'")
    func stackBackwardCompatTheme() throws {
        // Build a real Stack, encode it, drop themeName from the
        // resulting JSON, then re-decode. This simulates an old
        // document that was saved before themes existed.
        let original = Stack(name: "Old Stack")
        let data = try JSONEncoder().encode(original)
        var dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        dict.removeValue(forKey: "themeName")
        let strippedData = try JSONSerialization.data(withJSONObject: dict)
        let stack = try JSONDecoder().decode(Stack.self, from: strippedData)
        #expect(stack.themeName == "System")
    }

    @Test("Card and Background default to themeName=nil")
    func cardAndBackgroundDefaultToNilTheme() {
        let c = Card(stackId: UUID(), backgroundId: UUID())
        let b = Background(stackId: UUID())
        #expect(c.themeName == nil)
        #expect(b.themeName == nil)
    }

    // MARK: - HypeDocument themes field

    @Test("New HypeDocument has empty user themes array")
    func newDocumentHasNoUserThemes() {
        let doc = HypeDocument.newDocument(name: "Empty")
        #expect(doc.themes.isEmpty)
    }

    @Test("HypeDocument round-trips with user themes")
    func documentRoundTripsWithThemes() throws {
        var doc = HypeDocument.newDocument(name: "Themed")
        let copy = BuiltInThemes.modernLight.duplicate(named: "My Theme")
        doc.themes.append(copy)

        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(HypeDocument.self, from: data)
        #expect(decoded.themes.count == 1)
        #expect(decoded.themes[0].name == "My Theme")
        #expect(decoded.themes[0].basedOn == "Modern Light")
        #expect(decoded.themes[0].isBuiltIn == false)
    }

    @Test("HypeDocument JSON without themes field decodes with []")
    func documentBackwardCompatThemesEmpty() throws {
        // Encode a fresh doc, drop the themes field manually,
        // re-decode. Simulates an old .hype file.
        let doc = HypeDocument.newDocument(name: "Old")
        var dict = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(doc)) as! [String: Any]
        dict.removeValue(forKey: "themes")
        let strippedData = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(HypeDocument.self, from: strippedData)
        #expect(decoded.themes.isEmpty)
    }
}
