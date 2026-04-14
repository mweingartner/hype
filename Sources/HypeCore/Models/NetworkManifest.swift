import Foundation

public enum NetworkTransportKind: String, Codable, Sendable, CaseIterable {
    case http
    case tcp
}

public enum NetworkBindScope: String, Codable, Sendable, CaseIterable {
    case loopback
    case lan
    case any
}

public struct OutboundHostRule: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var hostPattern: String
    public var allowedSchemes: [String]
    public var allowedPorts: [Int]

    public init(
        id: UUID = UUID(),
        hostPattern: String,
        allowedSchemes: [String] = ["http", "https", "tcp", "tls"],
        allowedPorts: [Int] = []
    ) {
        self.id = id
        self.hostPattern = hostPattern
        self.allowedSchemes = allowedSchemes
        self.allowedPorts = allowedPorts
    }
}

public struct SavedNetworkListener: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var transport: NetworkTransportKind
    public var port: Int
    public var host: String
    public var bindScope: NetworkBindScope
    public var callbackMessage: String
    public var autoStart: Bool
    public var httpMethod: String?
    public var httpPath: String?

    public init(
        id: UUID = UUID(),
        name: String,
        transport: NetworkTransportKind,
        port: Int,
        host: String = "127.0.0.1",
        bindScope: NetworkBindScope = .loopback,
        callbackMessage: String,
        autoStart: Bool = false,
        httpMethod: String? = nil,
        httpPath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.transport = transport
        self.port = port
        self.host = host
        self.bindScope = bindScope
        self.callbackMessage = callbackMessage
        self.autoStart = autoStart
        self.httpMethod = httpMethod
        self.httpPath = httpPath
    }
}

public struct StackNetworkManifest: Codable, Sendable, Equatable {
    public var outboundHostRules: [OutboundHostRule]
    public var savedListeners: [SavedNetworkListener]

    public init(
        outboundHostRules: [OutboundHostRule] = [],
        savedListeners: [SavedNetworkListener] = []
    ) {
        self.outboundHostRules = outboundHostRules
        self.savedListeners = savedListeners
    }
}
