import Foundation

// MARK: - OpenverseProvider

/// Searches Openverse (Creative Commons) for freely-licensed images.
///
/// No authentication required. Uses `User-Agent: Hype/1.0 (https://hype.app; webAssets)`
/// per the Openverse API usage requirements.
actor OpenverseProvider: WebAssetSearchClient {

    nonisolated let provider: WebAssetSearchProvider = .openverse

    private let sessionFactory: WebAssetURLSessionFactory

    init(sessionFactory: WebAssetURLSessionFactory = .init()) {
        self.sessionFactory = sessionFactory
    }

    // MARK: - WebAssetSearchClient

    func search(_ query: WebAssetSearchQuery) async throws -> [WebAssetSearchResult] {
        let pageSize = min(max(query.maxResults, 1), 20)
        var components = URLComponents(string: "https://api.openverse.engineering/v1/images/")!
        components.queryItems = [
            URLQueryItem(name: "q",         value: query.query),
            URLQueryItem(name: "page_size", value: String(pageSize)),
            URLQueryItem(name: "mature",    value: "false"),
        ]
        guard let url = components.url else {
            throw WebAssetSearchError.providerRejected("Failed to build Openverse URL")
        }
        guard url.scheme?.lowercased() == "https" else {
            throw WebAssetSearchError.httpOnly(url)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let session = sessionFactory.makeProviderSession()
        let (data, response) = try await session.boundedData(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw WebAssetSearchError.providerRejected(body)
        }

        return try parseResults(from: data)
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

    private func parseResults(from data: Data) throws -> [WebAssetSearchResult] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return []
        }

        return results.compactMap { parseResult($0) }
    }

    private func parseResult(_ dict: [String: Any]) -> WebAssetSearchResult? {
        guard let nativeID = dict["id"] as? String,
              let urlString = dict["url"] as? String,
              let downloadURL = URL(string: urlString) else { return nil }

        let title = dict["title"] as? String ?? ""
        let thumbnailString = dict["thumbnail"] as? String ?? ""
        let thumbnailURL = URL(string: thumbnailString)
        let creator = dict["creator"] as? String ?? ""
        let foreignLandingURL = dict["foreign_landing_url"] as? String ?? ""
        let width = dict["width"] as? Int
        let height = dict["height"] as? Int
        let fileSizeBytes = (dict["filesize"] as? Int).map { Int64($0) }
        let fileType = dict["filetype"] as? String ?? ""

        // MIME type
        let inferredMime = mimeType(fromPathExtension: fileType)
            ?? mimeType(fromPathExtension: downloadURL.pathExtension)
            ?? "image/png"

        // License
        let licenseCode = (dict["license"] as? String ?? "").lowercased()
        let licenseVersion = dict["license_version"] as? String ?? ""
        let licenseURL = dict["license_url"] as? String ?? ""
        let licenseIdentifier = licenseVersion.isEmpty ? licenseCode : "\(licenseCode)-\(licenseVersion)"
        let licenseDisplayName = licenseIdentifier.uppercased()
        let shareableCodes: Set<String> = ["cc0", "pdm", "by", "by-sa"]
        let isShareable = shareableCodes.contains(licenseCode)

        let license = AssetLicense(
            name: licenseDisplayName,
            identifier: licenseIdentifier,
            url: licenseURL,
            isShareable: isShareable
        )

        // Attribution
        let attribution = AssetAttribution(
            creator: creator,
            title: title,
            sourceURL: foreignLandingURL,
            downloadURL: urlString,
            providerName: "Openverse",
            providerIdentifier: "openverse"
        )

        let candidateID = webAssetCandidateID(provider: .openverse, nativeID: nativeID)

        return WebAssetSearchResult(
            id: candidateID,
            title: title,
            thumbnailURL: thumbnailURL,
            downloadURL: downloadURL,
            mimeType: inferredMime,
            width: width,
            height: height,
            fileSizeBytes: fileSizeBytes,
            license: license,
            attribution: attribution,
            providerRaw: .openverse
        )
    }
}
