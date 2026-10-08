import Foundation

/// App-local connection to the user's existing bridge. Never stores a credential
/// or travels with a stack/exported runtime.
public enum BraveSearchConfiguration {
    public static let enabledKey = "hype.braveSearch.enabled"
    public static let endpointKey = "hype.braveSearch.endpoint"
    public static let defaultEndpoint = "http://127.0.0.1:18424/mcp"

    public static func makeSession(defaults: UserDefaults = .standard) -> BraveSearchSession? {
        guard defaults.bool(forKey: enabledKey) else { return nil }
        return BraveSearchSession(endpoint: defaults.string(forKey: endpointKey) ?? defaultEndpoint)
    }

    public static func validatedEndpoint(_ text: String) throws -> URL {
        guard let components = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              let url = components.url else {
            throw BraveSearchError.invalidEndpoint
        }
        return url
    }
}
