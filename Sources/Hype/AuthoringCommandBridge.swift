import SwiftUI

struct HypeAuthoringCommandContext {
    var canDuplicateSelection: Bool
    var duplicateSelection: () -> Void
}

private struct HypeAuthoringCommandContextKey: FocusedValueKey {
    typealias Value = HypeAuthoringCommandContext
}

extension FocusedValues {
    var hypeAuthoringCommandContext: HypeAuthoringCommandContext? {
        get { self[HypeAuthoringCommandContextKey.self] }
        set { self[HypeAuthoringCommandContextKey.self] = newValue }
    }
}
