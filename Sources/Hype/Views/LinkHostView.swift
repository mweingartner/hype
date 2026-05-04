import AppKit
import HypeCore

/// AppKit-hosted hyperlink for `link` parts.
///
/// Renders the link text as a blue underlined `NSTextField`. Mouse-up
/// fires the `onClick` closure which is wired to open the URL (after
/// scheme allow-listing) and dispatch the `linkOpened` lifecycle message.
final class LinkHostNSView: NSView {

    private let textField = NSTextField(labelWithString: "")

    /// Called when the user clicks the link. Implementors should call
    /// `safeLinkOpen(urlString:)` after dispatching the `linkOpened` message.
    var onClick: (() -> Void)?

    // Security condition 1: only these schemes are allowed.
    private static let allowedSchemes: Set<String> = ["http", "https", "mailto"]

    // Cached applied state.
    private var appliedText: String?
    private var appliedURL: String?
    private var appliedFontName: String?
    private var appliedFontSize: Double?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.isEditable = false
        textField.isSelectable = false
        textField.drawsBackground = false
        textField.isBordered = false
        addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(_ part: Part) {
        let newText = part.textContent.isEmpty ? part.url : part.textContent
        let newURL = part.url
        let newFontName = part.textFont
        let newFontSize = part.textSize

        guard newText != appliedText || newURL != appliedURL
            || newFontName != appliedFontName || newFontSize != appliedFontSize else { return }

        appliedText = newText
        appliedURL = newURL
        appliedFontName = newFontName
        appliedFontSize = newFontSize

        let fontSize = CGFloat(newFontSize > 0 ? newFontSize : 14)
        let nsFont = NSFont(name: newFontName, size: fontSize)
            ?? NSFont.systemFont(ofSize: fontSize)

        let linkColor = NSColor(red: 0, green: 0.4, blue: 0.8, alpha: 1)
        let attrString = NSAttributedString(string: newText, attributes: [
            .font: nsFont,
            .foregroundColor: linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ])
        textField.attributedStringValue = attrString
    }

    override func mouseUp(with event: NSEvent) {
        onClick?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    /// Open a URL only if it passes the scheme allow-list.
    ///
    /// Security condition 1: guard against `file://`, `javascript:`, and
    /// other potentially dangerous schemes. Only http, https, and mailto
    /// are permitted.
    func safeLinkOpen(urlString: String) {
        guard !urlString.isEmpty,
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              Self.allowedSchemes.contains(scheme) else {
            HypeLogger.shared.warn(
                "link: refusing to open URL with disallowed or missing scheme '\(urlString)'",
                source: "Link"
            )
            return
        }
        NSWorkspace.shared.open(url)
    }
}
