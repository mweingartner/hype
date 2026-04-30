import SwiftUI
import HypeCore

/// Root view of the Theme Designer.
///
/// A three-column `HSplitView`:
/// - **Left**: `ThemeSidebar` — built-in catalog + user themes.
/// - **Middle**: `ThemeEditor` — sectioned form bound to the selected
///   theme. Disabled for built-ins (banner shown).
/// - **Right**: `ThemePreview` — synthetic mini-card and the
///   "Affected by this theme" usage panel.
///
/// State management:
/// - `selectedThemeID` is the only piece of UI state owned at this
///   level. Defaults to System's UUID so the app opens to a known
///   theme. If the bound document mutates externally and the
///   currently-selected theme disappears (a HypeTalk script deleted
///   it, say), `resolvedSelection` falls back to System AND
///   surfaces a transient banner so the user knows what happened.
/// - The document binding flows down to all three children. Edits
///   from the editor pane round-trip through
///   `HypeDocument.updateTheme(id:)`; the sidebar and preview
///   re-render reactively.
///
/// Why this is a top-level view rather than a sheet on the
/// PropertyInspector: the designer is a long-running surface that
/// the user wants to keep open while reorganizing their stack. See
/// `ThemeDesignerWindowController.swift` for the window opener.
struct ThemeDesignerView: View {
    @Binding var document: HypeDocumentWrapper
    @Environment(\.hypeTheme) private var hypeTheme
    var onDone: (() -> Void)? = nil

    @State private var selectedThemeID: UUID? = BuiltInThemes.system.id
    @State private var staleSelectionBanner: String? = nil

    /// All themes available to the document, in display order.
    private var allThemes: [HypeTheme] {
        document.document.allAvailableThemes
    }

    /// Resolve the currently-selected theme. If the previously-
    /// selected id no longer exists, snap back to System and surface
    /// a transient banner explaining what happened.
    private var resolvedSelection: HypeTheme {
        if let id = selectedThemeID,
           let theme = allThemes.first(where: { $0.id == id }) {
            return theme
        }
        return BuiltInThemes.system
    }

    var body: some View {
        VStack(spacing: 0) {
            if let banner = staleSelectionBanner {
                staleBanner(text: banner)
            }

            HSplitView {
                ThemeSidebar(
                    document: $document,
                    selectedThemeID: $selectedThemeID
                )

                ThemeEditor(
                    theme: resolvedSelection,
                    document: $document
                )
                .frame(minWidth: 360, idealWidth: 420)

                ThemePreview(
                    theme: resolvedSelection,
                    document: $document
                )
            }

            footer
        }
        .frame(minWidth: 820, minHeight: 520)
        // Designer window surface — chrome around the sidebar,
        // editor, and preview is themed by the active stack theme.
        // The preview pane itself renders the in-progress edited
        // theme (see ThemePreview), so the inner sample stays
        // independent of this outer chrome.
        .background(hypeTheme.inspectorBackground.swiftUIColor)
        // Force chrome colorScheme so the sidebar and editor labels
        // stay readable on the themed bg.
        .environment(\.colorScheme, hypeTheme.chromeColorScheme)
        .onChange(of: document.document.themes.map(\.id)) { _, _ in
            // The user theme array changed underneath us. If our
            // selection points at a theme that no longer exists,
            // snap to System and remember why so we can show the
            // banner once.
            if let id = selectedThemeID,
               !allThemes.contains(where: { $0.id == id }) {
                staleSelectionBanner = "The previously selected theme was removed. Showing System."
                selectedThemeID = BuiltInThemes.system.id

                // Auto-dismiss the banner after a short delay.
                Task {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    await MainActor.run { staleSelectionBanner = nil }
                }
            }
        }
    }

    @ViewBuilder
    private func staleBanner(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundColor(.orange)
            Text(text)
                .font(.system(size: 11))
            Spacer()
            Button(action: { staleSelectionBanner = nil }) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
        }
        .padding(8)
        .background(Color.orange.opacity(0.10))
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            Spacer()
            Button("Done") {
                if let onDone {
                    onDone()
                }
            }
            .keyboardShortcut(.return)
        }
        .padding(8)
        // Themed footer strip with a divider drawn on top using
        // the theme's panelDivider token instead of a hardcoded
        // black 8% overlay.
        .background(hypeTheme.toolbarBackground.swiftUIColor)
        .environment(\.colorScheme, hypeTheme.toolbarColorScheme)
        .overlay(
            Rectangle()
                .fill(hypeTheme.panelDivider.swiftUIColor)
                .frame(height: 1),
            alignment: .top
        )
    }
}
