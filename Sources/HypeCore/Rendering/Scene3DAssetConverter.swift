import Foundation
import ModelIO

// MARK: - Scene3DAssetConverter

/// Converts between 3D file formats using Apple's ModelIO.
///
/// Converts ModelIO-readable 3D files to USDZ for "Open in AR" flows.
/// GLB is intentionally not considered render-convertible here because
/// current macOS ModelIO returns an empty asset for GLB in Hype's runtime.
/// Meshy GLB assets should be generated with a USDZ companion instead.
/// The conversion is synchronous; the caller MUST run it off the main thread
/// (or in a detached Task).
///
/// Conversion path: `MDLAsset(url:)` → `MDLAsset.export(to:)`.
///
/// **Security (C12):** the output USDZ is bounded by the source asset's size.
/// Phase 1 enforces a 50 MB cap at ingest; converter output cannot exceed that.
/// No additional size cap is introduced here — the cap already exists upstream.
///
/// Threading: synchronous. Call from a background queue or detached Task.
/// macOS 13+ required for ModelIO conversion support.
public struct Scene3DAssetConverter: Sendable {

    // MARK: - Error type

    public enum ConvertError: Error, Sendable, Equatable, LocalizedError {
        /// Input file doesn't exist at the given path.
        case inputMissing(path: String)
        /// macOS version too old for MDLAsset GLB / FBX support (requires macOS 13+).
        case unsupportedOS
        /// `MDLAsset(url:)` returned an empty asset (zero sub-assets).
        case assetEmpty
        /// `MDLAsset.export(to:)` threw an error.
        case exportFailed(reason: String)
        /// Input extension is already `.usdz` — no conversion needed.
        case alreadyTargetFormat

        public var errorDescription: String? {
            switch self {
            case .inputMissing(let path):
                return "3D asset file not found at path: \(path)."
            case .unsupportedOS:
                return "AR Quick Look requires macOS 13 or later."
            case .assetEmpty:
                return "The 3D asset file appears to be empty or unreadable."
            case .exportFailed(let reason):
                return "Failed to convert to USDZ: \(String(reason.prefix(200)))."
            case .alreadyTargetFormat:
                return "Asset is already in USDZ format — no conversion needed."
            }
        }
    }

    public init() {}

    // MARK: - Public API

    /// Convert any MDLAsset-readable format to a USDZ at `outputURL`.
    ///
    /// If `inputURL` already points to a `.usdz` file, throws `.alreadyTargetFormat` —
    /// the caller should detect this and skip the round trip.
    ///
    /// - Parameters:
    ///   - inputURL: An absolute `file://` URL to a `.fbx` / `.obj` / `.ply` etc.
    ///   - outputURL: An absolute `file://` URL with the `.usdz` extension. Will
    ///     be overwritten if it exists.
    /// - Throws: `ConvertError`.
    public func convertToUSDZ(inputURL: URL, outputURL: URL) throws {
        // Short-circuit for already-USDZ input.
        if inputURL.pathExtension.lowercased() == "usdz" {
            throw ConvertError.alreadyTargetFormat
        }

        // Verify the input file exists.
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw ConvertError.inputMissing(path: inputURL.path)
        }

        if #available(macOS 13, *) {
            let asset = MDLAsset(url: inputURL)
            guard asset.count > 0 else {
                throw ConvertError.assetEmpty
            }
            do {
                try asset.export(to: outputURL)
            } catch {
                throw ConvertError.exportFailed(reason: error.localizedDescription)
            }
        } else {
            throw ConvertError.unsupportedOS
        }
    }
}
