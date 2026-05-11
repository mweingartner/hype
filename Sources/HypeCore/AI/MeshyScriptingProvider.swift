import Foundation

// MARK: - MeshyScriptingProvider

/// HypeTalk runtime seam for Meshy.ai generation.
///
/// The script layer uses this protocol so the Interpreter and StackRuntime
/// don't depend on the concrete `MeshyAIClient` (which lives in HypeCore/AI/)
/// for dependency injection.
///
/// Implementations:
/// - Production: `LiveMeshyScriptingProvider` (in `Sources/Hype/Runtime/`) —
///   wraps `MeshyAIClient`, reads the API key from Keychain at call time,
///   runs a text-to-3D generation via `Generate3DJob.run(kind: .text(...))`,
///   and installs the resulting asset into the active document via
///   `HypeDocumentMutationCoordinator`.
/// - Tests: `StubMeshyScriptingProvider` — returns a canned asset name
///   without performing any I/O.
public protocol MeshyScriptingProvider: Sendable {

    /// Run a synchronous (blocking) text-to-3D generation and return the
    /// name of the newly-created asset.
    ///
    /// Throws on gate refusal (key missing / stack disabled), API error,
    /// network error, or empty prompt. Sets `env.it` / `env.result` to
    /// the asset name on success.
    ///
    /// The async-callback form goes through `StackRuntime.startMeshyRequest`
    /// instead of calling this method directly.
    ///
    /// - Parameters:
    ///   - prompt: The text-to-3D prompt. An empty prompt throws
    ///     `MeshyError.validationFailed`.
    ///   - style: Optional Meshy art style ("realistic" / "sculpture").
    ///     Unknown strings fall back to "realistic".
    ///   - model: Optional Meshy model string (e.g. "meshy-5"). Unknown
    ///     strings fall back to `.meshy6`.
    ///   - document: The live `HypeDocument` (for gate checks and existing
    ///     asset-name dedup).
    /// - Returns: The new asset's name (not UUID — HypeTalk is name-centric).
    func generateSync(
        prompt: String,
        style: String?,
        model: String?,
        document: HypeDocument
    ) async throws -> String

    /// Phase 4: synchronous remesh of an existing repository asset.
    ///
    /// Throws `MeshyError.unsupportedSource` if the asset has no Meshy task id.
    /// Same gate / Keychain / mutation-coordinator structure as `generateSync`.
    ///
    /// - Parameters:
    ///   - sourceAssetName: Name of the source `model3D` asset in the repository.
    ///   - targetPolycount: Target polygon count, validated to 100…300_000.
    ///   - document: The live `HypeDocument`.
    /// - Returns: The new asset's name.
    func remeshSync(
        sourceAssetName: String,
        targetPolycount: Int,
        document: HypeDocument
    ) async throws -> String

    /// Phase 4: synchronous retexture of an existing repository asset.
    ///
    /// Throws `MeshyError.unsupportedSource` if the asset has no Meshy task id.
    /// Throws `MeshyError.validationFailed` if `stylePrompt` is empty.
    ///
    /// - Parameters:
    ///   - sourceAssetName: Name of the source `model3D` asset in the repository.
    ///   - stylePrompt: Texture description (max 600 chars; truncated silently).
    ///   - document: The live `HypeDocument`.
    /// - Returns: The new asset's name.
    func retextureSync(
        sourceAssetName: String,
        stylePrompt: String,
        document: HypeDocument
    ) async throws -> String
}

// MARK: - StubMeshyScriptingProvider

/// Test stub — returns "stub-3d-model.glb" on every call without performing
/// any I/O. Used by `StackRuntimeConfiguration` as the default provider
/// (so tests that don't configure Meshy don't hit the network accidentally)
/// and as the placeholder for `ExecutionContext` in unit tests.
public struct StubMeshyScriptingProvider: MeshyScriptingProvider {

    /// The asset name returned by `generateSync`. Settable for test assertions.
    public var stubbedName: String

    public init(stubbedName: String = "stub-3d-model.glb") {
        self.stubbedName = stubbedName
    }

    public func generateSync(
        prompt: String,
        style: String?,
        model: String?,
        document: HypeDocument
    ) async throws -> String {
        return stubbedName
    }

    public func remeshSync(
        sourceAssetName: String,
        targetPolycount: Int,
        document: HypeDocument
    ) async throws -> String {
        return stubbedName
    }

    public func retextureSync(
        sourceAssetName: String,
        stylePrompt: String,
        document: HypeDocument
    ) async throws -> String {
        return stubbedName
    }
}
