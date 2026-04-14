import AppKit

/// A simple table-based popup for code completion suggestions.
class CompletionViewController: NSViewController {
    var suggestions: [String] = [] {
        didSet { tableView?.reloadData() }
    }
    var onSelect: ((String) -> Void)?
    private var tableView: NSTableView?

    override func loadView() {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 150))
        let table = NSTableView()
        let column = NSTableColumn(identifier: .init("suggestion"))
        column.width = 190
        table.addTableColumn(column)
        table.headerView = nil
        table.delegate = self
        table.dataSource = self
        table.rowHeight = 20
        table.target = self
        table.doubleAction = #selector(rowDoubleClicked)
        scroll.documentView = table
        self.tableView = table
        self.view = scroll
    }

    @objc func rowDoubleClicked() {
        let row = tableView?.selectedRow ?? -1
        guard row >= 0, row < suggestions.count else { return }
        onSelect?(suggestions[row])
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 { // Return
            let row = tableView?.selectedRow ?? 0
            if row >= 0 && row < suggestions.count {
                onSelect?(suggestions[row])
            }
        } else if event.keyCode == 53 { // Escape
            dismiss(nil)
        } else {
            super.keyDown(with: event)
        }
    }
}

extension CompletionViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        suggestions.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        let cell = NSTextField(labelWithString: suggestions[row])
        cell.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        return cell
    }
}
