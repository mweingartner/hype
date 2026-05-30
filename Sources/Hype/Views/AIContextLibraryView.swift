import SwiftUI
import AppKit
import HypeCore

struct AIContextShelfView: View {
    @Binding var document: HypeDocumentWrapper
    @Environment(\.hypeTheme) private var hypeTheme
    @State private var isExpanded = false
    @State private var showNoteSheet = false
    @State private var latestImportSummary: AIContextImportSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    isExpanded.toggle()
                } label: {
                    Label("Context", systemImage: isExpanded ? "folder.badge.minus" : "folder.badge.plus")
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .semibold))

                Text(summary)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()

                Button("Files") {
                    AIContextImportController.importFiles(into: $document) { report in
                        latestImportSummary = report.shouldNotifyUser ? AIContextImportSummary(report: report) : nil
                    }
                }
                .font(.system(size: 10))
                .buttonStyle(.borderless)
                .help("Attach files or images to this stack's AI context")

                Button("Folder") {
                    AIContextImportController.importFolder(into: $document) { report in
                        latestImportSummary = report.shouldNotifyUser ? AIContextImportSummary(report: report) : nil
                    }
                }
                .font(.system(size: 10))
                .buttonStyle(.borderless)
                .help("Attach a folder snapshot to this stack's AI context")

                Button("Note") {
                    showNoteSheet = true
                }
                .font(.system(size: 10))
                .buttonStyle(.borderless)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    if document.document.aiContextLibrary.items.isEmpty {
                        Text("Attach rules, examples, images, or an asset folder before asking AI to build a complex stack.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(document.document.aiContextLibrary.items.prefix(8)) { item in
                            HStack(spacing: 6) {
                                Image(systemName: item.isImage ? "photo" : "doc.text")
                                    .foregroundColor(.secondary)
                                    .frame(width: 14)
                                Text(item.relativePath)
                                    .font(.system(size: 10))
                                    .lineLimit(1)
                                Text(item.role.displayName)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                        if document.document.aiContextLibrary.items.count > 8 {
                            Text("+ \(document.document.aiContextLibrary.items.count - 8) more item(s)")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Button("Open Context Library") {
                            openAIContextLibraryWindow(document: $document)
                        }
                        .font(.system(size: 10))
                        .buttonStyle(.borderless)
                        Spacer()
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(hypeTheme.inspectorBackground.swiftUIColor.opacity(0.65))
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .sheet(isPresented: $showNoteSheet) {
            AIContextNoteSheet(document: $document, isPresented: $showNoteSheet)
        }
        .alert(item: $latestImportSummary) { summary in
            Alert(
                title: Text("AI Context Import Summary"),
                message: Text(summary.text),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var summary: String {
        let lib = document.document.aiContextLibrary
        if lib.items.isEmpty { return "No attached context" }
        return "\(lib.items.count) item(s), \(lib.sources.count) source(s)"
    }
}

struct AIContextLibraryView: View {
    @Binding var document: HypeDocumentWrapper
    var initialItemId: UUID?
    var onDone: (() -> Void)?

    @Environment(\.hypeTheme) private var hypeTheme
    @State private var selectedItemId: UUID?
    @State private var showNoteSheet = false
    @State private var latestImportSummary: AIContextImportSummary?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("AI Context Library", systemImage: "folder.badge.gearshape")
                    .font(.headline)
                Spacer()
                Button("Add Files") {
                    AIContextImportController.importFiles(into: $document) { report in
                        latestImportSummary = report.shouldNotifyUser ? AIContextImportSummary(report: report) : nil
                    }
                }
                Button("Add Folder") {
                    AIContextImportController.importFolder(into: $document) { report in
                        latestImportSummary = report.shouldNotifyUser ? AIContextImportSummary(report: report) : nil
                    }
                }
                Button("Add Note") { showNoteSheet = true }
                if let onDone {
                    Button("Done") { onDone() }
                }
            }
            .padding(10)
            .background(hypeTheme.toolbarBackground.swiftUIColor)
            .environment(\.colorScheme, hypeTheme.toolbarColorScheme)

            HSplitView {
                sourceList
                    .frame(minWidth: 260, idealWidth: 320)
                detailPane
                    .frame(minWidth: 360)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(hypeTheme.inspectorBackground.swiftUIColor)
        .environment(\.colorScheme, hypeTheme.chromeColorScheme)
        .sheet(isPresented: $showNoteSheet) {
            AIContextNoteSheet(document: $document, isPresented: $showNoteSheet)
        }
        .alert(item: $latestImportSummary) { summary in
            Alert(
                title: Text("AI Context Import Summary"),
                message: Text(summary.text),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear {
            if selectedItemId == nil {
                selectedItemId = initialItemId ?? document.document.aiContextLibrary.items.first?.id
            }
        }
    }

    private var sourceList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(document.document.aiContextLibrary.promptSummary(maxItems: 5))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding([.horizontal, .top], 10)

            List(selection: $selectedItemId) {
                ForEach(document.document.aiContextLibrary.sources) { source in
                    Section(source.name) {
                        ForEach(items(for: source.id)) { item in
                            HStack(spacing: 8) {
                                Image(systemName: item.isImage ? "photo" : "doc.text")
                                    .foregroundColor(.secondary)
                                    .frame(width: 16)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.relativePath)
                                        .lineLimit(1)
                                    Text("\(item.role.displayName) · \(item.mimeType)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .tag(item.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selectedItem {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedItem.relativePath)
                            .font(.headline)
                        Text("\(selectedItem.mimeType) · \(selectedItem.byteCount) bytes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Remove") {
                        document.document.aiContextLibrary.removeItem(id: selectedItem.id)
                        selectedItemId = nil
                    }
                    .foregroundColor(.red)
                }

                Picker("Role", selection: roleBinding(for: selectedItem.id)) {
                    ForEach(AIContextRole.allCases, id: \.rawValue) { role in
                        Text(role.displayName).tag(role)
                    }
                }

                if selectedItem.isImage, let data = selectedItem.data, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 260)
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(8)
                }

                Text("Summary")
                    .font(.subheadline.weight(.semibold))
                Text(selectedItem.textSummary.isEmpty ? "(no text summary)" : selectedItem.textSummary)
                    .font(.system(size: 12))
                    .textSelection(.enabled)

                if selectedItem.isText {
                    Text("Content Preview")
                        .font(.subheadline.weight(.semibold))
                    ScrollView {
                        Text(String(selectedItem.textChunks.map(\.text).joined().prefix(8_000)))
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Attach project context for AI")
                        .font(.headline)
                    Text("Use files for rules and examples, folders for asset packs, images for card art or sprites, and notes for direct design guidance. Hype stores a stack-scoped snapshot and exposes it to the model through safe context tools.")
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                Spacer()
            }
        }
        .padding(16)
    }

    private var selectedItem: AIContextItem? {
        selectedItemId.flatMap { document.document.aiContextLibrary.item(id: $0) }
    }

    private func items(for sourceId: UUID) -> [AIContextItem] {
        document.document.aiContextLibrary.items.filter { $0.sourceId == sourceId }
    }

    private func roleBinding(for itemId: UUID) -> Binding<AIContextRole> {
        Binding(
            get: {
                document.document.aiContextLibrary.item(id: itemId)?.role ?? .unknown
            },
            set: { newRole in
                if let index = document.document.aiContextLibrary.items.firstIndex(where: { $0.id == itemId }) {
                    document.document.aiContextLibrary.items[index].role = newRole
                }
            }
        )
    }
}

private struct AIContextNoteSheet: View {
    @Binding var document: HypeDocumentWrapper
    @Binding var isPresented: Bool
    @State private var title = "Rules Note"
    @State private var text = ""
    @State private var role: AIContextRole = .rules

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add AI Context Note")
                .font(.headline)
            TextField("Title", text: $title)
            Picker("Role", selection: $role) {
                ForEach(AIContextRole.allCases, id: \.rawValue) { role in
                    Text(role.displayName).tag(role)
                }
            }
            TextEditor(text: $text)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 180)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Add") {
                    let result = AIContextIngestor.makeTextNote(title: title, text: text, role: role)
                    document.document.aiContextLibrary.addSource(result.0, items: result.1)
                    HypeDocumentMutationCoordinator.shared.flushAllAutosaves()
                    isPresented = false
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 460)
    }
}

private struct AIContextImportSummary: Identifiable {
    let id = UUID()
    let text: String

    init(report: AIContextImportReport) {
        self.text = report.userSummary
    }
}

@MainActor
enum AIContextImportController {
    static func importFiles(into document: Binding<HypeDocumentWrapper>) {
        importFiles(into: document, onReport: { _ in })
    }

    static func importFiles(
        into document: Binding<HypeDocumentWrapper>,
        onReport: @escaping (AIContextImportReport) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.title = "Add AI Context Files"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { response in
            guard response == .OK else { return }
            let report = AIContextIngestor.ingestFiles(urls: panel.urls)
            add(report, to: document)
            log(report)
            onReport(report)
        }
    }

    static func importFolder(into document: Binding<HypeDocumentWrapper>) {
        importFolder(into: document, onReport: { _ in })
    }

    static func importFolder(
        into document: Binding<HypeDocumentWrapper>,
        onReport: @escaping (AIContextImportReport) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.title = "Add AI Context Folder"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.begin { response in
            guard response == .OK, let url = panel.urls.first else { return }
            let report = AIContextIngestor.ingestDirectoryWithReport(url: url)
            add(report, to: document)
            log(report)
            onReport(report)
        }
    }

    private static func add(
        _ report: AIContextImportReport,
        to document: Binding<HypeDocumentWrapper>
    ) {
        guard !report.sources.isEmpty else { return }
        var wrapper = document.wrappedValue
        for addition in report.sources {
            wrapper.document.aiContextLibrary.addSource(addition.source, items: addition.items)
        }
        document.wrappedValue = wrapper
        HypeDocumentMutationCoordinator.shared.flushAllAutosaves()
    }

    private static func log(_ report: AIContextImportReport) {
        if report.shouldNotifyUser {
            HypeLogger.shared.warn(report.userSummary, source: "AI Context")
        } else {
            HypeLogger.shared.info(report.userSummary, source: "AI Context")
        }
    }
}

@MainActor private var activeAIContextLibraryWindows: [NSWindow] = []

@MainActor
func openAIContextLibraryWindow(
    document: Binding<HypeDocumentWrapper>,
    initialItemId: UUID? = nil
) {
    if let existing = activeAIContextLibraryWindows.first {
        existing.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return
    }

    var window: NSWindow?
    let closeAction: () -> Void = {
        if let window {
            window.close()
        }
    }
    let view = AIContextLibraryView(document: document, initialItemId: initialItemId, onDone: closeAction)
    let host = NSHostingView(rootView: view)
    let created = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
    )
    window = created
    created.title = "AI Context Library"
    created.center()
    created.contentView = host
    created.isReleasedWhenClosed = false
    created.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    activeAIContextLibraryWindows.append(created)
    _ = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: created, queue: .main) { _ in
        Task { @MainActor in
            activeAIContextLibraryWindows.removeAll { $0 === created }
        }
    }
}
