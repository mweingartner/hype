import Foundation
import Testing
@testable import HypeCore

@Suite("HypeTalk script trace recorder")
struct HypeTalkScriptTraceRecorderTests {
    @Test("records only while enabled and clears entries")
    func recordsOnlyWhileEnabledAndClears() {
        let recorder = HypeTalkScriptTraceRecorder()
        let entry = HypeTalkScriptTraceEntry(
            message: "mouseUp",
            handler: "mouseUp",
            ownerDescription: "button \"Run\"",
            source: HypeTalkScriptTraceSource(kind: "part", objectId: UUID()),
            line: 1,
            status: "completed",
            durationMilliseconds: 1.25,
            diagnostics: HypeTalkExecutionDiagnostics(statements: 3, expressions: 2)
        )

        recorder.record(entry)
        #expect(recorder.snapshot().entries.isEmpty)

        recorder.setEnabled(true)
        recorder.record(entry)

        let snapshot = recorder.snapshot()
        #expect(snapshot.isEnabled)
        #expect(snapshot.entries == [entry])

        recorder.clear()
        #expect(recorder.snapshot().entries.isEmpty)
    }

    @Test("runtime budget summary describes script frame pressure")
    func runtimeBudgetSummaryDescribesFramePressure() {
        let minimal = HypeTalkRuntimeBudgetSummary(durationMilliseconds: 0.4, budgetMilliseconds: 16.0)
        #expect(minimal.pressure == "minimal")
        #expect(abs(minimal.budgetPercent - 2.5) < 0.001)
        #expect(abs(minimal.frameEquivalents - 0.025) < 0.001)

        let overBudget = HypeTalkRuntimeBudgetSummary(durationMilliseconds: 32.0, budgetMilliseconds: 16.0)
        #expect(overBudget.pressure == "over-budget")
        #expect(abs(overBudget.budgetPercent - 200.0) < 0.001)
        #expect(abs(overBudget.frameEquivalents - 2.0) < 0.001)
    }

    @Test("message dispatch records handler trace with profiling data")
    func dispatchRecordsHandlerTrace() async throws {
        HypeTalkScriptTraceRecorder.shared.setEnabled(false)
        HypeTalkScriptTraceRecorder.shared.clear()

        var document = HypeDocument.newDocument()
        let cardId = try #require(document.sortedCards.first?.id)
        var button = Part(partType: .button, cardId: cardId, name: "Run")
        button.script = """
        on mouseUp
          put "ok" into gResult
        end mouseUp
        """
        document.addPart(button)

        HypeTalkScriptTraceRecorder.shared.setEnabled(true)
        defer {
            HypeTalkScriptTraceRecorder.shared.setEnabled(false)
            HypeTalkScriptTraceRecorder.shared.clear()
        }

        _ = await MessageDispatcher().dispatchAsync(
            message: "mouseUp",
            params: [],
            targetId: button.id,
            document: document,
            currentCardId: cardId
        )

        let entry = try #require(HypeTalkScriptTraceRecorder.shared.snapshot().entries.last)
        #expect(entry.message == "mouseUp")
        #expect(entry.handler == "mouseUp")
        #expect(entry.source.kind == "part")
        #expect(entry.source.objectId == button.id)
        #expect(entry.status == "completed")
        #expect(entry.durationMilliseconds >= 0)
        #expect(entry.diagnostics.handlerInvocations == 1)
        #expect(entry.diagnostics.statements >= 1)
    }
}
