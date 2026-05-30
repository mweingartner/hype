import Foundation
import Testing
@testable import HypeCore

@Suite("AI Context tool policy")
struct AIContextToolPolicyTests {
    @Test("local providers can read attached context without cloud opt-in")
    func localProvidersCanReadContext() {
        let document = documentWithContext(cloudAllowed: false)

        let policy = AIContextToolPolicy(provider: .ollama, trustBoundary: .authoringChat, document: document)

        #expect(policy.canReadExistingContext)
        #expect(policy.canImportContextAssets)
        #expect(policy.canWriteContextNotes)
        #expect(!policy.withholdsExistingContext)
    }

    @Test("cloud providers require per-stack context opt-in")
    func cloudProvidersRequireOptIn() {
        let document = documentWithContext(cloudAllowed: false)

        for provider in [HypeAIProvider.openAI, .zAI, .miniMax] {
            let policy = AIContextToolPolicy(provider: provider, trustBoundary: .authoringChat, document: document)
            #expect(!policy.canReadExistingContext)
            #expect(policy.withholdsExistingContext)
            #expect(policy.canWriteContextNotes)
        }
    }

    @Test("cloud opt-in enables context read tools")
    func cloudOptInEnablesReads() {
        let document = documentWithContext(cloudAllowed: true)

        let policy = AIContextToolPolicy(provider: .openAI, trustBoundary: .authoringChat, document: document)

        #expect(policy.canReadExistingContext)
        #expect(!policy.withholdsExistingContext)
    }

    @Test("local debug MCP is an explicit privileged context boundary")
    func localMCPBoundaryCanReadContext() {
        let document = documentWithContext(cloudAllowed: false)

        let policy = AIContextToolPolicy(provider: .openAI, trustBoundary: .localDebugMCP, document: document)

        #expect(policy.canReadExistingContext)
        #expect(policy.stateDescription.contains("local privileged MCP"))
    }

    @Test("tool filtering removes read tools but preserves write-only notes when context is unavailable")
    func toolFilteringPreservesWriteOnlyNotes() {
        let policy = AIContextToolPolicy.explicit(readExistingContext: false)

        let tools = HypeToolDefinitions.toolsApplyingAIContextPolicy(
            HypeToolDefinitions.allTools,
            policy: policy
        )
        let names = Set(tools.map(\.function.name))

        #expect(!names.contains("list_ai_context"))
        #expect(!names.contains("search_ai_context"))
        #expect(!names.contains("read_ai_context_item"))
        #expect(!names.contains("import_context_asset"))
        #expect(names.contains("write_ai_context_note"))
    }

    private func documentWithContext(cloudAllowed: Bool) -> HypeDocument {
        var document = HypeDocument.newDocument(name: "Context Policy")
        document.stack.aiContextCloudSharingAllowed = cloudAllowed
        let note = AIContextIngestor.makeTextNote(title: "Rules", text: "Use native controls.", role: .rules)
        document.aiContextLibrary.addSource(note.0, items: note.1)
        return document
    }
}
