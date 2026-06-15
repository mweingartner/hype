import Foundation
import Testing
@testable import Hype
@testable import HypeCore

@Suite("Hype trace configuration")
struct HypeTraceConfigurationTests {
    @Test("startup preference enables script tracing")
    func startupPreferenceEnablesScriptTracing() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: HypeTraceConfiguration.enabledKey)
        let recorder = HypeTalkScriptTraceRecorder()

        HypeTraceConfiguration.apply(defaults: defaults, recorder: recorder)

        #expect(recorder.snapshot().isEnabled)
    }

    @Test("missing startup preference leaves script tracing disabled")
    func missingStartupPreferenceLeavesScriptTracingDisabled() {
        let defaults = makeDefaults()
        let recorder = HypeTalkScriptTraceRecorder()

        HypeTraceConfiguration.apply(defaults: defaults, recorder: recorder)

        #expect(!recorder.snapshot().isEnabled)
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "HypeTraceConfigurationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
