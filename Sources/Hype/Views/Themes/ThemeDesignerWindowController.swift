import SwiftUI
import HypeCore

/// Window opener for the Theme Designer.
///
/// Mirrors the pattern used by `openAssetRepositoryWindow` and
/// `openScriptEditorWindow` in `PropertyInspector.swift`: a top-level
/// `@MainActor` function constructs an `NSWindow`, embeds the SwiftUI
/// view via `NSHostingView`, and stores a strong reference in a
/// module-private dictionary so subsequent invocations focus the
/// existing window rather than spawning duplicates.
///
/// Why a detached `NSWindow` rather than a SwiftUI `.sheet` or
/// `.popover`: the Theme Designer is a long-running editor surface
/// the user wants to keep open while they tweak cards on the canvas.
/// A modal sheet would block the canvas; a popover would dismiss the
/// moment focus moves elsewhere. A separate window also mirrors the
/// Asset Repository window so the app stays internally consistent.
///
/// The window is keyed to the focused document by stack id. Opening
/// the designer for a different document opens a second window so
/// each editor edits its own document — there is no global "the"
/// theme designer.

/// Strong references to open Theme Designer windows, keyed by stack
/// UUID. Without this map the `NSWindow` would be deallocated the
/// moment this opener returns because nothing in the SwiftUI view
/// graph retains it.
@MainActor
private var activeThemeDesignerWindows: [UUID: NSWindow] = [:]

/// Open (or surface) the Theme Designer window for the given
/// document. Idempotent per-document: a second invocation for the
/// same document brings the existing window forward.
@MainActor
func openThemeDesignerWindow(document: Binding<HypeDocumentWrapper>) {
    let stackId = document.wrappedValue.document.stack.id

    if let existing = activeThemeDesignerWindows[stackId] {
        existing.makeKeyAndOrderFront(nil)
        return
    }

    let savedWidth = UserDefaults.standard.double(forKey: "themeDesignerWidth")
    let savedHeight = UserDefaults.standard.double(forKey: "themeDesignerHeight")
    let width = savedWidth > 0 ? savedWidth : 980
    let height = savedHeight > 0 ? savedHeight : 620

    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: width, height: height),
        styleMask: [.titled, .closable, .resizable, .miniaturizable],
        backing: .buffered,
        defer: false
    )
    window.title = "Theme Designer — \(document.wrappedValue.document.stack.name)"
    window.minSize = NSSize(width: 820, height: 520)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .aqua)

    let closeAction: () -> Void = { [weak window] in window?.close() }
    let designerView = ThemeDesignerView(document: document, onDone: closeAction)
        .environment(\.colorScheme, .light)
        .colorScheme(.light)
        .preferredColorScheme(.light)

    let hostingView = NSHostingView(rootView: designerView)
    hostingView.appearance = NSAppearance(named: .aqua)
    window.contentView = hostingView
    window.center()
    window.makeKeyAndOrderFront(nil)

    activeThemeDesignerWindows[stackId] = window

    NotificationCenter.default.addObserver(
        forName: NSWindow.didResizeNotification,
        object: window,
        queue: .main
    ) { _ in
        MainActor.assumeIsolated {
            UserDefaults.standard.set(window.frame.width, forKey: "themeDesignerWidth")
            UserDefaults.standard.set(window.frame.height, forKey: "themeDesignerHeight")
        }
    }
    NotificationCenter.default.addObserver(
        forName: NSWindow.willCloseNotification,
        object: window,
        queue: .main
    ) { _ in
        MainActor.assumeIsolated {
            _ = activeThemeDesignerWindows.removeValue(forKey: stackId)
        }
    }
}
