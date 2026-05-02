import AppKit
import HypeCore

/// AppKit-hosted `NSColorWell` for color-well parts. The well's
/// color binds to the part's `colorWellHex`; user picks fire
/// `onColorChange` so the chat panel + HypeTalk reads stay in sync.
final class ColorWellHostNSView: NSView {

    let colorWell = NSColorWell()

    /// ISO hex of the last user-picked color. Closed over by the
    /// chat panel's writeback.
    var onColorChange: ((String) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        colorWell.translatesAutoresizingMaskIntoConstraints = false
        colorWell.target = self
        colorWell.action = #selector(colorDidChange)
        addSubview(colorWell)
        NSLayoutConstraint.activate([
            colorWell.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            colorWell.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            colorWell.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            colorWell.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Last-applied hex so apply() can compare-and-skip. Without
    /// this guard, every draw cycle would reset the color well's
    /// live value to the document's value — which clobbers the
    /// user's interactive picking mid-pick.
    private var appliedHex: String?
    private var appliedInteractive: Bool?

    func apply(_ part: Part) {
        if part.colorWellHex != appliedHex {
            if let nsColor = NSColor(hexString: part.colorWellHex) {
                colorWell.color = nsColor
            }
            appliedHex = part.colorWellHex
        }
        if part.colorWellInteractive != appliedInteractive {
            colorWell.isEnabled = part.colorWellInteractive
            appliedInteractive = part.colorWellInteractive
        }
    }

    @objc private func colorDidChange() {
        let hex = colorWell.color.hexString
        // Update the cached "last-applied" so apply() doesn't see
        // a "change" and clobber the live value.
        appliedHex = hex
        onColorChange?(hex)
    }
}
