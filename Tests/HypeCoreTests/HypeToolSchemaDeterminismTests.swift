import Foundation
import Testing
@testable import HypeCore

@Suite("Hype tool schema determinism")
struct HypeToolSchemaDeterminismTests {
    /// Swift dictionary order changes on every process launch. A tool schema
    /// built from dictionary iteration therefore renders differently each run,
    /// which invalidates any provider's cached prompt prefix (tens of thousands
    /// of tokens of tool schemas) every time Hype restarts.
    @Test("every tool's required list is in a stable, sorted order")
    func requiredListsAreSorted() {
        for tool in HypeToolDefinitions.allTools + HypeToolDefinitions.webAssetTools {
            let required = tool.function.parameters.required
            #expect(required == required.sorted(), "\(tool.function.name)")
            #expect(Set(required).isSubset(of: Set(tool.function.parameters.properties.keys)), "\(tool.function.name)")
        }
    }

    @Test("the tool catalog encodes to identical JSON on repeated encodes with sorted keys")
    func catalogEncodingIsStable() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let first = try encoder.encode(HypeToolDefinitions.cardControlAuthoringTools)
        let second = try encoder.encode(HypeToolDefinitions.cardControlAuthoringTools)
        #expect(first == second)
    }
}
