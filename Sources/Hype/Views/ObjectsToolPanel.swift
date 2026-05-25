import AppKit
import HypeCore
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

private struct ObjectToolDragButton: NSViewRepresentable {
    let tool: ToolName
    let isActive: Bool
    let help: ObjectToolHoverHelp
    let buttonSize: CGFloat
    let onSelect: () -> Void

    func makeNSView(context: Context) -> ObjectToolDragButtonNSView {
        ObjectToolDragButtonNSView(
            tool: tool,
            isActive: isActive,
            help: help,
            onSelect: onSelect
        )
    }

    func updateNSView(_ nsView: ObjectToolDragButtonNSView, context: Context) {
        nsView.configure(
            tool: tool,
            isActive: isActive,
            help: help,
            onSelect: onSelect
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ObjectToolDragButtonNSView, context: Context) -> CGSize? {
        CGSize(width: buttonSize, height: buttonSize)
    }
}

private final class ObjectToolDragButtonNSView: NSView, NSDraggingSource {
    private let imageView = NSImageView()
    private var tool: ToolName
    private var isActiveTool: Bool
    private var help: ObjectToolHoverHelp
    private var onSelect: () -> Void
    private var mouseDownPoint: NSPoint?
    private var mouseDownEvent: NSEvent?
    private var didBeginDrag = false
    private var hoverTrackingArea: NSTrackingArea?

    init(tool: ToolName, isActive: Bool, help: ObjectToolHoverHelp, onSelect: @escaping () -> Void) {
        self.tool = tool
        self.isActiveTool = isActive
        self.help = help
        self.onSelect = onSelect
        super.init(frame: NSRect(x: 0, y: 0, width: 36, height: 36))
        wantsLayer = true
        imageView.imageScaling = .scaleProportionallyDown
        addSubview(imageView)
        configure(tool: tool, isActive: isActive, help: help, onSelect: onSelect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 36, height: 36) }

    func configure(tool: ToolName, isActive: Bool, help: ObjectToolHoverHelp, onSelect: @escaping () -> Void) {
        self.tool = tool
        self.isActiveTool = isActive
        self.help = help
        self.onSelect = onSelect
        imageView.image = NSImage(systemSymbolName: tool.systemImageName, accessibilityDescription: tool.displayTitle)
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: isActive ? .semibold : .regular)
        imageView.contentTintColor = isActive ? .controlAccentColor : .labelColor
        toolTip = nil
        setAccessibilityIdentifier(HypeAccessibilityID.tool(tool))
        setAccessibilityRole(.button)
        setAccessibilityLabel(tool.displayTitle)
        setAccessibilityHelp(tool.description)
        setAccessibilityValue(isActive ? "selected" : "not selected")
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let imageSize: CGFloat = 18
        imageView.frame = NSRect(
            x: (bounds.width - imageSize) / 2,
            y: (bounds.height - imageSize) / 2,
            width: imageSize,
            height: imageSize
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        hoverTrackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        ObjectToolHelpWindowPresenter.shared.show(help)
    }

    override func mouseExited(with event: NSEvent) {
        ObjectToolHelpWindowPresenter.shared.hide(help)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        mouseDownEvent = event
        didBeginDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didBeginDrag,
              let start = mouseDownPoint,
              let downEvent = mouseDownEvent else {
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let dx = point.x - start.x
        let dy = point.y - start.y
        guard hypot(dx, dy) >= 3 else {
            return
        }

        didBeginDrag = true
        ObjectToolHelpWindowPresenter.shared.hide(help)
        onSelect()

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(
            ObjectToolCatalog.dragPayload(for: tool),
            forType: NSPasteboard.PasteboardType(ObjectToolCatalog.dragPasteboardTypeRaw)
        )
        pasteboardItem.setString(ObjectToolCatalog.dragPayload(for: tool), forType: .string)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(bounds.insetBy(dx: 2, dy: 2), contents: draggingPreviewImage())
        beginDraggingSession(with: [draggingItem], event: downEvent, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if !didBeginDrag {
            onSelect()
        }
        didBeginDrag = false
        mouseDownPoint = nil
        mouseDownEvent = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isActiveTool else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        false
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        didBeginDrag = false
        mouseDownPoint = nil
        mouseDownEvent = nil
    }

    private func draggingPreviewImage() -> NSImage {
        let size = bounds.size == .zero ? NSSize(width: 36, height: 36) : bounds.size
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
        let rect = NSRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        NSColor.controlAccentColor.withAlphaComponent(0.65).setStroke()
        let outline = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        outline.lineWidth = 1.5
        outline.stroke()
        if let symbol = NSImage(systemSymbolName: tool.systemImageName, accessibilityDescription: tool.displayTitle) {
            symbol.lockFocus()
            NSColor.controlAccentColor.set()
            symbol.unlockFocus()
            let symbolSize = NSSize(width: 18, height: 18)
            let symbolRect = NSRect(
                x: (size.width - symbolSize.width) / 2,
                y: (size.height - symbolSize.height) / 2,
                width: symbolSize.width,
                height: symbolSize.height
            )
            symbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 0.95)
        }
        image.unlockFocus()
        return image
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
/// **Hover help** uses one visible surface: an immediate floating help
/// card owned by `ObjectToolHelpWindowPresenter`. Native `.help(_:)` /
/// `NSToolTip` wiring is intentionally avoided for these same controls
/// because running both surfaces produces duplicate bubbles. Accessibility
/// labels, hints, and values still expose the same guidance to assistive
/// technologies without creating a second visual tooltip.
struct ObjectsToolPanel: View {
    @Binding var currentTool: ToolName
    @Binding var selectedPartIds: Set<UUID>
    let isRuntimeMode: Bool
    let targetPlatforms: [HypeTargetPlatform]

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
                        ForEach(Array(ObjectToolCatalog.authoringSections(for: targetPlatforms).enumerated()), id: \.offset) { index, section in
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
        .onHover { setActiveHelp(help, isHovering: $0) }
        .accessibilityLabel(title)
        .accessibilityHint(help.body)
        .accessibilityValue(isActive ? "active" : "inactive")
        .accessibilityIdentifier(HypeAccessibilityID.toolbar("mode.\(title.lowercased())"))
    }

    @ViewBuilder
    private func toolButton(_ tool: ToolName) -> some View {
        let help = ObjectToolHoverHelp(title: tool.displayTitle, body: ObjectToolCatalog.tooltipBody(for: tool))

        if ObjectToolCatalog.createdPartType(for: tool) != nil {
            ObjectToolDragButton(
                tool: tool,
                isActive: currentTool == tool,
                help: help,
                buttonSize: Self.buttonSize,
                onSelect: {
                    currentTool = tool
                    selectedPartIds = []
                }
            )
            .frame(width: Self.buttonSize, height: Self.buttonSize)
            .accessibilityLabel(tool.displayTitle)
            .accessibilityHint(tool.description)
            .accessibilityValue(currentTool == tool ? "selected" : "not selected")
            .accessibilityIdentifier(HypeAccessibilityID.tool(tool))
        } else {
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
            .onHover { setActiveHelp(help, isHovering: $0) }
            .accessibilityLabel(tool.displayTitle)
            .accessibilityHint(tool.description)
            .accessibilityValue(currentTool == tool ? "selected" : "not selected")
            .accessibilityIdentifier(HypeAccessibilityID.tool(tool))
        }
    }
}
