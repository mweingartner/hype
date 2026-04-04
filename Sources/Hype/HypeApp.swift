import SwiftUI
import HypeCore
import UniformTypeIdentifiers

@main
struct HypeApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: HypeDocumentWrapper()) { file in
            MainContentView(document: file.$document)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Divider()
            }
            GoMenuCommands()
            ToolsMenuCommands()
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
