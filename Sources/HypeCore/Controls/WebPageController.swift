import Foundation

/// Validates and manages URLs for web page parts.
public struct WebPageController: Sendable {

    /// Allowed URL schemes for web page parts.
    private static let allowedSchemes = Set(["https", "http"])

    /// Validate a URL for web page use. Returns nil if invalid.
    public static func validateURL(_ urlString: String) -> URL? {
        guard !urlString.isEmpty,
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              allowedSchemes.contains(scheme) else {
            return nil
        }
        // Block private/loopback IPs
        if let host = url.host?.lowercased() {
            let blocked = ["localhost", "127.0.0.1", "::1", "0.0.0.0",
                          "ip6-localhost", "ip6-loopback"]
            if blocked.contains(host) { return nil }
            if host.hasPrefix("10.") || host.hasPrefix("192.168.") { return nil }
            if host.hasPrefix("172.") {
                let parts = host.split(separator: ".")
                if parts.count >= 2, let second = Int(parts[1]), (16...31).contains(second) { return nil }
            }
        }
        return url
    }

    /// Resolve the URL for a web page part, checking linked fields.
    public static func resolveURL(part: Part, document: HypeDocument) -> URL? {
        // Check linked field first
        if let linkedFieldId = part.urlSourceFieldId,
           let field = document.parts.first(where: { $0.id == linkedFieldId }) {
            return validateURL(field.textContent.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        // Fall back to static URL
        return validateURL(part.url)
    }
}
