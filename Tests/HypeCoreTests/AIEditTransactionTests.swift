import Testing
@testable import HypeCore

@Suite("AI edit transactions")
struct AIEditTransactionTests {
    @Test("preview runs tools against a draft without mutating the live document")
    func previewDoesNotMutateLiveDocument() async {
        let document = HypeDocument.newDocument(name: "Transaction")
        let cardId = document.cards[0].id
        let runner = AIEditTransactionRunner()
        let call = OllamaToolCall(function: OllamaToolCallFunction(
            name: "create_button",
            arguments: [
                "name": "Draft Button",
                "left": "40",
                "top": "50"
            ]
        ))

        let transaction = await runner.preview(
            toolCalls: [call],
            document: document,
            currentCardId: cardId,
            prompt: "Create a button",
            providerName: "Test"
        )

        #expect(document.parts.isEmpty)
        #expect(transaction.state == .preview)
        #expect(transaction.previewDocument.parts.count == 1)
        #expect(transaction.delta.createdPartIds.count == 1)
        #expect(transaction.operations.first?.toolName == "create_button")
        #expect(transaction.operations.first?.delta.createdPartIds.count == 1)
    }

    @Test("apply and rollback are explicit state transitions")
    func applyAndRollbackAreExplicit() async {
        var document = HypeDocument.newDocument(name: "Transaction")
        let originalStackName = document.stack.name
        let cardId = document.cards[0].id
        let runner = AIEditTransactionRunner()
        let call = OllamaToolCall(function: OllamaToolCallFunction(
            name: "set_stack_property",
            arguments: ["property": "name", "value": "Edited By AI"]
        ))

        var transaction = await runner.preview(
            toolCalls: [call],
            document: document,
            currentCardId: cardId,
            prompt: "Rename the stack",
            providerName: "Test"
        )

        #expect(document.stack.name == originalStackName)
        runner.apply(&transaction, to: &document)
        #expect(transaction.state == .applied)
        #expect(document.stack.name == "Edited By AI")
        #expect(transaction.delta.stackChanged)

        runner.rollback(&transaction, to: &document)
        #expect(transaction.state == .rolledBack)
        #expect(document.stack.name == originalStackName)
    }

    @Test("batch transaction reports merged delta")
    func batchTransactionReportsMergedDelta() async {
        let document = HypeDocument.newDocument(name: "Transaction")
        let cardId = document.cards[0].id
        let runner = AIEditTransactionRunner()
        let calls = [
            OllamaToolCall(function: OllamaToolCallFunction(
                name: "create_button",
                arguments: ["name": "One"]
            )),
            OllamaToolCall(function: OllamaToolCallFunction(
                name: "create_field",
                arguments: ["name": "Two"]
            ))
        ]

        let transaction = await runner.preview(
            toolCalls: calls,
            document: document,
            currentCardId: cardId,
            prompt: "Create controls",
            providerName: "Test"
        )

        #expect(document.parts.isEmpty)
        #expect(transaction.operations.count == 2)
        #expect(transaction.delta.createdPartIds.count == 2)
        #expect(transaction.previewDocument.parts.count == 2)
    }
}
