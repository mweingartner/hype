import Foundation

// MARK: - Meshy3DAssetImporter

/// Downloads a completed Meshy task's model bytes and converts them into
/// one or more `SpriteAsset` values of `kind == .model3D`.
///
/// The caller is responsible for inserting the returned assets into
/// `document.spriteRepository`. The first asset in the returned array is
/// always the primary GLB; subsequent entries are optional USDZ / FBX.
///
/// Threading: all downloads happen on the `client` actor. The returned
/// `[SpriteAsset]` is value-typed and safe to write on the main actor.
public struct Meshy3DAssetImporter: Sendable {

    // MARK: - Options

    public struct DefaultOptions: Sendable {
        /// When true, the asset name is derived from the first 3–4 words
        /// of the prompt (sanitised). When false, the caller must supply
        /// a name via another path.
        public var nameFromPrompt: Bool = true
        public var maxPromptWordsForName: Int = 4

        public init() {}
    }

    // MARK: - Private state

    private let client: MeshyClient
    private let logger: HypeLogger

    // MARK: - Init

    public init(client: MeshyClient, logger: HypeLogger = .shared) {
        self.client = client
        self.logger = logger
    }

    // MARK: - Public API

    /// Download the GLB (always) and optional USDZ / FBX, then build
    /// `SpriteAsset` values for each successfully downloaded format.
    ///
    /// - If the GLB download fails, this method throws.
    /// - If an optional format (USDZ / FBX) fails, it is omitted from the
    ///   result without throwing — matching user expectation that getting
    ///   one of three formats is still useful.
    ///
    /// - Parameters:
    ///   - result: The completed task result from `MeshyTaskMonitor`.
    ///   - existingAssetNames: Names already in the repository (for dedup).
    ///   - options: Name-derivation options.
    /// - Returns: An array of `SpriteAsset` values. The first is always the
    ///   primary GLB asset.
    public func importTask(
        result: MeshyTaskResult,
        existingAssetNames: Set<String>,
        options: DefaultOptions = DefaultOptions()
    ) async throws -> [SpriteAsset] {

        var assets: [SpriteAsset] = []
        var usedNames: Set<String> = existingAssetNames

        // Always download the primary GLB.
        let glbData = try await client.downloadModel(from: result.modelURL, allowedFormat: .glb)
        let baseName = derivedName(from: result.prompt, wordLimit: options.maxPromptWordsForName)
        let provenance = makeProvenance(result: result)

        let glbAsset = Self.buildAsset(
            from: glbData,
            format: .glb,
            suggestedName: baseName + ".glb",
            existingNames: usedNames,
            provenance: provenance
        )
        assets.append(glbAsset)
        usedNames.insert(glbAsset.name)

        // Optional USDZ.
        if let usdzURL = result.alsoUSDZ {
            if let usdzData = try? await client.downloadModel(from: usdzURL, allowedFormat: .usdz) {
                let usdzAsset = Self.buildAsset(
                    from: usdzData,
                    format: .usdz,
                    suggestedName: baseName + ".usdz",
                    existingNames: usedNames,
                    provenance: provenance
                )
                assets.append(usdzAsset)
                usedNames.insert(usdzAsset.name)
            } else {
                logger.info("Optional USDZ download failed for task \(result.taskId) — omitting", source: "Meshy")
            }
        }

        // Optional FBX.
        if let fbxURL = result.alsoFBX {
            if let fbxData = try? await client.downloadModel(from: fbxURL, allowedFormat: .fbx) {
                let fbxAsset = Self.buildAsset(
                    from: fbxData,
                    format: .fbx,
                    suggestedName: baseName + ".fbx",
                    existingNames: usedNames,
                    provenance: provenance
                )
                assets.append(fbxAsset)
                usedNames.insert(fbxAsset.name)
            } else {
                logger.info("Optional FBX download failed for task \(result.taskId) — omitting", source: "Meshy")
            }
        }

        logger.info(
            "Imported \(assets.count) asset(s) from task \(result.taskId)",
            source: "Meshy"
        )
        return assets
    }

    /// Build a `SpriteAsset` for a single downloaded format. Public for
    /// test access — lets tests exercise asset-construction without hitting
    /// the network.
    ///
    /// - Parameters:
    ///   - data: The raw model bytes.
    ///   - format: The output format (determines MIME type and tags).
    ///   - suggestedName: Preferred file name; will be deduplicated.
    ///   - existingNames: Names already in use (for dedup loop).
    ///   - provenance: Metadata about the generation origin.
    ///   - isRigged: Phase 3 — true for rigged and animated assets.
    ///   - animationActionId: Phase 3 — the Meshy action id, when applicable.
    ///   - extraTags: Phase 3 — additional tags appended to the base set.
    /// - Returns: A `SpriteAsset` with `kind == .model3D`.
    public static func buildAsset(
        from data: Data,
        format: MeshyOutputFormat,
        suggestedName: String,
        existingNames: Set<String>,
        provenance: AssetProvenance,
        isRigged: Bool = false,
        animationActionId: Int? = nil,
        extraTags: [String] = []
    ) -> SpriteAsset {
        let uniqueName = deduplicate(name: suggestedName, against: existingNames)
        let baseTags = ["meshy", "ai-generated", format.rawValue, "format:\(format.rawValue)"]
        return SpriteAsset(
            id: UUID(),
            name: uniqueName,
            kind: .model3D,
            mimeType: format.mimeType,
            data: data,
            width: 0,   // Not pixel data.
            height: 0,
            tags: baseTags + extraTags,
            slices: [],
            animationClips: [],
            tileWidth: 0,
            tileHeight: 0,
            tileColumns: 0,
            tileRows: 0,
            provenance: provenance,
            isRigged: isRigged,
            animationActionId: animationActionId
        )
    }

    // MARK: - Phase 3: Rigging import

    /// Download the rigged GLB and optional basic walk/run clips, then build
    /// `SpriteAsset` values for each successfully downloaded resource.
    ///
    /// - Parameters:
    ///   - result: The completed rigging task result.
    ///   - sourceAssetName: Display name of the source asset (used to derive
    ///     names for the new assets, e.g. "hero" → "hero-rigged.glb").
    ///   - existingAssetNames: Names already in the repository (for dedup).
    ///   - sourcePrompt: Prompt / description for provenance (usually the
    ///     source asset's provenance.searchQuery).
    ///   - options: Name-derivation options.
    /// - Returns: An array of `SpriteAsset` values with `isRigged = true`.
    ///   First is always the primary rigged GLB; subsequent entries are
    ///   optional basic walk/run clips.
    /// - Throws: `MeshyError` if the primary GLB download fails.
    public func importRiggingTask(
        result: MeshyTaskResult,
        sourceAssetName: String,
        existingAssetNames: Set<String>,
        sourcePrompt: String = "",
        options: DefaultOptions = DefaultOptions()
    ) async throws -> [SpriteAsset] {
        var assets: [SpriteAsset] = []
        var usedNames: Set<String> = existingAssetNames

        let provenance = makeRigProvenance(result: result, sourcePrompt: sourcePrompt)
        let baseName = sourceAssetName.isEmpty ? "model" : sourceAssetName

        // Primary rigged GLB.
        let glbData = try await client.downloadModel(from: result.modelURL, allowedFormat: .glb)
        let riggedAsset = Self.buildAsset(
            from: glbData,
            format: .glb,
            suggestedName: "\(baseName)-rigged.glb",
            existingNames: usedNames,
            provenance: provenance,
            isRigged: true,
            animationActionId: nil,
            extraTags: ["meshy-rigged"]
        )
        assets.append(riggedAsset)
        usedNames.insert(riggedAsset.name)

        // Optional basic walking clip.
        if let walkURL = result.basicWalkUrl {
            if let walkData = try? await client.downloadModel(from: walkURL, allowedFormat: .glb) {
                let walkAsset = Self.buildAsset(
                    from: walkData,
                    format: .glb,
                    suggestedName: "\(baseName)-walking.glb",
                    existingNames: usedNames,
                    provenance: provenance,
                    isRigged: true,
                    animationActionId: nil,
                    extraTags: ["meshy-rigged", "meshy-basic-walking"]
                )
                assets.append(walkAsset)
                usedNames.insert(walkAsset.name)
            } else {
                logger.info("Basic walking animation download failed for task \(result.taskId) — omitting", source: "Meshy")
            }
        }

        // Optional basic running clip.
        if let runURL = result.basicRunUrl {
            if let runData = try? await client.downloadModel(from: runURL, allowedFormat: .glb) {
                let runAsset = Self.buildAsset(
                    from: runData,
                    format: .glb,
                    suggestedName: "\(baseName)-running.glb",
                    existingNames: usedNames,
                    provenance: provenance,
                    isRigged: true,
                    animationActionId: nil,
                    extraTags: ["meshy-rigged", "meshy-basic-running"]
                )
                assets.append(runAsset)
                usedNames.insert(runAsset.name)
            } else {
                logger.info("Basic running animation download failed for task \(result.taskId) — omitting", source: "Meshy")
            }
        }

        logger.info("Imported \(assets.count) rigged asset(s) from task \(result.taskId)", source: "Meshy")
        return assets
    }

    // MARK: - Phase 3: Animation import

    /// Download the animated GLB and build a `SpriteAsset` with
    /// `isRigged = true` and `animationActionId = actionId.value`.
    ///
    /// - Parameters:
    ///   - result: The completed animation task result.
    ///   - sourceAssetName: Display name of the source asset.
    ///   - actionId: The Meshy action id that was applied.
    ///   - actionName: Display-friendly name of the action (used for naming).
    ///   - existingAssetNames: Names already in the repository (for dedup).
    ///   - sourcePrompt: Prompt / description for provenance.
    ///   - options: Name-derivation options.
    /// - Returns: A single `SpriteAsset` with `isRigged = true` and
    ///   `animationActionId` set.
    /// - Throws: `MeshyError` if the GLB download fails.
    public func importAnimationTask(
        result: MeshyTaskResult,
        sourceAssetName: String,
        actionId: MeshyActionId,
        actionName: String,
        existingAssetNames: Set<String>,
        sourcePrompt: String = "",
        options: DefaultOptions = DefaultOptions()
    ) async throws -> SpriteAsset {
        let provenance = makeRigProvenance(result: result, sourcePrompt: sourcePrompt)
        let baseName = sourceAssetName.isEmpty ? "model" : sourceAssetName
        // Derive a file-system-safe action name.
        let safeAction = actionName.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }

        let glbData = try await client.downloadModel(from: result.modelURL, allowedFormat: .glb)
        let asset = Self.buildAsset(
            from: glbData,
            format: .glb,
            suggestedName: "\(baseName)-\(safeAction).glb",
            existingNames: existingAssetNames,
            provenance: provenance,
            isRigged: true,
            animationActionId: actionId.value,
            extraTags: ["meshy-rigged", "meshy-animation", "action:\(actionId.value)"]
        )

        logger.info("Imported animated asset (action \(actionId.value)) from task \(result.taskId)", source: "Meshy")
        return asset
    }

    // MARK: - Private helpers

    private func makeProvenance(result: MeshyTaskResult) -> AssetProvenance {
        AssetProvenance(
            origin: .aiGenerated,
            searchQuery: result.prompt,
            license: AssetLicense(
                name: "Meshy.ai",
                identifier: "meshy",
                url: "https://docs.meshy.ai",
                isShareable: false
            ),
            attribution: AssetAttribution(
                creator: "AI",
                title: result.prompt,
                sourceURL: "",
                downloadURL: result.modelURL.absoluteString,
                providerName: "Meshy.ai",
                providerIdentifier: "meshy",
                taskId: result.taskId   // Phase 3: enables rigging chaining
            ),
            importedAt: Date()
        )
    }

    /// Build a provenance record for a rigging or animation task result.
    private func makeRigProvenance(result: MeshyTaskResult, sourcePrompt: String) -> AssetProvenance {
        AssetProvenance(
            origin: .aiGenerated,
            searchQuery: sourcePrompt,
            license: AssetLicense(
                name: "Meshy.ai",
                identifier: "meshy",
                url: "https://docs.meshy.ai",
                isShareable: false
            ),
            attribution: AssetAttribution(
                creator: "AI",
                title: sourcePrompt,
                sourceURL: "",
                downloadURL: result.modelURL.absoluteString,
                providerName: "Meshy.ai",
                providerIdentifier: "meshy",
                taskId: result.taskId
            ),
            importedAt: Date()
        )
    }

    /// Derive a sanitised base name from the prompt's first N words.
    ///
    /// Rules: lower-case, ASCII only, non-alphanumeric → `-`,
    /// leading/trailing `-` stripped, consecutive `-` collapsed.
    private func derivedName(from prompt: String, wordLimit: Int) -> String {
        let words = prompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .prefix(wordLimit)
        let raw = words.joined(separator: "-").lowercased()
        // Sanitise: keep alphanumeric + hyphen; replace others.
        let sanitised = raw.unicodeScalars.map { scalar -> Character in
            let ch = Character(scalar)
            if ch.isLetter || ch.isNumber || ch == "-" { return ch }
            return "-"
        }
        let joined = String(sanitised)
        // Collapse runs of hyphens and strip leading/trailing.
        var result = ""
        var prevWasHyphen = false
        for ch in joined {
            if ch == "-" {
                if !prevWasHyphen && !result.isEmpty { result.append(ch) }
                prevWasHyphen = true
            } else {
                result.append(ch)
                prevWasHyphen = false
            }
        }
        // Strip trailing hyphen.
        while result.hasSuffix("-") { result.removeLast() }
        return result.isEmpty ? "mesh" : result
    }

    /// Deduplicates `name` against `existingNames` by appending " 2", " 3", …
    /// until a unique name is found.
    private static func deduplicate(name: String, against existingNames: Set<String>) -> String {
        guard existingNames.contains(name) else { return name }
        var counter = 2
        // Strip the extension to de-dup the base name.
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        while true {
            let candidate = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            if !existingNames.contains(candidate) { return candidate }
            counter += 1
        }
    }
}
