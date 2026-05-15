import Foundation

// MARK: - Generate3DJob

/// Reusable text-to-3D / image-to-3D / multi-image-to-3D pipeline.
///
/// Builds the right `MeshyAIClient` POST, spins up a `MeshyTaskMonitor`,
/// streams progress to an optional callback, and returns the imported
/// `SpriteAsset`s via `Meshy3DAssetImporter`. Both the `Generate3DSheet`
/// SwiftUI view and the AI tool executor use this type — it is the single
/// well-tested code path for all Meshy generation.
///
/// Threading: all I/O happens inside `MeshyClient` (an actor). Progress
/// callbacks fire on the calling task's executor — call sites that need
/// `MainActor` isolation must hop themselves via `await MainActor.run { }`.
public struct Generate3DJob: Sendable {

    // MARK: - Kind

    /// Which Meshy generation endpoint to use.
    public enum Kind: Sendable, Equatable {
        /// Text-to-3D via `/openapi/v2/text-to-3d`.
        case text(prompt: String, artStyle: MeshyArtStyle)
        /// Single-image-to-3D via `/openapi/v1/image-to-3d`.
        case singleImage(image: MeshyImageInput.Resolved)
        /// Multi-image-to-3D via `/openapi/v1/multi-image-to-3d` (2..4 images).
        case multiImage(images: [MeshyImageInput.Resolved])
    }

    public enum TextQuality: String, Codable, Sendable, Equatable, CaseIterable, Identifiable {
        case preview
        case refined

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .preview: return "Fast preview"
            case .refined: return "Refined"
            }
        }
    }

    // MARK: - Options

    /// Run-shaping options shared across all three kinds.
    public struct Options: Sendable, Equatable {
        public var aiModel: MeshyAIModel
        public var shouldRemesh: Bool
        public var alsoUSDZ: Bool
        public var alsoFBX: Bool
        public var textQuality: TextQuality
        public var targetPolycount: Int?
        public var topology: String?
        public var symmetryMode: String?
        public var enablePbr: Bool?
        public var assetName: String?
        /// Hard wall-clock cap passed to `MeshyTaskMonitor.Config.hardTimeout`.
        ///
        /// - Sheet UI: 1800 s (30 min, Phase 1 default).
        /// - AI tool path: 300 s (5 min — safety valve so generation doesn't
        ///   starve the AI iteration loop indefinitely).
        public var hardTimeout: TimeInterval

        public init(
            aiModel: MeshyAIModel = .meshy6,
            shouldRemesh: Bool = false,
            alsoUSDZ: Bool = true,
            alsoFBX: Bool = false,
            textQuality: TextQuality = .preview,
            targetPolycount: Int? = nil,
            topology: String? = nil,
            symmetryMode: String? = nil,
            enablePbr: Bool? = nil,
            assetName: String? = nil,
            hardTimeout: TimeInterval = 1800
        ) {
            self.aiModel = aiModel
            self.shouldRemesh = shouldRemesh
            self.alsoUSDZ = alsoUSDZ
            self.alsoFBX = alsoFBX
            self.textQuality = textQuality
            self.targetPolycount = targetPolycount
            self.topology = topology
            self.symmetryMode = symmetryMode
            self.enablePbr = enablePbr
            self.assetName = assetName
            self.hardTimeout = hardTimeout
        }

        public var requestedFormats: [String] {
            var formats: [MeshyOutputFormat] = [.glb]
            if alsoUSDZ { formats.append(.usdz) }
            if alsoFBX { formats.append(.fbx) }
            return Array(Set(formats.map(\.rawValue))).sorted()
        }
    }

    // MARK: - Progress

    /// Progress callback type. Fires on every monitor state change.
    public typealias ProgressHandler = @Sendable (MeshyTaskMonitor.State) async -> Void

    // MARK: - Private state

    private let client: MeshyClient
    private let logger: HypeLogger

    // MARK: - Init

    public init(client: MeshyClient, logger: HypeLogger = .shared) {
        self.client = client
        self.logger = logger
    }

    // MARK: - Public API

    /// Run the full pipeline: POST → poll → download → build assets.
    ///
    /// - Parameters:
    ///   - kind: Which Meshy endpoint to hit.
    ///   - options: Model / format / timeout options.
    ///   - existingAssetNames: Names already in the repository (for dedup).
    ///   - onProgress: Optional progress callback. Use for AI-tool
    ///     `logger.aiOutput` reporting and sheet UI updates.
    /// - Returns: The imported `SpriteAsset`s. First is always the primary GLB.
    /// - Throws: `MeshyError` on any pipeline failure.
    public func run(
        kind: Kind,
        options: Options,
        existingAssetNames: Set<String>,
        onProgress: ProgressHandler? = nil
    ) async throws -> [SpriteAsset] {
        try validate(options: options)

        // Step 1: Build request and POST to Meshy.
        let (taskId, taskKind, monitorPrompt) = try await createTask(kind: kind, options: options, onProgress: onProgress)

        // Step 2: Build monitor.
        var formats: Set<MeshyOutputFormat> = [.glb]
        if options.alsoUSDZ { formats.insert(.usdz) }
        if options.alsoFBX { formats.insert(.fbx) }

        let config = MeshyTaskMonitor.Config(
            pollInterval: 3.0,
            hardTimeout: options.hardTimeout
        )
        let monitor = MeshyTaskMonitor(
            client: client,
            taskId: taskId,
            prompt: monitorPrompt,
            aiModel: options.aiModel,
            requestedFormats: formats,
            taskKind: taskKind,
            config: config,
            logger: logger
        )

        // Step 3: Poll until terminal state.
        var taskResult: MeshyTaskResult?
        for await state in await monitor.progress() {
            await onProgress?(state)

            switch state {
            case .succeeded(let result):
                taskResult = result
            case .failed(let error):
                throw error
            case .cancelled:
                throw MeshyError.taskCancelled(taskId: taskId)
            case .pending, .inProgress:
                break
            }

            if taskResult != nil { break }

            // Cooperative cancellation — exit cleanly if the outer Task was cancelled.
            if Task.isCancelled {
                await monitor.cancel()
                throw CancellationError()
            }
        }

        guard let result = taskResult else {
            throw MeshyError.taskFailed(taskId: taskId, message: "No result received from monitor.")
        }

        // Step 4: Import downloaded assets.
        let importer = Meshy3DAssetImporter(client: client, logger: logger)
        return try await importer.importTask(
            result: result,
            existingAssetNames: existingAssetNames,
            options: .init(suggestedBaseName: options.assetName)
        )
    }

    // MARK: - Private helpers

    /// POST the appropriate request and return `(taskId, taskKind, monitorPrompt)`.
    ///
    /// The `monitorPrompt` flows into `SpriteAsset.provenance.searchQuery`.
    /// For image inputs it is a safe descriptor — NEVER a raw file path (M4).
    private func createTask(
        kind: Kind,
        options: Options,
        onProgress: ProgressHandler?
    ) async throws -> (taskId: String, taskKind: MeshyTaskKind, monitorPrompt: String) {
        switch kind {

        case .text(let prompt, let artStyle):
            let previewRequest = MeshyTextTo3DRequest(
                mode: .preview,
                prompt: String(prompt.prefix(600)),
                artStyle: artStyle,
                aiModel: options.aiModel,
                shouldRemesh: options.shouldRemesh,
                targetPolycount: options.targetPolycount,
                topology: options.topology,
                symmetryMode: options.symmetryMode,
                moderation: true,
                enablePbr: options.enablePbr,
                targetFormats: options.requestedFormats
            )
            let previewTaskId = try await client.createTextTo3DTask(previewRequest)
            guard options.textQuality == .refined else {
                return (previewTaskId, .textTo3D, prompt)
            }

            let previewResult = try await waitForIntermediateTask(
                taskId: previewTaskId,
                taskKind: .textTo3D,
                prompt: prompt,
                options: options,
                requestedFormats: [.glb],
                onProgress: onProgress
            )
            let refineRequest = MeshyTextTo3DRequest(
                mode: .refine,
                prompt: nil,
                artStyle: nil,
                aiModel: options.aiModel,
                shouldRemesh: false,
                targetPolycount: options.targetPolycount,
                topology: options.topology,
                symmetryMode: options.symmetryMode,
                moderation: true,
                enablePbr: options.enablePbr,
                targetFormats: options.requestedFormats,
                previewTaskId: previewResult.taskId
            )
            let refineTaskId = try await client.createTextTo3DTask(refineRequest)
            return (refineTaskId, .textTo3D, prompt)

        case .singleImage(let resolved):
            let request = MeshyImageTo3DRequest(
                imageData: resolved.dataURI,
                aiModel: options.aiModel,
                shouldRemesh: options.shouldRemesh,
                targetPolycount: options.targetPolycount,
                moderation: true,
                enablePbr: options.enablePbr,
                targetFormats: options.requestedFormats
            )
            let taskId = try await client.createImageTo3DTask(request)
            // M4: safe descriptor — never the raw file path.
            let safeDesc = resolved.sourceDescriptor  // "asset:<name>" | "file" | "base64:NKB"
            let monitorPrompt = "image-to-3D: \(safeDesc)"
            return (taskId, .imageTo3D, monitorPrompt)

        case .multiImage(let images):
            // M2: Combined 40 MB cap before encoding.
            let totalBytes = images.map(\.data.count).reduce(0, +)
            guard totalBytes <= 40 * 1024 * 1024 else {
                throw MeshyError.validationFailed(
                    field: "image_urls",
                    reason: "Total image size exceeds the 40 MB combined limit."
                )
            }
            let dataURIs = images.map(\.dataURI)
            let request = MeshyMultiImageTo3DRequest(
                imageData: dataURIs,
                aiModel: options.aiModel,
                shouldRemesh: options.shouldRemesh,
                targetPolycount: options.targetPolycount,
                moderation: true,
                enablePbr: options.enablePbr,
                targetFormats: options.requestedFormats
            )
            let taskId = try await client.createMultiImageTo3DTask(request)
            // M4: safe descriptor.
            let monitorPrompt = "multi-image-to-3D: \(images.count) images"
            return (taskId, .multiImageTo3D, monitorPrompt)
        }
    }

    private func validate(options: Options) throws {
        if let targetPolycount = options.targetPolycount,
           !(100...300_000).contains(targetPolycount) {
            throw MeshyError.invalidPolycount(value: targetPolycount)
        }
        if let topology = options.topology?.lowercased(),
           topology != "quad" && topology != "triangle" {
            throw MeshyError.validationFailed(
                field: "topology",
                reason: "Topology must be 'triangle' or 'quad'."
            )
        }
        if let symmetryMode = options.symmetryMode?.lowercased(),
           !["off", "auto", "on"].contains(symmetryMode) {
            throw MeshyError.validationFailed(
                field: "symmetry_mode",
                reason: "Symmetry mode must be 'off', 'auto', or 'on'."
            )
        }
    }

    private func waitForIntermediateTask(
        taskId: String,
        taskKind: MeshyTaskKind,
        prompt: String,
        options: Options,
        requestedFormats: Set<MeshyOutputFormat>,
        onProgress: ProgressHandler?
    ) async throws -> MeshyTaskResult {
        let monitor = MeshyTaskMonitor(
            client: client,
            taskId: taskId,
            prompt: prompt,
            aiModel: options.aiModel,
            requestedFormats: requestedFormats,
            taskKind: taskKind,
            config: MeshyTaskMonitor.Config(pollInterval: 3.0, hardTimeout: options.hardTimeout),
            logger: logger
        )

        for await state in await monitor.progress() {
            await onProgress?(state)
            switch state {
            case .succeeded(let result):
                return result
            case .failed(let error):
                throw error
            case .cancelled:
                throw MeshyError.taskCancelled(taskId: taskId)
            case .pending, .inProgress:
                break
            }
            if Task.isCancelled {
                await monitor.cancel()
                throw CancellationError()
            }
        }

        throw MeshyError.taskFailed(taskId: taskId, message: "No result received from preview task.")
    }
}
