import AppKit
import SwiftUI

private struct ObjectToolHoverHelp: Equatable, Sendable {
    let title: String
    let body: String

    var text: String {
        "\(title)\n\n\(body)"
    }
}

private struct ObjectToolFloatingHelpCard: View {
    let help: ObjectToolHoverHelp

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(help.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
            Text(help.body)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 320, alignment: .leading)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 6)
        .accessibilityHidden(true)
    }
}

@MainActor
private final class ObjectToolHelpWindowPresenter {
    static let shared = ObjectToolHelpWindowPresenter()

    private var panel: NSPanel?
    private var currentHelp: ObjectToolHoverHelp?

    private init() {}

    func show(_ help: ObjectToolHoverHelp) {
        currentHelp = help

        let host = NSHostingView(rootView: ObjectToolFloatingHelpCard(help: help))
        let width: CGFloat = 340
        let fitting = host.fittingSize
        let height = min(max(fitting.height, 80), 320)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)

        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentView = host
        panel.setContentSize(host.frame.size)
        panel.setFrameOrigin(frameOrigin(for: host.frame.size, near: NSEvent.mouseLocation))
        panel.orderFrontRegardless()
    }

    func hide(_ help: ObjectToolHoverHelp? = nil) {
        if let help, currentHelp != help {
            return
        }
        currentHelp = nil
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.transient, .ignoresCycle, .canJoinAllSpaces]
        return panel
    }

    private func frameOrigin(for size: NSSize, near mouse: NSPoint) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let margin: CGFloat = 12
        let cursorGap: CGFloat = 18

        var x = mouse.x + cursorGap
        var y = mouse.y - size.height - cursorGap

        if x + size.width > visible.maxX - margin {
            x = mouse.x - size.width - cursorGap
        }
        if y < visible.minY + margin {
            y = mouse.y + cursorGap
        }

        x = min(max(x, visible.minX + margin), visible.maxX - size.width - margin)
        y = min(max(y, visible.minY + margin), visible.maxY - size.height - margin)
        return NSPoint(x: x, y: y)
    }
}

/// Slide-out objects/tools panel docked on the left edge of the
/// stack window. Replaces the legacy top-of-window object toolbar.
///
/// Sections (top → bottom):
/// 1. Run / Edit mode toggle pair (vertical stack so each button has
///    its full width inside the narrow panel — the previous side-by-
///    side layout clipped both labels)
/// 2. Selection / Browse tools
/// 3. Object-creation tools, grouped by family (objects / framework)
///    with subtle section dividers and small captions
/// 4. Paint-layer tools (pencil, spray, bucket, eraser)
///
/// **Resizable**: the panel uses `minWidth / idealWidth / maxWidth`
/// rather than a fixed `.frame(width:)` so the user can drag the
/// `HSplitView` divider to widen the panel — the `LazyVGrid` then
/// reflows to two or three columns automatically (`.adaptive(...)`).
///
/// **Hover help** is provided twice: native `.help(_:)` for standard
/// macOS tooltips and an immediate in-app help card. The custom card
/// avoids the common failure mode where `NSToolTip` tracking is delayed
/// or suppressed while the user is moving quickly through the palette,
/// while the native tooltip keeps normal accessibility/platform behavior.
struct ObjectsToolPanel: View {
    @Binding var currentTool: ToolName
    @Binding var selectedPartIds: Set<UUID>
    let isRuntimeMode: Bool

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
                    help: ObjectToolHoverHelp(
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
                    help: ObjectToolHoverHelp(
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
                        ForEach(Array(ObjectToolCatalog.authoringSections.enumerated()), id: \.offset) { index, section in
                            if index > 0 {
                                sectionDivider
                            }
                            toolSection(section.title, tools: section.tools, gridItem: gridItem)
                        }
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
        .accessibilityLabel("Objects and Tools")
        .accessibilityIdentifier(HypeAccessibilityID.objectsPanel)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 1)
        }
        .onDisappear {
            Task { @MainActor in
                ObjectToolHelpWindowPresenter.shared.hide()
            }
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

    private func setActiveHelp(_ help: ObjectToolHoverHelp, isHovering: Bool) {
        Task { @MainActor in
            if isHovering {
                ObjectToolHelpWindowPresenter.shared.show(help)
            } else {
                ObjectToolHelpWindowPresenter.shared.hide(help)
            }
        }
    }

    // MARK: - Buttons

    @ViewBuilder
    private func modeButton(
        title: String,
        systemImage: String,
        isActive: Bool,
        help: ObjectToolHoverHelp,
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
        .help(help.text)
        .onHover { setActiveHelp(help, isHovering: $0) }
        .accessibilityLabel(title)
        .accessibilityValue(isActive ? "active" : "inactive")
        .accessibilityIdentifier(HypeAccessibilityID.toolbar("mode.\(title.lowercased())"))
    }

    @ViewBuilder
    private func toolButton(_ tool: ToolName) -> some View {
        let help = ObjectToolHoverHelp(title: tool.displayTitle, body: ObjectToolCatalog.tooltipBody(for: tool))

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
        .help(help.text)
        .onHover { setActiveHelp(help, isHovering: $0) }
        .accessibilityLabel(tool.displayTitle)
        .accessibilityHint(tool.description)
        .accessibilityValue(currentTool == tool ? "selected" : "not selected")
        .accessibilityIdentifier(HypeAccessibilityID.tool(tool))
    }
}
