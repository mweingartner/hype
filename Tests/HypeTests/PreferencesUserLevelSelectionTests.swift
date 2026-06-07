import HypeCore
import Testing
@testable import Hype

@Suite("Preferences user level selection")
struct PreferencesUserLevelSelectionTests {
    @Test("selection defaults to scripting when no stack is available")
    func selectionDefaultsToScripting() {
        let selection = UserLevelPreferenceSelection()
        #expect(selection.rawValue == HypeUserLevel.scripting.rawValue)
        #expect(selection.userLevel == .scripting)
    }

    @Test("selection syncs and clamps stack values for picker display")
    func selectionSyncsAndClampsStackValues() {
        var selection = UserLevelPreferenceSelection(stackRawValue: HypeUserLevel.typing.rawValue)
        #expect(selection.rawValue == HypeUserLevel.typing.rawValue)

        selection.sync(stackRawValue: 99)
        #expect(selection.rawValue == HypeUserLevel.scripting.rawValue)

        selection.sync(stackRawValue: -4)
        #expect(selection.rawValue == HypeUserLevel.browsing.rawValue)

        selection.sync(stackRawValue: nil)
        #expect(selection.rawValue == HypeUserLevel.scripting.rawValue)
    }

    @Test("selection returns the normalized value to write back to the stack")
    func selectionReturnsNormalizedWriteBackValue() {
        var selection = UserLevelPreferenceSelection()

        #expect(selection.select(HypeUserLevel.painting.rawValue) == HypeUserLevel.painting.rawValue)
        #expect(selection.rawValue == HypeUserLevel.painting.rawValue)

        #expect(selection.select(0) == HypeUserLevel.browsing.rawValue)
        #expect(selection.rawValue == HypeUserLevel.browsing.rawValue)
    }
}
