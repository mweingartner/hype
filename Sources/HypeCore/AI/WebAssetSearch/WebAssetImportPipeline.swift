import Foundation
#if canImport(AppKit)
import AppKit
#endif

// MARK: - WebAssetImportPipeline

/// Downloads, validates, sanitizes (for SVG), and packages a web-asset search
/// result into a `WebAssetDownloadResult` ready to be wrapped in a `SpriteAsset`.
///
/// All nine pipeline steps are enforced in order. See Section 7.1 of the spec
/// for the authoritative step list.
public actor WebAssetImportPipeline {

    /// 50 MB byte ceiling — prevents oversized downloads from exhausting memory.
    public static let maxBytesPerAsset: Int64 = 50 * 1024 * 1024

    /// 100 MP pixel rail — decompression-bomb defense.
    ///
    /// A small on-the-wire byte count can still decode to billions of pixels
    /// (e.g. WEBP). This guard runs AFTER `NSImage(data:)` succeeds, on the
    /// decoded image dimensions. It is a hard memory-safety stop, NOT user policy.
    /// Do NOT surface this constant in Preferences.
    public static let maxPixelsPerAsset: Int = 100_000_000

    /// The set of MIME types the pipeline can accept.
    public static let supportedMimeTypes: Set<String> = [
        "image/png", "image/jpeg", "image/webp", "image/gif", "image/svg+xml"
    ]

    private let sessionFactory: WebAssetURLSessionFactory

    public init(sessionFactory: WebAssetURLSessionFactory = .init()) {
        self.sessionFactory = sessionFactory
    }

    // MARK: - Main pipeline entry point

    /// Run all nine pipeline steps for a search result.
    ///
    /// - Parameter result: The search result to fetch and validate.
    /// - Returns: A `WebAssetDownloadResult` with validated bytes and dimensions.
    /// - Throws: `WebAssetSearchError` on any step failure.
    public func fetch(_ result: WebAssetSearchResult) async throws -> WebAssetDownloadResult {

        // Step 1: Pre-flight HTTPS check.
        guard result.downloadURL.scheme?.lowercased() == "https" else {
            throw WebAssetSearchError.httpOnly(result.downloadURL)
        }

        // Step 2: Build and issue the GET request.
        var request = URLRequest(url: result.downloadURL)
        request.httpMethod = "GET"

        // Steps 3-5 (byte ceiling, redirect block, SSRF check) are enforced
        // inside the URLSession delegate on the download session.
        let session = sessionFactory.makeDownloadSession()
        let (data, response) = try await session.boundedData(for: request)

        // Step 6: MIME validation.
        let responseMime: String
        if let http = response as? HTTPURLResponse {
            if http.statusCode != 200 {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw WebAssetSearchError.providerRejected(body)
            }
            // Extract base MIME type (strip parameters like charset=...)
            let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
            let baseMime = contentType.components(separatedBy: ";").first?
                .trimmingCharacters(in: .whitespaces) ?? ""
            responseMime = baseMime.isEmpty ? result.mimeType : baseMime
        } else {
            responseMime = result.mimeType
        }

        guard Self.supportedMimeTypes.contains(responseMime) else {
            throw WebAssetSearchError.unsupportedMimeType(responseMime)
        }

        // Step 7: SVG sanitization (only for image/svg+xml).
        let finalData: Data
        if responseMime == "image/svg+xml" {
            let (sanitized, _) = try SVGSanitizer.sanitize(data)
            finalData = sanitized
        } else {
            finalData = data
        }

        // Steps 8-9: Decode with NSImage; enforce 100 MP pixel rail.
        #if canImport(AppKit)
        guard let image = NSImage(data: finalData), image.size.width > 0, image.size.height > 0 else {
            throw WebAssetSearchError.decodeFailed(result.downloadURL)
        }

        let pixelWidth = Int(image.size.width)
        let pixelHeight = Int(image.size.height)
        let pixelCount = pixelWidth * pixelHeight

        // Step 9: Decompression-bomb pixel rail.
        guard pixelCount <= Self.maxPixelsPerAsset else {
            throw WebAssetSearchError.imageTooLarge(result.downloadURL, pixelCount: pixelCount)
        }
        #else
        let pixelWidth = result.width ?? 0
        let pixelHeight = result.height ?? 0
        #endif

        // Step 10: Return.
        return WebAssetDownloadResult(
            bytes: finalData,
            mimeType: responseMime,
            width: pixelWidth,
            height: pixelHeight,
            result: result
        )
    }

    // MARK: - SpriteAsset factory

    /// Create a `SpriteAsset` from a completed download.
    ///
    /// Callers MUST pass the sanitized form of `name` (via
    /// `HypeToolExecutor.sanitizeAssetName`). This method does NOT re-sanitize —
    /// the contract is that callers already sanitized, and passing raw AI-supplied
    /// names here is explicitly forbidden (Section 20, non-goal 16).
    public static func makeSpriteAsset(
        name: String,
        searchQuery: String,
        download: WebAssetDownloadResult
    ) -> SpriteAsset {
        let provenance = AssetProvenance(
            origin: .webSearch,
            searchQuery: searchQuery,
            license: download.result.license,
            attribution: download.result.attribution,
            importedAt: Date()
        )
        return SpriteAsset(
            id: UUID(),
            name: name,
            kind: .imageTexture,
            mimeType: download.mimeType,
            data: download.bytes,
            width: download.width,
            height: download.height,
            tags: [],
            slices: [],
            animationClips: [],
            tileWidth: 0,
            tileHeight: 0,
            tileColumns: 0,
            tileRows: 0,
            provenance: provenance
        )
    }
}
