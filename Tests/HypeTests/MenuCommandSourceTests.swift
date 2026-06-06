import Foundation
import Testing

@Suite("Menu command structure")
struct MenuCommandSourceTests {
    @Test("Hype augments the system View menu instead of declaring a duplicate")
    func viewMenuUsesCommandGroup() throws {
        let root = try packageRoot()
        let commandsURL = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("Hype")
            .appendingPathComponent("Views")
            .appendingPathComponent("GoMenuCommands.swift")
        let source = try String(contentsOf: commandsURL, encoding: .utf8)

        #expect(!source.contains("CommandMenu(\"View\")"))
        #expect(source.contains("CommandGroup(after: .toolbar)"))
        #expect(source.contains("Switch to Runtime Mode"))
        #expect(source.contains("Target Platforms…"))
        #expect(source.contains("Export Runtime Packages…"))
        #expect(source.contains("Test Stack in Simulator…"))
        #expect(source.contains("Show Console"))
    }

    @Test("Hype augments the system Edit menu with Duplicate on command-D")
    func editMenuHasDuplicateShortcut() throws {
        let root = try packageRoot()
        let commandsURL = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("Hype")
            .appendingPathComponent("Views")
            .appendingPathComponent("GoMenuCommands.swift")
        let source = try String(contentsOf: commandsURL, encoding: .utf8)

        #expect(!source.contains("\n        CommandMenu(\"Edit\")"))
        #expect(source.contains("CommandGroup(after: .pasteboard)"))
        #expect(source.contains("Button(\"Duplicate\")"))
        #expect(source.contains(".keyboardShortcut(\"d\", modifiers: .command)"))
    }

    @Test("Arrange menu exposes focused layer transfer command")
    func arrangeMenuHasLayerTransferCommand() throws {
        let root = try packageRoot()
        let commandsURL = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("Hype")
            .appendingPathComponent("Views")
            .appendingPathComponent("GoMenuCommands.swift")
        let bridgeURL = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("Hype")
            .appendingPathComponent("AuthoringCommandBridge.swift")
        let commandSource = try String(contentsOf: commandsURL, encoding: .utf8)
        let bridgeSource = try String(contentsOf: bridgeURL, encoding: .utf8)

        #expect(commandSource.contains("CommandMenu(\"Arrange\")"))
        #expect(commandSource.contains("authoringCommands?.layerTransferTitle"))
        #expect(commandSource.contains("transferSelectionToAlternateLayer"))
        #expect(commandSource.contains("canTransferSelectionToAlternateLayer"))
        #expect(bridgeSource.contains("var layerTransferTitle: String"))
        #expect(bridgeSource.contains("var canTransferSelectionToAlternateLayer: Bool"))
        #expect(bridgeSource.contains("var transferSelectionToAlternateLayer: () -> Void"))
    }

    @Test("runtime edit toggle cancels running scripts and returns to select tool")
    func runtimeEditToggleCancelsScripts() throws {
        let root = try packageRoot()
        let sourceURL = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("Hype")
            .appendingPathComponent("Views")
            .appendingPathComponent("MainContentView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("currentTool = .select"))
        #expect(source.contains("cancelRunningScripts()"))
        #expect(source.contains("Switch to Edit Mode"))
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
