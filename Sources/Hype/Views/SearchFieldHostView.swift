import AppKit
import HypeCore

/// AppKit-hosted search field for `searchField` parts.
///
/// Wraps `NSSearchField`. When `searchSendsImmediately` is true, the
/// `onSearchChange` closure fires on every keystroke (with a ~300ms
/// debounce). When false, it fires only when the user presses Return.
final class SearchFieldHostNSView: NSView, NSSearchFieldDelegate {

    let searchField = NSSearchField()

    /// Called when the search text changes. Parameter is the new text.
    var onSearchChange: ((String) -> Void)?

    // Debounce timer for immediate-mode dispatch.
    private var debounceTimer: Timer?
    private var sendsImmediately = false

    // Cached state.
    private var appliedText: String?
    private var appliedPrompt: String?
    private var appliedImmediate: Bool?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = false
        searchField.sendsWholeSearchString = true
        addSubview(searchField)
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: topAnchor),
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor),
            searchField.trailingAnchor.constraint(equalTo: trailingAnchor),
            searchField.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(_ part: Part) {
        let newText = String(part.searchText.prefix(1024))
        let newPrompt = String(part.searchPrompt.prefix(256))
        let newImmediate = part.searchSendsImmediately

        if newText != appliedText {
            appliedText = newText
            searchField.stringValue = newText
        }
        if newPrompt != appliedPrompt {
            appliedPrompt = newPrompt
            searchField.placeholderString = newPrompt
        }
        if newImmediate != appliedImmediate {
            appliedImmediate = newImmediate
            sendsImmediately = newImmediate
        }
    }

    // MARK: - NSSearchFieldDelegate / NSControlTextEditingDelegate

    func controlTextDidChange(_ obj: Notification) {
        guard sendsImmediately else { return }
        debounceTimer?.invalidate()
        let text = searchField.stringValue
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.onSearchChange?(String(text.prefix(1024)))
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let notification = obj.object as? NSSearchField else { return }
        // Return key: fire regardless of immediate setting.
        let text = notification.stringValue
        onSearchChange?(String(text.prefix(1024)))
    }
}
