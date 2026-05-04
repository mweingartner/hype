import AppKit
import HypeCore

/// AppKit-hosted action menu for `menu` parts.
///
/// Wraps an `NSPopUpButton` configured with `pullsDown = true` so the
/// title stays fixed and clicking reveals the items as a dropdown. Each
/// item can carry an optional inline HypeTalk script (after `||`).
///
/// When an item is selected `onItemSelected` is called with the item's
/// label string, letting CardCanvasView dispatch `menuItemSelected`.
final class MenuHostNSView: NSView {

    private let button = NSPopUpButton(frame: .zero, pullsDown: true)

    /// Called when the user picks an item. Parameter is the item label.
    var onItemSelected: ((String) -> Void)?

    // Cached state.
    private var appliedTitle: String?
    private var appliedItems: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.target = self
        button.action = #selector(itemSelected(_:))
        addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: topAnchor),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(_ part: Part) {
        let newTitle = String(part.menuTitle.prefix(256))
        let newItems = part.menuItems

        let titleChanged = newTitle != appliedTitle
        let itemsChanged = newItems != appliedItems

        guard titleChanged || itemsChanged else { return }
        appliedTitle = newTitle
        appliedItems = newItems

        button.removeAllItems()

        // The first item in a pull-down button is the title/placeholder.
        let displayTitle = newTitle.isEmpty ? "Menu" : newTitle
        button.addItem(withTitle: displayTitle)

        // Parse newline-separated "Label||script" (or bare "Label") items.
        let lines = newItems.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines {
            let trimmed = String(line).trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            // Extract the label portion (before "||" if present).
            let label: String
            if let range = trimmed.range(of: "||") {
                label = String(trimmed[trimmed.startIndex..<range.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
            } else {
                label = trimmed
            }
            button.addItem(withTitle: label)
        }
    }

    @objc private func itemSelected(_ sender: NSPopUpButton) {
        // Index 0 is the title placeholder — skip it.
        guard sender.indexOfSelectedItem > 0 else { return }
        let label = sender.titleOfSelectedItem ?? ""
        onItemSelected?(label)
        // Reset to title so the button looks like a menu, not a picker.
        sender.selectItem(at: 0)
    }
}
