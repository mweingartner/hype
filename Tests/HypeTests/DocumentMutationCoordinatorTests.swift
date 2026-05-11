import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Hype
@testable import HypeCore

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

        let snapshotData = try Data(contentsOf: store.snapshotURL(for: wrapper.document))
        let decoded = try JSONDecoder().decode(HypeDocument.self, from: snapshotData)
        #expect(decoded.stack.name == "Recovered Name")
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
        let snapshotData = try Data(contentsOf: snapshotURL)
        let decoded = try JSONDecoder().decode(HypeDocument.self, from: snapshotData)

        #expect(decoded.stack.name == "Recovery Test")
        #expect(decoded.stack.width == 1024)
        #expect(
            Set(store.availableSnapshots().map { $0.standardizedFileURL }) ==
            Set([snapshotURL.standardizedFileURL])
        )

        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

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
