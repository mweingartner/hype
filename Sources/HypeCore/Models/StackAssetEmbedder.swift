import Foundation

public enum StackAssetEmbedderError: Error, LocalizedError, Equatable {
    case missingLocalFile(String)
    case fileTooLarge(String, byteCount: Int64, limit: Int64)
    case readFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingLocalFile(let name):
            return "The referenced file could not be found: \(name)."
        case .fileTooLarge(let name, let byteCount, let limit):
            return "The referenced file is too large to embed: \(name) (\(byteCount) bytes, limit \(limit) bytes)."
        case .readFailed(let name):
            return "The referenced file could not be read: \(name)."
        }
    }
}

public struct StackAssetSelfContainmentIssue: Sendable, Equatable {
    public var partId: UUID
    public var partName: String
    public var partType: PartType
    public var property: String
    public var reference: String
    public var reason: String

    public init(
        partId: UUID,
        partName: String,
        partType: PartType,
        property: String,
        reference: String,
        reason: String
    ) {
        self.partId = partId
        self.partName = partName
        self.partType = partType
        self.property = property
        self.reference = reference
        self.reason = reason
    }
}

public struct StackAssetEmbeddingReport: Sendable, Equatable {
    public var embeddedAssetIds: [UUID]
    public var updatedPartIds: [UUID]

    public init(embeddedAssetIds: [UUID] = [], updatedPartIds: [UUID] = []) {
        self.embeddedAssetIds = embeddedAssetIds
        self.updatedPartIds = updatedPartIds
    }
}

/// Copies local file-backed control resources into the stack asset repository.
///
/// Webpage controls are intentionally excluded: their purpose is to reference
/// live web content. Other controls that render media should prefer repository
/// assets so exported iPhone/iPad apps contain the bytes they need.
public enum StackAssetEmbedder {
    public static let assetURLScheme = "asset"
    public static let defaultMaximumImportBytes: Int64 = 1_073_741_824

    public static func assetURLString(for asset: Asset) -> String {
        "\(assetURLScheme)://\(asset.id.uuidString)"
    }

    @discardableResult
    public static func embedReferencedAssets(
        in document: inout HypeDocument,
        maximumImportBytes: Int64 = defaultMaximumImportBytes
    ) throws -> StackAssetEmbeddingReport {
        var report = StackAssetEmbeddingReport()
        for index in document.parts.indices {
            var part = document.parts[index]
            var changed = false

            switch part.partType {
            case .pdf:
                if let ref = resolvedRef(part.pdfAssetRef, urlString: part.pdfURL, in: document.assetRepository, kind: .document) {
                    part.pdfAssetRef = ref
                    part.pdfURL = "asset://\(ref.id.uuidString)"
                    changed = true
                } else if let fileURL = localFileURL(from: part.pdfURL) {
                    let asset = try importLocalFile(
                        at: fileURL,
                        as: .document,
                        preferredName: fileURL.lastPathComponent,
                        into: &document.assetRepository,
                        maximumImportBytes: maximumImportBytes
                    )
                    part.pdfAssetRef = document.assetRepository.assetRef(for: asset)
                    part.pdfURL = assetURLString(for: asset)
                    report.embeddedAssetIds.append(asset.id)
                    changed = true
                }

            case .video:
                if let ref = resolvedRef(part.videoAssetRef, urlString: part.videoURL, in: document.assetRepository, kind: .videoClip) {
                    part.videoAssetRef = ref
                    part.videoURL = "asset://\(ref.id.uuidString)"
                    changed = true
                } else if let fileURL = localFileURL(from: part.videoURL) {
                    let asset = try importLocalFile(
                        at: fileURL,
                        as: .videoClip,
                        preferredName: fileURL.lastPathComponent,
                        into: &document.assetRepository,
                        maximumImportBytes: maximumImportBytes
                    )
                    part.videoAssetRef = document.assetRepository.assetRef(for: asset)
                    part.videoURL = assetURLString(for: asset)
                    report.embeddedAssetIds.append(asset.id)
                    changed = true
                }

            case .scene3D:
                if let ref = part.scene3DAssetRef,
                   document.assetRepository.asset(byId: ref.id) != nil {
                    part.scene3DURL = ""
                    part.scene3DSourceURL = ""
                    changed = true
                } else if let fileURL = localFileURL(from: part.scene3DSourceURL.isEmpty ? part.scene3DURL : part.scene3DSourceURL) {
                    let renderURL: URL
                    if STLConverter.isSTL(path: fileURL.path),
                       let converted = try? STLConverter.convert(stlPath: fileURL.path) {
                        renderURL = URL(fileURLWithPath: converted)
                    } else {
                        renderURL = fileURL
                    }
                    let asset = try importLocalFile(
                        at: renderURL,
                        as: .model3D,
                        preferredName: renderURL.lastPathComponent,
                        into: &document.assetRepository,
                        maximumImportBytes: maximumImportBytes
                    )
                    part.scene3DAssetRef = document.assetRepository.assetRef(for: asset)
                    part.scene3DURL = ""
                    part.scene3DSourceURL = ""
                    report.embeddedAssetIds.append(asset.id)
                    changed = true
                }

            case .audioRecorder:
                if part.audioData == nil,
                   let fileURL = localFileURL(from: part.audioOutputPath) {
                    let data = try readLocalFileData(at: fileURL, maximumImportBytes: maximumImportBytes)
                    part.audioData = data
                    part.audioEmbedInStack = true
                    changed = true
                }

            default:
                break
            }

            if changed {
                document.parts[index] = part
                report.updatedPartIds.append(part.id)
            }
        }
        return report
    }

    @discardableResult
    public static func importLocalFile(
        at fileURL: URL,
        as kind: AssetKind,
        preferredName: String? = nil,
        into repository: inout AssetRepository,
        maximumImportBytes: Int64 = defaultMaximumImportBytes
    ) throws -> Asset {
        let data = try readLocalFileData(at: fileURL, maximumImportBytes: maximumImportBytes)
        let name = sanitizedAssetName(preferredName?.isEmpty == false ? preferredName! : fileURL.lastPathComponent)
        if let existing = repository.assets.first(where: { $0.kind == kind && $0.name == name && $0.data == data }) {
            return existing
        }
        let asset = Asset(
            name: name,
            kind: kind,
            mimeType: mimeType(for: fileURL, kind: kind),
            data: data,
            tags: ["embedded", "user-import"],
            provenance: AssetProvenance(
                origin: .userImport,
                attribution: AssetAttribution(
                    title: name,
                    providerName: "Local File",
                    providerIdentifier: "local-file"
                )
            )
        )
        repository.addAsset(asset)
        return asset
    }

    public static func selfContainmentIssues(in document: HypeDocument) -> [StackAssetSelfContainmentIssue] {
        document.parts.compactMap { part in
            switch part.partType {
            case .pdf:
                if hasValidAssetRef(part.pdfAssetRef, expectedKind: .document, in: document.assetRepository) {
                    return nil
                }
                if let ref = part.pdfAssetRef {
                    return assetRefIssue(part: part, property: "pdfAssetRef", reference: ref, expectedKind: .document, in: document.assetRepository)
                }
                if part.pdfURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
                return issue(part: part, property: "pdfURL", reference: part.pdfURL)
            case .video:
                if hasValidAssetRef(part.videoAssetRef, expectedKind: .videoClip, in: document.assetRepository) {
                    return nil
                }
                if let ref = part.videoAssetRef {
                    return assetRefIssue(part: part, property: "videoAssetRef", reference: ref, expectedKind: .videoClip, in: document.assetRepository)
                }
                if part.videoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
                return issue(part: part, property: "videoURL", reference: part.videoURL)
            case .scene3D:
                if hasValidAssetRef(part.scene3DAssetRef, expectedKind: .model3D, in: document.assetRepository) {
                    return nil
                }
                if let ref = part.scene3DAssetRef {
                    return assetRefIssue(part: part, property: "scene3DAssetRef", reference: ref, expectedKind: .model3D, in: document.assetRepository)
                }
                let reference = part.scene3DSourceURL.isEmpty ? part.scene3DURL : part.scene3DSourceURL
                return reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : issue(part: part, property: "scene3DURL", reference: reference)
            case .audioRecorder:
                if part.audioOutputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || part.audioData != nil {
                    return nil
                }
                return issue(part: part, property: "audioOutputPath", reference: part.audioOutputPath)
            default:
                return nil
            }
        }
    }

    public static func assetId(fromAssetURLString raw: String) -> UUID? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == assetURLScheme else { return nil }
        if let host = url.host, let id = UUID(uuidString: host) {
            return id
        }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return UUID(uuidString: path)
    }

    private static func resolvedRef(
        _ explicitRef: AssetRef?,
        urlString: String,
        in repository: AssetRepository,
        kind: AssetKind
    ) -> AssetRef? {
        if let ref = explicitRef,
           let asset = repository.asset(byId: ref.id),
           asset.kind == kind {
            return repository.assetRef(for: asset)
        }
        if let id = assetId(fromAssetURLString: urlString),
           let asset = repository.asset(byId: id),
           asset.kind == kind {
            return repository.assetRef(for: asset)
        }
        return nil
    }

    private static func hasValidAssetRef(_ ref: AssetRef?, expectedKind: AssetKind, in repository: AssetRepository) -> Bool {
        guard let ref else { return false }
        return repository.asset(byId: ref.id)?.kind == expectedKind
    }

    private static func localFileURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() {
            switch scheme {
            case "file":
                return url
            case assetURLScheme, "http", "https":
                return nil
            default:
                return nil
            }
        }
        return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
    }

    private static func readLocalFileData(at fileURL: URL, maximumImportBytes: Int64) throws -> Data {
        guard fileURL.isFileURL else {
            throw StackAssetEmbedderError.missingLocalFile(fileURL.lastPathComponent)
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw StackAssetEmbedderError.missingLocalFile(fileURL.lastPathComponent)
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        if let fileSize = attributes?[.size] as? NSNumber {
            let byteCount = fileSize.int64Value
            guard byteCount <= maximumImportBytes else {
                throw StackAssetEmbedderError.fileTooLarge(fileURL.lastPathComponent, byteCount: byteCount, limit: maximumImportBytes)
            }
        }
        do {
            return try Data(contentsOf: fileURL)
        } catch {
            throw StackAssetEmbedderError.readFailed(fileURL.lastPathComponent)
        }
    }

    private static func sanitizedAssetName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Embedded Asset" : String(trimmed.prefix(240))
    }

    private static func mimeType(for url: URL, kind: AssetKind) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf": return "application/pdf"
        case "mov": return "video/quicktime"
        case "mp4", "m4v": return "video/mp4"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/mp4"
        case "caf": return "audio/x-caf"
        case "wav": return "audio/wav"
        case "usdz", "usd": return "model/vnd.usdz+zip"
        case "dae": return "model/vnd.collada+xml"
        case "obj": return "model/obj"
        case "fbx": return "model/fbx"
        case "glb": return "model/gltf-binary"
        case "gltf": return "model/gltf+json"
        default:
            switch kind {
            case .document: return "application/octet-stream"
            case .videoClip: return "video/quicktime"
            case .audioClip: return "audio/mp4"
            case .model3D: return "model/vnd.usdz+zip"
            default: return "application/octet-stream"
            }
        }
    }

    private static func issue(part: Part, property: String, reference: String) -> StackAssetSelfContainmentIssue {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason: String
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            reason = "Remote media is not embedded in standalone runtimes. Import the file into the stack asset repository first."
        } else if assetId(fromAssetURLString: trimmed) != nil {
            reason = "The part references a missing stack asset."
        } else {
            reason = "The part still references an external local file. Import it into the stack before deployment."
        }
        return StackAssetSelfContainmentIssue(
            partId: part.id,
            partName: part.name,
            partType: part.partType,
            property: property,
            reference: trimmed,
            reason: reason
        )
    }

    private static func assetRefIssue(
        part: Part,
        property: String,
        reference: AssetRef,
        expectedKind: AssetKind,
        in repository: AssetRepository
    ) -> StackAssetSelfContainmentIssue {
        let reason: String
        if let asset = repository.asset(byId: reference.id) {
            reason = "The part references a stack asset with kind \(asset.kind.rawValue), but expected \(expectedKind.rawValue)."
        } else {
            reason = "The part references a missing stack asset."
        }
        return StackAssetSelfContainmentIssue(
            partId: part.id,
            partName: part.name,
            partType: part.partType,
            property: property,
            reference: reference.id.uuidString,
            reason: reason
        )
    }
}
