import SwiftUI
import HypeCore

struct HypeAuthoringCommandContext {
    var userLevel: HypeUserLevel
    var canDuplicateSelection: Bool
    var duplicateSelection: () -> Void
    var layerTransferTitle: String
    var canTransferSelectionToAlternateLayer: Bool
    var transferSelectionToAlternateLayer: () -> Void
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
