import Foundation
import HypeCore

enum HypeTraceConfiguration {
    static let enabledKey = "hype.trace.enabled"

    static func apply(
        defaults: UserDefaults = .standard,
        recorder: HypeTalkScriptTraceRecorder = .shared
    ) {
        defaults.register(defaults: [enabledKey: false])
        recorder.setEnabled(defaults.bool(forKey: enabledKey))
    }
}
