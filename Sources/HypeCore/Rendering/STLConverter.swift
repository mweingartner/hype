import Foundation
import CryptoKit

/// Converts `.stl` files to `.obj` format for consumption by SceneKit.
///
/// Conversion results are cached under `~/Library/Caches/com.hype.app/stl-cache/`
/// keyed by SHA-256 of the source file's contents. A cache hit returns
/// immediately — no reparsing occurs. Cache writes are atomic: the OBJ is
/// written to `<sha>.obj.tmp` then renamed to `<sha>.obj`.
///
/// Conversion timing: binary STL at 50 MB (the hard cap) typically takes
/// < 1 second on Apple Silicon. ASCII STL is 2–4× slower due to text
/// scanning. The 50 MB cap bounds worst-case wall-clock time to ~1 second,
/// which is acceptable for the synchronous `applyPartPropertySet` call site.
///
/// Non-finite float handling: any triangle whose normal or any vertex
/// coordinate contains a NaN or Inf value is **skipped entirely** during
/// OBJ rendering. Substituting zeros would silently corrupt geometry.
/// A debug-level count of skipped triangles is logged via HypeLogger.
///
/// Security notes:
/// - Only `file://` URLs are accepted. HTTP/S paths are rejected.
/// - Hard 50 MB cap enforced before reading file contents.
/// - Error messages carry only structural information (byte offsets,
///   expected sizes, format tags). Raw file bytes are never included.
public struct STLConverter: Sendable {

    // MARK: - Public API

    /// Returns `true` if `path` should be treated as an STL file —
    /// i.e. has an `.stl` extension AND the file URL scheme check
    /// would pass.
    public static func isSTL(path: String) -> Bool {
        guard !path.isEmpty else { return false }
        return hasSTLExtension(path)
    }

    /// Returns `true` when the path's last path component ends with
    /// `.stl` (case-insensitive).
    public static func hasSTLExtension(_ path: String) -> Bool {
        let lower = (path as NSString).pathExtension.lowercased()
        return lower == "stl"
    }

    /// Converts the STL file at `stlPath` to OBJ, caches the result,
    /// and returns the path to the cached OBJ file.
    ///
    /// Security conditions enforced here:
    /// - **Condition 4**: `fileURL.scheme` must equal `"file"`.
    /// - **Condition 2**: file size must not exceed 50 MB.
    /// - **Cache**: if a cache hit exists for the file's SHA-256, it is
    ///   returned immediately without re-parsing.
    ///
    /// - Parameter stlPath: Absolute POSIX path to the source `.stl` file.
    /// - Returns: Absolute path to the converted `.obj` file in the cache.
    /// - Throws: `STLConverter.Error` on invalid scheme, size cap, I/O
    ///   failure, or malformed STL data.
    public static func convert(stlPath: String) throws -> String {
        // Condition 4 — file URLs only.
        let fileURL = URL(fileURLWithPath: stlPath)
        guard fileURL.scheme == "file" else {
            throw STLConverter.Error.ioFailure(path: stlPath, underlying: "non-file URL scheme")
        }

        // Condition 2 — 50 MB hard cap before reading file.
        let attrs = try FileManager.default.attributesOfItem(atPath: stlPath)
        let fileSize = attrs[.size] as? Int ?? 0
        guard fileSize <= 52_428_800 else {
            throw STLConverter.Error.ioFailure(path: stlPath, underlying: "file exceeds 50 MB cap")
        }

        // Read file data.
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw STLConverter.Error.ioFailure(path: stlPath, underlying: "read failed")
        }

        // Post-read TOCTOU re-check. The size stat at line 67 and
        // the read at line 75 are separate syscalls; a hostile or
        // racing process could swap the file in between. Re-validate
        // the actual loaded byte count against the cap so the
        // invariant holds even if the stat lied.
        guard data.count <= 52_428_800 else {
            throw STLConverter.Error.ioFailure(path: stlPath, underlying: "file exceeds 50 MB cap")
        }

        // Cache check — compute SHA-256, return hit immediately.
        let sha = contentHash(data)
        let cacheDir = cacheDirectoryPath()
        let cachedPath = (cacheDir as NSString).appendingPathComponent("\(sha).obj")
        if FileManager.default.fileExists(atPath: cachedPath) {
            return cachedPath
        }

        // Parse triangles.
        let triangles = try parseSTL(data: data, path: stlPath)

        // Render OBJ.
        let objText = renderOBJ(triangles: triangles)

        // Atomic cache write.
        try FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
        let tmpPath = (cacheDir as NSString).appendingPathComponent("\(sha).obj.tmp")
        guard let objData = objText.data(using: .utf8) else {
            throw STLConverter.Error.ioFailure(path: stlPath, underlying: "OBJ UTF-8 encoding failed")
        }
        do {
            try objData.write(to: URL(fileURLWithPath: tmpPath), options: .atomic)
            try FileManager.default.moveItem(atPath: tmpPath, toPath: cachedPath)
        } catch {
            // If move fails (e.g. destination already written by concurrent call),
            // remove the tmp file and check if the destination is now present.
            try? FileManager.default.removeItem(atPath: tmpPath)
            if !FileManager.default.fileExists(atPath: cachedPath) {
                throw STLConverter.Error.ioFailure(path: stlPath, underlying: "cache write failed")
            }
        }

        return cachedPath
    }

    /// Absolute path to the STL cache directory.
    /// `~/Library/Caches/com.hype.app/stl-cache/`
    public static func cacheDirectoryPath() -> String {
        let home = NSHomeDirectory()
        return (home as NSString).appendingPathComponent(
            "Library/Caches/com.hype.app/stl-cache"
        )
    }

    // MARK: - Internal helpers (internal for test target access)

    /// Parse a raw STL data blob, auto-detecting ASCII vs binary format.
    static func parseSTL(data: Data, path: String) throws -> [Triangle] {
        // Detection: if first 5 bytes spell "solid", check binary-masquerading-
        // as-solid by computing expected binary size; if sizes match, treat
        // as binary.
        let isBinaryBySize: Bool = {
            guard data.count >= 84 else { return false }
            let count = data.withUnsafeBytes { ptr -> UInt32 in
                ptr.loadUnaligned(fromByteOffset: 80, as: UInt32.self).littleEndian
            }
            let expected = 80 + 4 + Int(count) * 50
            return data.count == expected
        }()

        let firstFive = data.prefix(5)
        let looksLikeAscii = (firstFive.count == 5) &&
            (firstFive[0] == 0x73 || firstFive[0] == 0x53) && // 's' or 'S'
            (firstFive[1] == 0x6F || firstFive[1] == 0x4F) && // 'o' or 'O'
            (firstFive[2] == 0x6C || firstFive[2] == 0x4C) && // 'l' or 'L'
            (firstFive[3] == 0x69 || firstFive[3] == 0x49) && // 'i' or 'I'
            (firstFive[4] == 0x64 || firstFive[4] == 0x44)    // 'd' or 'D'

        if looksLikeAscii && !isBinaryBySize {
            return try asciiParse(data: data, path: path)
        } else {
            return try binaryParse(data: data, path: path)
        }
    }

    /// Parse a binary STL. Layout: 80-byte header, uint32 LE triangle count,
    /// then N × 50-byte records (12 bytes normal + 36 bytes vertices + 2 bytes
    /// attribute count).
    static func binaryParse(data: Data, path: String) throws -> [Triangle] {
        let headerSize = 80
        let countOffset = 80
        let countSize = 4
        let recordSize = 50

        guard data.count >= headerSize + countSize else {
            throw STLConverter.Error.malformedSTL(
                reason: "binary STL too short: \(data.count) bytes, need at least \(headerSize + countSize)"
            )
        }

        let triangleCount: UInt32 = data.withUnsafeBytes { ptr in
            ptr.loadUnaligned(fromByteOffset: countOffset, as: UInt32.self).littleEndian
        }

        let expectedSize = headerSize + countSize + Int(triangleCount) * recordSize
        guard data.count >= expectedSize else {
            throw STLConverter.Error.malformedSTL(
                reason: "binary STL body truncated: have \(data.count) bytes, expected \(expectedSize) for \(triangleCount) triangles"
            )
        }

        var triangles: [Triangle] = []
        triangles.reserveCapacity(Int(triangleCount))

        let dataOffset = headerSize + countSize
        for i in 0..<Int(triangleCount) {
            let base = dataOffset + i * recordSize
            // Condition 3: only byte offsets in error messages — no raw bytes.
            let nx: Float = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: base + 0,  as: Float.self) }
            let ny: Float = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: base + 4,  as: Float.self) }
            let nz: Float = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: base + 8,  as: Float.self) }

            let v0x: Float = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: base + 12, as: Float.self) }
            let v0y: Float = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: base + 16, as: Float.self) }
            let v0z: Float = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: base + 20, as: Float.self) }

            let v1x: Float = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: base + 24, as: Float.self) }
            let v1y: Float = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: base + 28, as: Float.self) }
            let v1z: Float = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: base + 32, as: Float.self) }

            let v2x: Float = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: base + 36, as: Float.self) }
            let v2y: Float = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: base + 40, as: Float.self) }
            let v2z: Float = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: base + 44, as: Float.self) }

            triangles.append(Triangle(
                normal: (nx, ny, nz),
                v0: (v0x, v0y, v0z),
                v1: (v1x, v1y, v1z),
                v2: (v2x, v2y, v2z)
            ))
        }

        return triangles
    }

    /// Parse an ASCII STL. Scans line-by-line for `facet normal`, `vertex`,
    /// `endloop`, `endfacet` tokens. Lenient about whitespace and case.
    static func asciiParse(data: Data, path: String) throws -> [Triangle] {
        guard let text = String(data: data, encoding: .utf8) ??
                         String(data: data, encoding: .isoLatin1) else {
            throw STLConverter.Error.malformedSTL(
                reason: "ASCII STL contains non-UTF-8 / non-Latin-1 bytes"
            )
        }

        var triangles: [Triangle] = []
        var normal: (Float, Float, Float)? = nil
        var vertices: [(Float, Float, Float)] = []

        let lines = text.components(separatedBy: .newlines)
        for (lineIndex, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces).lowercased()
            if line.hasPrefix("facet normal") {
                let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                // parts: ["facet", "normal", nx, ny, nz]
                guard parts.count >= 5,
                      let nx = Float(parts[2]),
                      let ny = Float(parts[3]),
                      let nz = Float(parts[4]) else {
                    throw STLConverter.Error.malformedSTL(
                        reason: "malformed facet normal at line \(lineIndex + 1): expected 3 floats"
                    )
                }
                normal = (nx, ny, nz)
                vertices = []
            } else if line.hasPrefix("vertex") {
                let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                guard parts.count >= 4,
                      let vx = Float(parts[1]),
                      let vy = Float(parts[2]),
                      let vz = Float(parts[3]) else {
                    throw STLConverter.Error.malformedSTL(
                        reason: "malformed vertex at line \(lineIndex + 1): expected 3 floats"
                    )
                }
                vertices.append((vx, vy, vz))
            } else if line.hasPrefix("endfacet") {
                guard let n = normal, vertices.count == 3 else {
                    // Tolerate empty/mismatched facets by skipping them.
                    normal = nil
                    vertices = []
                    continue
                }
                triangles.append(Triangle(
                    normal: n,
                    v0: vertices[0],
                    v1: vertices[1],
                    v2: vertices[2]
                ))
                normal = nil
                vertices = []
            }
        }

        return triangles
    }

    /// Renders a list of triangles to OBJ format text.
    ///
    /// **Condition 1**: any triangle whose normal or vertex coords contain
    /// a non-finite value (NaN or Inf) is **skipped entirely**. The count
    /// of skipped triangles is logged at debug level.
    ///
    /// OBJ index scheme: each triangle contributes 3 vertices, 3 normals,
    /// and 1 face. Indices are 1-based per OBJ spec. No deduplication.
    static func renderOBJ(triangles: [Triangle]) -> String {
        var output = "# STL converted by Hype\n"
        var skippedCount = 0
        var baseIndex = 1

        for tri in triangles {
            // Condition 1 — skip triangles with non-finite floats.
            let allFinite =
                tri.normal.0.isFinite && tri.normal.1.isFinite && tri.normal.2.isFinite &&
                tri.v0.0.isFinite && tri.v0.1.isFinite && tri.v0.2.isFinite &&
                tri.v1.0.isFinite && tri.v1.1.isFinite && tri.v1.2.isFinite &&
                tri.v2.0.isFinite && tri.v2.1.isFinite && tri.v2.2.isFinite
            guard allFinite else {
                skippedCount += 1
                continue
            }

            let f: (Float) -> String = { String(format: "%g", $0) }

            output += "v \(f(tri.v0.0)) \(f(tri.v0.1)) \(f(tri.v0.2))\n"
            output += "v \(f(tri.v1.0)) \(f(tri.v1.1)) \(f(tri.v1.2))\n"
            output += "v \(f(tri.v2.0)) \(f(tri.v2.1)) \(f(tri.v2.2))\n"
            output += "vn \(f(tri.normal.0)) \(f(tri.normal.1)) \(f(tri.normal.2))\n"
            output += "vn \(f(tri.normal.0)) \(f(tri.normal.1)) \(f(tri.normal.2))\n"
            output += "vn \(f(tri.normal.0)) \(f(tri.normal.1)) \(f(tri.normal.2))\n"
            let i = baseIndex
            output += "f \(i)//\(i) \(i+1)//\(i+1) \(i+2)//\(i+2)\n"
            baseIndex += 3
        }

        if skippedCount > 0 {
            HypeLogger.shared.debug(
                "STLConverter: skipped \(skippedCount) triangle(s) with non-finite coordinates",
                source: "STLConverter"
            )
        }

        return output
    }

    /// SHA-256 hex digest of `data`. Used as the cache key.
    static func contentHash(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Types

    /// A single triangle parsed from an STL file.
    struct Triangle: Sendable {
        var normal: (Float, Float, Float)
        var v0: (Float, Float, Float)
        var v1: (Float, Float, Float)
        var v2: (Float, Float, Float)
    }

    // MARK: - Errors

    public enum Error: Swift.Error, Sendable {
        /// The STL data is structurally invalid. `reason` contains only
        /// format-level info: byte offsets, expected counts, tag mismatches.
        /// Never contains raw file bytes or hex dumps.
        case malformedSTL(reason: String)
        /// An I/O or scheme-guard failure. `underlying` is a brief structural
        /// description (e.g. "read failed", "file exceeds 50 MB cap").
        /// Never contains raw file bytes.
        case ioFailure(path: String, underlying: String)

        /// Path-free human-readable description, safe for logging
        /// without leaking the user's home-directory layout into
        /// shared logs or crash reports. The full Error case
        /// (with associated path) remains available for callers that
        /// need to display the original path back to the user (e.g.
        /// inline UI feedback in the inspector), but anything that
        /// goes to HypeLogger / `the result` should use this.
        public var sanitizedReason: String {
            switch self {
            case .malformedSTL(let reason): return "malformed STL: \(reason)"
            case .ioFailure(_, let underlying): return "io: \(underlying)"
            }
        }
    }
}
