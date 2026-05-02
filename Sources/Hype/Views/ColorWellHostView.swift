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

    func apply(_ part: Part) {
        if let nsColor = NSColor(hexString: part.colorWellHex) {
            colorWell.color = nsColor
        }
        colorWell.isEnabled = part.colorWellInteractive
    }

    @objc private func colorDidChange() {
        let hex = colorWell.color.hexString
        onColorChange?(hex)
    }
}
