import Foundation

// MARK: - MeshyImageInput

/// A single image input for image-to-3D or multi-image-to-3D generation.
///
/// Resolves to a validated, MIME-typed, size-capped `MeshyImageInput.Resolved`
/// via `resolve(in:)`. The validation pipeline is deliberately strict:
///   - Path inputs must be ABSOLUTE; relative paths and `..` traversal segments
///     are rejected outright (Phase 2 threat surface).
///   - Asset-name inputs are looked up via `SpriteRepository.asset(byName:)`
///     and must have `kind` in `[.imageTexture, .spriteSheet, .tileSet]` —
///     not `.model3D`, not `.audioClip`.
///   - Base64 inputs are length-capped at ~14 MB encoded (≈10 MB raw),
///     then MIME-sniffed.
///   - All resolved bytes are sniffed for magic bytes (PNG / JPEG / WebP)
///     and rejected if they don't match an allowed format. The Meshy
///     `image_data` data URI prefix is set from the sniff result, NOT
///     from any user-supplied MIME claim.
///
/// 10 MB per-image cap enforced in every code path.
public enum MeshyImageInput: Sendable, Equatable {

    /// Absolute file path on the local disk. Phase 2 path-traversal
    /// invariant: the path must (a) start with "/", (b) contain no
    /// ".." segment after normalization, (c) not point inside system
    /// directories defined in `blockedPathPrefixes`.
    case filePath(String)

    /// Name of an existing Sprite Repository asset, looked up by
    /// `SpriteRepository.asset(byName:)`. Must be an image-kinded
    /// asset (`.imageTexture` | `.spriteSheet` | `.tileSet`).
    case assetName(String)

    /// Raw base64-encoded image data. The decoder accepts standard
    /// base64 with or without a `"data:image/<mime>;base64,"` prefix.
    case base64(String)

    // MARK: - Resolved

    /// The result of resolving a `MeshyImageInput` to canonical
    /// image bytes ready for transport to Meshy.
    public struct Resolved: Sendable, Equatable {
        /// Raw image bytes (PNG / JPEG / WebP).
        public let data: Data
        /// MIME type determined by magic-byte sniff — one of
        /// `"image/png"`, `"image/jpeg"`, or `"image/webp"`.
        public let mimeType: String
        /// Source-descriptor string used for tagging the resulting
        /// model3D asset's provenance.
        ///
        /// Security H1: for `.filePath` inputs, this is `"file"`
        /// — NEVER the raw file path — to prevent the descriptor from
        /// leaking into tool result strings or log lines. Full path is
        /// only used for the SpriteAsset provenance internally.
        public let sourceDescriptor: String

        /// `"data:<mimeType>;base64,<base64-encoded bytes>"` form for
        /// the Meshy `image_data` field. The MIME prefix uses the
        /// sniffed type, not any caller-supplied claim.
        public var dataURI: String {
            "data:\(mimeType);base64,\(data.base64EncodedString())"
        }
    }

    // MARK: - Validation constants

    /// Per-image byte cap (10 MB), pre-encode.
    /// Reflects Meshy's documented image-to-3D upload limit.
    public static let maxBytesPerImage: Int = 10 * 1024 * 1024

    /// Allowed MIME types (matched by magic-byte sniff).
    public static let allowedMimeTypes: Set<String> = [
        "image/png", "image/jpeg", "image/webp"
    ]

    /// Blocked path prefixes — any resolved (symlink-followed) path
    /// beginning with one of these is rejected regardless of other checks.
    public static let blockedPathPrefixes: [String] = [
        "/etc/", "/private/etc/",
        "/usr/", "/System/",
        "/Library/Keychains/",
        "/var/db/", "/private/var/db/",
    ]

    // MARK: - Resolution

    /// Resolve to canonical image bytes against the given repository.
    ///
    /// - Parameter repository: Used only for `.assetName` inputs.
    /// - Throws: `MeshyError.validationFailed` for invalid paths,
    ///   missing assets, oversized inputs, or unsupported MIME types.
    public func resolve(in repository: SpriteRepository) throws -> Resolved {
        switch self {
        case .filePath(let path):
            return try resolveFilePath(path)
        case .assetName(let name):
            return try resolveAssetName(name, in: repository)
        case .base64(let string):
            return try resolveBase64(string)
        }
    }

    // MARK: - MIME sniffing

    /// Sniff the MIME type from the first 12 bytes of `data`.
    ///
    /// Returns `nil` if the bytes don't match any allowed format.
    /// Magic-byte references: PNG RFC 2083, JPEG ISO 10918, WebP RIFF.
    public static func sniffMimeType(_ data: Data) -> String? {
        guard data.count >= 4 else { return nil }
        let bytes = Array(data.prefix(12))

        // PNG: 89 50 4E 47 0D 0A 1A 0A
        if data.count >= 8 {
            let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
            if Array(data.prefix(8)) == pngMagic {
                return "image/png"
            }
        }

        // JPEG: FF D8 FF
        if bytes.count >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
            return "image/jpeg"
        }

        // WebP: bytes 0-3 == "RIFF" AND bytes 8-11 == "WEBP"
        if data.count >= 12 {
            let riff: [UInt8] = [0x52, 0x49, 0x46, 0x46]  // "RIFF"
            let webp: [UInt8] = [0x57, 0x45, 0x42, 0x50]  // "WEBP"
            if Array(data[0..<4]) == riff && Array(data[8..<12]) == webp {
                return "image/webp"
            }
        }

        return nil
    }

    // MARK: - Private path resolution

    private func resolveFilePath(_ path: String) throws -> Resolved {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)

        // Must be non-empty and absolute.
        guard !trimmed.isEmpty else {
            throw MeshyError.validationFailed(field: "image_path", reason: "Image path must not be empty.")
        }
        guard trimmed.hasPrefix("/") else {
            throw MeshyError.validationFailed(field: "image_path", reason: "Image path must be an absolute path (starting with '/').")
        }

        // Canonicalize: resolve symlinks so containment checks operate on
        // real filesystem locations (security M1 + §11.1 item 1).
        let resolvedURL = URL(fileURLWithPath: trimmed).resolvingSymlinksInPath()
        let resolvedPath = resolvedURL.path

        // Reject path traversal — check standardized path for ".." segments.
        let standardized = (trimmed as NSString).standardizingPath
        if standardized.components(separatedBy: "/").contains("..") {
            throw MeshyError.validationFailed(field: "image_path", reason: "Image path must not contain traversal segments.")
        }

        // Reject system directories (checked on the canonical / symlink-resolved path).
        for blocked in Self.blockedPathPrefixes {
            if resolvedPath.hasPrefix(blocked) {
                throw MeshyError.validationFailed(field: "image_path", reason: "Image path is in a restricted location.")
            }
        }

        // Positive-control: must be under home, temp, or a user-owned location.
        // Anchors are also canonicalized via resolvingSymlinksInPath (security M1).
        let canonicalHome = URL(fileURLWithPath: NSHomeDirectory())
            .resolvingSymlinksInPath().path
        let canonicalTemp = URL(fileURLWithPath: NSTemporaryDirectory())
            .resolvingSymlinksInPath().path

        let isUnderHome = resolvedPath.hasPrefix(canonicalHome)
        let isUnderTemp = resolvedPath.hasPrefix(canonicalTemp)
        guard isUnderHome || isUnderTemp else {
            throw MeshyError.validationFailed(
                field: "image_path",
                reason: "Image path must be under the user's home directory or the system temporary directory."
            )
        }

        // Read file bytes.
        let data: Data
        do {
            data = try Data(contentsOf: resolvedURL)
        } catch {
            throw MeshyError.validationFailed(field: "image_path", reason: "Could not read image file.")
        }

        // Size cap (pre-sniff).
        guard data.count <= Self.maxBytesPerImage else {
            throw MeshyError.validationFailed(field: "image_path", reason: "Image is too large. Maximum 10 MB.")
        }

        // MIME sniff — authoritative over extension or any claim.
        guard let mimeType = Self.sniffMimeType(data) else {
            throw MeshyError.validationFailed(field: "image_path", reason: "Unsupported image format. Allowed: PNG, JPEG, WebP.")
        }

        // Security H1: sourceDescriptor for filePath inputs is "file" only —
        // NEVER includes the raw path in the safe descriptor.
        return Resolved(data: data, mimeType: mimeType, sourceDescriptor: "file")
    }

    private func resolveAssetName(_ name: String, in repository: SpriteRepository) throws -> Resolved {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MeshyError.validationFailed(field: "image_asset_name", reason: "Asset name must not be empty.")
        }

        // Look up asset in repository.
        guard let asset = repository.asset(byName: trimmed) else {
            throw MeshyError.validationFailed(
                field: "image_asset_name",
                reason: "Asset '\(trimmed)' not found in the Sprite Repository."
            )
        }

        // Only image-kinded assets are allowed.
        let imageKinds: Set<AssetKind> = [.imageTexture, .spriteSheet, .tileSet]
        guard imageKinds.contains(asset.kind) else {
            throw MeshyError.validationFailed(
                field: "image_asset_name",
                reason: "Asset '\(trimmed)' is not an image asset. Only imageTexture, spriteSheet, or tileSet assets are accepted."
            )
        }

        // Size cap.
        guard asset.data.count <= Self.maxBytesPerImage else {
            throw MeshyError.validationFailed(field: "image_asset_name", reason: "Image asset is too large. Maximum 10 MB.")
        }

        // MIME sniff — trust bytes over the stored mimeType field.
        guard let mimeType = Self.sniffMimeType(asset.data) else {
            throw MeshyError.validationFailed(
                field: "image_asset_name",
                reason: "Unsupported image format. Allowed: PNG, JPEG, WebP."
            )
        }

        return Resolved(data: asset.data, mimeType: mimeType, sourceDescriptor: "asset:\(asset.name)")
    }

    private func resolveBase64(_ string: String) throws -> Resolved {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MeshyError.validationFailed(field: "image_base64", reason: "Base64 data must not be empty.")
        }

        // Strip optional data URI prefix.
        let rawBase64: String
        if trimmed.hasPrefix("data:") {
            // Format: "data:image/<mime>;base64,<base64-bytes>"
            if let commaRange = trimmed.range(of: ";base64,") {
                rawBase64 = String(trimmed[commaRange.upperBound...])
            } else if let commaRange = trimmed.range(of: ",") {
                rawBase64 = String(trimmed[commaRange.upperBound...])
            } else {
                rawBase64 = trimmed
            }
        } else {
            rawBase64 = trimmed
        }

        // Cap encoded length: base64 expands ~4/3x, so 10 MB raw → ~14 MB encoded.
        let encodedLengthCap = Int(Double(Self.maxBytesPerImage) * 1.4)
        guard rawBase64.count <= encodedLengthCap else {
            throw MeshyError.validationFailed(field: "image_base64", reason: "Base64 data is too large. Maximum ~14 MB encoded (10 MB raw).")
        }

        // Decode.
        guard let data = Data(base64Encoded: rawBase64, options: .ignoreUnknownCharacters) else {
            throw MeshyError.validationFailed(field: "image_base64", reason: "Invalid base64 encoding.")
        }

        // Post-decode size cap (TOCTOU re-check, §11.1 item 3).
        guard data.count <= Self.maxBytesPerImage else {
            throw MeshyError.validationFailed(field: "image_base64", reason: "Image is too large. Maximum 10 MB.")
        }

        // MIME sniff — authoritative over any claimed type in the data URI prefix.
        guard let mimeType = Self.sniffMimeType(data) else {
            throw MeshyError.validationFailed(field: "image_base64", reason: "Unsupported image format. Allowed: PNG, JPEG, WebP.")
        }

        let sizeDesc = "\(data.count / 1024)KB"
        return Resolved(data: data, mimeType: mimeType, sourceDescriptor: "base64:\(sizeDesc)")
    }
}
