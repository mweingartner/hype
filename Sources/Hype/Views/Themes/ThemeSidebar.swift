import SwiftUI
import HypeCore

/// Left pane of the Theme Designer.
///
/// Two `Section`s: "Built-in" (read-only catalog from
/// `BuiltInThemes.all`) and "My Themes" (user themes from
/// `document.themes`). The footer toolbar holds the [+ duplicate],
/// [duplicate-current], and [delete] buttons.
///
/// Renaming a user theme cascades through
/// `HypeDocument.updateTheme(id:)`, which rejects collisions and
/// rewrites every reference (stack/background/card `themeName`) to
/// the new name in the same transaction. A rejected rename reverts
/// the local draft so the user sees the rejection without losing the
/// rest of their session.
///
/// Built-in rows show a `lock.fill` icon and are not editable; the
/// only operation a built-in supports from this sidebar is "duplicate"
/// (via the toolbar) which produces a fresh user theme the user can
/// then edit.
struct ThemeSidebar: View {
    @Binding var document: HypeDocumentWrapper
    @Binding var selectedThemeID: UUID?
    @Environment(\.hypeTheme) private var hypeTheme

    /// Local rename buffers. Keyed by theme id so several user themes
    /// can be renamed independently in succession without their
    /// drafts colliding. Synced to `theme.name` whenever a fresh row
    /// is rendered for a theme that isn't currently being edited.
    @State private var renameDrafts: [UUID: String] = [:]
    @State private var duplicatePopoverShown: Bool = false
    @State private var duplicateSourceName: String = ""

    private var allThemes: [HypeTheme] {
        document.document.allAvailableThemes
    }

    private var selectedTheme: HypeTheme? {
        guard let id = selectedThemeID else { return nil }
        return allThemes.first(where: { $0.id == id })
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedThemeID) {
                Section("Built-in") {
                    ForEach(BuiltInThemes.all) { theme in
                        builtInRow(theme: theme)
                            .tag(Optional(theme.id))
                    }
                }
                Section("My Themes") {
                    if document.document.themes.isEmpty {
                        Text("No user themes yet.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(document.document.themes) { theme in
                            userRow(theme: theme)
                                .tag(Optional(theme.id))
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            footerToolbar
        }
        .frame(minWidth: 200, idealWidth: 220)
        // Sidebar panel — themed so the theme list reads as part of
        // the surrounding chrome. ThemeDesignerView already sets the
        // chrome colorScheme on its body; rendering the sidebar bg
        // here ensures the list area picks up the same surface
        // color.
        .background(hypeTheme.inspectorBackground.swiftUIColor)
    }

    // MARK: - Rows

    @ViewBuilder
    private func builtInRow(theme: HypeTheme) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(theme.name)
                .font(.system(size: 12))
        }
        .help("Built-in theme — duplicate to edit")
    }

    @ViewBuilder
    private func userRow(theme: HypeTheme) -> some View {
        let draftBinding = renameBinding(for: theme)
        TextField("Name", text: draftBinding, onCommit: { commitRename(themeId: theme.id) })
            .textFieldStyle(.plain)
            .font(.system(size: 12))
    }

    private func renameBinding(for theme: HypeTheme) -> Binding<String> {
        Binding(
            get: { renameDrafts[theme.id] ?? theme.name },
            set: { renameDrafts[theme.id] = $0 }
        )
    }

    /// Apply the local draft to the document. Reverts the draft if
    /// the model rejects the new name (collision).
    private func commitRename(themeId: UUID) {
        guard let draft = renameDrafts[themeId] else { return }
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            renameDrafts.removeValue(forKey: themeId)
            return
        }
        let accepted = document.document.updateTheme(id: themeId) { $0.name = trimmed }
        if !accepted {
            // Collision — revert the draft so the user sees the
            // original name reappear. NSAlert gives them a hint about
            // why the rename was rejected.
            let alert = NSAlert()
            alert.messageText = "Rename Failed"
            alert.informativeText = "A theme named \"\(trimmed)\" already exists. Theme names must be unique."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            _ = alert.runModal()
        }
        renameDrafts.removeValue(forKey: themeId)
    }

    // MARK: - Footer toolbar

    @ViewBuilder
    private var footerToolbar: some View {
        HStack(spacing: 8) {
            // [+] Duplicate which theme... popover
            Button(action: { duplicatePopoverShown = true }) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("Duplicate any theme...")
            .popover(isPresented: $duplicatePopoverShown) {
                duplicatePopover
            }

            // Duplicate currently selected
            Button(action: duplicateSelected) {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Duplicate selected theme")
            .disabled(selectedTheme == nil)

            Spacer()

            // Delete (user themes only)
            Button(action: deleteSelected) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete selected theme")
            .disabled(!canDeleteSelected)
        }
        .padding(8)
    }

    private var canDeleteSelected: Bool {
        guard let theme = selectedTheme else { return false }
        return !theme.isBuiltIn
    }

    @ViewBuilder
    private var duplicatePopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Duplicate which theme?")
                .font(.system(size: 12, weight: .semibold))

            Picker("Source", selection: $duplicateSourceName) {
                ForEach(allThemes) { theme in
                    Text(theme.name).tag(theme.name)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            HStack {
                Spacer()
                Button("Cancel") { duplicatePopoverShown = false }
                    .keyboardShortcut(.cancelAction)
                Button("Duplicate") {
                    performDuplicate(sourceName: duplicateSourceName)
                    duplicatePopoverShown = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(duplicateSourceName.isEmpty)
            }
        }
        .padding(12)
        .frame(width: 280)
        .onAppear {
            // Default to the currently selected theme, or the first
            // built-in if nothing is selected, so the user just hits
            // Enter to take a copy of what they were looking at.
            if duplicateSourceName.isEmpty {
                duplicateSourceName = selectedTheme?.name ?? BuiltInThemes.fallbackName
            }
        }
    }

    private func duplicateSelected() {
        guard let source = selectedTheme else { return }
        performDuplicate(sourceName: source.name)
    }

    private func performDuplicate(sourceName: String) {
        guard let copy = document.document.duplicateTheme(named: sourceName) else { return }
        selectedThemeID = copy.id
    }

    /// Show a confirmation dialog with a usage summary, then delete
    /// the user theme via `HypeDocument.deleteTheme`. After the
    /// delete the cascade resets references in the same transaction
    /// (see `clearThemeReferences`).
    private func deleteSelected() {
        guard let theme = selectedTheme, !theme.isBuiltIn else { return }
        let usage = document.document.usageCount(themeName: theme.name)

        let alert = NSAlert()
        alert.messageText = "Delete \"\(theme.name)\"?"
        alert.informativeText = usage.isInUse
            ? "Used by \(usage.cards) card\(usage.cards == 1 ? "" : "s")"
              + " and \(usage.backgrounds) background\(usage.backgrounds == 1 ? "" : "s")"
              + (usage.isStackDefault ? " (and is the stack default)" : "")
              + ". Those references will clear."
            : "This theme is not currently used."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        _ = document.document.deleteTheme(id: theme.id)
        // Reset selection to System so the editor pane has something
        // to render after the deletion.
        selectedThemeID = BuiltInThemes.system.id
    }
}
