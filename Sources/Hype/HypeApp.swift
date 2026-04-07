import SwiftUI
import HypeCore
import UniformTypeIdentifiers

/// App delegate to handle quit lifecycle and dispatch the "quit" system message.
final class HypeAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        // Dispatch "quit" message to the current card of each open document.
        // This gives scripts a chance to run cleanup handlers before the app exits.
        NotificationCenter.default.post(name: .hypeQuit, object: nil)
    }
}

extension Notification.Name {
    static let hypeQuit = Notification.Name("hypeQuit")
}

@main
struct HypeApp: App {
    @NSApplicationDelegateAdaptor(HypeAppDelegate.self) var appDelegate

    var body: some Scene {
        DocumentGroup(newDocument: HypeDocumentWrapper()) { file in
            MainContentView(document: file.$document)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Divider()
            }
            GoMenuCommands()
            ObjectsMenuCommands()
            ArrangeMenuCommands()
            ToolsMenuCommands()
            AIMenuCommands()
        }

        Settings {
            PreferencesView()
        }
    }
}

/// Wrapper to make HypeDocument work with SwiftUI DocumentGroup.
struct HypeDocumentWrapper: FileDocument {
    var document: HypeDocument

    static var readableContentTypes: [UTType] { [.hypeStack] }

    init() {
        self.document = HypeDocument.newDocument()
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.document = try JSONDecoder().decode(HypeDocument.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(document)
        return FileWrapper(regularFileWithContents: data)
    }
}

extension UTType {
    static let hypeStack = UTType(exportedAs: "com.hype.stack", conformingTo: .json)
}
