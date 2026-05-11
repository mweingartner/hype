import Foundation

// MARK: - RemeshAndRetextureFlow

/// Orchestrates the remesh OR retexture pipeline for a source `model3D` asset.
///
/// Parallel structure to `RigAndAnimateFlow` (Phase 3) — split into two
/// methods, each running a single Meshy task to completion and importing
/// the result as a new `model3D` asset.
///
/// Threading: same contract as `Generate3DJob` — the calling task's executor.
public struct RemeshAndRetextureFlow: Sendable {

    // MARK: - Options

    /// Options for the remesh pipeline.
    public struct RemeshOptions: Sendable, Equatable {
        /// Target polygon count. Validated to 100…300_000 (C5).
        public var targetPolycount: Int
        /// "quad" / "triangle". Default "triangle".
        public var topology: String
        /// 1…4 adaptive decimation. Default nil (Meshy default).
        public var decimationMode: Int?
        /// Hard wall-clock cap in seconds. Default 1800 (30 min).
        public var hardTimeout: TimeInterval

        public init(
            targetPolycount: Int = 30_000,
            topology: String = "triangle",
            decimationMode: Int? = nil,
            hardTimeout: TimeInterval = 1800
        ) {
            self.targetPolycount = targetPolycount
            self.topology = topology
            self.decimationMode = decimationMode
            self.hardTimeout = hardTimeout
        }
    }

    /// Options for the retexture pipeline.
    public struct RetextureOptions: Sendable, Equatable {
        /// Meshy model — defaults to `.meshy6`.
        public var aiModel: MeshyAIModel
        /// Generate PBR maps. Defaults to false.
        public var enablePbr: Bool
        /// 4K base color (meshy-6/latest only). Defaults to false.
        public var hdTexture: Bool
        /// Remove baked lighting from textures. Defaults to true.
        public var removeLighting: Bool
        /// Hard wall-clock cap in seconds. Default 1800 (30 min).
        public var hardTimeout: TimeInterval

        public init(
            aiModel: MeshyAIModel = .meshy6,
            enablePbr: Bool = false,
            hdTexture: Bool = false,
            removeLighting: Bool = true,
            hardTimeout: TimeInterval = 1800
        ) {
            self.aiModel = aiModel
            self.enablePbr = enablePbr
            self.hdTexture = hdTexture
            self.removeLighting = removeLighting
            self.hardTimeout = hardTimeout
        }
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

    /// Run a remesh task.
    ///
    /// **Security (C5):** `targetPolycount` is validated at three layers:
    /// client (`createRemeshTask`), here (pre-flight), and UI (slider clamp).
    ///
    /// - Parameters:
    ///   - sourceTaskId: Task id of the source 3D-generation task. Read
    ///     from the source asset's `provenance.attribution.taskId`.
    ///   - sourceAssetName: Source asset's display name (for derived naming).
    ///   - sourcePrompt: Source asset's `provenance.searchQuery` for inheritance.
    ///   - options: Remesh options.
    ///   - existingAssetNames: For dedup at import time.
    ///   - onProgress: Optional progress callback.
    /// - Returns: The imported `model3D` asset (lower-poly version of source).
    /// - Throws: `MeshyError`.
    public func runRemesh(
        sourceTaskId: String,
        sourceAssetName: String,
        sourcePrompt: String,
        options: RemeshOptions,
        existingAssetNames: Set<String>,
        onProgress: Generate3DJob.ProgressHandler? = nil
    ) async throws -> SpriteAsset {

        // Pre-flight: validate polycount (second layer of C5 defense).
        guard (100...300_000).contains(options.targetPolycount) else {
            throw MeshyError.invalidPolycount(value: options.targetPolycount)
        }

        // Step 1: POST /remesh.
        let request = MeshyRemeshRequest(
            inputTaskId: sourceTaskId,
            targetPolycount: options.targetPolycount,
            topology: options.topology,
            decimationMode: options.decimationMode
        )
        let remeshTaskId = try await client.createRemeshTask(request)

        // Step 2: Build monitor.
        let config = MeshyTaskMonitor.Config(
            pollInterval: 3.0,
            hardTimeout: options.hardTimeout
        )
        let monitor = MeshyTaskMonitor(
            client: client,
            taskId: remeshTaskId,
            prompt: "remesh: \(sourceAssetName) to \(options.targetPolycount)",
            aiModel: .meshy6,
            requestedFormats: [.glb],
            taskKind: .remesh,
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
                throw MeshyError.taskCancelled(taskId: remeshTaskId)
            case .pending, .inProgress:
                break
            }

            if taskResult != nil { break }

            if Task.isCancelled {
                await monitor.cancel()
                throw CancellationError()
            }
        }

        guard let result = taskResult else {
            throw MeshyError.taskFailed(taskId: remeshTaskId, message: "No result received from remesh monitor.")
        }

        // Step 4: Import downloaded asset.
        let importer = Meshy3DAssetImporter(client: client, logger: logger)
        let asset = try await importer.importRemeshTask(
            result: result,
            sourceAssetName: sourceAssetName,
            sourceTaskId: sourceTaskId,
            sourcePrompt: sourcePrompt,
            existingAssetNames: existingAssetNames
        )

        logger.info("runRemesh complete: \(asset.name) remeshTaskId=\(remeshTaskId)", source: "Meshy")
        return asset
    }

    /// Run a retexture task.
    ///
    /// - Parameters:
    ///   - sourceTaskId: Task id of the source.
    ///   - sourceAssetName: Source asset's display name.
    ///   - sourcePrompt: Source asset's `provenance.searchQuery`.
    ///   - newStylePrompt: User-supplied texture description. Max 600 chars
    ///     (truncated in `MeshyRetextureRequest.init`; never thrown on).
    ///   - options: Retexture options.
    ///   - existingAssetNames: For dedup.
    ///   - onProgress: Optional progress callback.
    /// - Returns: The imported `model3D` asset (same geometry, new texture).
    /// - Throws: `MeshyError`.
    public func runRetexture(
        sourceTaskId: String,
        sourceAssetName: String,
        sourcePrompt: String,
        newStylePrompt: String,
        options: RetextureOptions,
        existingAssetNames: Set<String>,
        onProgress: Generate3DJob.ProgressHandler? = nil
    ) async throws -> SpriteAsset {

        // Step 1: POST /retexture.
        let request = MeshyRetextureRequest(
            inputTaskId: sourceTaskId,
            textStylePrompt: newStylePrompt,
            aiModel: options.aiModel,
            enablePbr: options.enablePbr,
            hdTexture: options.hdTexture,
            removeLighting: options.removeLighting
        )
        let retextureTaskId = try await client.createRetextureTask(request)

        // Step 2: Build monitor.
        let config = MeshyTaskMonitor.Config(
            pollInterval: 3.0,
            hardTimeout: options.hardTimeout
        )
        let monitor = MeshyTaskMonitor(
            client: client,
            taskId: retextureTaskId,
            prompt: "retexture: \(sourceAssetName) — \(newStylePrompt.prefix(80))",
            aiModel: options.aiModel,
            requestedFormats: [.glb],
            taskKind: .retexture,
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
                throw MeshyError.taskCancelled(taskId: retextureTaskId)
            case .pending, .inProgress:
                break
            }

            if taskResult != nil { break }

            if Task.isCancelled {
                await monitor.cancel()
                throw CancellationError()
            }
        }

        guard let result = taskResult else {
            throw MeshyError.taskFailed(taskId: retextureTaskId, message: "No result received from retexture monitor.")
        }

        // Step 4: Import downloaded asset.
        let importer = Meshy3DAssetImporter(client: client, logger: logger)
        let asset = try await importer.importRetextureTask(
            result: result,
            sourceAssetName: sourceAssetName,
            sourceTaskId: sourceTaskId,
            sourcePrompt: sourcePrompt,
            newStylePrompt: newStylePrompt,
            existingAssetNames: existingAssetNames
        )

        logger.info("runRetexture complete: \(asset.name) retextureTaskId=\(retextureTaskId)", source: "Meshy")
        return asset
    }
}
