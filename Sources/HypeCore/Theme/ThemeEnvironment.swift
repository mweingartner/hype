import Foundation

#if canImport(SwiftUI)
import SwiftUI

/// SwiftUI environment plumbing for the active theme.
///
/// `HypeTheme` is injected into the environment once near the root
/// of the view tree (in MainContentView, after the cascade is
/// resolved for the current card), and any downstream view reads it
/// via `@Environment(\.hypeTheme) var theme`.
///
/// Default value is `BuiltInThemes.system`, which honors macOS
/// Light/Dark mode — so views that don't see an injected value
/// still render reasonably.

private struct HypeThemeKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: HypeTheme = BuiltInThemes.system
}

public extension EnvironmentValues {
    /// The currently-active theme for the surface this view is in.
    /// Reads cascade through MainContentView's
    /// `effectiveTheme(forCard:)` — see `ThemeResolver.swift`.
    var hypeTheme: HypeTheme {
        get { self[HypeThemeKey.self] }
        set { self[HypeThemeKey.self] = newValue }
    }
}

public extension View {
    /// Convenience for installing a theme on a subtree:
    ///   `myView.hypeTheme(theme)`
    func hypeTheme(_ theme: HypeTheme) -> some View {
        environment(\.hypeTheme, theme)
    }
}

#endif
