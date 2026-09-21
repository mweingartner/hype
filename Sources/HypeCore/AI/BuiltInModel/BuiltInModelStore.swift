import Foundation

/// Where a Built-in model variant's files were found.
public enum BuiltInModelLocation: Sendable, Equatable {
    /// Downloaded by Hype into Application Support.
    case installed(URL)
    /// Adopted in place from the user's Hugging Face cache (never modified or
    /// removed by Hype).
    case huggingFaceCache(URL)
    /// A directory the user pointed Hype at.
    case userDirectory(URL)

    public var directory: URL {
        switch self {
        case .installed(let url), .huggingFaceCache(let url), .userDirectory(let url):
            return url
        }
    }

    /// Only Hype's own copy may be deleted from Settings.
    public var isRemovable: Bool {
        if case .installed = self { return true }
        return false
    }
}

/// Finds, installs and removes Built-in model weights on disk.
///
/// Models live in `~/Library/Application Support/Hype/Models/<variant>/<revision>/`
/// — not Caches (purged under disk pressure) and excluded from backups (they can
/// always be downloaded again).
public struct BuiltInModelStore: Sendable {
    /// How strictly a directory is checked before its files are trusted.
    public enum Integrity: Sendable {
        /// Sizes, the SHA-256 of every small file on each lookup (tokenizer,
        /// chat template, config — the files that steer behaviour and are easy
        /// to edit), and the SHA-256 of every weight file once, remembered until
        /// the file changes. The default.
        case pinnedHashes
        /// Sizes only. For developer tooling pointed at ad-hoc model folders.
        case sizesOnly
    }

    /// Files at or below this size are hashed on every lookup.
    static let smallFileLimit: Int64 = 64 << 20

    public let modelsRoot: URL
    public let huggingFaceHubRoot: URL?
    public let integrity: Integrity
    private let defaultsSuiteName: String?

    public init(
        modelsRoot: URL? = nil,
        huggingFaceHubRoot: URL? = BuiltInModelStore.defaultHuggingFaceHubRoot(),
        defaultsSuiteName: String? = nil,
        integrity: Integrity = .pinnedHashes
    ) {
        self.modelsRoot = modelsRoot ?? BuiltInModelStore.defaultModelsRoot()
        self.huggingFaceHubRoot = huggingFaceHubRoot
        self.defaultsSuiteName = defaultsSuiteName
        self.integrity = integrity
    }

    public static func defaultModelsRoot(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Hype/Models", isDirectory: true)
    }

    public static func defaultHuggingFaceHubRoot() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        if let explicit = environment["HF_HUB_CACHE"], !explicit.isEmpty {
            return URL(fileURLWithPath: (explicit as NSString).expandingTildeInPath, isDirectory: true)
        }
        if let home = environment["HF_HOME"], !home.isEmpty {
            return URL(fileURLWithPath: (home as NSString).expandingTildeInPath, isDirectory: true)
                .appendingPathComponent("hub", isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".cache/huggingface/hub", isDirectory: true)
    }

    private var defaults: UserDefaults {
        defaultsSuiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    // MARK: - Locations

    public func installDirectory(for variant: BuiltInModelVariant) -> URL {
        variantRoot(for: variant)
            .appendingPathComponent(Self.safeComponent(variant.revision), isDirectory: true)
    }

    /// Directory partial downloads are written to before they are verified.
    public func stagingDirectory(for variant: BuiltInModelVariant) -> URL {
        variantRoot(for: variant)
            .appendingPathComponent(Self.safeComponent(variant.revision) + ".partial", isDirectory: true)
    }

    func variantRoot(for variant: BuiltInModelVariant) -> URL {
        modelsRoot.appendingPathComponent(Self.safeComponent(variant.id), isDirectory: true)
    }

    /// Catalog identifiers are compiled in today; this keeps `remove` and the
    /// install paths inside `modelsRoot` even if they ever come from elsewhere.
    static func safeComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let cleaned = String(value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        let trimmed = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return trimmed.isEmpty ? "_" : trimmed
    }

    func huggingFaceSnapshotDirectory(for variant: BuiltInModelVariant) -> URL? {
        guard let hub = huggingFaceHubRoot else { return nil }
        let folder = "models--" + variant.huggingFaceRepo.replacingOccurrences(of: "/", with: "--")
        return hub
            .appendingPathComponent(folder, isDirectory: true)
            .appendingPathComponent("snapshots", isDirectory: true)
            .appendingPathComponent(variant.revision, isDirectory: true)
    }

    /// First complete copy of the variant, in priority order: a user-supplied
    /// directory, Hype's own install, then the Hugging Face cache.
    public func location(
        of variant: BuiltInModelVariant,
        fileManager: FileManager = .default
    ) -> BuiltInModelLocation? {
        if let userDirectory = BuiltInModelSettings.modelDirectoryOverride(variantID: variant.id, defaults: defaults),
           isComplete(userDirectory, for: variant, fileManager: fileManager) {
            return .userDirectory(userDirectory)
        }
        let installed = installDirectory(for: variant)
        if isComplete(installed, for: variant, fileManager: fileManager) {
            return .installed(installed)
        }
        if let cached = huggingFaceSnapshotDirectory(for: variant),
           isComplete(cached, for: variant, fileManager: fileManager) {
            return .huggingFaceCache(cached)
        }
        return nil
    }

    public func installedDirectory(of variant: BuiltInModelVariant) throws -> URL {
        guard let location = location(of: variant) else {
            throw BuiltInModelError.notInstalled(variantName: variant.displayName)
        }
        return location.directory
    }

    /// Every pinned file is present with the pinned size, and every small file
    /// (tokenizer, chat template, config) matches its pinned SHA-256. Weight
    /// files are tens of gigabytes: they are hashed by `verifyWeights`, once.
    public func isComplete(
        _ directory: URL,
        for variant: BuiltInModelVariant,
        fileManager: FileManager = .default
    ) -> Bool {
        guard !variant.files.isEmpty else { return false }
        for file in variant.files {
            let url = directory.appendingPathComponent(file.path)
            guard let size = Self.fileSize(at: url, fileManager: fileManager), size == file.size else {
                return false
            }
            if integrity == .pinnedHashes, file.size <= Self.smallFileLimit,
               SmallFileHashCache.shared.sha256(of: url) != file.sha256.lowercased() {
                return false
            }
        }
        return true
    }

    /// Hashes every weight file against the catalog — once. A file is hashed
    /// again only if its size or modification date changed since it was last
    /// verified. This is what makes weights adopted from the Hugging Face cache
    /// or a custom folder (which Hype did not download itself) trustworthy.
    public func verifyWeights(
        of variant: BuiltInModelVariant,
        at directory: URL,
        fileManager: FileManager = .default
    ) throws {
        guard integrity == .pinnedHashes else { return }
        var ledger = VerifiedWeightsLedger.load(from: ledgerURL)
        var changed = false
        for file in variant.files where file.size > Self.smallFileLimit {
            let url = directory.appendingPathComponent(file.path).resolvingSymlinksInPath()
            guard let stamp = VerifiedWeightsLedger.Stamp(url: url, sha256: file.sha256.lowercased(), fileManager: fileManager) else {
                throw BuiltInModelDownloadError.sizeMismatch(path: file.path)
            }
            if ledger.entries[url.path] == stamp { continue }
            guard try BuiltInModelDownloader.sha256(of: url) == stamp.sha256 else {
                throw BuiltInModelDownloadError.checksumMismatch(path: file.path)
            }
            ledger.entries[url.path] = stamp
            changed = true
        }
        if changed { ledger.save(to: ledgerURL) }
    }

    /// True when `verifyWeights` would have nothing left to hash.
    public func weightsAreVerified(
        of variant: BuiltInModelVariant,
        at directory: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        guard integrity == .pinnedHashes else { return true }
        let ledger = VerifiedWeightsLedger.load(from: ledgerURL)
        return variant.files.filter { $0.size > Self.smallFileLimit }.allSatisfy { file in
            let url = directory.appendingPathComponent(file.path).resolvingSymlinksInPath()
            guard let stamp = VerifiedWeightsLedger.Stamp(url: url, sha256: file.sha256.lowercased(), fileManager: fileManager) else {
                return false
            }
            return ledger.entries[url.path] == stamp
        }
    }

    /// Records files the downloader has just hashed, so first use does not
    /// hash them a second time.
    func recordVerifiedWeights(of variant: BuiltInModelVariant, at directory: URL) {
        guard integrity == .pinnedHashes else { return }
        var ledger = VerifiedWeightsLedger.load(from: ledgerURL)
        for file in variant.files where file.size > Self.smallFileLimit {
            let url = directory.appendingPathComponent(file.path).resolvingSymlinksInPath()
            if let stamp = VerifiedWeightsLedger.Stamp(url: url, sha256: file.sha256.lowercased()) {
                ledger.entries[url.path] = stamp
            }
        }
        ledger.save(to: ledgerURL)
    }

    var ledgerURL: URL {
        modelsRoot.appendingPathComponent("verified-weights.json")
    }

    public func installedVariants() -> [BuiltInModelVariant] {
        BuiltInModelCatalog.variants.filter { location(of: $0) != nil }
    }

    // MARK: - Removal and accounting

    /// Deletes Hype's own copy (and any partial download). Adopted Hugging Face
    /// cache copies and user directories are never touched.
    public func remove(_ variant: BuiltInModelVariant, fileManager: FileManager = .default) throws {
        let variantRoot = variantRoot(for: variant)
        guard fileManager.fileExists(atPath: variantRoot.path) else { return }
        try fileManager.removeItem(at: variantRoot)
    }

    /// Bytes Hype's own copy occupies on disk.
    public func diskUsageBytes(of variant: BuiltInModelVariant, fileManager: FileManager = .default) -> Int64 {
        let variantRoot = variantRoot(for: variant)
        guard let enumerator = fileManager.enumerator(
            at: variantRoot,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    public func freeDiskBytes() -> Int64? {
        let probe = Self.nearestExistingAncestor(of: modelsRoot)
        #if os(macOS) || os(iOS)
        let values = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
        #else
        let values = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        return values?.volumeAvailableCapacity.map(Int64.init)
        #endif
    }

    static func fileSize(at url: URL, fileManager: FileManager = .default) -> Int64? {
        // Hugging Face cache entries are symlinks into `blobs/`; resolve them.
        let resolved = url.resolvingSymlinksInPath()
        guard let attributes = try? fileManager.attributesOfItem(atPath: resolved.path),
              let size = attributes[.size] as? NSNumber else { return nil }
        return size.int64Value
    }

    static func nearestExistingAncestor(of url: URL, fileManager: FileManager = .default) -> URL {
        var candidate = url
        while !fileManager.fileExists(atPath: candidate.path), candidate.pathComponents.count > 1 {
            candidate = candidate.deletingLastPathComponent()
        }
        return candidate
    }
}

/// Which weight files have been hashed against the catalog, and what they looked
/// like (size, modification date) when they were.
struct VerifiedWeightsLedger: Codable {
    struct Stamp: Codable, Equatable {
        let size: Int64
        let modified: Double
        let sha256: String

        init?(url: URL, sha256: String, fileManager: FileManager = .default) {
            guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                  let size = attributes[.size] as? NSNumber,
                  let modified = attributes[.modificationDate] as? Date else { return nil }
            self.size = size.int64Value
            self.modified = modified.timeIntervalSince1970
            self.sha256 = sha256
        }
    }

    var entries: [String: Stamp] = [:]

    static func load(from url: URL) -> VerifiedWeightsLedger {
        guard let data = try? Data(contentsOf: url),
              let ledger = try? JSONDecoder().decode(VerifiedWeightsLedger.self, from: data) else {
            return VerifiedWeightsLedger()
        }
        return ledger
    }

    func save(to url: URL) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

/// `location(of:)` runs on every AI request and Settings refresh; remember small
/// files' hashes until the file changes instead of re-reading them each time.
final class SmallFileHashCache: @unchecked Sendable {
    static let shared = SmallFileHashCache()

    private struct Key: Hashable {
        let path: String
        let size: Int64
        let modified: Double
    }

    private let lock = NSLock()
    private var hashes: [Key: String] = [:]

    func sha256(of url: URL) -> String? {
        let resolved = url.resolvingSymlinksInPath()
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path),
              let size = attributes[.size] as? NSNumber,
              let modified = attributes[.modificationDate] as? Date else { return nil }
        let key = Key(path: resolved.path, size: size.int64Value, modified: modified.timeIntervalSince1970)
        lock.lock()
        if let known = hashes[key] {
            lock.unlock()
            return known
        }
        lock.unlock()
        guard let digest = try? BuiltInModelDownloader.sha256(of: resolved) else { return nil }
        lock.lock()
        hashes[key] = digest
        lock.unlock()
        return digest
    }
}
