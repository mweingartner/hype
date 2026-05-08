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
///
/// **Hover help** is delivered via SwiftUI's native `.help(_:)`
/// modifier, which wraps `NSToolTip`. The previous implementation
/// used a custom SwiftUI flyout view with `.onHover` plumbing,
/// debounce timers, and an animated transition. That looked nice on
/// paper but had three real-world problems:
///   - the slide-from-leading-edge transition read as the bubble
///     "flying" in/out, distracting from the content;
///   - the 0.1s hide delay made the bubble vanish before the user
///     could read multi-line descriptions;
///   - `.onHover` inside a `.background(GeometryReader)` was flaky
///     in practice — depending on layout/animation interactions the
///     hover events sometimes failed to fire at all, leaving users
///     with no help bubbles AT ALL.
///
/// `NSToolTip` is what every native macOS app uses, and it's what
/// users expect. It appears after a system-tuned hover delay
/// (~0.7s, configurable via NSUserDefaults), wraps multi-line
/// content cleanly, and disappears when the cursor leaves —
/// without animation, race conditions, or tracking-area gotchas.
struct ObjectsToolPanel: View {
    @Binding var currentTool: ToolName
    @Binding var selectedPartIds: Set<UUID>

    /// Persisted across launches and across all windows.
    @AppStorage("hypeRuntimeMode") private var isRuntimeMode: Bool = false

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
        .stepper, .slider, .segmented,
        .progressView, .gauge, .divider
    ]
    // .toggle, .link, .menu, .searchField removed in dedup —
    // create them as button (with .toggle / .link / .popup style)
    // or field (with .search style) instead.

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
                    title: "Run",
                    systemImage: "play.fill",
                    isActive: isRuntimeMode,
                    helpText: tooltipText(
                        title: "Runtime Mode",
                        body: "Hides editing chrome (property inspector, sprite repository, AI panel) and runs the stack as the end user experiences it. Toggle with ⇧⌘E."
                    ),
                    action: {
                        if !isRuntimeMode {
                            NotificationCenter.default.post(name: .toggleRuntimeMode, object: nil)
                        }
                    }
                )

                modeButton(
                    title: "Edit",
                    systemImage: "pencil",
                    isActive: !isRuntimeMode,
                    helpText: tooltipText(
                        title: "Edit Mode",
                        body: "Restores the property inspector and the full tool palette so you can author the stack. Toggle with ⇧⌘E."
                    ),
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

    /// Format a tooltip string with a short title on the first line
    /// followed by a blank line and the body. NSToolTip wraps long
    /// text automatically (~250pt-wide); the leading title gives a
    /// quick read of what the icon does even when the body wraps to
    /// several lines.
    private func tooltipText(title: String, body: String) -> String {
        "\(title)\n\n\(body)"
    }

    // MARK: - Buttons

    @ViewBuilder
    private func modeButton(
        title: String,
        systemImage: String,
        isActive: Bool,
        helpText: String,
        action: @escaping () -> Void
    ) -> some View {
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
        .help(helpText)
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
        .help(tooltipText(title: tool.displayTitle, body: tool.description))
    }
}
