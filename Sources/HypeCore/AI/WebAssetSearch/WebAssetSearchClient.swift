import Foundation

// MARK: - Provider Enum

/// The supported web-asset search providers.
public enum WebAssetSearchProvider: String, Codable, Sendable, CaseIterable {
    case openverse
    case wikimedia
    case pexels

    public var displayName: String {
        switch self {
        case .openverse: return "Openverse"
        case .wikimedia: return "Wikimedia Commons"
        case .pexels:    return "Pexels"
        }
    }
}

// MARK: - Query / Result / Download types

/// A search request sent to a `WebAssetSearchClient`.
public struct WebAssetSearchQuery: Sendable {
    public var query: String
    public var maxResults: Int

    public init(query: String, maxResults: Int = 8) {
        self.query = query
        self.maxResults = maxResults
    }
}

/// A single search result returned by a provider.
public struct WebAssetSearchResult: Sendable, Identifiable {
    public let id: String                   // First 16 hex of SHA-256 over "<provider>-<nativeID>"
    public let title: String
    public let thumbnailURL: URL?
    public let downloadURL: URL
    public let mimeType: String
    public let width: Int?
    public let height: Int?
    public let fileSizeBytes: Int64?
    public let license: AssetLicense
    public let attribution: AssetAttribution
    public let providerRaw: WebAssetSearchProvider
}

/// The result of successfully downloading and validating an asset.
public struct WebAssetDownloadResult: Sendable {
    public let bytes: Data
    public let mimeType: String
    public let width: Int
    public let height: Int
    public let result: WebAssetSearchResult
}

// MARK: - Error

/// All errors that can be thrown by the web-asset search pipeline.
public enum WebAssetSearchError: Error, LocalizedError, Sendable {
    /// Provider not configured — e.g. missing API key.
    case notConfigured(String)
    /// Provider returned a non-2xx status.
    case providerRejected(String)
    /// Download URL uses HTTP, not HTTPS.
    case httpOnly(URL)
    /// A redirect was attempted; all redirects are blocked.
    case redirectBlocked(from: URL, to: URL)
    /// Resolved IP address falls in a private/loopback/link-local range (SSRF defense).
    case ssrfBlocked(URL)
    /// Download exceeded the 50 MB OOM byte ceiling.
    case payloadTooLarge(URL, bytes: Int64)
    /// Decoded image exceeds the 100 MP decompression-bomb pixel rail.
    case imageTooLarge(URL, pixelCount: Int)
    /// Response MIME type is not in the supported set.
    case unsupportedMimeType(String)
    /// SVG failed sanitization.
    case svgRejected(String)
    /// Image bytes did not decode via NSImage.
    case decodeFailed(URL)
    /// Candidate ID is unknown — must call search first.
    case unknownCandidate(String)
    /// Web asset search is disabled for this stack.
    case webAssetsDisabled
    /// Network / transport-level failure. The underlying error is held for
    /// internal diagnostics only — it is NEVER forwarded to AI-visible strings.
    case networkFailure(Error)

    public var errorDescription: String? {
        switch self {
        case .notConfigured(let msg):          return "Not configured: \(msg)"
        case .providerRejected(let body):      return "Provider rejected: \(body)"
        case .httpOnly(let url):               return "HTTP not allowed: \(url)"
        case .redirectBlocked(let from, _):    return "Redirect blocked from \(from)"
        case .ssrfBlocked(let url):            return "SSRF blocked: \(url)"
        case .payloadTooLarge(let url, _):     return "Payload too large: \(url)"
        case .imageTooLarge(let url, _):       return "Image too large: \(url)"
        case .unsupportedMimeType(let t):      return "Unsupported MIME: \(t)"
        case .svgRejected(let why):            return "SVG rejected: \(why)"
        case .decodeFailed(let url):           return "Decode failed: \(url)"
        case .unknownCandidate(let id):        return "Unknown candidate: \(id)"
        case .webAssetsDisabled:               return "Web assets disabled"
        case .networkFailure(let err):         return "Network failure: \(err.localizedDescription)"
        }
    }
}

// MARK: - Protocol

/// A provider-specific adapter that can search for and download web assets.
///
/// Implementations: `OpenverseProvider`, `WikimediaProvider`, `PexelsProvider`.
/// All concrete implementations are `actor`s for safe concurrent use.
public protocol WebAssetSearchClient: Sendable {
    var provider: WebAssetSearchProvider { get }
    func search(_ query: WebAssetSearchQuery) async throws -> [WebAssetSearchResult]
    func download(_ result: WebAssetSearchResult) async throws -> Data
}

// MARK: - Factory

/// Creates the appropriate `WebAssetSearchClient` for the given provider.
public enum WebAssetSearchClientFactory {
    /// Build a client for the specified provider.
    ///
    /// - Parameters:
    ///   - provider: Which search provider to use.
    ///   - keychain: Keychain type for secret retrieval (injectable for tests).
    ///   - sessionFactory: URL session factory (injectable for tests).
    /// - Returns: A concrete `WebAssetSearchClient` implementation.
    public static func make(
        provider: WebAssetSearchProvider,
        keychain: KeychainStore.Type = KeychainStore.self,
        sessionFactory: WebAssetURLSessionFactory = .init()
    ) -> any WebAssetSearchClient {
        switch provider {
        case .openverse:  return OpenverseProvider(sessionFactory: sessionFactory)
        case .wikimedia:  return WikimediaProvider(sessionFactory: sessionFactory)
        case .pexels:     return PexelsProvider(keychain: keychain, sessionFactory: sessionFactory)
        }
    }
}

// MARK: - SHA-256 candidate ID helper

import CommonCrypto

/// Compute the first 16 hex characters of SHA-256 over an input string.
/// Used to derive stable, opaque `WebAssetSearchResult.id` values that are
/// safe to store in a chat session without leaking internal provider IDs.
func webAssetCandidateID(provider: WebAssetSearchProvider, nativeID: String) -> String {
    let input = "\(provider.rawValue)-\(nativeID)"
    guard let data = input.data(using: .utf8) else { return nativeID }
    var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    _ = data.withUnsafeBytes {
        CC_SHA256($0.baseAddress, CC_LONG(data.count), &digest)
    }
    return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
}

// MARK: - MIME fallback helper

/// Infer a MIME type from a URL path extension when the provider doesn't
/// supply one explicitly.
func mimeType(fromPathExtension ext: String) -> String? {
    switch ext.lowercased() {
    case "svg":               return "image/svg+xml"
    case "png":               return "image/png"
    case "jpg", "jpeg":       return "image/jpeg"
    case "webp":              return "image/webp"
    case "gif":               return "image/gif"
    default:                  return nil
    }
}
