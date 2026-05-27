import AppKit
import HypeCore

@MainActor
final class MusicInstrumentPopupHostNSView: NSView {
    var onInstrumentChange: ((String) -> Void)?

    private let popup = NSPopUpButton()
    private var isApplying = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildUI()
    }

    func apply(part: Part) {
        isApplying = true
        populateIfNeeded()
        let resolved = MusicInstrumentCatalog.resolve(part.musicInstrumentName).name
        if let item = popup.itemArray.first(where: { ($0.representedObject as? String) == resolved }) {
            popup.select(item)
        } else {
            popup.selectItem(at: 0)
        }
        toolTip = "Choose the instrument this control uses when it plays notes."
        isApplying = false
    }

    private func buildUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.controlSize = .small
        popup.font = .systemFont(ofSize: 11)
        popup.target = self
        popup.action = #selector(instrumentChanged)
        addSubview(popup)
        NSLayoutConstraint.activate([
            popup.leadingAnchor.constraint(equalTo: leadingAnchor),
            popup.trailingAnchor.constraint(equalTo: trailingAnchor),
            popup.topAnchor.constraint(equalTo: topAnchor),
            popup.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        populateIfNeeded()
    }

    private func populateIfNeeded() {
        guard popup.numberOfItems != MusicInstrumentCatalog.instruments.count else { return }
        popup.removeAllItems()
        for instrument in MusicInstrumentCatalog.instruments {
            popup.addItem(withTitle: instrument.isPercussion ? "\(instrument.name) (Drums)" : instrument.name)
            popup.lastItem?.representedObject = instrument.name
        }
    }

    @objc private func instrumentChanged() {
        guard !isApplying,
              let instrument = popup.selectedItem?.representedObject as? String else {
            return
        }
        onInstrumentChange?(instrument)
    }
}
