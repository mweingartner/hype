import Foundation

/// Dispatches messages through the HyperCard-style object hierarchy:
/// part -> card -> background -> stack.
public struct MessageDispatcher: Sendable {

    public init() {}

    /// Dispatch a message through the hierarchy, returning the result from the first
    /// handler that does not pass it.
    public func dispatch(
        message: String,
        params: [Value],
        targetId: UUID,
        document: HypeDocument,
        currentCardId: UUID,
        dialogProvider: DialogProvider = StubDialogProvider()
    ) -> ExecutionResult {
        let chain = buildHierarchy(targetId: targetId, document: document, currentCardId: currentCardId)

        for objectId in chain {
            guard let script = findScript(objectId: objectId, document: document) else { continue }
            guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            // Tokenize and parse the script.
            var lexer = Lexer(source: script)
            let tokens = lexer.tokenize()
            var parser = Parser(tokens: tokens)
            guard let parsedScript = try? parser.parse() else { continue }

            // Look for a matching handler.
            guard let handler = parsedScript.handlers.first(where: {
                $0.name.lowercased() == message.lowercased()
            }) else { continue }

            // Execute the handler.
            let context = ExecutionContext(targetId: objectId, currentCardId: currentCardId, document: document, dialogProvider: dialogProvider)
            let interpreter = Interpreter()
            let result = interpreter.execute(handler: handler, params: params, context: context)

            // If the handler passed the message, continue up the hierarchy.
            if result.status != .passed {
                return result
            }
        }

        // No handler caught the message — return completed.
        return ExecutionResult(status: .completed, returnValue: nil)
    }

    /// Build the message-passing hierarchy chain from the target up to the stack.
    private func buildHierarchy(targetId: UUID, document: HypeDocument, currentCardId: UUID) -> [UUID] {
        var chain: [UUID] = [targetId]

        // If target is a part, add card -> background -> stack.
        if let part = document.parts.first(where: { $0.id == targetId }) {
            if let cardId = part.cardId {
                if !chain.contains(cardId) {
                    chain.append(cardId)
                }
                if let card = document.cards.first(where: { $0.id == cardId }) {
                    chain.append(card.backgroundId)
                }
            } else if let bgId = part.backgroundId {
                chain.append(bgId)
            }
        } else if let card = document.cards.first(where: { $0.id == targetId }) {
            // Target is a card — add background -> stack.
            chain.append(card.backgroundId)
        }

        chain.append(document.stack.id)

        // Deduplicate while preserving order.
        var seen = Set<UUID>()
        return chain.filter { seen.insert($0).inserted }
    }

    /// Find the script associated with an object ID.
    private func findScript(objectId: UUID, document: HypeDocument) -> String? {
        // Check parts.
        if let part = document.parts.first(where: { $0.id == objectId }) {
            return part.script.isEmpty ? nil : part.script
        }
        // Cards, backgrounds, and stacks do not have script fields in the current model.
        // This is a future enhancement.
        return nil
    }
}
