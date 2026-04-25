import Testing
@testable import HypeCore

@Suite("HypeLogger", .serialized)
struct HypeLoggerTests {

    @Test("log sanitization redacts common secret fields")
    func redactsCommonSecretFields() {
        HypeLogger.shared.clear()

        HypeLogger.shared.info(
            """
            api_key: secret123
            password='letmein'
            authorization: Bearer abcdef
            keep: visible
            """,
            source: "Test"
        )

        let entry = HypeLogger.shared.entries.last
        #expect(entry?.message.contains("[redacted]") == true)
        #expect(entry?.message.contains("secret123") == false)
        #expect(entry?.message.contains("letmein") == false)
        #expect(entry?.message.contains("abcdef") == false)
        #expect(entry?.message.contains("keep: visible") == true)
    }

    @Test("long log entries are bounded for console stability")
    func truncatesLongEntries() {
        HypeLogger.shared.clear()

        HypeLogger.shared.info(String(repeating: "x", count: 25_000), source: "Test")

        let entry = HypeLogger.shared.entries.last
        #expect(entry?.message.contains("[truncated ") == true)
        #expect((entry?.message.count ?? 0) < 25_000)
    }

    @Test("AI dialog helper records role and source")
    func aiDialogLogsRoleAndSource() {
        HypeLogger.shared.clear()

        HypeLogger.shared.aiDialog(role: "user", content: "Create a card", source: "AI Chat")

        let entry = HypeLogger.shared.entries.last
        #expect(entry?.source == "AI Chat")
        #expect(entry?.message.contains("USER:") == true)
        #expect(entry?.message.contains("Create a card") == true)
    }
}
