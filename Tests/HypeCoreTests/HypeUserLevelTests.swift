import Testing
@testable import HypeCore

@Suite("Hype user level")
struct HypeUserLevelTests {
    @Test("numeric values clamp to HyperCard range")
    func numericValuesClamp() {
        #expect(HypeUserLevel.clamped(-10) == .browsing)
        #expect(HypeUserLevel.clamped(1) == .browsing)
        #expect(HypeUserLevel.clamped(5) == .scripting)
        #expect(HypeUserLevel.clamped(42) == .scripting)
    }

    @Test("parser accepts numbers and level names")
    func parserAcceptsNumbersAndNames() {
        #expect(HypeUserLevel.parse("1") == .browsing)
        #expect(HypeUserLevel.parse("typing") == .typing)
        #expect(HypeUserLevel.parse("Paint") == .painting)
        #expect(HypeUserLevel.parse("authoring") == .authoring)
        #expect(HypeUserLevel.parse("user script") == nil)
        #expect(HypeUserLevel.parse("scripting") == .scripting)
    }
}
