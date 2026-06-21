import SwiftUI
import HypeCore

@MainActor
private var activeScriptDebuggerWindow: NSWindow?

@MainActor
func openScriptDebuggerWindow(document: Binding<HypeDocumentWrapper>) {
    if let window = activeScriptDebuggerWindow {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return
    }

    HypeTalkScriptTraceRecorder.shared.setEnabled(true)

    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1180, height: 720),
        styleMask: [.titled, .closable, .resizable, .miniaturizable],
        backing: .buffered,
        defer: false
    )
    window.title = "Script Debugger"
    window.minSize = NSSize(width: 900, height: 560)
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: ScriptDebuggerView(document: document))
    window.center()
    NSApp.activate(ignoringOtherApps: true)
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

private enum DebuggerVariableScope: String, CaseIterable, Identifiable {
    case all = "All"
    case special = "Special"
    case locals = "Locals"
    case globals = "Globals"

    var id: String { rawValue }
}

private struct ScriptDebuggerView: View {
    @Binding var document: HypeDocumentWrapper
    @State private var snapshot = HypeTalkScriptTraceRecorder.shared.snapshot()
    @State private var filterText = ""
    @State private var selectedEntryId: HypeTalkScriptTraceEntry.ID?
    @State private var breakpointHandler = ""
    @State private var breakpointLine = ""
    @State private var watchpointScope = "auto"
    @State private var watchpointName = ""
    @State private var variableScope: DebuggerVariableScope = .all
    @State private var variableFilter = ""

    private let refreshTimer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    private var selectedEntry: HypeTalkScriptTraceEntry? {
        if let selectedEntryId,
           let entry = snapshot.entries.first(where: { $0.id == selectedEntryId }) {
            return entry
        }
        return snapshot.entries.last
    }

    private var inspectedVariables: HypeTalkVariableScopeSnapshot? {
        snapshot.pausedState?.variables ?? selectedEntry?.variables
    }

    private var inspectedContextTitle: String {
        if let pausedState = snapshot.pausedState {
            return pauseReference(pausedState)
        }
        if let selectedEntry {
            return sourceReference(selectedEntry)
        }
        return "No selection"
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
                || !entry.breakpointHits.isEmpty
                || !entry.watchpointHits.isEmpty
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
                inspectorPane
                    .frame(minWidth: 280, idealWidth: 340)
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
            Label(traceStatusTitle, systemImage: snapshot.pausedState == nil ? (snapshot.isEnabled ? "record.circle" : "pause.circle") : "pause.fill")
                .foregroundStyle(snapshot.pausedState == nil ? (snapshot.isEnabled ? .red : .secondary) : .orange)
                .font(.system(size: 13, weight: .semibold))
                .frame(minWidth: 96, alignment: .leading)

            if snapshot.pausedState != nil {
                ScriptDebuggerStepControls(isPaused: true) {
                    snapshot = HypeTalkScriptTraceRecorder.shared.snapshot()
                }
            }

            Button {
                HypeTalkScriptTraceRecorder.shared.setEnabled(!snapshot.isEnabled)
                snapshot = HypeTalkScriptTraceRecorder.shared.snapshot()
            } label: {
                Image(systemName: snapshot.isEnabled ? "pause.fill" : "record.circle")
            }
            .buttonStyle(.bordered)
            .help(snapshot.isEnabled ? "Pause tracing" : "Resume tracing")

            Button {
                HypeTalkScriptTraceRecorder.shared.clear()
                snapshot = HypeTalkScriptTraceRecorder.shared.snapshot()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .help("Clear the trace")

            Divider()
                .frame(height: 18)

            summaryChip("Runs", "\(snapshot.entries.count)")
            summaryChip("Avg Budget", budgetSummary(averageBudget))
                .help(String(format: "Average script handler cost: %.2f ms against a %.2f ms frame budget", averageBudget.durationMilliseconds, averageBudget.budgetMilliseconds))
            summaryChip("Statements", "\(totals.statements)")
            summaryChip("Expressions", "\(totals.expressions)")
            summaryChip("Breakpoints", "\(snapshot.breakpoints.count)")
            summaryChip("Watchpoints", "\(snapshot.watchpoints.count)")

            Spacer()

            TextField("Filter trace", text: $filterText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
        }
        .padding(10)
    }

    private var inspectorPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            inspectorHeader
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let pausedState = snapshot.pausedState {
                        pauseBanner(pausedState)
                    }
                    breakpointEditor
                    Divider()
                    watchpointEditor
                    Divider()
                    variableInspector
                }
                .padding(12)
            }
        }
    }

    private var inspectorHeader: some View {
        HStack {
            Text("Inspector")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text(inspectedContextTitle)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func pauseBanner(_ pausedState: HypeTalkScriptPauseState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "pause.fill")
                    .foregroundStyle(.orange)
                Text("Execution halted")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                ScriptDebuggerStepControls(isPaused: true, showsLabels: false, controlSize: .small) {
                    snapshot = HypeTalkScriptTraceRecorder.shared.snapshot()
                }
            }
            Text("\(pauseReasonTitle(pausedState)) at \(pausedState.context.handler) in \(pauseReference(pausedState))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.35)))
    }

    private var variableInspector: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Variables")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Picker("Scope", selection: $variableScope) {
                    ForEach(DebuggerVariableScope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 230)
            }

            TextField("Filter variables", text: $variableFilter)
                .textFieldStyle(.roundedBorder)

            if let variables = inspectedVariables {
                let sections = variableSections(for: variables)
                if sections.allSatisfy({ $0.variables.isEmpty }) {
                    emptyInlineState("No matching variables", systemImage: "magnifyingglass")
                } else {
                    ForEach(sections, id: \.title) { section in
                        if !section.variables.isEmpty {
                            variableSection(section.title, variables: section.variables)
                        }
                    }
                }
            } else {
                emptyInlineState("Run a handler while tracing is enabled.", systemImage: "tray")
            }
        }
    }

    private func variableSection(_ title: String, variables: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text("\(variables.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            ForEach(variables, id: \.0) { name, value in
                HStack(alignment: .top, spacing: 8) {
                    Text(name)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .frame(width: 126, alignment: .leading)
                        .lineLimit(2)
                    Text(value.isEmpty ? "(empty)" : value)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.055)))
            }
        }
    }

    private var breakpointEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Breakpoints", count: snapshot.breakpoints.count)
            HStack(spacing: 6) {
                TextField(selectedEntry?.handler ?? "handler", text: $breakpointHandler)
                    .textFieldStyle(.roundedBorder)
                TextField("line", text: $breakpointLine)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                Button {
                    addBreakpoint()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add breakpoint for the selected source")
                .disabled(selectedEntry == nil)
            }
            if snapshot.breakpoints.isEmpty {
                emptyInlineState("Select a trace row, then add a handler or line breakpoint.", systemImage: "circle")
            } else {
                ForEach(snapshot.breakpoints) { breakpoint in
                    HStack(spacing: 8) {
                        Image(systemName: breakpoint.isEnabled ? "circle.fill" : "circle")
                            .foregroundStyle(.red)
                            .font(.system(size: 8))
                        Text(breakpointLabel(breakpoint))
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                        Spacer()
                        Button {
                            HypeTalkScriptTraceRecorder.shared.removeBreakpoint(id: breakpoint.id)
                            snapshot = HypeTalkScriptTraceRecorder.shared.snapshot()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                        .help("Remove breakpoint")
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private var watchpointEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Watch Editor", count: snapshot.watchpoints.count)
            HStack(spacing: 6) {
                Picker("", selection: $watchpointScope) {
                    Text("Auto").tag("auto")
                    Text("Local").tag("local")
                    Text("Global").tag("global")
                    Text("Special").tag("special")
                }
                .labelsHidden()
                .frame(width: 92)
                TextField("name", text: $watchpointName)
                    .textFieldStyle(.roundedBorder)
                Button {
                    addWatchpoint()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add watchpoint")
                .disabled(watchpointName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if snapshot.watchpoints.isEmpty {
                emptyInlineState("Track a variable by name across handler runs.", systemImage: "eye")
            } else {
                ForEach(snapshot.watchpoints) { watchpoint in
                    HStack(spacing: 6) {
                        Image(systemName: "eye")
                            .foregroundStyle(.secondary)
                        Text("\(watchpoint.scope):\(watchpoint.name)")
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                        Spacer()
                        Button {
                            HypeTalkScriptTraceRecorder.shared.removeWatchpoint(id: watchpoint.id)
                            snapshot = HypeTalkScriptTraceRecorder.shared.snapshot()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                        .help("Remove watchpoint")
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
                VStack(spacing: 0) {
                    traceTable
                    Divider()
                    traceDetail
                }
            }
        }
    }

    private var traceTable: some View {
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
            .width(min: 170, ideal: 240)

            TableColumn("Handler") { entry in
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.handler)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    Text(entry.message)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .width(min: 120, ideal: 160)

            TableColumn("Status") { entry in
                statusBadge(entry)
            }
            .width(116)

            TableColumn("Budget") { entry in
                let budget = HypeTalkRuntimeBudgetSummary(durationMilliseconds: entry.durationMilliseconds)
                Text(budgetSummary(budget))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(budgetColor(budget))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .help(String(format: "%.2f ms, %.2fx frame budget", budget.durationMilliseconds, budget.frameEquivalents))
            }
            .width(106)

            TableColumn("Profile") { entry in
                Text(profileSummary(entry.diagnostics))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(min: 280, ideal: 380)
        }
    }

    private var traceDetail: some View {
        Group {
            if let selectedEntry {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        statusBadge(selectedEntry)
                        Text(selectedEntry.handler)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        Text(sourceReference(selectedEntry))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            openSource(for: selectedEntry)
                        } label: {
                            Label("Open Script", systemImage: "curlybraces")
                        }
                        .controlSize(.small)
                    }
                    HStack(spacing: 14) {
                        detailMetric("Duration", String(format: "%.2f ms", selectedEntry.durationMilliseconds))
                        detailMetric("Statements", "\(selectedEntry.diagnostics.statements)")
                        detailMetric("Expressions", "\(selectedEntry.diagnostics.expressions)")
                        detailMetric("Reads", "\(selectedEntry.diagnostics.propertyReads)")
                        detailMetric("Writes", "\(selectedEntry.diagnostics.propertyWrites)")
                        detailMetric("Loops", "\(selectedEntry.diagnostics.loopIterations)")
                    }
                    if !selectedEntry.watchpointHits.isEmpty {
                        Text(watchpointHitSummary(selectedEntry.watchpointHits))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)
                    }
                }
                .padding(10)
            } else {
                emptyInlineState("Select a trace row to inspect timing, source, and variable state.", systemImage: "sidebar.right")
                    .padding(10)
            }
        }
        .frame(minHeight: 92, idealHeight: 112, maxHeight: 138, alignment: .topLeading)
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

    private func sectionTitle(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Text("\(count)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func emptyInlineState(_ message: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    private func statusBadge(_ entry: HypeTalkScriptTraceEntry) -> some View {
        HStack(spacing: 4) {
            if !entry.breakpointHits.isEmpty {
                Image(systemName: "circle.fill")
                    .foregroundStyle(.red)
                    .help("Breakpoint hit")
            }
            if !entry.watchpointHits.isEmpty {
                Image(systemName: "eye.fill")
                    .foregroundStyle(.orange)
                    .help(watchpointHitSummary(entry.watchpointHits))
            }
            Text(entry.status)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color(for: entry.status))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6).fill(color(for: entry.status).opacity(0.10)))
    }

    private func detailMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
    }

    private var traceStatusTitle: String {
        if snapshot.pausedState != nil { return "Halted" }
        return snapshot.isEnabled ? "Tracing" : "Paused"
    }

    private func pauseReasonTitle(_ pause: HypeTalkScriptPauseState) -> String {
        switch pause.reason {
        case "stepInto": return "Step into"
        case "stepOver": return "Step over"
        default: return "Breakpoint"
        }
    }

    private func variableSections(
        for variables: HypeTalkVariableScopeSnapshot
    ) -> [(title: String, variables: [(String, String)])] {
        let special = filteredVariables([
            ("it", variables.it),
            ("the result", variables.result),
        ])
        let locals = filteredVariables(sortedVariables(variables.locals))
        let globals = filteredVariables(sortedVariables(variables.globals))

        switch variableScope {
        case .all:
            return [
                ("Special", special),
                ("Locals", locals),
                ("Globals", globals),
            ]
        case .special:
            return [("Special", special)]
        case .locals:
            return [("Locals", locals)]
        case .globals:
            return [("Globals", globals)]
        }
    }

    private func filteredVariables(_ variables: [(String, String)]) -> [(String, String)] {
        let query = variableFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return variables }
        return variables.filter { name, value in
            name.lowercased().contains(query) || value.lowercased().contains(query)
        }
    }

    private func sortedVariables(_ variables: [String: String]) -> [(String, String)] {
        variables
            .map { ($0.key, $0.value) }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
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

    private func pauseReference(_ pause: HypeTalkScriptPauseState) -> String {
        pause.context.line > 0 ? "\(pause.context.ownerDescription):\(pause.context.line)" : pause.context.ownerDescription
    }

    private func color(for status: String) -> Color {
        switch status {
        case "error": return .red
        case "cancelled": return .orange
        case "paused": return .orange
        case "completed", "success": return .green
        case "passed": return .secondary
        default: return .primary
        }
    }

    private func budgetColor(_ budget: HypeTalkRuntimeBudgetSummary) -> Color {
        switch budget.pressure {
        case "over-budget": return .red
        case "heavy": return .orange
        default: return .secondary
        }
    }

    private func addBreakpoint() {
        guard let selectedEntry else { return }
        let line = Int(breakpointLine.trimmingCharacters(in: .whitespacesAndNewlines))
        let handler = breakpointHandler.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = HypeTalkScriptTraceRecorder.shared.addBreakpoint(
            HypeTalkScriptBreakpoint(
                sourceKind: selectedEntry.source.kind,
                objectId: selectedEntry.source.objectId,
                handler: handler.isEmpty ? selectedEntry.handler : handler,
                line: line
            )
        )
        breakpointHandler = ""
        breakpointLine = ""
        snapshot = HypeTalkScriptTraceRecorder.shared.snapshot()
    }

    private func addWatchpoint() {
        let name = watchpointName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        _ = HypeTalkScriptTraceRecorder.shared.addWatchpoint(
            HypeTalkScriptWatchpoint(scope: watchpointScope, name: name)
        )
        watchpointName = ""
        snapshot = HypeTalkScriptTraceRecorder.shared.snapshot()
    }

    private func breakpointLabel(_ breakpoint: HypeTalkScriptBreakpoint) -> String {
        let handler = breakpoint.handler?.isEmpty == false ? breakpoint.handler! : "*"
        let line = breakpoint.line.map { ":\($0)" } ?? ""
        return "\(breakpoint.sourceKind) \(handler)\(line)"
    }

    private func watchpointHitSummary(_ hits: [HypeTalkScriptWatchpointHit]) -> String {
        hits.map { hit in
            let oldValue = hit.oldValue ?? "(unset)"
            return "\(hit.scope):\(hit.name) \(oldValue) -> \(hit.newValue)"
        }.joined(separator: "\n")
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
