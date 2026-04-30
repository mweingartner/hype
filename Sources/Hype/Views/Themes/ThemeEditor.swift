import SwiftUI
import AppKit
import HypeCore

/// System font families, loaded once for theme font pickers. Mirrors
/// the same constant in `PropertyInspector.swift` — kept module-local
/// so the editor file is self-contained.
private let themeFontFamilies: [String] = NSFontManager.shared.availableFontFamilies.sorted()

/// The middle pane of the Theme Designer.
///
/// A scrollable `Form` of disclosure groups, one per category in
/// `HypeTheme`: identity, surface colors, part defaults, selection,
/// chrome, typography, structure, and the nested `HypeScriptTheme`.
///
/// Editing rules:
/// - When the bound theme has `isBuiltIn == true`, EVERY editor field
///   is disabled and a banner at the top tells the user to duplicate
///   first. This matches the contract of
///   `HypeDocument.updateTheme(id:)`, which silently refuses to
///   mutate a built-in theme — disabling the inputs makes that
///   refusal visible up front.
/// - Edits are debounced (200 ms) before being written through
///   `HypeDocument.updateTheme(id:) { $0 = updatedTheme }`. Without
///   the debounce, every keystroke in a slider or hex field would
///   drive a document mutation and a full SwiftUI invalidation, which
///   on a large stack noticeably stutters the preview pane.
/// - Renames are committed by the sidebar, not the editor — the
///   identity row here renders the name read-only, since rename
///   collisions need cascade-rename of references and that's
///   logically a sidebar concern. The basedOn label is purely
///   informational ("based on Sunset").
struct ThemeEditor: View {
    /// The theme being edited. We keep an internal `State` copy that
    /// flushes back to the document on a debounce so the live preview
    /// updates instantly without flooding the document with writes.
    let theme: HypeTheme
    @Binding var document: HypeDocumentWrapper
    @Environment(\.hypeTheme) private var hypeTheme

    @State private var draft: HypeTheme
    @State private var saveTask: Task<Void, Never>? = nil

    init(theme: HypeTheme, document: Binding<HypeDocumentWrapper>) {
        self.theme = theme
        self._document = document
        self._draft = State(initialValue: theme)
    }

    private var isReadOnly: Bool { draft.isBuiltIn }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if isReadOnly {
                    builtInBanner
                }

                identityGroup
                surfaceColorsGroup
                partDefaultsGroup
                selectionGroup
                chromeGroup
                typographyGroup
                structureGroup
                scriptThemeGroup
            }
            .padding(16)
        }
        // Editor panel surface — themed so the form pane matches
        // the rest of the designer chrome. The values being edited
        // (color wells, font pickers) are content and stay
        // independent of this outer chrome.
        .background(hypeTheme.inspectorBackground.swiftUIColor)
        .environment(\.colorScheme, hypeTheme.chromeColorScheme)
        .onChange(of: theme) { _, newValue in
            // External replacement (sidebar selected a different
            // theme, or document mutated underneath us) — replace the
            // draft wholesale and cancel any pending save.
            saveTask?.cancel()
            draft = newValue
        }
        .onChange(of: draft) { _, _ in
            scheduleSave()
        }
        .onDisappear {
            // Flush any pending edit so we don't lose the last few
            // keystrokes on window close.
            saveTask?.cancel()
            commitDraft()
        }
    }

    // MARK: - Read-only banner

    @ViewBuilder
    private var builtInBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .foregroundColor(.secondary)
            Text("Built-in themes can't be edited. Click ")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            + Text("Duplicate")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            + Text(" in the sidebar to make a copy.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(10)
        .background(Color.yellow.opacity(0.15))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.yellow.opacity(0.6), lineWidth: 1)
        )
        .cornerRadius(6)
    }

    // MARK: - Identity

    @ViewBuilder
    private var identityGroup: some View {
        DisclosureGroup("Identity") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Name")
                        .font(.system(size: 11))
                        .frame(width: 140, alignment: .trailing)
                        .foregroundColor(.secondary)
                    Text(draft.name)
                        .font(.system(size: 11))
                    Spacer()
                }
                if let basedOn = draft.basedOn {
                    HStack {
                        Text("Based on")
                            .font(.system(size: 11))
                            .frame(width: 140, alignment: .trailing)
                            .foregroundColor(.secondary)
                        Text(basedOn)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
                HStack {
                    Text("Type")
                        .font(.system(size: 11))
                        .frame(width: 140, alignment: .trailing)
                        .foregroundColor(.secondary)
                    Text(draft.isBuiltIn ? "Built-in" : "User")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                Text("Rename via the sidebar.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.leading, 148)
            }
        }
    }

    // MARK: - Color groups

    @ViewBuilder
    private var surfaceColorsGroup: some View {
        DisclosureGroup("Surface Colors") {
            VStack(alignment: .leading, spacing: 6) {
                ThemeColorWell(label: "Card Background", color: $draft.cardBackground, disabled: isReadOnly)
                ThemeColorWell(label: "Card Foreground", color: $draft.cardForeground, disabled: isReadOnly)
                ThemeColorWell(label: "Background Fill", color: $draft.backgroundFill, disabled: isReadOnly)
                ThemeColorWell(label: "Canvas Margin", color: $draft.canvasMargin, disabled: isReadOnly)
            }
        }
    }

    @ViewBuilder
    private var partDefaultsGroup: some View {
        DisclosureGroup("Part Defaults") {
            VStack(alignment: .leading, spacing: 6) {
                groupHeader("Button")
                ThemeColorWell(label: "Background", color: $draft.buttonBackground, disabled: isReadOnly)
                ThemeColorWell(label: "Foreground", color: $draft.buttonForeground, disabled: isReadOnly)
                ThemeColorWell(label: "Border", color: $draft.buttonBorder, disabled: isReadOnly)
                ThemeColorWell(label: "Hilite", color: $draft.buttonHilite, disabled: isReadOnly)

                groupHeader("Field")
                ThemeColorWell(label: "Background", color: $draft.fieldBackground, disabled: isReadOnly)
                ThemeColorWell(label: "Foreground", color: $draft.fieldForeground, disabled: isReadOnly)
                ThemeColorWell(label: "Border", color: $draft.fieldBorder, disabled: isReadOnly)

                groupHeader("Shape")
                ThemeColorWell(label: "Fill (default)", color: $draft.shapeFillDefault, disabled: isReadOnly)
                ThemeColorWell(label: "Stroke (default)", color: $draft.shapeStrokeDefault, disabled: isReadOnly)
            }
        }
    }

    @ViewBuilder
    private var selectionGroup: some View {
        DisclosureGroup("Selection / Accent") {
            VStack(alignment: .leading, spacing: 6) {
                ThemeColorWell(label: "Accent", color: $draft.accent, disabled: isReadOnly)
                ThemeColorWell(label: "Selection Fill", color: $draft.selectionFill, disabled: isReadOnly)
                ThemeColorWell(label: "Selection Stroke", color: $draft.selectionStroke, disabled: isReadOnly)
            }
        }
    }

    @ViewBuilder
    private var chromeGroup: some View {
        DisclosureGroup("Chrome (author mode)") {
            VStack(alignment: .leading, spacing: 6) {
                ThemeColorWell(label: "Toolbar Background", color: $draft.toolbarBackground, disabled: isReadOnly)
                ThemeColorWell(label: "Inspector Background", color: $draft.inspectorBackground, disabled: isReadOnly)
                ThemeColorWell(label: "Panel Divider", color: $draft.panelDivider, disabled: isReadOnly)
            }
        }
    }

    // MARK: - Typography

    @ViewBuilder
    private var typographyGroup: some View {
        DisclosureGroup("Typography") {
            VStack(alignment: .leading, spacing: 6) {
                fontPickerRow(label: "Body Font", binding: $draft.defaultFontFamily)
                numberRow(label: "Body Size", binding: $draft.defaultFontSize, range: 8...48, step: 1)

                fontPickerRow(label: "Heading Font", binding: $draft.headingFontFamily)
                numberRow(label: "Heading Size", binding: $draft.headingFontSize, range: 10...64, step: 1)

                fontPickerRow(label: "Mono Font", binding: $draft.monospaceFontFamily)
                numberRow(label: "Label Size", binding: $draft.labelFontSize, range: 6...24, step: 1)
            }
        }
    }

    // MARK: - Structure

    @ViewBuilder
    private var structureGroup: some View {
        DisclosureGroup("Structure") {
            VStack(alignment: .leading, spacing: 6) {
                numberRow(label: "Corner (small)", binding: $draft.cornerRadiusSmall, range: 0...32, step: 1)
                numberRow(label: "Corner (medium)", binding: $draft.cornerRadiusMedium, range: 0...48, step: 1)
                numberRow(label: "Corner (large)", binding: $draft.cornerRadiusLarge, range: 0...64, step: 1)
                numberRow(label: "Spacing Unit", binding: $draft.spacingUnit, range: 1...32, step: 1)
                numberRow(label: "Stroke (thin)", binding: $draft.strokeWidthThin, range: 0.5...8, step: 0.5)
                numberRow(label: "Stroke (medium)", binding: $draft.strokeWidthMedium, range: 0.5...12, step: 0.5)
                numberRow(label: "Shadow Opacity", binding: $draft.shadowOpacity, range: 0...1, step: 0.05)
                numberRow(label: "Shadow Radius", binding: $draft.shadowRadius, range: 0...32, step: 1)
            }
        }
    }

    // MARK: - Script sub-theme

    @ViewBuilder
    private var scriptThemeGroup: some View {
        DisclosureGroup("Script Theme") {
            VStack(alignment: .leading, spacing: 6) {
                ThemeColorWell(label: "Background", color: $draft.scriptTheme.background, disabled: isReadOnly)
                ThemeColorWell(label: "Foreground", color: $draft.scriptTheme.foreground, disabled: isReadOnly)
                ThemeColorWell(label: "Keyword", color: $draft.scriptTheme.keyword, disabled: isReadOnly)
                ThemeColorWell(label: "Command", color: $draft.scriptTheme.command, disabled: isReadOnly)
                ThemeColorWell(label: "String", color: $draft.scriptTheme.stringLiteral, disabled: isReadOnly)
                ThemeColorWell(label: "Number", color: $draft.scriptTheme.numberLiteral, disabled: isReadOnly)
                ThemeColorWell(label: "Comment", color: $draft.scriptTheme.comment, disabled: isReadOnly)
                ThemeColorWell(label: "Identifier", color: $draft.scriptTheme.identifier, disabled: isReadOnly)
                ThemeColorWell(label: "Property", color: $draft.scriptTheme.property, disabled: isReadOnly)
                ThemeColorWell(label: "Operator", color: $draft.scriptTheme.operatorSymbol, disabled: isReadOnly)
                ThemeColorWell(label: "Bracket", color: $draft.scriptTheme.bracket, disabled: isReadOnly)
                ThemeColorWell(label: "Error", color: $draft.scriptTheme.error, disabled: isReadOnly)
                ThemeColorWell(label: "Selection", color: $draft.scriptTheme.selection, disabled: isReadOnly)
                ThemeColorWell(label: "Line Number", color: $draft.scriptTheme.lineNumber, disabled: isReadOnly)
                ThemeColorWell(label: "Current Line", color: $draft.scriptTheme.currentLine, disabled: isReadOnly)

                Divider().padding(.vertical, 4)

                numberRow(label: "Font Size", binding: $draft.scriptTheme.fontSize, range: 8...32, step: 1)
                numberRow(label: "Line Spacing", binding: $draft.scriptTheme.lineSpacing, range: 0.8...3, step: 0.05)
            }
        }
    }

    // MARK: - Reusable rows

    @ViewBuilder
    private func groupHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.secondary)
            .padding(.top, 4)
    }

    @ViewBuilder
    private func numberRow(
        label: String,
        binding: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .frame(width: 140, alignment: .trailing)
                .foregroundColor(.secondary)
            Slider(value: binding, in: range, step: step)
                .frame(maxWidth: .infinity)
            TextField("", value: binding, format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 60)
        }
        .disabled(isReadOnly)
    }

    @ViewBuilder
    private func fontPickerRow(label: String, binding: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .frame(width: 140, alignment: .trailing)
                .foregroundColor(.secondary)
            Picker("", selection: binding) {
                // Anchor the current value at the top so themes that
                // reference a font not installed on this Mac still
                // show their saved value rather than silently snapping
                // to the first installed family.
                if !themeFontFamilies.contains(binding.wrappedValue) {
                    Text("\(binding.wrappedValue) (missing)")
                        .tag(binding.wrappedValue)
                }
                ForEach(themeFontFamilies, id: \.self) { family in
                    Text(family).tag(family)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .disabled(isReadOnly)
    }

    // MARK: - Save plumbing

    /// Schedule a debounced commit. Replaces any in-flight save so a
    /// burst of keystrokes results in exactly one document write at
    /// the tail of the burst.
    private func scheduleSave() {
        guard !isReadOnly else { return }
        saveTask?.cancel()
        saveTask = Task { [draft] in
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
            if Task.isCancelled { return }
            await MainActor.run {
                applySave(draft)
            }
        }
    }

    /// Synchronous flush — used on view disappear so we don't drop
    /// the user's last edit.
    private func commitDraft() {
        guard !isReadOnly else { return }
        applySave(draft)
    }

    private func applySave(_ updated: HypeTheme) {
        // Always re-resolve the document at write time. Don't trust a
        // closure-captured wrapper — by the time the debounce fires,
        // SwiftUI may have replaced the binding's underlying value.
        _ = document.document.updateTheme(id: updated.id) { $0 = updated }
    }
}
