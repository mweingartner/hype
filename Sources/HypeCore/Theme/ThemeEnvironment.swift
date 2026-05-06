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

    /// Apply the theme's surface treatment to this view's background.
    ///
    /// When `theme.usesGlassMaterial == true` we swap in
    /// `.regularMaterial` so the surface picks up live vibrancy
    /// (Liquid Glass). Otherwise we apply the theme's resolved
    /// background color as a flat fill. This lets every panel /
    /// inspector / popover root opt into the theme's chrome with one
    /// modifier instead of repeated branching.
    ///
    /// Variants:
    /// - `surface(.canvas)`: card background
    /// - `surface(.panel)`: inspector / sidebar
    /// - `surface(.toolbar)`: title-bar-adjacent chrome
    @ViewBuilder
    func hypeSurface(_ surface: HypeThemeSurface, theme: HypeTheme? = nil) -> some View {
        modifier(HypeSurfaceModifier(surface: surface, override: theme))
    }
}

/// The semantic surface a view occupies. Determines which color
/// token from the theme is used as the flat-fill fallback when the
/// theme is NOT in glass mode.
public enum HypeThemeSurface: Sendable {
    case canvas        // card background
    case panel         // inspector, AI chat, sprite repository
    case toolbar       // title bar / toolbar chrome
    case popover       // floating menus, completion popups
}

private struct HypeSurfaceModifier: ViewModifier {
    @Environment(\.hypeTheme) private var envTheme
    let surface: HypeThemeSurface
    let override: HypeTheme?

    func body(content: Content) -> some View {
        let theme = override ?? envTheme
        return content.modifier(_HypeSurfaceBackground(theme: theme, surface: surface))
    }
}

/// Inner modifier — separated so the outer can resolve the theme via
/// the environment without putting `let` inside a `@ViewBuilder`.
private struct _HypeSurfaceBackground: ViewModifier {
    let theme: HypeTheme
    let surface: HypeThemeSurface

    @ViewBuilder
    func body(content: Content) -> some View {
        if theme.usesGlassMaterial {
            // Liquid Glass: live vibrancy + a tinted overlay so the
            // theme's color identity still bleeds through. The
            // material picker matches Apple's recommended pairing —
            // panels use `.regularMaterial`, popovers use
            // `.thinMaterial`, the canvas uses `.thickMaterial` to
            // stay reading-friendly.
            switch surface {
            case .canvas:
                content.background(.thickMaterial, in: Rectangle())
            case .panel, .toolbar:
                content.background(.regularMaterial, in: Rectangle())
            case .popover:
                content.background(.thinMaterial, in: Rectangle())
            }
        } else {
            content.background(_resolvedSurfaceColor(theme: theme, surface: surface))
        }
    }
}

private func _resolvedSurfaceColor(theme: HypeTheme, surface: HypeThemeSurface) -> Color {
    let hex: String
    switch surface {
    case .canvas:  hex = theme.cardBackground.rawDescription
    case .panel:   hex = theme.inspectorBackground.rawDescription
    case .toolbar: hex = theme.toolbarBackground.rawDescription
    case .popover: hex = theme.cardBackground.rawDescription
    }
    return SwiftUIColorFromHex(hex)
}

/// Bridge: parse a `"#RRGGBB"` / `"#RRGGBBAA"` / system-key hex form
/// into a SwiftUI `Color`. Falls back to `.clear` when the hex is
/// invalid; system keys not recognized fall through to the SwiftUI
/// system equivalents (windowBackground, etc.).
private func SwiftUIColorFromHex(_ raw: String) -> Color {
    var s = raw.trimmingCharacters(in: .whitespaces)
    if s.hasPrefix("system:") {
        // Mirror ColorRef.systemKey — translate the macOS-color name
        // back into a SwiftUI semantic color where one exists. Falls
        // back to `.primary` so we don't leak through as transparent.
        let key = String(s.dropFirst("system:".count))
        switch key {
        case "controlBackgroundColor": return Color(NSColor.controlBackgroundColor)
        case "windowBackgroundColor":  return Color(NSColor.windowBackgroundColor)
        case "textBackgroundColor":    return Color(NSColor.textBackgroundColor)
        case "labelColor":             return Color(NSColor.labelColor)
        case "separatorColor":         return Color(NSColor.separatorColor)
        case "controlAccentColor":     return Color(NSColor.controlAccentColor)
        default:                       return Color.primary
        }
    }
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6 || s.count == 8,
          let v = UInt32(s, radix: 16)
    else { return Color.clear }
    let r, g, b, a: Double
    if s.count == 8 {
        r = Double((v >> 24) & 0xFF) / 255
        g = Double((v >> 16) & 0xFF) / 255
        b = Double((v >>  8) & 0xFF) / 255
        a = Double( v        & 0xFF) / 255
    } else {
        r = Double((v >> 16) & 0xFF) / 255
        g = Double((v >>  8) & 0xFF) / 255
        b = Double( v        & 0xFF) / 255
        a = 1.0
    }
    return Color(red: r, green: g, blue: b, opacity: a)
}

#endif
