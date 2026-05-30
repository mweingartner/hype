import Foundation
import Testing

@Suite("Console script editor routing")
struct ConsoleScriptEditorRoutingTests {
    @Test("console Open Script links use the shared detached script editor window")
    func consoleOpenScriptUsesSharedScriptEditorWindow() throws {
        let source = try String(
            contentsOf: packageRoot()
                .appendingPathComponent("Sources")
                .appendingPathComponent("Hype")
                .appendingPathComponent("Views")
                .appendingPathComponent("MainContentView.swift"),
            encoding: .utf8
        )

        #expect(!source.contains("ScriptErrorSheetRequest"))
        #expect(!source.contains(".sheet(item: $scriptErrorSheetRequest)"))
        #expect(source.contains("makeScriptErrorOpenRequest"))
        #expect(source.contains("openScriptEditorWindow("))
    }

    private func packageRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
