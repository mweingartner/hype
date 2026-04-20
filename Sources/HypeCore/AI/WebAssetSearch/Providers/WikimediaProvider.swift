import Foundation

// MARK: - WikimediaProvider

/// Searches Wikimedia Commons for freely-licensed images.
///
/// Uses two API calls: first a search to get titles, then imageinfo for metadata.
/// No authentication required. `User-Agent: Hype/1.0 (https://hype.app; webAssets)`
/// is required by Wikimedia's bot policy.
actor WikimediaProvider: WebAssetSearchClient {

    nonisolated let provider: WebAssetSearchProvider = .wikimedia

    private let sessionFactory: WebAssetURLSessionFactory

    init(sessionFactory: WebAssetURLSessionFactory = .init()) {
        self.sessionFactory = sessionFactory
    }

    private static let apiBase = "https://commons.wikimedia.org/w/api.php"

    // MARK: - WebAssetSearchClient

    func search(_ query: WebAssetSearchQuery) async throws -> [WebAssetSearchResult] {
        let limit = min(max(query.maxResults, 1), 20)

        // Step 1: search for file titles
        var searchComponents = URLComponents(string: Self.apiBase)!
        searchComponents.queryItems = [
            URLQueryItem(name: "action",      value: "query"),
            URLQueryItem(name: "list",        value: "search"),
            URLQueryItem(name: "srsearch",    value: "filetype:bitmap \(query.query)"),
            URLQueryItem(name: "srlimit",     value: String(limit)),
            URLQueryItem(name: "srnamespace", value: "6"),
            URLQueryItem(name: "format",      value: "json"),
        ]
        guard let searchURL = searchComponents.url else {
            throw WebAssetSearchError.providerRejected("Failed to build Wikimedia search URL")
        }

        var searchRequest = URLRequest(url: searchURL)
        searchRequest.httpMethod = "GET"

        let session = sessionFactory.makeProviderSession()
        let (searchData, searchResponse) = try await session.boundedData(for: searchRequest)

        if let http = searchResponse as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: searchData, encoding: .utf8) ?? ""
            throw WebAssetSearchError.providerRejected(body)
        }

        guard let searchJSON = try? JSONSerialization.jsonObject(with: searchData) as? [String: Any],
              let queryBlock = searchJSON["query"] as? [String: Any],
              let searchResults = queryBlock["search"] as? [[String: Any]] else {
            return []
        }

        let titles = searchResults.compactMap { $0["title"] as? String }
        guard !titles.isEmpty else { return [] }

        // Step 2: fetch imageinfo for the titles
        var infoComponents = URLComponents(string: Self.apiBase)!
        infoComponents.queryItems = [
            URLQueryItem(name: "action",   value: "query"),
            URLQueryItem(name: "prop",     value: "imageinfo"),
            URLQueryItem(name: "iiprop",   value: "url|size|mime|extmetadata"),
            URLQueryItem(name: "titles",   value: titles.joined(separator: "|")),
            URLQueryItem(name: "format",   value: "json"),
        ]
        guard let infoURL = infoComponents.url else {
            throw WebAssetSearchError.providerRejected("Failed to build Wikimedia imageinfo URL")
        }

        var infoRequest = URLRequest(url: infoURL)
        infoRequest.httpMethod = "GET"

        let (infoData, infoResponse) = try await session.boundedData(for: infoRequest)

        if let http = infoResponse as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: infoData, encoding: .utf8) ?? ""
            throw WebAssetSearchError.providerRejected(body)
        }

        return parseImageInfo(from: infoData)
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

    private func parseImageInfo(from data: Data) -> [WebAssetSearchResult] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let query = json["query"] as? [String: Any],
              let pages = query["pages"] as? [String: Any] else { return [] }

        var results: [WebAssetSearchResult] = []

        for (_, pageValue) in pages {
            guard let page = pageValue as? [String: Any],
                  let imageInfoArray = page["imageinfo"] as? [[String: Any]],
                  let imageInfo = imageInfoArray.first else { continue }

            guard let urlString = imageInfo["url"] as? String,
                  let downloadURL = URL(string: urlString),
                  downloadURL.scheme?.lowercased() == "https" else { continue }

            let title = page["title"] as? String ?? ""
            let descriptionURL = imageInfo["descriptionurl"] as? String ?? ""
            let width = imageInfo["width"] as? Int
            let height = imageInfo["height"] as? Int
            let mimeRaw = imageInfo["mime"] as? String ?? ""
            let resolvedMime = mimeRaw.isEmpty
                ? (mimeType(fromPathExtension: downloadURL.pathExtension) ?? "image/png")
                : mimeRaw

            // Metadata from extmetadata
            let extmeta = imageInfo["extmetadata"] as? [String: Any] ?? [:]
            let licenseShortName = (extmeta["LicenseShortName"] as? [String: Any])?["value"] as? String ?? ""
            let licenseURL = (extmeta["LicenseUrl"] as? [String: Any])?["value"] as? String ?? ""
            let artist = stripHTML((extmeta["Artist"] as? [String: Any])?["value"] as? String ?? "")

            // Normalize: Wikimedia returns "CC BY-SA 4.0" (spaces) but search codes use hyphens.
            // Replace spaces with hyphens so "cc by-sa 4.0" → "cc-by-sa-4.0", which
            // contains "cc-by-sa" correctly. Also keep the original for "public domain" check.
            let licenseId = licenseShortName.lowercased()
            let licenseIdNormalized = licenseId.replacingOccurrences(of: " ", with: "-")
            let shareableCodes = ["cc0", "cc-by", "cc-by-sa", "pdm", "public-domain", "public domain"]
            let isShareable = shareableCodes.contains { code in
                licenseId.contains(code) || licenseIdNormalized.contains(code)
            }

            // Wikimedia file page URL
            let nativeID = title
            let candidateID = webAssetCandidateID(provider: .wikimedia, nativeID: nativeID)

            let license = AssetLicense(
                name: licenseShortName,
                identifier: licenseShortName.uppercased(),
                url: licenseURL,
                isShareable: isShareable
            )

            let attribution = AssetAttribution(
                creator: artist,
                title: title.replacingOccurrences(of: "File:", with: ""),
                sourceURL: descriptionURL,
                downloadURL: urlString,
                providerName: "Wikimedia Commons",
                providerIdentifier: "wikimedia"
            )

            results.append(WebAssetSearchResult(
                id: candidateID,
                title: title.replacingOccurrences(of: "File:", with: ""),
                thumbnailURL: nil,
                downloadURL: downloadURL,
                mimeType: resolvedMime,
                width: width,
                height: height,
                fileSizeBytes: nil,
                license: license,
                attribution: attribution,
                providerRaw: .wikimedia
            ))
        }

        return results
    }

    /// Strip basic HTML tags from Wikimedia's artist field.
    ///
    /// Wikimedia returns artist attribution as HTML — e.g.
    /// `<a href="...">Jane Doe</a>`. We want the text, not the tags.
    ///
    /// Range endpoint is `end.upperBound` (inclusive of `>`) rather than
    /// `end.lowerBound`, which would have left a stray `>` in the output.
    /// (Security Finding N-2, post-Builder code review.) An unterminated
    /// `<` (no matching `>`) causes the loop to exit gracefully, leaving
    /// the partial tag in place — the string still flows through
    /// `sanitizeField` before reaching the stack script so any stray
    /// character that sneaks through can't break out of the comment
    /// block.
    private func stripHTML(_ input: String) -> String {
        var result = input
        while let start = result.range(of: "<"),
              let end = result.range(of: ">", range: start.upperBound..<result.endIndex) {
            result.removeSubrange(start.lowerBound..<end.upperBound)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
