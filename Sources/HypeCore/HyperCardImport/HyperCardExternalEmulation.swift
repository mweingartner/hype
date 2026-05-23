import Foundation

public struct HyperCardExternalCall: Sendable, Equatable {
    public var name: String
    public var kind: HyperCardExternalKind
    public var arguments: [Value]

    public init(name: String, kind: HyperCardExternalKind, arguments: [Value]) {
        self.name = name
        self.kind = kind
        self.arguments = arguments
    }
}

public struct HyperCardExternalCallContext: Sendable {
    public var targetId: UUID
    public var currentCardId: UUID
    public var document: HypeDocument

    public init(targetId: UUID, currentCardId: UUID, document: HypeDocument) {
        self.targetId = targetId
        self.currentCardId = currentCardId
        self.document = document
    }
}

public struct HyperCardExternalResult: Sendable {
    public var value: Value
    public var result: Value
    public var modifiedDocument: HypeDocument?
    public var passMessage: Bool
    public var diagnostic: String?

    public init(
        value: Value = "",
        result: Value = "",
        modifiedDocument: HypeDocument? = nil,
        passMessage: Bool = false,
        diagnostic: String? = nil
    ) {
        self.value = value
        self.result = result
        self.modifiedDocument = modifiedDocument
        self.passMessage = passMessage
        self.diagnostic = diagnostic
    }
}

public struct HyperCardExternalRegistry: Sendable {
    public typealias Handler = @Sendable (HyperCardExternalCall, HyperCardExternalCallContext) async -> HyperCardExternalResult

    public struct Entry: Sendable {
        public var status: HyperCardExternalEmulationStatus
        public var handler: Handler?

        public init(status: HyperCardExternalEmulationStatus, handler: Handler? = nil) {
            self.status = status
            self.handler = handler
        }
    }

    public static let `default` = HyperCardExternalRegistry(entries: Self.defaultEntries)

    private let entries: [String: Entry]

    public init(entries: [String: Entry] = [:]) {
        self.entries = entries
    }

    public func status(for name: String, kind: HyperCardExternalKind) -> HyperCardExternalEmulationStatus {
        entries[key(name: name, kind: kind)]?.status ?? .unknown
    }

    public func invoke(
        _ call: HyperCardExternalCall,
        context: HyperCardExternalCallContext
    ) async -> HyperCardExternalResult {
        let lookupKey = key(name: call.name, kind: call.kind)
        guard let entry = entries[lookupKey] else {
            return unsupportedResult(for: call, status: .unknown)
        }
        guard let handler = entry.handler else {
            return unsupportedResult(for: call, status: entry.status)
        }
        return await handler(call, context)
    }

    private func unsupportedResult(
        for call: HyperCardExternalCall,
        status: HyperCardExternalEmulationStatus
    ) -> HyperCardExternalResult {
        let label = call.kind.rawValue
        let message: String
        switch status {
        case .knownUnsupported:
            message = "\(label) '\(call.name)' is known but is not emulated yet."
        case .unknown:
            message = "Can't Load External: \(label) '\(call.name)' is not available in Hype."
        case .emulated:
            message = "\(label) '\(call.name)' has no registered implementation."
        }
        HypeLogger.shared.warn(message, source: "HyperCardExternalRegistry")
        return HyperCardExternalResult(value: "", result: message, diagnostic: message)
    }

    private func key(name: String, kind: HyperCardExternalKind) -> String {
        "\(kind.rawValue):\(Self.normalizedName(name))"
    }

    private static func normalizedName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    private static var defaultEntries: [String: Entry] {
        var result: [String: Entry] = [:]
        func put(_ kind: HyperCardExternalKind, _ names: [String], _ entry: Entry) {
            for name in names {
                result["\(kind.rawValue):\(normalizedName(name))"] = entry
            }
        }

        put(.xcmd, ["SetCursor", "Cursor"], Entry(status: .emulated) { call, _ in
            let cursorName = call.arguments.first ?? ""
            return HyperCardExternalResult(value: "", result: cursorName)
        })
        put(.xcmd, ["AddColor", "ColorizeCard", "ColorizeHC", "ColorTools"], Entry(status: .knownUnsupported))
        put(.xcmd, ["CompileIt", "CompileIt!"], Entry(status: .knownUnsupported))
        put(.xcmd, ["FullPrint", "PrintReport"], Entry(status: .knownUnsupported))
        put(.xcmd, ["ReadWrite", "FileIO", "OpenFile", "SaveFile"], Entry(status: .knownUnsupported))
        put(.xcmd, ["SerialPort", "Modem", "AppleEvents"], Entry(status: .knownUnsupported))

        put(.xfcn, ["ExternalVersion", "XCMDVersion", "HypeVersion"], Entry(status: .emulated) { _, _ in
            HyperCardExternalResult(value: "Hype HyperCard compatibility layer", result: "")
        })
        put(.xfcn, ["AddColorVersion"], Entry(status: .knownUnsupported))
        put(.xfcn, ["ReadFile", "WriteFile", "Directory"], Entry(status: .knownUnsupported))
        return result
    }
}
