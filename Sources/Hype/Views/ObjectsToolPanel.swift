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
///
/// Hovering any button for ~0.4s pops a fly-out info window to the
/// right of the panel describing what the tool does. Provides
/// substantially richer guidance than the native `.help()` tooltip
/// — full title + 2-3 sentence description per tool, matching the
/// pedagogical goal of "the user shouldn't need to memorize the
/// icon set."
struct ObjectsToolPanel: View {
    @Binding var currentTool: ToolName
    @Binding var selectedPartIds: Set<UUID>

    /// Persisted across launches and across all windows.
    @AppStorage("hypeRuntimeMode") private var isRuntimeMode: Bool = false

    /// Fly-out hover state. `hoveredItem` identifies the button the
    /// flyout is currently attached to; `hoveredFrameMidY` is the
    /// vertical center of that button (in panel-local coordinates)
    /// so the flyout aligns with it. Both are nil/0 when no flyout
    /// is showing.
    @State private var hoveredItem: FlyoutItem? = nil
    @State private var hoveredFrameMidY: CGFloat = 0
    /// Pending dispatch to set / unset `hoveredItem` after a short
    /// delay. Cancelled and replaced on every `.onHover` toggle so
    /// quick mouse passes don't trigger the flyout, and so moving
    /// between adjacent buttons doesn't flicker.
    @State private var hoverWorkItem: DispatchWorkItem? = nil

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
    /// Delay between hover-start and flyout-show. ~0.4s feels
    /// responsive without firing on every quick mouse pass.
    private static let hoverShowDelay: TimeInterval = 0.4
    /// Delay between hover-end and flyout-hide. Short, but non-zero
    /// so moving between adjacent buttons doesn't flicker.
    private static let hoverHideDelay: TimeInterval = 0.1
    private static let panelWidth: CGFloat = 52
    /// Width of the fly-out info window itself.
    private static let flyoutWidth: CGFloat = 260

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
                    item: .runMode,
                    title: "Run",
                    systemImage: "play.fill",
                    isActive: isRuntimeMode,
                    action: {
                        if !isRuntimeMode {
                            NotificationCenter.default.post(name: .toggleRuntimeMode, object: nil)
                        }
                    }
                )

                modeButton(
                    item: .editMode,
                    title: "Edit",
                    systemImage: "pencil",
                    isActive: !isRuntimeMode,
                    action: {
                        if isRuntimeMode {
                            NotificationCenter.default.post(name: .toggleRuntimeMode, object: nil)
                        }
                    }
                )
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
        .frame(width: Self.panelWidth)
        .background(.regularMaterial)
        .overlay(alignment: .trailing) {
            // Right-edge separator so the panel reads as a distinct
            // surface from the canvas margin.
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 1)
        }
        .coordinateSpace(name: "objectsToolPanel")
        // Fly-out overlay — anchored to the trailing edge of the
        // panel and offset vertically to align with the hovered
        // button. `allowsHitTesting(false)` lets the user keep
        // interacting with buttons while the flyout is on screen.
        .overlay(alignment: .topLeading) {
            if let item = hoveredItem {
                ToolFlyoutView(title: item.title, description: item.description)
                    .frame(width: Self.flyoutWidth, alignment: .topLeading)
                    .offset(
                        x: Self.panelWidth + 8,
                        y: max(0, hoveredFrameMidY - 30)
                    )
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                    .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: hoveredItem)
    }

    // MARK: - Buttons

    @ViewBuilder
    private func modeButton(item: FlyoutItem, title: String, systemImage: String, isActive: Bool, action: @escaping () -> Void) -> some View {
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
        .background(hoverGeometry(for: item))
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
        .background(hoverGeometry(for: .tool(tool)))
    }

    /// Per-button hover detector + frame tracker. Built as a
    /// `GeometryReader` background so SwiftUI gives us the button's
    /// frame in panel-local coordinates. `Color.clear`'s
    /// `.contentShape(Rectangle())` ensures hover events fire even
    /// over the button's transparent regions.
    private func hoverGeometry(for item: FlyoutItem) -> some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .onHover { hovering in
                    let midY = geo.frame(in: .named("objectsToolPanel")).midY
                    scheduleFlyout(for: item, hovering: hovering, midY: midY)
                }
        }
    }

    /// Schedule (or cancel) a flyout transition. Uses
    /// `DispatchWorkItem` so a fast mouse-out can cancel a still-
    /// pending show, and a fast mouse-in can cancel a pending hide.
    private func scheduleFlyout(for item: FlyoutItem, hovering: Bool, midY: CGFloat) {
        hoverWorkItem?.cancel()
        if hovering {
            let work = DispatchWorkItem {
                hoveredItem = item
                hoveredFrameMidY = midY
            }
            hoverWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverShowDelay, execute: work)
        } else {
            let work = DispatchWorkItem {
                if hoveredItem == item {
                    hoveredItem = nil
                }
            }
            hoverWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverHideDelay, execute: work)
        }
    }
}

// MARK: - Flyout content

/// Identifies a single button slot for fly-out attachment. Mode
/// buttons (Run/Edit) aren't ToolNames so we wrap both in a single
/// enum.
private enum FlyoutItem: Hashable {
    case runMode
    case editMode
    case tool(ToolName)

    var title: String {
        switch self {
        case .runMode: return "Runtime Mode"
        case .editMode: return "Edit Mode"
        case .tool(let t): return t.displayTitle
        }
    }

    var description: String {
        switch self {
        case .runMode:
            return "Hides editing chrome (property inspector, sprite repository, AI panel) and runs the stack as the end user experiences it. Toggle with ⇧⌘E or the Run/Edit pair at the top of this panel."
        case .editMode:
            return "Restores the property inspector and the full tool palette so you can author the stack. Toggle with ⇧⌘E or the Run/Edit pair at the top of this panel."
        case .tool(let t):
            return t.description
        }
    }
}

/// Rendered fly-out info window. A rounded rect with `.thickMaterial`
/// background, subtle drop shadow, and accent-colored title.
private struct ToolFlyoutView: View {
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
            Text(description)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.thickMaterial)
                .shadow(color: .black.opacity(0.18), radius: 8, x: 2, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.35), lineWidth: 0.5)
        )
    }
}
