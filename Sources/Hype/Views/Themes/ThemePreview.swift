import SwiftUI
import HypeCore

/// The right pane of the Theme Designer.
///
/// Two stacked sections:
///
/// 1. **Live preview** — a synthetic 360x240 mini-card rendered with
///    the currently-edited theme. Includes one of every common part
///    surface (button, field, shape, label) plus a faux-selection
///    rectangle so the user can judge selection contrast at a glance.
///    Updates instantly as the user edits the theme — every value is
///    pulled from the bound `theme` so SwiftUI re-renders on change.
///
/// 2. **Affected panel** — usage counts via
///    `HypeDocument.usageCount(themeName:)`, telling the user which
///    cards / backgrounds / stack default actually use the theme they
///    are editing. Built-in themes typically show "Stack default" or
///    "Not currently used"; user themes show whatever the user has
///    assigned via the inspector or HypeTalk.
///
/// Both sections re-evaluate when `document` changes, so deleting a
/// card that referenced this theme or assigning the theme elsewhere
/// updates the panel without any explicit refresh notification.
struct ThemePreview: View {
    /// The theme being authored. The inner sample card renders with
    /// THIS theme so the preview always reflects the in-progress
    /// edits — never the active stack theme. The outer container
    /// chrome around the preview, however, uses the active stack
    /// theme via `hypeTheme` below.
    let theme: HypeTheme
    @Binding var document: HypeDocumentWrapper
    @Environment(\.hypeTheme) private var hypeTheme

    private var usage: ThemeUsage {
        document.document.usageCount(themeName: theme.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("PREVIEW")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)

            previewCard
                .frame(width: 360, height: 240)

            Divider()

            affectedSection

            Spacer()
        }
        .padding(16)
        .frame(width: 400, alignment: .topLeading)
        // Outer chrome — uses the ACTIVE stack theme (via
        // `hypeTheme`), not the in-progress edited `theme`. This
        // keeps the preview pane's surrounding background
        // consistent with the rest of the designer window. The
        // inner `previewCard` continues to use `theme` so the
        // sample renders with the user's edits.
        .background(hypeTheme.inspectorBackground.swiftUIColor)
        .environment(\.colorScheme, hypeTheme.chromeColorScheme)
    }

    // MARK: - Preview card

    @ViewBuilder
    private var previewCard: some View {
        ZStack {
            // Background fill behind the card so the user can see the
            // contrast between cardBackground and backgroundFill.
            theme.backgroundFill.swiftUIColor

            RoundedRectangle(cornerRadius: theme.cornerRadiusMedium)
                .fill(theme.cardBackground.swiftUIColor)
                .shadow(
                    color: Color.black.opacity(theme.shadowOpacity),
                    radius: theme.shadowRadius,
                    x: 0,
                    y: 2
                )
                .padding(12)

            VStack(alignment: .leading, spacing: 12) {
                // Heading using the theme's heading font.
                Text(theme.name)
                    .font(theme.headingFont)
                    .foregroundColor(theme.cardForeground.swiftUIColor)

                // Sample button.
                sampleButton

                // Sample field.
                sampleField

                // Sample shape, with a faux-selection ring so the
                // user can judge selection contrast against the card
                // surface.
                sampleShape

                Spacer(minLength: 0)
            }
            .padding(24)
        }
        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: theme.cornerRadiusMedium)
                .stroke(theme.panelDivider.swiftUIColor, lineWidth: theme.strokeWidthThin)
        )
    }

    @ViewBuilder
    private var sampleButton: some View {
        Text("Click me")
            .font(theme.bodyFont)
            .foregroundColor(theme.buttonForeground.swiftUIColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: theme.cornerRadiusSmall)
                    .fill(theme.buttonBackground.swiftUIColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: theme.cornerRadiusSmall)
                    .stroke(theme.buttonBorder.swiftUIColor, lineWidth: theme.strokeWidthThin)
            )
    }

    @ViewBuilder
    private var sampleField: some View {
        Text("Sample text")
            .font(theme.bodyFont)
            .foregroundColor(theme.fieldForeground.swiftUIColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(width: 200, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: theme.cornerRadiusSmall)
                    .fill(theme.fieldBackground.swiftUIColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: theme.cornerRadiusSmall)
                    .stroke(theme.fieldBorder.swiftUIColor, lineWidth: theme.strokeWidthThin)
            )
    }

    @ViewBuilder
    private var sampleShape: some View {
        // Selection ring — a translucent fill plus a 2px stroke. This
        // is the same composition used by `CardCanvasView` for
        // selected parts, so the preview matches what the user sees
        // when they actually select a part on a card.
        RoundedRectangle(cornerRadius: theme.cornerRadiusSmall)
            .fill(theme.shapeFillDefault.swiftUIColor)
            .frame(width: 60, height: 36)
            .overlay(
                RoundedRectangle(cornerRadius: theme.cornerRadiusSmall)
                    .stroke(theme.shapeStrokeDefault.swiftUIColor, lineWidth: theme.strokeWidthMedium)
            )
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: theme.cornerRadiusSmall + 4)
                    .fill(theme.selectionFill.swiftUIColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: theme.cornerRadiusSmall + 4)
                    .stroke(theme.selectionStroke.swiftUIColor, lineWidth: theme.strokeWidthMedium)
            )
    }

    // MARK: - Affected section

    @ViewBuilder
    private var affectedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AFFECTED BY THIS THEME")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)

            if usage.isInUse {
                if usage.cards > 0 {
                    Label(
                        "\(usage.cards) card\(usage.cards == 1 ? "" : "s")",
                        systemImage: "rectangle.portrait"
                    )
                    .font(.system(size: 11))
                }
                if usage.backgrounds > 0 {
                    Label(
                        "\(usage.backgrounds) background\(usage.backgrounds == 1 ? "" : "s")",
                        systemImage: "rectangle.on.rectangle"
                    )
                    .font(.system(size: 11))
                }
                if usage.isStackDefault {
                    Label("Stack default", systemImage: "square.stack.3d.up")
                        .font(.system(size: 11))
                }
            } else {
                Text("Not currently used")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }
}
