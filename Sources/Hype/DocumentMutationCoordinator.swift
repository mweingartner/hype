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

/// Manages serialized, latest-wins background recovery snapshot writes.
///
/// All methods on this class are called from the main actor (the coordinator),
/// but the actual disk I/O is dispatched onto a private serial queue. The
/// latest-wins latch (`pendingDocument`) ensures that if multiple writes are
/// requested before the current write finishes, only the most recently
/// requested document state is written to disk — intermediate states are
/// silently dropped.
///
/// `flush()` provides a synchronous drain: it blocks the caller until any
/// in-flight write completes and the latest pending document has been
/// persisted. This satisfies the app-quit / window-close contract: calling
/// `flushAllAutosaves()` on the coordinator right before termination
/// guarantees the most recent edit reaches disk.
///
/// The `writeListener` closure, if set, is called synchronously on the
/// serial queue after each successful write. Tests inject this seam to
/// observe write events without hitting real disk paths.
///
/// Thread-safety: all mutable state is accessed exclusively on `queue`
/// (a private serial `DispatchQueue`). `@unchecked Sendable` is used
/// because Swift 6 cannot verify queue-based exclusion statically.
final class RecoveryWriteScheduler: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.hype.recovery-writer", qos: .utility)
    private let store: HypeRecoveryStore

    // All fields below are accessed exclusively on `queue`.
    private var pendingDocument: HypeDocument?
    private var isWriting = false

    /// Called after every successful recovery write (on the serial queue).
    /// Access is serialised through `queue`; use `setWriteListener(_:)`.
    private var writeListener: (@Sendable (HypeDocument) -> Void)?

    init(store: HypeRecoveryStore) {
        self.store = store
    }

    /// Registers a listener that is called after each successful write.
    /// Dispatches the update synchronously onto the serial queue so all
    /// subsequent `enqueue` operations are guaranteed to observe the new value.
    func setWriteListener(_ listener: (@Sendable (HypeDocument) -> Void)?) {
        queue.sync {
            self.writeListener = listener
        }
    }

    /// Enqueues `document` for a background recovery write using a
    /// latest-wins latch. If a write is already in progress, the new
    /// document replaces any previously pending document so only the
    /// latest state reaches disk.
    func enqueue(_ document: HypeDocument) {
        queue.async { [weak self] in
            guard let self else { return }
            if self.isWriting {
                // A write is already in flight; record this as the
                // pending document so the drain loop picks it up.
                self.pendingDocument = document
            } else {
                self.isWriting = true
                self.performWrite(document)
            }
        }
    }

    /// Blocks the caller until all pending and in-flight recovery writes
    /// complete. Guarantees the most recent document state is on disk
    /// before returning. Called from the app-quit / window-close flush
    /// path on the main actor.
    func flush() {
        let semaphore = DispatchSemaphore(value: 0)
        queue.async { [weak self] in
            guard let self else {
                semaphore.signal()
                return
            }
            // Drain the pending write if one is queued. This runs on the
            // serial queue so it cannot race with `enqueue` or `performWrite`.
            if let pending = self.pendingDocument, !self.isWriting {
                self.isWriting = true
                self.pendingDocument = nil
                self.performWrite(pending)
            }
            // Wait until `isWriting` is false, which means the chain has
            // drained. We poll with a tight spin on the serial queue —
            // this is only called on quit/close so blocking is acceptable.
            self.drainAndSignal(semaphore)
        }
        semaphore.wait()
    }

    // MARK: - Private

    /// Performs the write synchronously on the serial queue, then checks
    /// for a pending document and chains another write if one arrived
    /// while the current write was in progress.
    private func performWrite(_ document: HypeDocument) {
        do {
            try store.write(document)
            writeListener?(document)
        } catch {
            HypeLogger.shared.warn(
                "Could not write recovery snapshot for \(document.stack.name): \(error.localizedDescription)",
                source: "Autosave"
            )
        }

        if let next = pendingDocument {
            pendingDocument = nil
            performWrite(next)
        } else {
            isWriting = false
        }
    }

    /// Waits on the serial queue until the write chain is idle, then
    /// signals the semaphore. Because this is dispatched onto the same
    /// serial queue as all writes, it is guaranteed to run only after
    /// the chain started by `performWrite` finishes.
    private func drainAndSignal(_ semaphore: DispatchSemaphore) {
        // At this point we are already on the serial queue. If `isWriting`
        // is still true, the write chain is executing synchronously on THIS
        // queue — which means we'd deadlock if we blocked. Instead, re-
        // dispatch to give the chain a chance to complete.
        if isWriting {
            queue.async { [weak self] in
                self?.drainAndSignal(semaphore)
            }
        } else {
            semaphore.signal()
        }
    }
}

/// Central mutation boundary for Hype documents.
///
/// This class solves the immediate architectural gap without requiring a
/// risky one-shot rewrite of every view: views can receive a tracked
/// `Binding<HypeDocumentWrapper>`, and any nested mutation performed through
/// that binding is compared, registered with the active UndoManager, written to
/// recovery storage, and sent through NSDocument autosave.
///
/// ### Coalesced canvas mutation optimisation
///
/// During a continuous canvas gesture (drag-to-move, drag-to-resize, etc.)
/// `performContinuousCanvasMutation` wraps each frame mutation in
/// `performWithoutUndo`, raising `undoSuppressionDepth > 0`. At the same time
/// `beginCoalescedUndo` records the pre-gesture document snapshot in
/// `coalescedUndoStarts`.
///
/// While BOTH conditions are true (`undoSuppressionDepth > 0` AND
/// `!coalescedUndoStarts.isEmpty`), `apply()` skips:
/// - The JSON-equivalence check (the gesture caller knows the document
///   changed; skipping the full re-encode of every asset byte saves
///   hundreds of MB/s on media-heavy stacks at 60-120 fps).
/// - Per-frame recovery writes and autosave scheduling (these are deferred
///   to `endCoalescedUndo`).
///
/// `endCoalescedUndo` performs exactly ONE equivalence check against the
/// pre-gesture snapshot, ONE undo registration (if the document changed),
/// ONE recovery write, and ONE autosave schedule.
///
/// ### Async recovery writes
///
/// `persistRecoverySnapshot` in all cases (coalesced or discrete) is now
/// dispatched onto a private serial background queue via
/// `RecoveryWriteScheduler` using a latest-wins latch: if a new write is
/// requested while one is in flight, only the most recent document state
/// is persisted — no intermediate state is written unnecessarily.
///
/// `flushAllAutosaves` synchronously drains the background writer before
/// returning, satisfying the app-quit / window-close guarantee.
@MainActor
final class HypeDocumentMutationCoordinator {
    static let shared = HypeDocumentMutationCoordinator()

    private let recoveryStore: HypeRecoveryStore
    private let autosaveDelayNanoseconds: UInt64
    private let autosaveDocuments: @MainActor () -> Void
    private let recoveryWriter: RecoveryWriteScheduler

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

    /// The currently-visible card in the active document scene. Debug and MCP
    /// automation paths use this as their card context when a request does not
    /// explicitly name a card.
    var activeCardId: UUID?

    init(
        recoveryStore: HypeRecoveryStore = HypeRecoveryStore(),
        autosaveDelayNanoseconds: UInt64 = 700_000_000,
        autosaveDocuments: @escaping @MainActor () -> Void = HypeDocumentMutationCoordinator.autosaveOpenDocuments
    ) {
        self.recoveryStore = recoveryStore
        self.autosaveDelayNanoseconds = autosaveDelayNanoseconds
        self.autosaveDocuments = autosaveDocuments
        self.recoveryWriter = RecoveryWriteScheduler(store: recoveryStore)
    }

    /// Injects a listener that is called after every background recovery
    /// write. Used by tests to observe write events without polling disk.
    ///
    /// The listener is called on the recovery writer's private serial queue,
    /// not on the main actor. Tests should use a thread-safe counter or a
    /// `DispatchSemaphore` to communicate results back.
    ///
    /// This method is synchronous: it blocks until the listener is registered
    /// on the writer's serial queue, so subsequent `enqueue` calls are
    /// guaranteed to see it.
    func setRecoveryWriteListener(_ listener: (@Sendable (HypeDocument) -> Void)?) {
        recoveryWriter.setWriteListener(listener)
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
        // One recovery write and one autosave schedule for the entire gesture.
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
            recoveryWriter.enqueue(document)
        }
        // Drain the background writer synchronously so the most recent
        // document state is guaranteed to be on disk before we return.
        // This is called from app-quit / window-close handlers where
        // blocking the main thread briefly is acceptable.
        recoveryWriter.flush()
        autosaveDocuments()
    }

    func pendingRecoverySnapshots() -> [URL] {
        recoveryStore.availableSnapshots()
    }

    // MARK: - Private

    /// Applies a new document wrapper value to a source binding.
    ///
    /// During a coalesced canvas gesture (`undoSuppressionDepth > 0` while
    /// `coalescedUndoStarts` is non-empty) this method intentionally skips:
    /// - The full-document JSON equivalence check. The gesture caller knows
    ///   the document changed (it called `performContinuousCanvasMutation`),
    ///   so the expensive re-encode of every embedded asset byte is wasteful.
    /// - Per-frame recovery writes and autosave scheduling. `endCoalescedUndo`
    ///   issues exactly one of each at gesture completion.
    ///
    /// Outside a coalesced gesture, the equivalence check is performed as
    /// before: a no-op write (e.g. a session-only `scriptGlobals` change)
    /// is detected and dropped without registering undo or scheduling a save.
    private func apply(
        _ newValue: HypeDocumentWrapper,
        to source: Binding<HypeDocumentWrapper>,
        undoManager: UndoManager?,
        actionName: String
    ) {
        let newDocument = newValue.document

        // Fast path: a coalesced canvas gesture is in flight. Skip the
        // expensive JSON equivalence check and per-frame I/O; both will
        // happen once at gesture end via `endCoalescedUndo`.
        if undoSuppressionDepth > 0 && !coalescedUndoStarts.isEmpty {
            source.wrappedValue = newValue
            latestDocuments[newDocument.stack.id] = newDocument
            HypeLogger.shared.debug(actionName, source: "Document Mutation")
            return
        }

        let oldDocument = source.wrappedValue.document
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

    /// Enqueues a background recovery write and schedules the debounced
    /// NSDocument autosave. The recovery write is dispatched immediately
    /// onto a background serial queue (latest-wins); the NSDocument save
    /// is debounced by `autosaveDelayNanoseconds`.
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

    /// Enqueues a recovery snapshot write onto the background serial queue.
    /// The write is latest-wins: if multiple writes are requested before
    /// one completes, only the most recently requested document is written.
    private func persistRecoverySnapshot(_ document: HypeDocument) {
        recoveryWriter.enqueue(document)
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
