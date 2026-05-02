import SwiftUI

/// Slide-out objects/tools panel docked on the left edge of the
/// stack window. Replaces the legacy top-of-window object toolbar.
///
/// Auto-flow into a second column when the window is too short to
/// hold every tool button at the chosen icon size — `LazyVGrid` with
/// `GridItem(.adaptive(...))` handles that automatically. The panel
/// width adapts to the column count: one column when everything
/// fits, two columns otherwise.
///
/// First two items are the **Run** and **Edit** mode toggles per the
/// design brief — they are visually separated from the tool palette
/// by a divider so users see them as a distinct affordance, not as
/// "another tool."
struct ObjectsToolPanel: View {
    @Binding var currentTool: ToolName
    @Binding var selectedPartIds: Set<UUID>

    /// Persisted across launches and across all windows.
    @AppStorage("hypeRuntimeMode") private var isRuntimeMode: Bool = false

    /// Pre-computed tool list — `ToolName.allCases` minus tools that
    /// don't make sense in browse-only runtime mode.
    private var palette: [ToolName] {
        // In runtime mode the palette is hidden entirely (see
        // MainContentView's slide-out gating). When edit mode the
        // full palette is exposed.
        ToolName.allCases
    }

    /// Diameter of each tool button. Fixed so the grid math stays
    /// predictable across themes.
    private static let buttonSize: CGFloat = 36

    var body: some View {
        // Adaptive grid: 1 column when window is tall enough for
        // every tool, 2 columns when it isn't. The fixed-width
        // GridItem with min: 44 keeps the cells from expanding past
        // the button-size + padding.
        let gridItem = GridItem(.adaptive(minimum: 44, maximum: 44), spacing: 4)

        VStack(spacing: 0) {
            // Run / Edit toggle pair — first two items per spec.
            HStack(spacing: 4) {
                modeButton(
                    title: "Run",
                    systemImage: "play.fill",
                    isActive: isRuntimeMode,
                    action: {
                        if !isRuntimeMode {
                            NotificationCenter.default.post(name: .toggleRuntimeMode, object: nil)
                        }
                    }
                )
                .help("Runtime mode (⇧⌘E) — hide editing chrome and run the stack")

                modeButton(
                    title: "Edit",
                    systemImage: "pencil",
                    isActive: !isRuntimeMode,
                    action: {
                        if isRuntimeMode {
                            NotificationCenter.default.post(name: .toggleRuntimeMode, object: nil)
                        }
                    }
                )
                .help("Edit mode (⇧⌘E) — show the property inspector and tool palette")
            }
            .padding(.horizontal, 4)
            .padding(.top, 6)
            .padding(.bottom, 4)

            Divider()
                .padding(.horizontal, 4)

            // Tool palette — hidden in runtime mode.
            if !isRuntimeMode {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: [gridItem], spacing: 4) {
                        ForEach(palette, id: \.self) { tool in
                            toolButton(tool)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                }
            } else {
                // Spacer so the panel still occupies its width when
                // the palette is hidden — feels less like the panel
                // collapsed.
                Spacer()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // The panel's natural width grows with column count. 52 pt
        // for one column, 96 pt for two. SwiftUI evaluates this
        // implicitly when the LazyVGrid wraps to two columns.
        .frame(width: 52)
        .background(.regularMaterial)
        .overlay(alignment: .trailing) {
            // Right-edge separator so the panel reads as a distinct
            // surface from the canvas margin.
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 1)
        }
    }

    @ViewBuilder
    private func modeButton(title: String, systemImage: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: isActive ? .semibold : .regular))
                Text(title)
                    .font(.system(size: 9))
            }
            .foregroundColor(isActive ? .accentColor : .primary)
            .frame(width: 38, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func toolButton(_ tool: ToolName) -> some View {
        Button(action: {
            currentTool = tool
            selectedPartIds = []
        }) {
            Image(systemName: tool.systemImageName)
                .font(.system(size: 14))
                .foregroundColor(currentTool == tool ? .accentColor : .primary)
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(currentTool == tool ? Color.accentColor.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(tool.rawValue.capitalized)
    }
}
