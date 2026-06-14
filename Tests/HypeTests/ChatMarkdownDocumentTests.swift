import Testing
@testable import Hype

@Suite("Chat markdown document")
@MainActor
struct ChatMarkdownDocumentTests {
    @Test("plain assistant text is not treated as markdown")
    func plainTextNotMarkdown() {
        let document = ChatMarkdownDocument("Created the button and set its script.")

        #expect(document.containsMarkdown == false)
        #expect(document.blocks == [.text("Created the button and set its script.")])
    }

    @Test("detects common markdown block and inline syntax")
    func detectsCommonMarkdown() {
        #expect(ChatMarkdownDocument("## Summary\nBuilt **three** cards.").containsMarkdown)
        #expect(ChatMarkdownDocument("- first\n- second").containsMarkdown)
        #expect(ChatMarkdownDocument("Use `go card 2` next.").containsMarkdown)
        #expect(ChatMarkdownDocument("> Looks good").containsMarkdown)
    }

    @Test("extracts well formed markdown table blocks")
    func extractsMarkdownTableBlocks() throws {
        let markdown = """
        Before table.

        | Name | Status |
        | --- | :---: |
        | Intro | Done |
        | Menu | Pending |

        After table.
        """

        let document = ChatMarkdownDocument(markdown)
        #expect(document.containsMarkdown)
        #expect(document.blocks.count == 3)

        guard case .table(let table) = document.blocks[1] else {
            Issue.record("Expected middle block to be a markdown table")
            return
        }

        #expect(table.headers == ["Name", "Status"])
        #expect(table.rows == [
            ["Intro", "Done"],
            ["Menu", "Pending"],
        ])
    }

    @Test("splits adjacent markdown sections into separate render blocks")
    func splitsAdjacentMarkdownSections() {
        let markdown = """
        ## Summary
        Built the stack.
        - Added cards
        - Wired navigation
        ## Next Steps
        Test the script.
        """

        let document = ChatMarkdownDocument(markdown)

        #expect(document.blocks == [
            .text("## Summary"),
            .text("Built the stack."),
            .text("- Added cards\n- Wired navigation"),
            .text("## Next Steps"),
            .text("Test the script."),
        ])
    }
}
