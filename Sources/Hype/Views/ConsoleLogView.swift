import SwiftUI
import HypeCore
import AppKit

/// The console log window's SwiftUI content.
/// Shows all HypeLogger entries with search, clear, copy, and
/// scroll-to-bottom behavior.
struct ConsoleLogView: View {
    @Environment(\.hypeTheme) private var hypeTheme
    @State private var entries: [LogEntry] = HypeLogger.shared.entries
    @State private var searchText: String = ""
    @State private var autoScroll: Bool = true
    @State private var selectedEntryIds: Set<UUID> = []

    private var filteredEntries: [LogEntry] {
        if searchText.isEmpty { return entries }
        let lower = searchText.lowercased()
        return entries.filter {
            $0.message.lowercased().contains(lower) ||
            $0.source.lowercased().contains(lower) ||
            $0.level.rawValue.lowercased().contains(lower)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                // Search field — themed inset so the field reads as
                // an embedded control on the toolbar surface.
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search logs...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                }
                .padding(4)
                .background(hypeTheme.inspectorBackground.swiftUIColor)
                .cornerRadius(6)
                .frame(maxWidth: 300)

                Spacer()

                Text("\(filteredEntries.count) entries")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))

                Button(action: copySelected) {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy selected entries")
                .disabled(selectedEntryIds.isEmpty)

                Button(action: copyAll) {
                    Image(systemName: "doc.on.clipboard")
                }
                .help("Copy all visible entries")

                Button(action: revealLogFile) {
                    Image(systemName: "folder")
                }
                .help("Reveal log file in Finder")

                Button(action: clearLog) {
                    Image(systemName: "trash")
                }
                .help("Clear console")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            // Header strip — toolbar token so swapping themes also
            // retints the console's top bar.
            .background(hypeTheme.toolbarBackground.swiftUIColor)
            .environment(\.colorScheme, hypeTheme.toolbarColorScheme)

            Divider()

            // Log entries
            ScrollViewReader { proxy in
                List(filteredEntries, selection: $selectedEntryIds) { entry in
                    logEntryRow(entry)
                        .id(entry.id)
                        .tag(entry.id)
                }
                .listStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .onChange(of: entries.count) { _, _ in
                    if autoScroll, let last = filteredEntries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: HypeLogger.didLogNotification)) { _ in
            entries = HypeLogger.shared.entries
        }
        .frame(minWidth: 600, minHeight: 200)
        // Console window surface — pull from the active theme so
        // the standalone console window is themed too.
        .background(hypeTheme.inspectorBackground.swiftUIColor)
        .environment(\.colorScheme, hypeTheme.chromeColorScheme)
    }

    @ViewBuilder
    private func logEntryRow(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            // Timestamp
            Text(timeString(entry.timestamp))
                .foregroundColor(.secondary)
                .frame(width: 75, alignment: .leading)

            // Level badge
            Text(entry.level.rawValue)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(levelColor(entry.level))
                .frame(width: 42, alignment: .center)

            // Source
            if !entry.source.isEmpty {
                Text(entry.source)
                    .foregroundColor(.purple)
                    .frame(width: 80, alignment: .leading)
            }

            // Message (selectable)
            Text(entry.message)
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
    }

    private func levelColor(_ level: LogLevel) -> Color {
        switch level {
        case .debug:   return .gray
        case .info:    return .blue
        case .warning: return .orange
        case .error:   return .red
        }
    }

    private func timeString(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df.string(from: date)
    }

    // MARK: - Actions

    private func clearLog() {
        HypeLogger.shared.clear()
        entries = []
        selectedEntryIds = []
    }

    private func copySelected() {
        let text = filteredEntries
            .filter { selectedEntryIds.contains($0.id) }
            .map(\.formatted)
            .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func copyAll() {
        let text = filteredEntries.map(\.formatted).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func revealLogFile() {
        if let url = HypeLogger.shared.logFileURL {
            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
        }
    }
}

// MARK: - Console Window Management

/// Keeps a strong reference to the console window.
@MainActor
private var consoleWindow: NSWindow?

/// Open (or bring to front) the console log window.
@MainActor
func openConsoleWindow() {
    if let existing = consoleWindow {
        existing.makeKeyAndOrderFront(nil)
        return
    }

    let savedW = UserDefaults.standard.double(forKey: "consoleWindowWidth")
    let savedH = UserDefaults.standard.double(forKey: "consoleWindowHeight")
    let w = savedW > 100 ? savedW : 700
    let h = savedH > 100 ? savedH : 350

    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: w, height: h),
        styleMask: [.titled, .closable, .resizable, .miniaturizable],
        backing: .buffered,
        defer: false
    )
    window.title = "Hype Console"
    window.minSize = NSSize(width: 400, height: 200)
    window.isReleasedWhenClosed = false

    let hostingView = NSHostingView(rootView: ConsoleLogView())
    window.contentView = hostingView
    window.center()
    window.makeKeyAndOrderFront(nil)

    consoleWindow = window

    NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { _ in
        MainActor.assumeIsolated {
            UserDefaults.standard.set(window.frame.width, forKey: "consoleWindowWidth")
            UserDefaults.standard.set(window.frame.height, forKey: "consoleWindowHeight")
        }
    }
    NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
        MainActor.assumeIsolated {
            consoleWindow = nil
        }
    }
}
