import Foundation

/// Executor branches for the Meshy 3D generation AI tools:
/// `list_3d_models`, `bind_3d_model_to_scene3d`,
/// `generate_3d_model_from_text`, `generate_3d_model_from_image`,
/// `generate_3d_model_from_images`, `remesh_3d_model`, `retexture_3d_model`.
///
/// These are extracted from `HypeToolExecutor.execute` to reduce file size.
/// All tool names, arguments, and return strings are identical to the original;
/// this is a pure mechanical move with no behavioral change.
package enum Scene3DExecutorBranches {

    // MARK: - Tool dispatcher stubs (called from HypeToolExecutor.execute)

    /// Handles the `list_3d_models` tool case.
    package static func executeListModel3DAssets(
        document: HypeDocument
    ) -> String {
        let models = document.spriteRepository.assets
            .filter { $0.kind == .model3D }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        guard !models.isEmpty else {
            return "(no 3D models in repository)"
        }

        let cap = 50
        let shown = Array(models.prefix(cap))
        var lines = shown.map { asset in
            var row = "name=\(asset.name) id=\(asset.id) size=\(asset.data.count)B is_rigged=\(asset.isRigged)"
            if let actionId = asset.animationActionId {
                row += " action_id=\(actionId)"
            }
            return row
        }
        if models.count > cap {
            lines.append("… and \(models.count - cap) more — use the Sprite Repository to see all.")
        }
        return lines.joined(separator: "\n")
    }

    /// Handles the `bind_3d_model_to_scene3d` tool case.
    package static func executeBindModel3DToScene3D(
        arguments: [String: String],
        document: inout HypeDocument,
        currentCardId: UUID,
        context: HypeToolExecutor
    ) -> String {
        let partName = (arguments["scene3d_part_name"] ?? arguments["part_name"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let assetName = (arguments["model_asset_name"] ?? arguments["asset_name"] ?? arguments["model"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !partName.isEmpty else {
            return "bind_3d_model_to_scene3d requires 'scene3d_part_name'."
        }
        guard !assetName.isEmpty else {
            return "bind_3d_model_to_scene3d requires 'model_asset_name'."
        }
        guard let index = context.scopedPartIndex(named: partName, currentCardId: currentCardId, in: document) else {
            return "Scene3D part '\(partName)' not found."
        }
        guard document.parts[index].partType == .scene3D else {
            return "Part '\(partName)' is a \(document.parts[index].partType.rawValue), not a scene3D part."
        }
        guard let asset = document.spriteRepository.asset(byName: assetName) else {
            return "3D model asset '\(assetName)' not found in the Sprite Repository."
        }
        guard asset.kind == .model3D else {
            return "Asset '\(assetName)' is \(asset.kind.rawValue), not model3D."
        }

        document.parts[index].scene3DAssetRef = document.spriteRepository.assetRef(for: asset)
        document.parts[index].scene3DSourceURL = ""
        document.parts[index].scene3DURL = ""
        return "Bound model3D asset '\(asset.name)' to scene3D part '\(document.parts[index].name)'."
    }

    /// Handles the `generate_3d_model_from_text` tool case.
    package static func executeGenerate3DFromText(
        arguments: [String: String],
        document: inout HypeDocument,
        currentCardId: UUID,
        context: HypeToolExecutor
    ) async -> String {
        // Step A: Gate check.
        let (client, gateError) = meshyGateAndClient(document: document, context: context)
        if let err = gateError { return err }
        guard let client else { return "Internal error: no Meshy client." }

        // Step B: Validate arguments.
        let promptRaw = arguments["prompt"] ?? ""
        let prompt = promptRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            return "generate_3d_model_from_text requires 'prompt'."
        }
        guard prompt.count <= 600 else {
            return "generate_3d_model_from_text: prompt must be ≤ 600 characters."
        }

        // Validate place_on_card / part_name constraint before starting generation.
        let placeOnCard = (arguments["place_on_card"] ?? "").lowercased() == "true"
        if placeOnCard {
            let rawPartName = arguments["part_name"] ?? ""
            guard context.sanitizeAssetName(rawPartName) != nil, !rawPartName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return "generate_3d_model_from_text requires 'part_name' when place_on_card='true'."
            }
        }

        let artStyleRaw = (arguments["art_style"] ?? "realistic").lowercased()
        let artStyle: MeshyArtStyle = artStyleRaw == "sculpture" ? .sculpture : .realistic
        let aiModel: MeshyAIModel = parseAIModel(arguments["ai_model"])
        let shouldRemesh = context.boolArgument(arguments["should_remesh"]) ?? aiModel.defaultRemesh
        let (assetName, assetNameError) = optional3DAssetName(arguments: arguments, toolName: "generate_3d_model_from_text", context: context)
        if let assetNameError { return assetNameError }

        // Step C: Progress reporter (D in plan).
        let reporter = Meshy3DToolProgressReporter(
            logger: .shared,
            toolName: "generate_3d_model_from_text",
            taskKindDescription: "text-to-3D"
        )

        // Step D: Run the job (E in plan).
        let job = Generate3DJob(client: client)
        let options = generate3DOptions(
            arguments: arguments,
            aiModel: aiModel,
            shouldRemesh: shouldRemesh,
            assetName: assetName,
            hardTimeout: 300,   // 5-min cap for AI tool path.
            context: context
        )
        let existing = Set(document.spriteRepository.assets.map(\.name))
        let assets: [SpriteAsset]
        do {
            assets = try await job.run(
                kind: .text(prompt: prompt, artStyle: artStyle),
                options: options,
                existingAssetNames: existing,
                onProgress: { state in reporter.report(state) }
            )
        } catch let error as MeshyError {
            if case .timedOut = error {
                return "Meshy generation timed out after 5 minutes. The Meshy task may still be running — check your dashboard. The Generate 3D sheet (Sprite Repository → Generate 3D) supports the full 30-minute wait."
            }
            return "Meshy generation failed: \(error.errorDescription ?? "unknown error")."
        } catch is CancellationError {
            return "Meshy generation cancelled."
        } catch {
            return "Meshy generation failed: \(error.localizedDescription)"
        }

        // Step E: Integration (F in plan).
        for asset in assets {
            document.spriteRepository.addAsset(asset)
        }
        guard let primary = assets.first else {
            return "Meshy generation failed: no assets were imported."
        }

        var result = "Generated 3D model '\(primary.name)' and added to the Sprite Repository."
        if let partResult = placeScene3DPartIfRequested(
            arguments: arguments,
            document: &document,
            currentCardId: currentCardId,
            primaryAsset: primary,
            context: context
        ) {
            result += " \(partResult)"
        }
        return result
    }

    /// Handles the `generate_3d_model_from_image` tool case.
    package static func executeGenerate3DFromImage(
        arguments: [String: String],
        document: inout HypeDocument,
        currentCardId: UUID,
        context: HypeToolExecutor
    ) async -> String {
        // Step A: Gate check.
        let (client, gateError) = meshyGateAndClient(document: document, context: context)
        if let err = gateError { return err }
        guard let client else { return "Internal error: no Meshy client." }

        // Validate place_on_card / part_name before starting generation.
        let placeOnCard = (arguments["place_on_card"] ?? "").lowercased() == "true"
        if placeOnCard {
            let rawPartName = arguments["part_name"] ?? ""
            guard context.sanitizeAssetName(rawPartName) != nil, !rawPartName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return "generate_3d_model_from_image requires 'part_name' when place_on_card='true'."
            }
        }

        // Step B: Parse image input — exactly one of the three sources must be set.
        let imageInput: MeshyImageInput
        if let pathArg = arguments["image_path"].flatMap({ $0.isEmpty ? nil : $0 }) {
            imageInput = .filePath(pathArg)
        } else if let nameArg = arguments["image_asset_name"].flatMap({ $0.isEmpty ? nil : $0 }) {
            imageInput = .assetName(nameArg)
        } else if let b64Arg = arguments["image_base64"].flatMap({ $0.isEmpty ? nil : $0 }) {
            imageInput = .base64(b64Arg)
        } else {
            return "generate_3d_model_from_image requires one of: image_path, image_asset_name, or image_base64."
        }

        // Resolve and validate the image input.
        let resolved: MeshyImageInput.Resolved
        do {
            resolved = try imageInput.resolve(in: document.spriteRepository)
        } catch let error as MeshyError {
            return "Image validation failed: \(error.errorDescription ?? "unknown error")."
        } catch {
            return "Image validation failed: \(error.localizedDescription)"
        }

        let aiModel: MeshyAIModel = parseAIModel(arguments["ai_model"])
        let shouldRemesh = context.boolArgument(arguments["should_remesh"]) ?? aiModel.defaultRemesh
        let (assetName, assetNameError) = optional3DAssetName(arguments: arguments, toolName: "generate_3d_model_from_image", context: context)
        if let assetNameError { return assetNameError }

        let reporter = Meshy3DToolProgressReporter(
            logger: .shared,
            toolName: "generate_3d_model_from_image",
            taskKindDescription: "image-to-3D"
        )

        let job = Generate3DJob(client: client)
        let options = generate3DOptions(
            arguments: arguments,
            aiModel: aiModel,
            shouldRemesh: shouldRemesh,
            assetName: assetName,
            hardTimeout: 300,
            context: context
        )
        let existing = Set(document.spriteRepository.assets.map(\.name))
        let assets: [SpriteAsset]
        do {
            assets = try await job.run(
                kind: .singleImage(image: resolved),
                options: options,
                existingAssetNames: existing,
                onProgress: { state in reporter.report(state) }
            )
        } catch let error as MeshyError {
            if case .timedOut = error {
                return "Meshy generation timed out after 5 minutes. The Meshy task may still be running — check your dashboard. The Generate 3D sheet (Sprite Repository → Generate 3D) supports the full 30-minute wait."
            }
            return "Meshy generation failed: \(error.errorDescription ?? "unknown error")."
        } catch is CancellationError {
            return "Meshy generation cancelled."
        } catch {
            return "Meshy generation failed: \(error.localizedDescription)"
        }

        for asset in assets {
            document.spriteRepository.addAsset(asset)
        }
        guard let primary = assets.first else {
            return "Meshy generation failed: no assets were imported."
        }

        // H1: result string uses asset name only — never sourceDescriptor.
        var result = "Generated 3D model '\(primary.name)' from image and added to the Sprite Repository."
        if let partResult = placeScene3DPartIfRequested(
            arguments: arguments,
            document: &document,
            currentCardId: currentCardId,
            primaryAsset: primary,
            context: context
        ) {
            result += " \(partResult)"
        }
        return result
    }

    /// Handles the `generate_3d_model_from_images` tool case.
    package static func executeGenerate3DFromImages(
        arguments: [String: String],
        document: inout HypeDocument,
        currentCardId: UUID,
        context: HypeToolExecutor
    ) async -> String {
        // Step A: Gate check.
        let (client, gateError) = meshyGateAndClient(document: document, context: context)
        if let err = gateError { return err }
        guard let client else { return "Internal error: no Meshy client." }

        // Validate place_on_card / part_name before starting generation.
        let placeOnCard = (arguments["place_on_card"] ?? "").lowercased() == "true"
        if placeOnCard {
            let rawPartName = arguments["part_name"] ?? ""
            guard context.sanitizeAssetName(rawPartName) != nil, !rawPartName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return "generate_3d_model_from_images requires 'part_name' when place_on_card='true'."
            }
        }

        // Step B: Parse comma-separated image refs.
        let imagesArg = arguments["images"] ?? ""
        guard !imagesArg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "generate_3d_model_from_images requires 'images' — a comma-separated list of 2–4 refs (prefix each with 'asset:', 'path:', or 'base64:')."
        }

        // Split on commas. Each ref must have a prefix.
        let rawRefs = imagesArg.split(separator: ",", omittingEmptySubsequences: true).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard (2...4).contains(rawRefs.count) else {
            return "generate_3d_model_from_images requires 2 to 4 image refs (got \(rawRefs.count))."
        }

        var inputs: [MeshyImageInput] = []
        for ref in rawRefs {
            if ref.hasPrefix("asset:") {
                inputs.append(.assetName(String(ref.dropFirst("asset:".count))))
            } else if ref.hasPrefix("path:") {
                inputs.append(.filePath(String(ref.dropFirst("path:".count))))
            } else if ref.hasPrefix("base64:") {
                inputs.append(.base64(String(ref.dropFirst("base64:".count))))
            } else {
                return "Image ref '\(ref.prefix(40))' must be prefixed with 'asset:', 'path:', or 'base64:'."
            }
        }

        // Resolve all inputs.
        var resolvedImages: [MeshyImageInput.Resolved] = []
        for input in inputs {
            do {
                let resolved = try input.resolve(in: document.spriteRepository)
                resolvedImages.append(resolved)
            } catch let error as MeshyError {
                return "Image validation failed: \(error.errorDescription ?? "unknown error")."
            } catch {
                return "Image validation failed: \(error.localizedDescription)"
            }
        }

        // M2: Combined 40 MB cap — checked again inside Generate3DJob but
        // surfacing here gives a better error message.
        let totalBytes = resolvedImages.map(\.data.count).reduce(0, +)
        guard totalBytes <= 40 * 1024 * 1024 else {
            return "Total image size (\(totalBytes / 1_048_576) MB) exceeds the 40 MB combined limit."
        }

        let aiModel: MeshyAIModel = parseAIModel(arguments["ai_model"])
        let shouldRemesh = context.boolArgument(arguments["should_remesh"]) ?? aiModel.defaultRemesh
        let (assetName, assetNameError) = optional3DAssetName(arguments: arguments, toolName: "generate_3d_model_from_images", context: context)
        if let assetNameError { return assetNameError }

        let reporter = Meshy3DToolProgressReporter(
            logger: .shared,
            toolName: "generate_3d_model_from_images",
            taskKindDescription: "multi-image-to-3D"
        )

        let job = Generate3DJob(client: client)
        let options = generate3DOptions(
            arguments: arguments,
            aiModel: aiModel,
            shouldRemesh: shouldRemesh,
            assetName: assetName,
            hardTimeout: 300,
            context: context
        )
        let existing = Set(document.spriteRepository.assets.map(\.name))
        let assets: [SpriteAsset]
        do {
            assets = try await job.run(
                kind: .multiImage(images: resolvedImages),
                options: options,
                existingAssetNames: existing,
                onProgress: { state in reporter.report(state) }
            )
        } catch let error as MeshyError {
            if case .timedOut = error {
                return "Meshy generation timed out after 5 minutes. The Meshy task may still be running — check your dashboard. The Generate 3D sheet (Sprite Repository → Generate 3D) supports the full 30-minute wait."
            }
            return "Meshy generation failed: \(error.errorDescription ?? "unknown error")."
        } catch is CancellationError {
            return "Meshy generation cancelled."
        } catch {
            return "Meshy generation failed: \(error.localizedDescription)"
        }

        for asset in assets {
            document.spriteRepository.addAsset(asset)
        }
        guard let primary = assets.first else {
            return "Meshy generation failed: no assets were imported."
        }

        // H1: result string uses asset name only — never sourceDescriptors.
        var result = "Generated 3D model '\(primary.name)' from \(resolvedImages.count) images and added to the Sprite Repository."
        if let partResult = placeScene3DPartIfRequested(
            arguments: arguments,
            document: &document,
            currentCardId: currentCardId,
            primaryAsset: primary,
            context: context
        ) {
            result += " \(partResult)"
        }
        return result
    }

    /// Handles the `remesh_3d_model` tool case.
    ///
    /// **Security (C5):** validates `targetPolycount` at this executor layer
    /// (third defense-in-depth layer after client + flow).
    package static func executeRemesh3D(
        arguments: [String: String],
        document: inout HypeDocument,
        currentCardId: UUID,
        context: HypeToolExecutor
    ) async -> String {
        // Step A: Gate check.
        let (client, gateError) = meshyGateAndClient(document: document, context: context)
        if let err = gateError { return err }
        guard let client else { return "Internal error: no Meshy client." }

        // Step B: Validate source asset.
        let sourceAssetName = (arguments["source_asset_name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceAssetName.isEmpty else {
            return "remesh_3d_model requires 'source_asset_name'."
        }
        guard let sourceAsset = document.spriteRepository.assets.first(where: { $0.name == sourceAssetName }) else {
            return "remesh_3d_model: asset '\(sourceAssetName)' not found in the Sprite Repository."
        }
        let sourceTaskId = sourceAsset.provenance?.attribution.taskId ?? ""
        guard !sourceTaskId.isEmpty,
              sourceAsset.provenance?.attribution.providerIdentifier == "meshy" else {
            return "remesh_3d_model: '\(sourceAssetName)' wasn't generated by Meshy. Remesh requires a Meshy-generated source model."
        }

        // Step C: Validate target_polycount (C5 — third layer).
        let polycountRaw = (arguments["target_polycount"] ?? "30000").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let targetPolycount = Int(polycountRaw), (100...300_000).contains(targetPolycount) else {
            return "remesh_3d_model: 'target_polycount' must be an integer between 100 and 300,000 (got '\(polycountRaw)')."
        }
        let topologyRaw = (arguments["topology"] ?? "triangle").lowercased()
        let topology = topologyRaw == "quad" ? "quad" : "triangle"

        // Validate place_on_card / part_name constraint.
        let placeOnCard = (arguments["place_on_card"] ?? "").lowercased() == "true"
        if placeOnCard {
            let rawPartName = arguments["part_name"] ?? ""
            guard context.sanitizeAssetName(rawPartName) != nil, !rawPartName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return "remesh_3d_model requires 'part_name' when place_on_card='true'."
            }
        }

        // Step D: Run the remesh flow (5-min cap for AI tool path).
        let reporter = Meshy3DToolProgressReporter(
            logger: .shared,
            toolName: "remesh_3d_model",
            taskKindDescription: "remesh"
        )
        let flow = RemeshAndRetextureFlow(client: client)
        let options = RemeshAndRetextureFlow.RemeshOptions(
            targetPolycount: targetPolycount,
            topology: topology,
            hardTimeout: 300
        )
        let sourcePrompt = sourceAsset.provenance?.searchQuery ?? ""
        let existingNames = Set(document.spriteRepository.assets.map(\.name))

        let asset: SpriteAsset
        do {
            asset = try await flow.runRemesh(
                sourceTaskId: sourceTaskId,
                sourceAssetName: sourceAssetName,
                sourcePrompt: sourcePrompt,
                options: options,
                existingAssetNames: existingNames,
                onProgress: { state in reporter.report(state) }
            )
        } catch let error as MeshyError {
            if case .timedOut = error {
                return "Meshy remesh timed out after 5 minutes. The task may still be running — check your Meshy dashboard."
            }
            return "Meshy remesh failed: \(error.errorDescription ?? "unknown error")."
        } catch is CancellationError {
            return "Meshy remesh cancelled."
        } catch {
            return "Meshy remesh failed: \(error.localizedDescription)"
        }

        // Step E: Install asset into document (AIEditTransaction captures this).
        document.spriteRepository.addAsset(asset)

        var result = "Remeshed '\(sourceAssetName)' to \(targetPolycount) polygons. New asset '\(asset.name)' added to the Sprite Repository."
        if let partResult = placeScene3DPartIfRequested(
            arguments: arguments,
            document: &document,
            currentCardId: currentCardId,
            primaryAsset: asset,
            context: context
        ) {
            result += " \(partResult)"
        }
        return result
    }

    /// Handles the `retexture_3d_model` tool case.
    ///
    /// **Security (C6):** validates `style_prompt` is non-empty; truncation
    /// to 600 chars is applied in `MeshyRetextureRequest.init`.
    package static func executeRetexture3D(
        arguments: [String: String],
        document: inout HypeDocument,
        currentCardId: UUID,
        context: HypeToolExecutor
    ) async -> String {
        // Step A: Gate check.
        let (client, gateError) = meshyGateAndClient(document: document, context: context)
        if let err = gateError { return err }
        guard let client else { return "Internal error: no Meshy client." }

        // Step B: Validate source asset.
        let sourceAssetName = (arguments["source_asset_name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceAssetName.isEmpty else {
            return "retexture_3d_model requires 'source_asset_name'."
        }
        guard let sourceAsset = document.spriteRepository.assets.first(where: { $0.name == sourceAssetName }) else {
            return "retexture_3d_model: asset '\(sourceAssetName)' not found in the Sprite Repository."
        }
        let sourceTaskId = sourceAsset.provenance?.attribution.taskId ?? ""
        guard !sourceTaskId.isEmpty,
              sourceAsset.provenance?.attribution.providerIdentifier == "meshy" else {
            return "retexture_3d_model: '\(sourceAssetName)' wasn't generated by Meshy. Retexture requires a Meshy-generated source model."
        }

        // Step C: Validate style_prompt (C6 — empty check; truncation happens in init).
        let stylePromptRaw = (arguments["style_prompt"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stylePromptRaw.isEmpty else {
            return "retexture_3d_model requires 'style_prompt'."
        }
        if stylePromptRaw.count > 600 {
            HypeLogger.shared.info("retexture_3d_model: style_prompt truncated from \(stylePromptRaw.count) to 600 chars", source: "Meshy")
        }

        let aiModel = parseAIModel(arguments["ai_model"])
        let enablePbr = (arguments["enable_pbr"] ?? "").lowercased() == "true"
        let hdTexture = (arguments["hd_texture"] ?? "").lowercased() == "true"

        // Validate place_on_card / part_name constraint.
        let placeOnCard = (arguments["place_on_card"] ?? "").lowercased() == "true"
        if placeOnCard {
            let rawPartName = arguments["part_name"] ?? ""
            guard context.sanitizeAssetName(rawPartName) != nil, !rawPartName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return "retexture_3d_model requires 'part_name' when place_on_card='true'."
            }
        }

        // Step D: Run the retexture flow (5-min cap for AI tool path).
        let reporter = Meshy3DToolProgressReporter(
            logger: .shared,
            toolName: "retexture_3d_model",
            taskKindDescription: "retexture"
        )
        let flow = RemeshAndRetextureFlow(client: client)
        let options = RemeshAndRetextureFlow.RetextureOptions(
            aiModel: aiModel,
            enablePbr: enablePbr,
            hdTexture: hdTexture,
            hardTimeout: 300
        )
        let sourcePrompt = sourceAsset.provenance?.searchQuery ?? ""
        let existingNames = Set(document.spriteRepository.assets.map(\.name))

        let asset: SpriteAsset
        do {
            asset = try await flow.runRetexture(
                sourceTaskId: sourceTaskId,
                sourceAssetName: sourceAssetName,
                sourcePrompt: sourcePrompt,
                newStylePrompt: stylePromptRaw,
                options: options,
                existingAssetNames: existingNames,
                onProgress: { state in reporter.report(state) }
            )
        } catch let error as MeshyError {
            if case .timedOut = error {
                return "Meshy retexture timed out after 5 minutes. The task may still be running — check your Meshy dashboard."
            }
            return "Meshy retexture failed: \(error.errorDescription ?? "unknown error")."
        } catch is CancellationError {
            return "Meshy retexture cancelled."
        } catch {
            return "Meshy retexture failed: \(error.localizedDescription)"
        }

        // Step E: Install asset into document (AIEditTransaction captures this).
        document.spriteRepository.addAsset(asset)

        var result = "Retextured '\(sourceAssetName)' with style '\(stylePromptRaw.prefix(80))'. New asset '\(asset.name)' added to the Sprite Repository."
        if let partResult = placeScene3DPartIfRequested(
            arguments: arguments,
            document: &document,
            currentCardId: currentCardId,
            primaryAsset: asset,
            context: context
        ) {
            result += " \(partResult)"
        }
        return result
    }

    // MARK: - Meshy 3D tool helpers (moved from HypeToolExecutor)

    /// Gate check + client construction shared by all three generators.
    ///
    /// - Returns: `(.some(client), nil)` when gate passes, or `(nil, .some(errorString))` on refusal.
    /// - Note: Gate is checked BEFORE invoking `meshyClientFactory` (invariant §11.2 item 7).
    package static func meshyGateAndClient(
        document: HypeDocument,
        context: HypeToolExecutor
    ) -> (client: MeshyClient?, error: String?) {
        let keyIsSet = KeychainStore.hasSecret(account: KeychainStore.meshyAPIKeyAccount)
        let gateStatus = Meshy3DGate.status(for: document, keyIsSet: keyIsSet)
        switch gateStatus {
        case .stackDisabled:
            return (nil, "Meshy is not enabled for this stack. Enable it in Preferences → Meshy.ai.")
        case .apiKeyMissing:
            return (nil, "Set your Meshy API key in Preferences → Meshy.ai.")
        case .ready:
            break
        }

        // Gate passed — build the client.
        do {
            let client: MeshyClient = try context.meshyClientFactory?() ?? {
                let key = try KeychainStore.getSecret(account: KeychainStore.meshyAPIKeyAccount)
                return MeshyAIClient(apiKey: key)
            }()
            return (client, nil)
        } catch {
            return (nil, "Failed to read Meshy API key from keychain.")
        }
    }

    /// Parse optional `place_on_card` arguments and create a `scene3D` part,
    /// wiring `scene3DAssetRef` to the first imported asset.
    ///
    /// - Returns: A success description string for the created part, or `nil`
    ///   when `place_on_card != "true"`.
    package static func placeScene3DPartIfRequested(
        arguments: [String: String],
        document: inout HypeDocument,
        currentCardId: UUID,
        primaryAsset: SpriteAsset,
        context: HypeToolExecutor
    ) -> String? {
        guard (arguments["place_on_card"] ?? "").lowercased() == "true" else {
            return nil
        }
        let rawPartName = arguments["part_name"] ?? ""
        guard let safePartName = context.sanitizeAssetName(rawPartName), !safePartName.isEmpty else {
            return nil  // Caller validates part_name before calling us.
        }

        let place = context.placement(arguments: arguments, currentCardId: currentCardId, document: document)
        var part = Part(
            partType: .scene3D,
            cardId: place.cardId,
            backgroundId: place.backgroundId,
            name: safePartName,
            left: Double(arguments["left"] ?? "100") ?? 100,
            top: Double(arguments["top"] ?? "100") ?? 100,
            width: Double(arguments["width"] ?? "400") ?? 400,
            height: Double(arguments["height"] ?? "300") ?? 300
        )
        part.scene3DAssetRef = document.spriteRepository.assetRef(for: primaryAsset)
        document.addPart(part)
        let layer = place.backgroundId != nil ? " on background" : ""
        return "Created scene3D part '\(safePartName)'\(layer) referencing '\(primaryAsset.name)'."
    }

    /// Parse an `ai_model` argument string into a `MeshyAIModel`.
    package static func parseAIModel(_ raw: String?) -> MeshyAIModel {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return .meshy6
        }
        return MeshyAIModel(rawValue: trimmed) ?? .meshy6
    }

    package static func generate3DOptions(
        arguments: [String: String],
        aiModel: MeshyAIModel,
        shouldRemesh: Bool,
        assetName: String? = nil,
        hardTimeout: TimeInterval,
        context: HypeToolExecutor
    ) -> Generate3DJob.Options {
        let qualityRaw = (arguments["quality"] ?? "preview")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let quality: Generate3DJob.TextQuality = ["refine", "refined", "high", "final"].contains(qualityRaw)
            ? .refined
            : .preview
        let topologyRaw = arguments["topology"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let topology = topologyRaw == "quad" ? "quad" : (topologyRaw == "triangle" ? "triangle" : nil)
        let symmetryRaw = arguments["symmetry_mode"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let symmetryMode = ["off", "auto", "on"].contains(symmetryRaw ?? "") ? symmetryRaw : nil

        return Generate3DJob.Options(
            aiModel: aiModel,
            shouldRemesh: shouldRemesh,
            alsoUSDZ: context.boolArgument(arguments["with_usdz"] ?? arguments["also_usdz"]) ?? true,
            alsoFBX: context.boolArgument(arguments["with_fbx"] ?? arguments["also_fbx"]) ?? false,
            textQuality: quality,
            targetPolycount: context.intArgument(arguments["target_polycount"]),
            topology: topology,
            symmetryMode: symmetryMode,
            enablePbr: context.boolArgument(arguments["enable_pbr"]),
            assetName: assetName,
            hardTimeout: hardTimeout
        )
    }

    package static func optional3DAssetName(
        arguments: [String: String],
        toolName: String,
        context: HypeToolExecutor
    ) -> (String?, String?) {
        guard let raw = arguments["asset_name"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return (nil, nil)
        }
        guard let safe = context.sanitizeAssetName(raw) else {
            return (nil, "\(toolName): asset_name is invalid — use 1-128 ASCII letters / digits / _ / - / . / space.")
        }
        return (safe, nil)
    }
}
