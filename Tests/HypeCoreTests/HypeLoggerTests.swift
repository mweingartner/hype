import Testing
@testable import HypeCore

@Suite("HypeLogger")
struct HypeLoggerTests {

    // Each test uses a private `HypeLogger` rather than `HypeLogger.shared`
    // so a sibling suite that touches the singleton (under the parallel
    // runner) can't pollute or wipe these test entries between the
    // .info() write and the `.entries.last` read. The earlier
    // singleton-based test was suite-local-serialized but cross-suite
    // races in `swift test` (no `--no-parallel`) still produced flakes.
    // `setupFileLogging: false` keeps each test purely in-memory.

    @Test("log sanitization redacts common secret fields")
    func redactsCommonSecretFields() {
        let logger = HypeLogger(setupFileLogging: false)
        logger.info(
            """
            api_key: secret123
            password='letmein'
            authorization: Bearer abcdef
            keep: visible
            """,
            source: "Test"
        )

        let entry = logger.entries.last
        #expect(entry?.message.contains("[redacted]") == true)
        #expect(entry?.message.contains("secret123") == false)
        #expect(entry?.message.contains("letmein") == false)
        #expect(entry?.message.contains("abcdef") == false)
        #expect(entry?.message.contains("keep: visible") == true)
    }

    @Test("long log entries are bounded for console stability")
    func truncatesLongEntries() {
        let logger = HypeLogger(setupFileLogging: false)
        logger.info(String(repeating: "x", count: 25_000), source: "Test")

        let entry = logger.entries.last
        #expect(entry?.message.contains("[truncated ") == true)
        #expect((entry?.message.count ?? 0) < 25_000)
    }

    @Test("AI dialog helper records role and source")
    func aiDialogLogsRoleAndSource() {
        let logger = HypeLogger(setupFileLogging: false)
        logger.aiDialog(role: "user", content: "Create a card", source: "AI Chat")

        let entry = logger.entries.last
        #expect(entry?.source == "AI Chat")
        #expect(entry?.message.contains("USER:") == true)
        #expect(entry?.message.contains("Create a card") == true)
    }
}
