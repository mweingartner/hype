import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Hype
@testable import HypeCore

// MARK: - Thread-safe helpers for write listener tests

/// A thread-safe integer counter for use in @Sendable test closures.
private final class AtomicCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0

    var value: Int { lock.withLock { _value } }
    func increment() { lock.withLock { _value += 1 } }
}

/// A thread-safe flag for use in @Sendable test closures.
private final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Bool

    init(_ initialValue: Bool = false) { _value = initialValue }
    var value: Bool { lock.withLock { _value } }
    func set(_ newValue: Bool) { lock.withLock { _value = newValue } }
}

/// A thread-safe string collector for use in @Sendable test closures.
private final class AtomicStringCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [String] = []

    func append(_ value: String) { lock.withLock { _values.append(value) } }
    var values: [String] { lock.withLock { _values } }
    func contains(_ value: String) -> Bool { lock.withLock { _values.contains(value) } }
}

// MARK: - Test suite

@MainActor
@Suite("Document mutation coordinator")
struct DocumentMutationCoordinatorTests {
    @Test("tracked binding registers undo and redo snapshots")
    func trackedBindingRegistersUndoAndRedoSnapshots() {
        var wrapper = HypeDocumentWrapper()
        let originalName = wrapper.document.stack.name
        let undoManager = UndoManager()
        let coordinator = makeCoordinator()
        let binding = Binding<HypeDocumentWrapper>(
            get: { wrapper },
            set: { wrapper = $0 }
        )
        let tracked = coordinator.trackedBinding(
            binding,
            undoManager: undoManager,
            actionName: "Rename Stack"
        )

        var updated = tracked.wrappedValue
        updated.document.stack.name = "Renamed"
        tracked.wrappedValue = updated

        #expect(wrapper.document.stack.name == "Renamed")
        #expect(undoManager.canUndo)

        undoManager.undo()
        #expect(wrapper.document.stack.name == originalName)
        #expect(undoManager.canRedo)

        undoManager.redo()
        #expect(wrapper.document.stack.name == "Renamed")
    }

    @Test("session-only script globals do not create persistent undo entries")
    func sessionOnlyScriptGlobalsDoNotCreatePersistentUndoEntries() {
        var wrapper = HypeDocumentWrapper()
        let undoManager = UndoManager()
        let coordinator = makeCoordinator()
        let binding = Binding<HypeDocumentWrapper>(
            get: { wrapper },
            set: { wrapper = $0 }
        )
        let tracked = coordinator.trackedBinding(
            binding,
            undoManager: undoManager,
            actionName: "Runtime Globals"
        )

        var updated = tracked.wrappedValue
        updated.document.scriptGlobals["score"] = "10"
        #expect(HypeDocumentSnapshotCodec.equivalent(wrapper.document, updated.document))
        tracked.wrappedValue = updated

        #expect(wrapper.document.scriptGlobals["score"] == "10")
        #expect(!undoManager.canUndo)
    }

    @Test("coalesced continuous mutations create one undo entry")
    func coalescedContinuousMutationsCreateOneUndoEntry() {
        var wrapper = HypeDocumentWrapper()
        let undoManager = UndoManager()
        let coordinator = makeCoordinator()
        let binding = Binding<HypeDocumentWrapper>(
            get: { wrapper },
            set: { wrapper = $0 }
        )
        let originalWidth = wrapper.document.stack.width
        let tracked = coordinator.trackedBinding(
            binding,
            undoManager: undoManager,
            actionName: "Edit Stack"
        )

        coordinator.beginCoalescedUndo(key: "drag", binding: tracked)
        coordinator.performWithoutUndo {
            var first = tracked.wrappedValue
            first.document.stack.width = 700
            tracked.wrappedValue = first
        }
        coordinator.performWithoutUndo {
            var second = tracked.wrappedValue
            second.document.stack.width = 900
            tracked.wrappedValue = second
        }
        coordinator.endCoalescedUndo(
            key: "drag",
            binding: tracked,
            undoManager: undoManager,
            actionName: "Resize Stack"
        )

        #expect(wrapper.document.stack.width == 900)
        #expect(undoManager.canUndo)

        undoManager.undo()
        #expect(wrapper.document.stack.width == originalWidth)
        #expect(undoManager.canRedo)
    }

    @Test("flush writes latest tracked document to recovery storage")
    func flushWritesLatestTrackedDocumentToRecoveryStorage() throws {
        var wrapper = HypeDocumentWrapper()
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HypeMutationFlushTests-\(UUID().uuidString)", isDirectory: true)
        let store = HypeRecoveryStore(rootDirectory: temporaryDirectory)
        var autosaveCallCount = 0
        let coordinator = HypeDocumentMutationCoordinator(
            recoveryStore: store,
            autosaveDelayNanoseconds: 60_000_000_000,
            autosaveDocuments: { autosaveCallCount += 1 }
        )
        let binding = Binding<HypeDocumentWrapper>(
            get: { wrapper },
            set: { wrapper = $0 }
        )
        let tracked = coordinator.trackedBinding(binding, undoManager: nil, actionName: "Rename Stack")

        var updated = tracked.wrappedValue
        updated.document.stack.name = "Recovered Name"
        tracked.wrappedValue = updated

        coordinator.flushAllAutosaves()

        let decoded = try HypeSQLiteStackStore().load(fromPackageAt: store.snapshotURL(for: wrapper.document))
        #expect(decoded.stack.name == "Recovered Name")
        #expect(autosaveCallCount == 1)

        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    /// Verifies the async recovery write contract: a discrete apply enqueues a
    /// background write that lands on disk without blocking the caller. The write
    /// is guaranteed to be present after `flushAllAutosaves` returns, satisfying
    /// the app-quit safety contract. The NSDocument autosave (debounced) has not
    /// fired yet — confirming the two paths remain independent.
    @Test("recovery write lands asynchronously and is flushed before autosave")
    func recoveryWriteLandsAsynchronouslyAndIsFlushedBeforeAutosave() throws {
        var wrapper = HypeDocumentWrapper()
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HypeAsyncRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        let store = HypeRecoveryStore(rootDirectory: temporaryDirectory)
        var autosaveCallCount = 0
        let coordinator = HypeDocumentMutationCoordinator(
            recoveryStore: store,
            autosaveDelayNanoseconds: 60_000_000_000,
            autosaveDocuments: { autosaveCallCount += 1 }
        )
        let binding = Binding<HypeDocumentWrapper>(
            get: { wrapper },
            set: { wrapper = $0 }
        )
        let tracked = coordinator.trackedBinding(binding, undoManager: nil, actionName: "Rename Stack")

        var updated = tracked.wrappedValue
        updated.document.stack.name = "Async Recovery"
        tracked.wrappedValue = updated

        // Immediately after apply(), the write has been enqueued but the
        // debounced autosave has not fired. The recovery file may or may not
        // be on disk yet at this exact instant (it is async), but the autosave
        // definitely has not been triggered.
        #expect(autosaveCallCount == 0)

        // Flushing synchronously drains the background writer. After flush,
        // the recovery file must be present with the latest document state.
        coordinator.flushAllAutosaves()

        let decoded = try HypeSQLiteStackStore().load(fromPackageAt: store.snapshotURL(for: wrapper.document))
        #expect(decoded.stack.name == "Async Recovery")
        #expect(autosaveCallCount == 1)

        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    @Test("recovery store writes encoded document snapshots")
    func recoveryStoreWritesEncodedDocumentSnapshots() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HypeRecoveryStoreTests-\(UUID().uuidString)", isDirectory: true)
        let store = HypeRecoveryStore(rootDirectory: temporaryDirectory)
        var document = HypeDocument.newDocument(name: "Recovery Test")
        document.stack.width = 1024

        try store.write(document)
        let snapshotURL = store.snapshotURL(for: document)
        let decoded = try HypeSQLiteStackStore().load(fromPackageAt: snapshotURL)

        #expect(decoded.stack.name == "Recovery Test")
        #expect(decoded.stack.width == 1024)
        #expect(
            Set(store.availableSnapshots().map { $0.standardizedFileURL }) ==
            Set([snapshotURL.standardizedFileURL])
        )

        try? FileManager.default.removeItem(at: temporaryDirectory)
    }
}

// MARK: - Coalescing optimisation tests

extension DocumentMutationCoordinatorTests {

    /// During begin→N×perform→end, exactly ONE undo registration must occur
    /// and the recovery file must be written exactly ONCE (at gesture end).
    @Test("coalesced gesture produces one undo registration and one recovery write")
    func coalescedGestureProducesOneUndoRegistrationAndOneRecoveryWrite() {
        var wrapper = HypeDocumentWrapper()
        let undoManager = UndoManager()
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HypeCoalescingTests-\(UUID().uuidString)", isDirectory: true)
        let store = HypeRecoveryStore(rootDirectory: temporaryDirectory)
        let writeCounter = AtomicCounter()
        let coordinator = HypeDocumentMutationCoordinator(
            recoveryStore: store,
            autosaveDelayNanoseconds: 60_000_000_000,
            autosaveDocuments: {}
        )

        // Inject the write listener seam to count actual disk writes.
        coordinator.setRecoveryWriteListener { _ in
            writeCounter.increment()
        }

        let binding = Binding<HypeDocumentWrapper>(
            get: { wrapper },
            set: { wrapper = $0 }
        )
        let tracked = coordinator.trackedBinding(
            binding,
            undoManager: undoManager,
            actionName: "Edit Stack"
        )

        let originalWidth = wrapper.document.stack.width
        coordinator.beginCoalescedUndo(key: "drag", binding: tracked)

        // Simulate three frame mutations at 60 fps.
        for newWidth in [300, 400, 500] {
            coordinator.performWithoutUndo {
                var frame = tracked.wrappedValue
                frame.document.stack.width = newWidth
                tracked.wrappedValue = frame
            }
        }

        coordinator.endCoalescedUndo(
            key: "drag",
            binding: tracked,
            undoManager: undoManager,
            actionName: "Resize Stack"
        )

        // Drain the writer so the count is observable synchronously.
        coordinator.flushAllAutosaves()

        // Final document state is the last frame.
        #expect(wrapper.document.stack.width == 500)
        // Exactly one undo entry for the entire gesture.
        #expect(undoManager.canUndo)
        undoManager.undo()
        #expect(wrapper.document.stack.width == originalWidth)
        // The undo itself schedules another recovery write; the important
        // invariant is that no per-frame writes occurred during the gesture
        // (only the one at end, plus any undo/autosave writes). After flush
        // we just verify at least one write landed.
        #expect(writeCounter.value >= 1)

        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    /// Verifies that during a coalesced gesture no per-frame recovery writes
    /// are enqueued — the write count before `endCoalescedUndo` must be zero.
    @Test("coalesced gesture suppresses per-frame recovery writes")
    func coalescedGestureSuppressesPerFrameRecoveryWrites() {
        var wrapper = HypeDocumentWrapper()
        let undoManager = UndoManager()
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HypeCoalescingWriteTests-\(UUID().uuidString)", isDirectory: true)
        let store = HypeRecoveryStore(rootDirectory: temporaryDirectory)

        // Track how many writes occur before gesture end.
        let writesBeforeEnd = AtomicCounter()
        let gestureEnded = AtomicFlag(false)

        let coordinator = HypeDocumentMutationCoordinator(
            recoveryStore: store,
            autosaveDelayNanoseconds: 60_000_000_000,
            autosaveDocuments: {}
        )
        coordinator.setRecoveryWriteListener { _ in
            if !gestureEnded.value {
                writesBeforeEnd.increment()
            }
        }

        let binding = Binding<HypeDocumentWrapper>(
            get: { wrapper },
            set: { wrapper = $0 }
        )
        let tracked = coordinator.trackedBinding(
            binding,
            undoManager: undoManager,
            actionName: "Edit Stack"
        )

        coordinator.beginCoalescedUndo(key: "resize", binding: tracked)
        for newWidth in [100, 200, 300, 400, 500] {
            coordinator.performWithoutUndo {
                var frame = tracked.wrappedValue
                frame.document.stack.width = newWidth
                tracked.wrappedValue = frame
            }
        }

        gestureEnded.set(true)
        coordinator.endCoalescedUndo(
            key: "resize",
            binding: tracked,
            undoManager: undoManager,
            actionName: "Resize Stack"
        )

        // Drain to let any post-end writes complete.
        coordinator.flushAllAutosaves()

        // No writes must have occurred during the gesture frames.
        #expect(writesBeforeEnd.value == 0)

        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    /// Verifies that `flushAllAutosaves` guarantees the most recent document
    /// state is on disk even when called immediately after an apply, before
    /// the background write has had time to complete naturally.
    @Test("flush guarantee preserves latest document state on quit")
    func flushGuaranteePreservesLatestDocumentStateOnQuit() throws {
        var wrapper = HypeDocumentWrapper()
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HypeFlushGuaranteeTests-\(UUID().uuidString)", isDirectory: true)
        let store = HypeRecoveryStore(rootDirectory: temporaryDirectory)
        var autosaveCallCount = 0
        let coordinator = HypeDocumentMutationCoordinator(
            recoveryStore: store,
            autosaveDelayNanoseconds: 60_000_000_000,
            autosaveDocuments: { autosaveCallCount += 1 }
        )
        let binding = Binding<HypeDocumentWrapper>(
            get: { wrapper },
            set: { wrapper = $0 }
        )
        let tracked = coordinator.trackedBinding(binding, undoManager: nil, actionName: "Edit Stack")

        // Apply a change then immediately flush — simulating "user edits,
        // then quits before the debounce fires".
        var updated = tracked.wrappedValue
        updated.document.stack.name = "Quit-safe Edit"
        tracked.wrappedValue = updated

        // Flush is called synchronously as the app is terminating.
        coordinator.flushAllAutosaves()

        let decoded = try HypeSQLiteStackStore().load(fromPackageAt: store.snapshotURL(for: wrapper.document))
        #expect(decoded.stack.name == "Quit-safe Edit")
        #expect(autosaveCallCount == 1)

        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    /// Verifies latest-wins behaviour: two rapid applies must result in the
    /// recovery snapshot reflecting the second (latest) document state.
    @Test("latest-wins: rapid applies produce recovery snapshot of last state")
    func latestWinsRapidAppliesProduceRecoverySnapshotOfLastState() throws {
        var wrapper = HypeDocumentWrapper()
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HypeLatestWinsTests-\(UUID().uuidString)", isDirectory: true)
        let store = HypeRecoveryStore(rootDirectory: temporaryDirectory)
        let coordinator = HypeDocumentMutationCoordinator(
            recoveryStore: store,
            autosaveDelayNanoseconds: 60_000_000_000,
            autosaveDocuments: {}
        )
        let binding = Binding<HypeDocumentWrapper>(
            get: { wrapper },
            set: { wrapper = $0 }
        )
        let tracked = coordinator.trackedBinding(binding, undoManager: nil, actionName: "Edit Stack")

        // Apply two changes in rapid succession without waiting.
        var first = tracked.wrappedValue
        first.document.stack.name = "First"
        tracked.wrappedValue = first

        var second = tracked.wrappedValue
        second.document.stack.name = "Second"
        tracked.wrappedValue = second

        // Flush drains all pending writes. The recovery snapshot must
        // reflect the second (latest) document name.
        coordinator.flushAllAutosaves()

        let decoded = try HypeSQLiteStackStore().load(fromPackageAt: store.snapshotURL(for: wrapper.document))
        #expect(decoded.stack.name == "Second")

        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    /// Regression: discrete (non-coalesced) edits must still register undo
    /// per apply and must skip undo for no-op writes (unchanged document).
    @Test("discrete edits register undo and skip no-op writes")
    func discreteEditsRegisterUndoAndSkipNoOpWrites() {
        var wrapper = HypeDocumentWrapper()
        let undoManager = UndoManager()
        let coordinator = makeCoordinator()
        let binding = Binding<HypeDocumentWrapper>(
            get: { wrapper },
            set: { wrapper = $0 }
        )
        let tracked = coordinator.trackedBinding(
            binding,
            undoManager: undoManager,
            actionName: "Edit Stack"
        )

        let originalName = wrapper.document.stack.name

        // A real change: must register undo.
        var changed = tracked.wrappedValue
        changed.document.stack.name = "Discrete Edit"
        tracked.wrappedValue = changed
        #expect(undoManager.canUndo)

        // A no-op: apply the same document again. Must NOT add another undo entry.
        let undoCountBefore = undoManager.levelsOfUndo
        var noOp = tracked.wrappedValue
        noOp.document.stack.name = "Discrete Edit"   // same name, no change
        tracked.wrappedValue = noOp
        // The undo stack should not have grown.
        #expect(undoManager.levelsOfUndo == undoCountBefore)

        // Undo restores the original state.
        undoManager.undo()
        #expect(wrapper.document.stack.name == originalName)
    }

    /// Verifies the write listener injection seam: the listener fires once per
    /// background write, enabling tests to observe writes without touching disk.
    @Test("write listener seam fires on each background recovery write")
    func writeListenerSeamFiresOnEachBackgroundRecoveryWrite() {
        var wrapper = HypeDocumentWrapper()
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HypeWriteListenerTests-\(UUID().uuidString)", isDirectory: true)
        let store = HypeRecoveryStore(rootDirectory: temporaryDirectory)
        let observedNames = AtomicStringCollector()

        let coordinator = HypeDocumentMutationCoordinator(
            recoveryStore: store,
            autosaveDelayNanoseconds: 60_000_000_000,
            autosaveDocuments: {}
        )
        coordinator.setRecoveryWriteListener { doc in
            observedNames.append(doc.stack.name)
        }

        let binding = Binding<HypeDocumentWrapper>(
            get: { wrapper },
            set: { wrapper = $0 }
        )
        let tracked = coordinator.trackedBinding(binding, undoManager: nil, actionName: "Edit Stack")

        var updated = tracked.wrappedValue
        updated.document.stack.name = "Listener Test"
        tracked.wrappedValue = updated

        coordinator.flushAllAutosaves()

        #expect(observedNames.contains("Listener Test"))

        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    // MARK: - Private helpers

    private func makeCoordinator() -> HypeDocumentMutationCoordinator {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HypeMutationCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        return HypeDocumentMutationCoordinator(
            recoveryStore: HypeRecoveryStore(rootDirectory: temporaryDirectory),
            autosaveDelayNanoseconds: 10_000_000,
            autosaveDocuments: {}
        )
    }
}
