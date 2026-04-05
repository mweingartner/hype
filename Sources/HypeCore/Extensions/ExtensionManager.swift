import Foundation

/// An extension that adds commands/functions to HypeTalk.
public struct HypeExtension: Identifiable, Sendable {
    public var id: String
    public var name: String
    public var version: String
    public var commands: [String]
    public var functions: [String]
    public var enabled: Bool

    public init(id: String, name: String, version: String = "1.0", commands: [String] = [], functions: [String] = [], enabled: Bool = true) {
        self.id = id
        self.name = name
        self.version = version
        self.commands = commands
        self.functions = functions
        self.enabled = enabled
    }
}

/// Manages loaded extensions (modern XCMDs).
public actor ExtensionManager {
    private var extensions: [String: HypeExtension] = [:]

    public init() {}

    public func register(_ ext: HypeExtension) {
        extensions[ext.id] = ext
    }

    public func unregister(id: String) {
        extensions.removeValue(forKey: id)
    }

    public func getExtension(id: String) -> HypeExtension? {
        extensions[id]
    }

    public func allExtensions() -> [HypeExtension] {
        Array(extensions.values)
    }

    /// Find which extension provides a given command.
    public func findCommand(_ name: String) -> HypeExtension? {
        extensions.values.first { $0.enabled && $0.commands.contains(name.lowercased()) }
    }

    /// Find which extension provides a given function.
    public func findFunction(_ name: String) -> HypeExtension? {
        extensions.values.first { $0.enabled && $0.functions.contains(name.lowercased()) }
    }
}
