import Foundation

/// Executor branches for the three web-asset AI tools:
/// `search_web_for_sprite`, `import_web_asset`, and `find_and_import_sprite`.
///
/// These are extracted from `HypeToolExecutor.execute` to reduce file size.
/// All tool names, arguments, and return strings are identical to the original;
/// this is a pure mechanical move with no behavioral change.
///
/// Call-site in `HypeToolExecutor.execute`:
/// ```swift
/// case "search_web_for_sprite":
///     return await WebAssetExecutorBranches.executeSearchWebForSprite(
///         arguments: arguments, document: &document,
///         currentCardId: currentCardId, context: self)
/// ```
package enum WebAssetExecutorBranches {

    // MARK: - Phase context for error formatting

    /// Phase context for error formatting (controls whether body summary is included).
    package enum WebAssetErrorPhase { case search, download }

    // MARK: - Tool case branches

    /// Handles the `search_web_for_sprite` tool case.
    package static func executeSearchWebForSprite(
        arguments: [String: String],
        document: HypeDocument,
        currentCardId: UUID,
        context: HypeToolExecutor
    ) async -> String {
        // Gate 0: per-turn soft cap
        guard let session = context.webAssetSession else {
            return "Web asset search is off for this stack. Ask the user to enable it in Preferences → Web Asset Search → Current Stack."
        }
        let capAllowed = await session.shouldAllowDispatch()
        guard capAllowed else {
            return "Safety limit reached: too many web asset operations in one turn. Start a new message to continue."
        }
        // Gate 1: webAssetsAllowed
        guard document.stack.webAssetsAllowed else {
            return "Web asset search is off for this stack. Ask the user to enable it in Preferences → Web Asset Search → Current Stack."
        }
        // Gate 2: wired dependencies
        guard let client = context.webAssetClient else {
            return "search_web_for_sprite not configured: no search client available."
        }

        let query = arguments["query"] ?? ""
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return "search_web_for_sprite requires 'query'."
        }
        let maxResults = min(max(Int(arguments["max_results"] ?? "8") ?? 8, 1), 20)

        do {
            let results = try await client.search(WebAssetSearchQuery(query: query, maxResults: maxResults))
            _ = await session.recordSearch(query: query, results: results)
            if results.isEmpty {
                return "No \(client.provider.displayName) results for \"\(query)\"."
            }
            let lines = results.map { r in
                let w = r.width ?? 0; let h = r.height ?? 0
                let lic = r.license.name.isEmpty ? "unknown" : r.license.name
                return "candidate_id=\(r.id) provider=\(r.providerRaw.rawValue) title=\"\(r.title)\" size=\(w)x\(h) license=\(lic) url=\(r.downloadURL.absoluteString)"
            }
            return "Found \(results.count) candidate(s) from \(client.provider.displayName):\n" + lines.joined(separator: "\n")
        } catch let error as WebAssetSearchError {
            return formatWebAssetError(error, context: "search_web_for_sprite", phase: .search)
        } catch {
            return "search_web_for_sprite network error (transport failure)"
        }
    }

    /// Handles the `import_web_asset` tool case.
    package static func executeImportWebAsset(
        arguments: [String: String],
        document: inout HypeDocument,
        currentCardId: UUID,
        context: HypeToolExecutor
    ) async -> String {
        // Gate 0: per-turn soft cap
        guard let session = context.webAssetSession else {
            return "Web asset search is off for this stack. Ask the user to enable it in Preferences → Web Asset Search → Current Stack."
        }
        let capAllowed2 = await session.shouldAllowDispatch()
        guard capAllowed2 else {
            return "Safety limit reached: too many web asset operations in one turn. Start a new message to continue."
        }
        // Gate 1: webAssetsAllowed
        guard document.stack.webAssetsAllowed else {
            return "Web asset search is off for this stack. Ask the user to enable it in Preferences → Web Asset Search → Current Stack."
        }
        // Gate 2: wired dependencies
        guard let client = context.webAssetClient, let pipeline = context.webAssetPipeline else {
            return "import_web_asset not configured: no search client or pipeline available."
        }

        let candidateId = arguments["candidate_id"] ?? ""
        let rawName = arguments["asset_name"] ?? ""
        guard !candidateId.isEmpty, !rawName.isEmpty else {
            return "import_web_asset requires 'candidate_id' and 'asset_name'."
        }
        // Gate 3: asset_name sanitization (Finding 8)
        guard let cleanedName = context.sanitizeAssetName(rawName) else {
            return "asset_name '\(rawName)' is invalid — use 1-128 characters, letters / digits / _ / - / . / space only"
        }
        guard let candidate = await session.candidate(id: candidateId) else {
            return "Unknown candidate_id '\(candidateId)'. Call search_web_for_sprite first; candidate ids only live for the current chat session."
        }
        let searchQuery = await session.queryForCandidate(id: candidateId) ?? ""

        do {
            let download = try await pipeline.fetch(candidate)
            let asset = WebAssetImportPipeline.makeSpriteAsset(
                name: cleanedName,
                searchQuery: searchQuery,
                download: download
            )
            document.spriteRepository.addAsset(asset)
            let webAssets = document.spriteRepository.assets.filter { $0.provenance?.origin == .webSearch }
            document.stack.script = StackScriptAttributionSync.sync(
                stackScript: document.stack.script,
                webAssets: webAssets
            )
            return "Imported '\(cleanedName)' (\(download.width)x\(download.height), \(download.bytes.count) bytes) from \(candidate.providerRaw.displayName)."
        } catch let error as WebAssetSearchError {
            return formatWebAssetError(error, context: "import_web_asset", phase: .download)
        } catch {
            return "import_web_asset network error (transport failure)"
        }
    }

    /// Handles the `find_and_import_sprite` tool case.
    package static func executeFindAndImportSprite(
        arguments: [String: String],
        document: inout HypeDocument,
        currentCardId: UUID,
        context: HypeToolExecutor
    ) async -> String {
        // Gate 0: per-turn soft cap
        guard let session = context.webAssetSession else {
            return "Web asset search is off for this stack. Ask the user to enable it in Preferences → Web Asset Search → Current Stack."
        }
        let capAllowed3 = await session.shouldAllowDispatch()
        guard capAllowed3 else {
            return "Safety limit reached: too many web asset operations in one turn. Start a new message to continue."
        }
        // Gate 1: webAssetsAllowed
        guard document.stack.webAssetsAllowed else {
            return "Web asset search is off for this stack. Ask the user to enable it in Preferences → Web Asset Search → Current Stack."
        }
        // Gate 2: wired dependencies
        guard let client = context.webAssetClient, let pipeline = context.webAssetPipeline else {
            return "find_and_import_sprite not configured: no search client or pipeline available."
        }

        let fQuery = arguments["query"] ?? ""
        let rawName3 = arguments["asset_name"] ?? ""
        guard !fQuery.isEmpty, !rawName3.isEmpty else {
            return "find_and_import_sprite requires 'query' and 'asset_name'."
        }
        // Gate 3: asset_name sanitization (Finding 8)
        guard let cleanedName3 = context.sanitizeAssetName(rawName3) else {
            return "asset_name '\(rawName3)' is invalid — use 1-128 characters, letters / digits / _ / - / . / space only"
        }

        do {
            let results = try await client.search(WebAssetSearchQuery(query: fQuery, maxResults: 8))
            _ = await session.recordSearch(query: fQuery, results: results)
            guard let first = results.first else {
                return "No \(client.provider.displayName) results for \"\(fQuery)\". find_and_import_sprite did not install anything."
            }
            let download = try await pipeline.fetch(first)
            let asset = WebAssetImportPipeline.makeSpriteAsset(
                name: cleanedName3,
                searchQuery: fQuery,
                download: download
            )
            document.spriteRepository.addAsset(asset)
            let webAssets3 = document.spriteRepository.assets.filter { $0.provenance?.origin == .webSearch }
            document.stack.script = StackScriptAttributionSync.sync(
                stackScript: document.stack.script,
                webAssets: webAssets3
            )
            return "Installed '\(cleanedName3)' from \(first.providerRaw.displayName) (query: \"\(fQuery)\")."
        } catch let error as WebAssetSearchError {
            return formatWebAssetError(error, context: "find_and_import_sprite", phase: .download)
        } catch {
            return "find_and_import_sprite network error (transport failure)"
        }
    }

    // MARK: - Web Asset Helpers (moved from HypeToolExecutor)

    /// Map a `WebAssetSearchError` to a safe, concise AI-visible string.
    ///
    /// Transport-level `localizedDescription` is NEVER forwarded to the AI
    /// (Security Finding 5). `providerRejected` body summaries are trimmed to
    /// 100 printable characters and omitted entirely for download-phase errors
    /// (Security Finding 9).
    package static func formatWebAssetError(
        _ error: WebAssetSearchError,
        context: String,
        phase: WebAssetErrorPhase
    ) -> String {
        switch error {
        case .notConfigured(let msg):
            return "\(context) not configured: \(msg)"

        case .providerRejected(let body):
            switch phase {
            case .search:
                // Trim to 100 printable chars; strip control characters.
                let printable = body.unicodeScalars.filter { scalar in
                    scalar.value >= 0x20 && scalar.value != 0x7F
                }.map { String($0) }.joined()
                let summary = String(printable.prefix(100))
                // Provider name from the error context (best-effort)
                return "\(context.replacingOccurrences(of: "_", with: " ").capitalized) rejected search: \(summary)"
            case .download:
                return "\(context.replacingOccurrences(of: "_", with: " ").capitalized) rejected download (HTTP error)."
            }

        case .httpOnly(let url):
            return "Rejected \(url): only HTTPS downloads are allowed."

        case .redirectBlocked(let from, let to):
            return "Rejected \(from): redirect to \(to) blocked."

        case .ssrfBlocked(let url):
            return "Rejected \(url): network target not allowed."

        case .payloadTooLarge(let url, _):
            return "Rejected \(url): download exceeded 50 MB OOM ceiling."

        case .imageTooLarge(let url, _):
            return "Rejected \(url): decoded image exceeds 100 MP memory safety rail."

        case .unsupportedMimeType(let t):
            return "Rejected image: MIME \"\(t)\" is not a supported image format (png, jpg, webp, gif, svg)."

        case .svgRejected(let why):
            return "Rejected SVG: failed sanitization (\(why))."

        case .decodeFailed(let url):
            return "Rejected \(url): image data did not decode."

        case .unknownCandidate(let id):
            return "Unknown candidate_id '\(id)'. Call search_web_for_sprite first; candidate ids only live for the current chat session."

        case .webAssetsDisabled:
            return "Web asset search is off for this stack."

        case .networkFailure:
            // Do NOT forward localizedDescription — fixed safe string only (Finding 5).
            return "\(context) network error (transport failure)"
        }
    }
}
