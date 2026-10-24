import Foundation
import Testing
@testable import HypeCore

@Suite("AI response narration")
struct AIResponseSpeechPlannerTests {
    @Test("one message creates one announcement, while a later turn may repeat wording")
    func claimsMessageOnce() {
        var planner = AIResponseSpeechPlanner()
        let id = UUID()
        #expect(planner.prepare("Created the customer form.", responseID: id) == "Created the customer form.")
        #expect(planner.prepare("Created the customer form.", responseID: id) == nil)
        #expect(planner.prepare("Created the customer form.", responseID: UUID()) == "Created the customer form.")
    }

    @Test("summarizes actions without reading code, tables, URLs, and verbose details")
    func extractsSummary() throws {
        let response = """
        Here is the implementation.
        Updated the Score field and fixed the Next button.
        ```hypetalk
        on mouseUp
          put "implementation-secret" into field "Score"
        end mouseUp
        ```
        | property | value |
        | payload | table-detail |
        The layout follows the existing form style.
        [Reference](https://example.com/private-payload)
        """
        let summary = try #require(AIResponseSpeechPlanner.summary(of: response))
        #expect(summary == "Updated the Score field and fixed the Next button. The layout follows the existing form style.")
        #expect(!summary.contains("implementation-secret"))
        #expect(!summary.contains("table-detail"))
        #expect(!summary.contains("https://"))
    }

    @Test("long output becomes at most 45 words and 320 characters")
    func boundsSummary() throws {
        let text = "Updated the form. " + Array(repeating: "This detailed explanation describes every field and implementation choice.", count: 80).joined(separator: " ")
        let summary = try #require(AIResponseSpeechPlanner.summary(of: text))
        #expect(summary.hasPrefix("Updated the form."))
        #expect(summary.count <= 320)
        #expect(summary.split(whereSeparator: \.isWhitespace).count <= 45)
        #expect(summary.count < text.count / 10)
    }

    @Test("empty and code-only output does not create a speech job", arguments: ["", " \n", "```json\n{\"payload\":123}\n```", "| key | value |"])
    func skipsNonProse(_ text: String) {
        #expect(AIResponseSpeechPlanner.summary(of: text) == nil)
    }
}
