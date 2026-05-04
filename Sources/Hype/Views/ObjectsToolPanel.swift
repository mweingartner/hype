import SwiftUI

/// Slide-out objects/tools panel docked on the left edge of the
/// stack window. Replaces the legacy top-of-window object toolbar.
///
/// Sections (top → bottom):
/// 1. Run / Edit mode toggle pair (vertical stack so each button has
///    its full width inside the narrow panel — the previous side-by-
///    side layout clipped both labels)
/// 2. Selection / Browse tools
/// 3. Object-creation tools, grouped by family (basic / framework /
///    form-controls / paint shortcuts) with subtle section dividers
///    and small captions
/// 4. Paint-layer tools (pencil, spray, bucket, eraser, line)
///
/// **Resizable**: the panel uses `minWidth / idealWidth / maxWidth`
/// rather than a fixed `.frame(width:)` so the user can drag the
/// `HSplitView` divider to widen the panel — the `LazyVGrid` then
/// reflows to two or three columns automatically (`.adaptive(...)`).
struct ObjectsToolPanel: View {
    @Binding var currentTool: ToolName
    @Binding var selectedPartIds: Set<UUID>

    /// Persisted across launches and across all windows.
    @AppStorage("hypeRuntimeMode") private var isRuntimeMode: Bool = false

    /// Fly-out hover state. `hoveredItem` identifies the button the
    /// flyout is currently attached to; `hoveredFrameMidY` is the
    /// vertical center of that button (in panel-local coordinates)
    /// so the flyout aligns with it.
    @State private var hoveredItem: FlyoutItem? = nil
    @State private var hoveredFrameMidY: CGFloat = 0
    @State private var hoverWorkItem: DispatchWorkItem? = nil

    /// Measured panel width — flyouts position themselves just past
    /// the trailing edge of THIS, not the ideal-width constant, so
    /// a user-resized panel still gets correctly-anchored flyouts.
    /// Updated via a GeometryReader background on the root.
    @State private var measuredPanelWidth: CGFloat = 52

    // MARK: - Tool grouping

    /// Selection / runtime-vs-edit clicking. Two distinct semantics
    /// even though the icons sit close to each other in the panel.
    private static let selectionTools: [ToolName] = [.browse, .select]

    /// Classic HyperCard-feeling object creators: button, field,
    /// shape, image. Plus the more recent web/video/chart trio.
    private static let basicTools: [ToolName] = [
        .button, .field, .shape, .image, .text,
        .webpage, .video, .chart
    ]

    /// Framework-backed controls added in 2026 — calendar, PDF, map,
    /// 3D scene, etc. Grouped together so users can see them as a
    /// distinct "richer media" family.
    private static let frameworkTools: [ToolName] = [
        .calendar, .pdf, .map, .colorWell, .audioRecorder,
        .scene3D, .spriteArea
    ]

    /// AppKit form controls. They share a control-value backing
    /// field and a similar feel.
    private static let formControlTools: [ToolName] = [
        .stepper, .slider, .toggle, .segmented,
        .progressView, .gauge, .link, .menu, .searchField, .divider
    ]

    /// Drag-to-create vector shape shortcuts (rectangle, oval, line)
    /// PLUS the raster-paint tools (pencil, spray, bucket, eraser).
    /// Grouped at the bottom because they're used less often than
    /// object-creation tools.
    private static let paintTools: [ToolName] = [
        .rect, .oval, .line,
        .pencil, .spray, .bucket, .eraser
    ]

    // MARK: - Sizing constants

    private static let buttonSize: CGFloat = 36
    private static let panelMinWidth: CGFloat = 60
    private static let panelIdealWidth: CGFloat = 60
    private static let panelMaxWidth: CGFloat = 220
    private static let hoverShowDelay: TimeInterval = 0.4
    private static let hoverHideDelay: TimeInterval = 0.1
    private static let flyoutWidth: CGFloat = 260

    var body: some View {
        // Adaptive grid — wraps to 2/3 columns automatically when
        // the user widens the panel via the HSplitView divider.
        let gridItem = GridItem(.adaptive(minimum: 44, maximum: 52), spacing: 4)

        VStack(spacing: 0) {
            // 1. Run / Edit toggle — VERTICAL stack so each label is
            //    fully visible inside the narrow panel. Side-by-side
            //    layout was clipping both buttons.
            VStack(spacing: 4) {
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

            Divider().padding(.horizontal, 4)

            if !isRuntimeMode {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        toolSection("Select", tools: Self.selectionTools, gridItem: gridItem)
                        sectionDivider
                        toolSection("Objects", tools: Self.basicTools, gridItem: gridItem)
                        sectionDivider
                        toolSection("Framework", tools: Self.frameworkTools, gridItem: gridItem)
                        sectionDivider
                        toolSection("Form", tools: Self.formControlTools, gridItem: gridItem)
                        sectionDivider
                        toolSection("Paint", tools: Self.paintTools, gridItem: gridItem)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                }
            } else {
                Spacer().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Resizable: HSplitView honours minWidth / idealWidth / maxWidth.
        // Default ~60pt for a single column; user can drag the divider
        // to ~220pt for two or three columns.
        .frame(
            minWidth: Self.panelMinWidth,
            idealWidth: Self.panelIdealWidth,
            maxWidth: Self.panelMaxWidth
        )
        .background(.regularMaterial)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 1)
        }
        .coordinateSpace(name: "objectsToolPanel")
        .background(
            // Measure the panel's actual width so the flyout
            // anchors next to the trailing edge regardless of
            // user resize.
            GeometryReader { geo in
                Color.clear
                    .onAppear { measuredPanelWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, w in
                        measuredPanelWidth = w
                    }
            }
        )
        .overlay(alignment: .topLeading) {
            if let item = hoveredItem {
                ToolFlyoutView(title: item.title, description: item.description)
                    .frame(width: Self.flyoutWidth, alignment: .topLeading)
                    .offset(
                        x: measuredPanelWidth + 8,
                        y: max(0, hoveredFrameMidY - 30)
                    )
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                    .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: hoveredItem)
    }

    @ViewBuilder
    private var sectionDivider: some View {
        Divider()
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
    }

    @ViewBuilder
    private func toolSection(_ title: String, tools: [ToolName], gridItem: GridItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            LazyVGrid(columns: [gridItem], spacing: 4) {
                ForEach(tools, id: \.self) { tool in
                    toolButton(tool)
                }
            }
        }
    }

    // MARK: - Buttons

    @ViewBuilder
    private func modeButton(item: FlyoutItem, title: String, systemImage: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                Text(title)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .foregroundColor(isActive ? .accentColor : .primary)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
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

    // MARK: - Hover plumbing

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
