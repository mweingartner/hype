import AppKit
import Foundation
import HypeCore
import SwiftUI

/// Encodes Hype documents into a deterministic value snapshot for equality.
///
/// The persisted `.hype` document is SQLite-backed, but undo/coalescing still
/// needs a cheap value-level equivalence check. `HypeDocument` excludes
/// session-only fields such as `scriptGlobals` from CodingKeys, so this
/// comparison prevents runtime-only global mutations from polluting undo/save
/// state.
enum HypeDocumentSnapshotCodec {
    static func data(for document: HypeDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(document)
    }

    static func equivalent(_ lhs: HypeDocument, _ rhs: HypeDocument) -> Bool {
        guard let left = try? data(for: lhs),
              let right = try? data(for: rhs) else {
            return false
        }
        return left == right
    }
}

/// Stores local recovery snapshots for documents whose latest edits may not
/// yet have been committed through the SwiftUI/NSDocument autosave path.
final class HypeRecoveryStore {
    let rootDirectory: URL
    private let store: HypeSQLiteStackStore

    init(rootDirectory: URL? = nil, store: HypeSQLiteStackStore = HypeSQLiteStackStore()) {
        self.store = store
        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            self.rootDirectory = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!
                .appendingPathComponent("Hype", isDirectory: true)
                .appendingPathComponent("Recovery", isDirectory: true)
        }
    }

    func snapshotURL(for document: HypeDocument) -> URL {
        rootDirectory
            .appendingPathComponent(document.stack.id.uuidString, isDirectory: false)
            .appendingPathExtension("hype-recovery")
    }

    func write(_ document: HypeDocument) throws {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try store.save(document, toPackageAt: snapshotURL(for: document))
    }

    func removeSnapshot(for document: HypeDocument) {
        try? FileManager.default.removeItem(at: snapshotURL(for: document))
    }

    func availableSnapshots() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ))?.filter { $0.pathExtension == "hype-recovery" } ?? []
    }
}

/// Central mutation boundary for Hype documents.
///
/// This class solves the immediate architectural gap without requiring a
/// risky one-shot rewrite of every view: views can receive a tracked
/// `Binding<HypeDocumentWrapper>`, and any nested mutation performed through
/// that binding is compared, registered with the active UndoManager, written to
/// recovery storage, and sent through NSDocument autosave.
@MainActor
final class HypeDocumentMutationCoordinator {
    static let shared = HypeDocumentMutationCoordinator()

    private let recoveryStore: HypeRecoveryStore
    private let autosaveDelayNanoseconds: UInt64
    private let autosaveDocuments: @MainActor () -> Void

    private var isApplyingUndoRedo = false
    private var undoSuppressionDepth = 0
    private var latestDocuments: [UUID: HypeDocument] = [:]
    private var pendingAutosaves: [UUID: Task<Void, Never>] = [:]
    private var coalescedUndoStarts: [String: HypeDocument] = [:]

    /// The currently-active document binding, used as a fallback for the
    /// Preferences scene. SwiftUI's `@FocusedValue(\.hypeCurrentDocument)`
    /// returns nil when the Preferences window itself becomes the focused
    /// scene (the document scene loses focus), which would leave per-stack
    /// toggles ("Enable for Current Stack", etc.) permanently disabled.
    /// `MainContentView` writes this on appear/becomeMain so Preferences
    /// can resolve the active document even when its own scene is in front.
    var activeDocumentBinding: Binding<HypeDocumentWrapper>?

    init(
        recoveryStore: HypeRecoveryStore = HypeRecoveryStore(),
        autosaveDelayNanoseconds: UInt64 = 700_000_000,
        autosaveDocuments: @escaping @MainActor () -> Void = HypeDocumentMutationCoordinator.autosaveOpenDocuments
    ) {
        self.recoveryStore = recoveryStore
        self.autosaveDelayNanoseconds = autosaveDelayNanoseconds
        self.autosaveDocuments = autosaveDocuments
    }

    func trackedBinding(
        _ source: Binding<HypeDocumentWrapper>,
        undoManager: UndoManager?,
        actionName: String = "Edit Stack"
    ) -> Binding<HypeDocumentWrapper> {
        Binding(
            get: { source.wrappedValue },
            set: { [weak self] newValue in
                guard let self else {
                    source.wrappedValue = newValue
                    return
                }
                self.apply(
                    newValue,
                    to: source,
                    undoManager: undoManager,
                    actionName: actionName
                )
            }
        )
    }

    func mutate(
        _ source: Binding<HypeDocumentWrapper>,
        undoManager: UndoManager?,
        actionName: String,
        _ mutation: (inout HypeDocument) -> Void
    ) {
        var updated = source.wrappedValue
        mutation(&updated.document)
        apply(updated, to: source, undoManager: undoManager, actionName: actionName)
    }

    func performWithoutUndo(_ work: () -> Void) {
        undoSuppressionDepth += 1
        defer { undoSuppressionDepth -= 1 }
        work()
    }

    func beginCoalescedUndo(
        key: String,
        binding: Binding<HypeDocumentWrapper>
    ) {
        guard coalescedUndoStarts[key] == nil else { return }
        coalescedUndoStarts[key] = binding.wrappedValue.document
    }

    func endCoalescedUndo(
        key: String,
        binding: Binding<HypeDocumentWrapper>,
        undoManager: UndoManager?,
        actionName: String
    ) {
        guard let startingDocument = coalescedUndoStarts.removeValue(forKey: key) else { return }
        let finalDocument = binding.wrappedValue.document
        guard !HypeDocumentSnapshotCodec.equivalent(startingDocument, finalDocument) else { return }
        registerUndo(
            from: startingDocument,
            to: finalDocument,
            binding: binding,
            undoManager: undoManager,
            actionName: actionName
        )
        scheduleAutosave(for: finalDocument)
    }

    func applyDocument(
        _ document: HypeDocument,
        to source: Binding<HypeDocumentWrapper>,
        undoManager: UndoManager?,
        actionName: String
    ) {
        var updated = source.wrappedValue
        updated.document = document
        apply(updated, to: source, undoManager: undoManager, actionName: actionName)
    }

    func noteDocumentOpened(_ document: HypeDocument) {
        latestDocuments[document.stack.id] = document
    }

    func flushAllAutosaves() {
        for task in pendingAutosaves.values {
            task.cancel()
        }
        pendingAutosaves.removeAll()

        for document in latestDocuments.values {
            persistRecoverySnapshot(document)
        }
        autosaveDocuments()
    }

    func pendingRecoverySnapshots() -> [URL] {
        recoveryStore.availableSnapshots()
    }

    private func apply(
        _ newValue: HypeDocumentWrapper,
        to source: Binding<HypeDocumentWrapper>,
        undoManager: UndoManager?,
        actionName: String
    ) {
        let oldDocument = source.wrappedValue.document
        let newDocument = newValue.document
        guard !HypeDocumentSnapshotCodec.equivalent(oldDocument, newDocument) else {
            source.wrappedValue = newValue
            latestDocuments[newDocument.stack.id] = newDocument
            return
        }

        source.wrappedValue = newValue
        latestDocuments[newDocument.stack.id] = newDocument

        if !isApplyingUndoRedo && undoSuppressionDepth == 0 {
            registerUndo(
                from: oldDocument,
                to: newDocument,
                binding: source,
                undoManager: undoManager,
                actionName: actionName
            )
        }

        scheduleAutosave(for: newDocument)
        HypeLogger.shared.debug(actionName, source: "Document Mutation")
    }

    private func registerUndo(
        from oldDocument: HypeDocument,
        to newDocument: HypeDocument,
        binding: Binding<HypeDocumentWrapper>,
        undoManager: UndoManager?,
        actionName: String
    ) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { coordinator in
            coordinator.applyUndoRedoSnapshot(
                oldDocument,
                inverseSnapshot: newDocument,
                binding: binding,
                undoManager: undoManager,
                actionName: actionName
            )
        }
        undoManager.setActionName(actionName)
    }

    private func applyUndoRedoSnapshot(
        _ snapshot: HypeDocument,
        inverseSnapshot: HypeDocument,
        binding: Binding<HypeDocumentWrapper>,
        undoManager: UndoManager,
        actionName: String
    ) {
        isApplyingUndoRedo = true
        var wrapper = binding.wrappedValue
        wrapper.document = snapshot
        binding.wrappedValue = wrapper
        isApplyingUndoRedo = false

        latestDocuments[snapshot.stack.id] = snapshot
        scheduleAutosave(for: snapshot)

        undoManager.registerUndo(withTarget: self) { coordinator in
            coordinator.applyUndoRedoSnapshot(
                inverseSnapshot,
                inverseSnapshot: snapshot,
                binding: binding,
                undoManager: undoManager,
                actionName: actionName
            )
        }
        undoManager.setActionName(actionName)
    }

    private func scheduleAutosave(for document: HypeDocument) {
        let stackId = document.stack.id
        persistRecoverySnapshot(document)
        pendingAutosaves[stackId]?.cancel()
        pendingAutosaves[stackId] = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: autosaveDelayNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let latest = latestDocuments[stackId] ?? document
            persistRecoverySnapshot(latest)
            autosaveDocuments()
            pendingAutosaves[stackId] = nil
        }
    }

    private func persistRecoverySnapshot(_ document: HypeDocument) {
        do {
            try recoveryStore.write(document)
        } catch {
            HypeLogger.shared.warn(
                "Could not write recovery snapshot for \(document.stack.name): \(error.localizedDescription)",
                source: "Autosave"
            )
        }
    }

    private static func autosaveOpenDocuments() {
        let documents = NSDocumentController.shared.documents
        guard !documents.isEmpty else { return }
        for document in documents {
            document.autosave(withImplicitCancellability: false) { error in
                if let error {
                    HypeLogger.shared.warn(
                        "NSDocument autosave failed: \(error.localizedDescription)",
                        source: "Autosave"
                    )
                }
            }
        }
    }
}
