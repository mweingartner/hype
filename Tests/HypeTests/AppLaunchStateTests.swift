import Testing
import Foundation
import AppKit
@testable import Hype

@Suite("App launch state")
struct AppLaunchStateTests {

    @Test("existing last-opened file is restored")
    func existingLastOpenedFileIsRestored() throws {
        let defaults = makeDefaults()
        let temporaryFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("hype")
        try Data("{}".utf8).write(to: temporaryFile)

        defaults.set(temporaryFile.path, forKey: AppLaunchState.Key.lastOpenedFilePath)
        let state = AppLaunchState(defaults: defaults)

        #expect(state.lastOpenedFileURL == temporaryFile)
    }

    @Test("missing last-opened file is ignored")
    func missingLastOpenedFileIsIgnored() {
        let defaults = makeDefaults()
        defaults.set("/tmp/does-not-exist-\(UUID().uuidString).hype", forKey: AppLaunchState.Key.lastOpenedFilePath)

        let state = AppLaunchState(defaults: defaults)

        #expect(state.lastOpenedFileURL == nil)
    }

    @Test("window frame is only restored when valid and visible")
    func windowFrameValidation() {
        let defaults = makeDefaults()
        let state = AppLaunchState(defaults: defaults)
        state.save(windowFrame: NSRect(x: 50, y: 60, width: 900, height: 700))

        let visible = state.visibleWindowFrame(using: [NSRect(x: 0, y: 0, width: 1600, height: 1000)])
        let hidden = state.visibleWindowFrame(using: [NSRect(x: 2000, y: 0, width: 500, height: 500)])

        #expect(visible == NSRect(x: 50, y: 60, width: 900, height: 700))
        #expect(hidden == nil)
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "AppLaunchStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
