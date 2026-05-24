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
///    form-controls) with subtle section dividers
///    and small captions
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

    @State private var activeHelp: HoverHelp?

    // MARK: - Sizing constants

    private static let buttonSize: CGFloat = 36
    private static let panelMinWidth: CGFloat = 60
    private static let panelIdealWidth: CGFloat = 60
    private static let panelMaxWidth: CGFloat = 220

    private struct HoverHelp: Equatable {
        let title: String
        let body: String

        var text: String {
            "\(title)\n\n\(body)"
        }
    }

    var body: some View {
        // Adaptive grid — wraps to 2/3 columns automatically when
        // the user widens the panel via the HSplitView divider.
        let gridItem = GridItem(.adaptive(minimum: 44, maximum: 52), spacing: 4)

        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                // 1. Run / Edit toggle — VERTICAL stack so each label is
                //    fully visible inside the narrow panel. Side-by-side
                //    layout was clipping both buttons.
                VStack(spacing: 4) {
                    modeButton(
                        title: "Run",
                        systemImage: "play.fill",
                        isActive: isRuntimeMode,
                        help: HoverHelp(
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
                        help: HoverHelp(
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

            if let activeHelp {
                hoverHelpCard(activeHelp)
                    .offset(x: Self.panelMinWidth + 8, y: 50)
                    .transition(.opacity)
                    .zIndex(10)
                    .allowsHitTesting(false)
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

    private func setActiveHelp(_ help: HoverHelp, isHovering: Bool) {
        if isHovering {
            activeHelp = help
        } else if activeHelp == help {
            activeHelp = nil
        }
    }

    @ViewBuilder
    private func hoverHelpCard(_ help: HoverHelp) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(help.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
            Text(help.body)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 300, alignment: .leading)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 6)
        .accessibilityHidden(true)
    }

    // MARK: - Buttons

    @ViewBuilder
    private func modeButton(
        title: String,
        systemImage: String,
        isActive: Bool,
        help: HoverHelp,
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
        let help = HoverHelp(title: tool.displayTitle, body: ObjectToolCatalog.tooltipBody(for: tool))

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
