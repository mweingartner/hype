import SwiftUI
import AppKit
import HypeCore

/// A theme-editor-friendly color well: a labeled row with a colored
/// swatch button on the left and a `#RRGGBB[AA]` text field on the
/// right. Both halves drive the same `Binding<ColorRef>` so editing
/// either updates the other.
///
/// Why not SwiftUI's built-in `ColorPicker`: ColorPicker emits a
/// `Color` and round-trips through SwiftUI's color machinery, which
/// loses fidelity when bouncing through `NSColor` and back to a
/// canonical hex. Theme editing wants exact bytes — a user typing
/// `#FF8800` should see `#FF8800` in the swatch and have `#FF8800`
/// written to disk, not `#FE7F00` or some "near" color the OS
/// rendered. Driving an `NSColorPanel` directly via target/action
/// keeps the color path lossless and lets us push hex strings to
/// the `ColorRef` model verbatim.
///
/// The hex text field validates on commit (Return / focus loss):
/// invalid input reverts to the previous swatch value rather than
/// silently corrupting the theme. System-key colors (e.g. the System
/// theme's `system.textColor`) are displayed as their resolved hex
/// for editing, but the user changing the swatch converts the field
/// to a fixed `.hex(...)` value — semantic system keys can only be
/// authored via JSON / HypeTalk for now, since exposing them in the
/// editor would require a separate "use system color" picker.
struct ThemeColorWell: View {
    let label: String
    @Binding var color: ColorRef
    var disabled: Bool = false

    /// Local hex draft. Synced from `color` on each render so external
    /// updates show up immediately, but the live editing buffer is
    /// `localHex` so users can type intermediate states like `#FF` on
    /// their way to `#FF8800` without the binding rejecting half-typed
    /// input.
    @State private var localHex: String = ""
    @FocusState private var hexFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .frame(width: 140, alignment: .trailing)
                .foregroundColor(.secondary)

            // Swatch button — opens NSColorPanel.
            Button(action: openColorPanel) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.swiftUIColor)
                    .frame(width: 28, height: 20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(disabled)
            .help("Click to open the color panel")

            // Hex text field. Editable only for `.hex` colors —
            // system-key colors render in the swatch but their key
            // is shown in the field instead of a hex value.
            TextField("", text: $localHex)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 88)
                .disabled(disabled)
                .focused($hexFieldFocused)
                .onSubmit { commitHex() }
                .onChange(of: hexFieldFocused) { _, isFocused in
                    if !isFocused { commitHex() }
                }
        }
        .onAppear { syncLocalHexFromColor() }
        .onChange(of: color) { _, _ in syncLocalHexFromColor() }
    }

    /// Pull the displayed hex out of the bound `ColorRef`.
    private func syncLocalHexFromColor() {
        switch color {
        case .hex(let h):
            localHex = h
        case .systemKey(let key):
            localHex = "system:\(key)"
        }
    }

    /// Parse the current `localHex` field. Valid input pushes a new
    /// `.hex(...)` value to the binding; invalid input reverts the
    /// field to the model's current canonical form so the user sees
    /// the rejection.
    private func commitHex() {
        let parsed = ColorRef.parse(localHex)
        // If the user kept the system-key form, leave the model as-is.
        if case .systemKey = color, localHex.lowercased().hasPrefix("system:") {
            return
        }
        color = parsed
        syncLocalHexFromColor()
    }

    /// Bring up the global `NSColorPanel`, point it at this well via
    /// a target-action shim, and translate panel changes back into
    /// the binding. The shim is retained for the lifetime of the
    /// panel session via the static registry below.
    private func openColorPanel() {
        let initial = color.nsColor
        let target = ThemeColorPanelTarget(initialColor: initial) { newColor in
            color = .hex(Self.hexString(from: newColor))
        }
        ThemeColorPanelRegistry.shared.activate(target: target)
        let panel = NSColorPanel.shared
        panel.color = initial
        panel.setTarget(target)
        panel.setAction(#selector(ThemeColorPanelTarget.colorDidChange(_:)))
        panel.showsAlpha = true
        panel.makeKeyAndOrderFront(nil)
    }

    /// Convert an `NSColor` to a `#RRGGBB[AA]` string, normalizing
    /// through sRGB so the result is independent of the source color
    /// space (NSColorPanel may hand back generic-RGB values).
    private static func hexString(from color: NSColor) -> String {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        let r = Int((srgb.redComponent * 255).rounded())
        let g = Int((srgb.greenComponent * 255).rounded())
        let b = Int((srgb.blueComponent * 255).rounded())
        let a = Int((srgb.alphaComponent * 255).rounded())
        if a == 255 {
            return String(format: "#%02X%02X%02X", r, g, b)
        }
        return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }
}

// MARK: - NSColorPanel target shim

/// `NSColorPanel` wants an Objective-C target/action — it can't talk
/// to a SwiftUI `@Binding` directly. This `NSObject` subclass bridges
/// the two: it holds the SwiftUI setter closure and forwards every
/// panel change to it.
final class ThemeColorPanelTarget: NSObject {
    private let onChange: (NSColor) -> Void
    private let initialColor: NSColor

    init(initialColor: NSColor, onChange: @escaping (NSColor) -> Void) {
        self.initialColor = initialColor
        self.onChange = onChange
    }

    @objc func colorDidChange(_ panel: NSColorPanel) {
        onChange(panel.color)
    }
}

/// Retains the most-recent panel target so AppKit's weak reference
/// to it doesn't deallocate the shim mid-edit. Only one swatch can
/// own the panel at a time (NSColorPanel is a singleton), so a
/// single slot is enough.
@MainActor
final class ThemeColorPanelRegistry {
    static let shared = ThemeColorPanelRegistry()
    private var current: ThemeColorPanelTarget?

    func activate(target: ThemeColorPanelTarget) {
        current = target
    }
}
