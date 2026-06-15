import SwiftUI
import HypeCore

@MainActor
private var activeScriptDebuggerWindow: NSWindow?

@MainActor
func openScriptDebuggerWindow(document: Binding<HypeDocumentWrapper>) {
    if let window = activeScriptDebuggerWindow {
        window.makeKeyAndOrderFront(nil)
        return
    }

    HypeTalkScriptTraceRecorder.shared.setEnabled(true)

    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 980, height: 620),
        styleMask: [.titled, .closable, .resizable, .miniaturizable],
        backing: .buffered,
        defer: false
    )
    window.title = "Script Debugger"
    window.minSize = NSSize(width: 760, height: 440)
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: ScriptDebuggerView(document: document))
    window.center()
    window.makeKeyAndOrderFront(nil)
    activeScriptDebuggerWindow = window

    NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
        MainActor.assumeIsolated {
            if activeScriptDebuggerWindow === window {
                activeScriptDebuggerWindow = nil
            }
            HypeTalkScriptTraceRecorder.shared.setEnabled(false)
        }
    }
}

private struct ScriptDebuggerView: View {
    @Binding var document: HypeDocumentWrapper
    @State private var snapshot = HypeTalkScriptTraceRecorder.shared.snapshot()
    @State private var filterText = ""
    @State private var selectedEntryId: HypeTalkScriptTraceEntry.ID?

    private let refreshTimer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    private var globals: [(key: String, value: String)] {
        document.document.scriptGlobals
            .map { ($0.key, $0.value) }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
    }

    private var filteredEntries: [HypeTalkScriptTraceEntry] {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let entries = snapshot.entries.reversed()
        guard !query.isEmpty else { return Array(entries) }
        return entries.filter { entry in
            entry.message.lowercased().contains(query)
                || entry.handler.lowercased().contains(query)
                || entry.ownerDescription.lowercased().contains(query)
                || entry.status.lowercased().contains(query)
        }
    }

    private var totals: HypeTalkExecutionDiagnostics {
        snapshot.entries.reduce(into: HypeTalkExecutionDiagnostics()) { partial, entry in
            partial.merge(entry.diagnostics)
        }
    }

    private var totalDuration: Double {
        snapshot.entries.reduce(0) { $0 + $1.durationMilliseconds }
    }

    private var averageBudget: HypeTalkRuntimeBudgetSummary {
        let average = snapshot.entries.isEmpty ? 0 : totalDuration / Double(snapshot.entries.count)
        return HypeTalkRuntimeBudgetSummary(durationMilliseconds: average)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                globalsPane
                    .frame(minWidth: 240, idealWidth: 280)
                tracePane
                    .frame(minWidth: 520)
            }
        }
        .onReceive(refreshTimer) { _ in
            snapshot = HypeTalkScriptTraceRecorder.shared.snapshot()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Label(snapshot.isEnabled ? "Tracing" : "Paused", systemImage: snapshot.isEnabled ? "record.circle" : "pause.circle")
                .foregroundStyle(snapshot.isEnabled ? .red : .secondary)
                .font(.system(size: 12, weight: .semibold))

            Button(snapshot.isEnabled ? "Pause" : "Resume") {
                HypeTalkScriptTraceRecorder.shared.setEnabled(!snapshot.isEnabled)
                snapshot = HypeTalkScriptTraceRecorder.shared.snapshot()
            }
            .buttonStyle(.bordered)

            Button("Clear") {
                HypeTalkScriptTraceRecorder.shared.clear()
                snapshot = HypeTalkScriptTraceRecorder.shared.snapshot()
            }
            .buttonStyle(.bordered)

            Divider()
                .frame(height: 18)

            summaryChip("Runs", "\(snapshot.entries.count)")
            summaryChip("Avg Budget", budgetSummary(averageBudget))
                .help(String(format: "Average script handler cost: %.2f ms against a %.2f ms frame budget", averageBudget.durationMilliseconds, averageBudget.budgetMilliseconds))
            summaryChip("Statements", "\(totals.statements)")
            summaryChip("Expressions", "\(totals.expressions)")

            Spacer()

            TextField("Filter trace", text: $filterText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
        }
        .padding(10)
    }

    private var globalsPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Globals")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(globals.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            if globals.isEmpty {
                ContentUnavailableView("No Globals", systemImage: "tray", description: Text("Run a script that declares or writes globals."))
            } else {
                List(globals, id: \.key) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.key)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        Text(item.value.isEmpty ? "(empty)" : item.value)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private var tracePane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Execution Trace")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("Newest first")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            if filteredEntries.isEmpty {
                ContentUnavailableView("No Trace Entries", systemImage: "waveform.path.ecg", description: Text("Use Runtime Mode or trigger HypeTalk handlers while tracing is enabled."))
            } else {
                Table(filteredEntries, selection: $selectedEntryId) {
                    TableColumn("Time") { entry in
                        Text(entry.timestamp, style: .time)
                            .font(.system(size: 11, design: .monospaced))
                    }
                    .width(72)

                    TableColumn("Source") { entry in
                        Button(sourceReference(entry)) {
                            openSource(for: entry)
                        }
                        .buttonStyle(.link)
                        .help("Open \(sourceReference(entry))")
                    }
                    .width(min: 160, ideal: 220)

                    TableColumn("Handler") { entry in
                        Text(entry.handler)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    }
                    .width(min: 90, ideal: 120)

                    TableColumn("Status") { entry in
                        Text(entry.status)
                            .foregroundStyle(color(for: entry.status))
                    }
                    .width(78)

                    TableColumn("Budget") { entry in
                        let budget = HypeTalkRuntimeBudgetSummary(durationMilliseconds: entry.durationMilliseconds)
                        Text(budgetSummary(budget))
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .help(String(format: "%.2f ms, %.2fx frame budget", budget.durationMilliseconds, budget.frameEquivalents))
                    }
                    .width(94)

                    TableColumn("Profile") { entry in
                        Text(profileSummary(entry.diagnostics))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 260, ideal: 360)
                }
            }
        }
    }

    private func summaryChip(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.09)))
    }

    private func profileSummary(_ diagnostics: HypeTalkExecutionDiagnostics) -> String {
        "stmt \(diagnostics.statements) | expr \(diagnostics.expressions) | read \(diagnostics.propertyReads) | write \(diagnostics.propertyWrites) | loops \(diagnostics.loopIterations) | async \(diagnostics.callbackRequests)"
    }

    private func budgetSummary(_ budget: HypeTalkRuntimeBudgetSummary) -> String {
        if budget.frameEquivalents >= 1 {
            return String(format: "%.2fx frame", budget.frameEquivalents)
        }
        return String(format: "%.0f%% frame", budget.budgetPercent)
    }

    private func sourceReference(_ entry: HypeTalkScriptTraceEntry) -> String {
        entry.line > 0 ? "\(entry.ownerDescription):\(entry.line)" : entry.ownerDescription
    }

    private func color(for status: String) -> Color {
        switch status {
        case "error": return .red
        case "cancelled": return .orange
        case "passed": return .secondary
        default: return .primary
        }
    }

    private func openSource(for entry: HypeTalkScriptTraceEntry) {
        guard let target = scriptTarget(for: entry.source) else { return }
        var info: [AnyHashable: Any] = ["target": target]
        if case .part(let partId) = target {
            info["partId"] = partId
        }
        NotificationCenter.default.post(
            name: .openPartScriptEditor,
            object: nil,
            userInfo: info
        )
    }

    private func scriptTarget(for source: HypeTalkScriptTraceSource) -> ScriptTarget? {
        switch source.kind {
        case "part":
            return source.objectId.map { .part($0) }
        case "card":
            return source.objectId.map { .card($0) }
        case "background":
            return source.objectId.map { .background($0) }
        case "stack":
            return .stack
        case "hype":
            return .hype
        default:
            return nil
        }
    }
}
