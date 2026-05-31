import Foundation

#if canImport(SwiftUI)
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

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
    static let defaultValue: HypeTheme = BuiltInThemes.system
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
    case panel         // inspector, AI chat, asset repository
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
        if theme.usesGlassMaterial && !LiquidGlassEnvironment.reduceTransparency {
            // Surface dispatch obeys Apple's Liquid Glass rule:
            // "Liquid Glass is exclusively for the navigation layer
            // that floats above app content. Never apply to content
            // itself." So the canvas (content layer) gets a flat
            // theme fill even when the theme opts into glass; only
            // panels / toolbars / popovers get the material.
            switch surface {
            case .canvas:
                // Content layer — flat fill, no glass. Apple HIG
                // anti-pattern check ("don't stack glass over
                // content") satisfied.
                content.background(_resolvedSurfaceColor(theme: theme, surface: surface))
            case .panel, .toolbar:
                content.modifier(LiquidGlassPanelMaterial(theme: theme))
            case .popover:
                content.modifier(LiquidGlassPopoverMaterial(theme: theme))
            }
        } else {
            // Non-glass theme OR user has enabled Reduce Transparency
            // — fall back to the resolved opaque surface color.
            // Honoring `accessibilityDisplayShouldReduceTransparency`
            // is the Apple-prescribed behavior; we MUST NOT override.
            content.background(_resolvedSurfaceColor(theme: theme, surface: surface))
        }
    }
}

/// Panel / toolbar surface: prefers Apple's `.glassEffect()` (macOS 26+
/// Liquid Glass) and falls back to `.regularMaterial` on older systems.
/// The Increase Contrast accessibility setting tilts the material a step
/// thicker so text legibility wins over translucency.
private struct LiquidGlassPanelMaterial: ViewModifier {
    let theme: HypeTheme

    func body(content: Content) -> some View {
        if #available(macOS 26, iOS 26, tvOS 26, *) {
            // Native Liquid Glass — refraction + specular highlight,
            // adapts to surrounding content + system tint. The
            // Increase Contrast setting is handled by the system
            // automatically (Apple HIG: "never override").
            content.background {
                Rectangle().glassEffect(in: Rectangle())
            }
        } else {
            // macOS 15 fallback — vibrancy via standard material.
            let mat: Material = LiquidGlassEnvironment.increaseContrast
                ? .thickMaterial
                : .regularMaterial
            content.background(mat, in: Rectangle())
        }
    }
}

/// Popover / floating-control surface. Apple's guidance for floating
/// controls over media is `.glassEffect(.clear)`; for general popovers
/// over panel content, `.regular` (default) is correct. We default to
/// regular here because Hype's popovers (color picker, menu) tend to
/// sit over the document, not media.
private struct LiquidGlassPopoverMaterial: ViewModifier {
    let theme: HypeTheme

    func body(content: Content) -> some View {
        if #available(macOS 26, iOS 26, tvOS 26, *) {
            content.background {
                Rectangle().glassEffect(in: Rectangle())
            }
        } else {
            let mat: Material = LiquidGlassEnvironment.increaseContrast
                ? .regularMaterial
                : .thinMaterial
            content.background(mat, in: Rectangle())
        }
    }
}

/// Process-wide accessibility-state cache for Liquid Glass decisions.
///
/// Reading `NSWorkspace.shared` properties is cheap but happens on
/// every SwiftUI render. The Apple HIG mandate is that we honor
/// `reduceTransparency` / `increaseContrast` automatically; this helper
/// centralises the read so renderers stay terse.
///
    public enum LiquidGlassEnvironment {

    /// True when the user has enabled "Reduce transparency" in System
    /// Settings → Accessibility → Display. When true, all glass
    /// surfaces fall back to opaque fills (per Apple HIG).
    public static var reduceTransparency: Bool {
        #if canImport(AppKit)
        return NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        #else
        return false
        #endif
    }

    /// True when the user has enabled "Increase contrast." Glass
    /// surfaces switch to a thicker material variant; CG renderers
    /// drop the specular highlight in favor of a sharper border.
    public static var increaseContrast: Bool {
        #if canImport(AppKit)
        return NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        #else
        return false
        #endif
    }

    /// True when the user has enabled "Reduce motion." Animated
    /// glass features (specular shimmer, GlassEffectContainer
    /// morphs) should fall back to static states. Currently Hype's
    /// CG glass is already static, but the flag exists for future
    /// SwiftUI `.glassEffect(.regular.interactive())` adoption.
    public static var reduceMotion: Bool {
        #if canImport(AppKit)
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #else
        return false
        #endif
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
        #if canImport(AppKit)
        switch key {
        case "controlBackgroundColor": return Color(NSColor.controlBackgroundColor)
        case "windowBackgroundColor":  return Color(NSColor.windowBackgroundColor)
        case "textBackgroundColor":    return Color(NSColor.textBackgroundColor)
        case "labelColor":             return Color(NSColor.labelColor)
        case "separatorColor":         return Color(NSColor.separatorColor)
        case "controlAccentColor":     return Color(NSColor.controlAccentColor)
        default:                       return Color.primary
        }
        #else
        switch key {
        case "controlBackgroundColor", "windowBackgroundColor", "textBackgroundColor":
            #if os(tvOS)
            return Color(UIColor.black)
            #else
            return Color(.systemBackground)
            #endif
        case "labelColor":
            return Color.primary
        case "separatorColor":
            return Color.secondary.opacity(0.35)
        case "controlAccentColor":
            return Color.accentColor
        default:
            return Color.primary
        }
        #endif
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
