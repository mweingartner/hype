import Foundation

// MARK: - PexelsProvider

/// Searches Pexels for high-quality royalty-free photos.
///
/// Requires a Pexels API key stored in the Keychain under the account
/// `KeychainStore.pexelsAPIKeyAccount`. The key is read silently at
/// search time — it is never logged, never embedded in error strings,
/// and never written to `UserDefaults` or `Stack.script`.
actor PexelsProvider: WebAssetSearchClient {

    nonisolated let provider: WebAssetSearchProvider = .pexels

    private let keychain: KeychainStore.Type
    private let sessionFactory: WebAssetURLSessionFactory

    init(
        keychain: KeychainStore.Type = KeychainStore.self,
        sessionFactory: WebAssetURLSessionFactory = .init()
    ) {
        self.keychain = keychain
        self.sessionFactory = sessionFactory
    }

    private static let searchURL = "https://api.pexels.com/v1/search"

    // MARK: - WebAssetSearchClient

    func search(_ query: WebAssetSearchQuery) async throws -> [WebAssetSearchResult] {
        // Read API key from Keychain at request time — never captured or cached.
        let apiKey: String
        do {
            apiKey = try keychain.getSecret(account: KeychainStore.pexelsAPIKeyAccount)
        } catch {
            throw WebAssetSearchError.notConfigured("Pexels API key not set.")
        }

        let perPage = min(max(query.maxResults, 1), 20)
        var components = URLComponents(string: Self.searchURL)!
        components.queryItems = [
            URLQueryItem(name: "query",    value: query.query),
            URLQueryItem(name: "per_page", value: String(perPage)),
        ]
        guard let url = components.url else {
            throw WebAssetSearchError.providerRejected("Failed to build Pexels URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // Authorization header: raw key, no "Bearer" prefix (Pexels spec).
        // Key is added just before the call and is NOT retained in any variable
        // accessible outside this function scope.
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")

        let session = sessionFactory.makeProviderSession()
        let (data, response) = try await session.boundedData(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            // Do NOT forward the Pexels error body. Pexels 401/403 responses
            // can include the API key (or enough context to reconstruct it)
            // in the first 100 bytes, which `formatWebAssetError` would then
            // expose to the AI. Emit a status-code-only message instead —
            // the caller knows it's a Pexels call from the provider context.
            // (Security Finding N-4.)
            throw WebAssetSearchError.providerRejected("Pexels HTTP \(http.statusCode)")
        }

        return parseResults(from: data)
    }

    func download(_ result: WebAssetSearchResult) async throws -> Data {
        guard result.downloadURL.scheme?.lowercased() == "https" else {
            throw WebAssetSearchError.httpOnly(result.downloadURL)
        }
        var request = URLRequest(url: result.downloadURL)
        request.httpMethod = "GET"

        let session = sessionFactory.makeDownloadSession()
        let (data, response) = try await session.boundedData(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw WebAssetSearchError.providerRejected("Download HTTP \(http.statusCode)")
        }
        return data
    }

    // MARK: - Response parsing

    private func parseResults(from data: Data) -> [WebAssetSearchResult] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let photos = json["photos"] as? [[String: Any]] else { return [] }

        return photos.compactMap { parsePhoto($0) }
    }

    private func parsePhoto(_ dict: [String: Any]) -> WebAssetSearchResult? {
        guard let nativeID = dict["id"].map({ "\($0)" }),
              let src = dict["src"] as? [String: Any],
              let originalURLString = src["original"] as? String,
              let downloadURL = URL(string: originalURLString),
              downloadURL.scheme?.lowercased() == "https" else { return nil }

        let photographer = dict["photographer"] as? String ?? ""
        let photographerURL = dict["photographer_url"] as? String ?? ""
        let altText = dict["alt"] as? String ?? ""
        let width = dict["width"] as? Int
        let height = dict["height"] as? Int

        let candidateID = webAssetCandidateID(provider: .pexels, nativeID: nativeID)

        // Pexels License is fixed — all content under Pexels License.
        let license = AssetLicense(
            name: "Pexels License",
            identifier: "pexels",
            url: "https://www.pexels.com/license/",
            isShareable: true
        )

        let attribution = AssetAttribution(
            creator: photographer,
            title: altText,
            sourceURL: photographerURL,
            downloadURL: originalURLString,
            providerName: "Pexels",
            providerIdentifier: "pexels"
        )

        return WebAssetSearchResult(
            id: candidateID,
            title: altText.isEmpty ? "Photo by \(photographer)" : altText,
            thumbnailURL: (src["medium"] as? String).flatMap { URL(string: $0) },
            downloadURL: downloadURL,
            mimeType: mimeType(fromPathExtension: downloadURL.pathExtension) ?? "image/jpeg",
            width: width,
            height: height,
            fileSizeBytes: nil,
            license: license,
            attribution: attribution,
            providerRaw: .pexels
        )
    }
}
