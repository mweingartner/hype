#if canImport(MLXLMCommon)
import CryptoKit
import Foundation
import HypeCore
import MLXLMCommon

/// Persists the static prompt prefix's KV cache so its minute-long prefill is
/// paid once per (model, tool set, guide) — not once per app launch.
///
/// Files live in `~/Library/Caches/Hype/BuiltInPromptCache/<variant>/`: they are
/// large (gigabytes), always reproducible, and the system may purge them.
///
/// A cache file is the model's "memory" of Hype's rules and language guide, so a
/// swapped file would steer the model without any visible trace. Each file
/// therefore carries an HMAC-SHA256 keyed with a per-install secret that lives
/// outside the Caches directory; a file without a valid tag is discarded.
struct PromptPrefixDiskCache {
    /// Prefixes kept per variant; each authoring surface has its own tool set.
    static let maximumFilesPerVariant = 3
    /// Below this a prefix prefills faster than it loads.
    static let minimumTokens = 4096

    let directory: URL
    /// Everything besides the tokens that makes a cache file valid.
    let signature: String

    init?(variantID: String, revision: String, kvCacheBits: Int?, kvQuantizationStart: Int = 0) {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        directory = caches
            .appendingPathComponent("Hype/BuiltInPromptCache", isDirectory: true)
            .appendingPathComponent(variantID, isDirectory: true)
        signature = "\(variantID)|\(revision)|kv\(kvCacheBits ?? 16)@\(kvCacheBits == nil ? 0 : kvQuantizationStart)"
    }

    func fileURL(for tokens: [Int]) -> URL {
        var hasher = SHA256()
        hasher.update(data: Data(signature.utf8))
        tokens.withUnsafeBufferPointer { hasher.update(bufferPointer: UnsafeRawBufferPointer($0)) }
        let name = hasher.finalize().prefix(16).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name + ".safetensors")
    }

    /// Cheap existence check; `load` still authenticates the file.
    func contains(tokens: [Int]) -> Bool {
        tokens.count >= Self.minimumTokens
            && FileManager.default.fileExists(atPath: fileURL(for: tokens).path)
    }

    func load(tokens: [Int], expectedLayers: Int) -> [any KVCache]? {
        guard tokens.count >= Self.minimumTokens else { return nil }
        let url = fileURL(for: tokens)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let expected = try? Data(contentsOf: Self.tagURL(for: url)),
              let key = Self.installKey(),
              let actual = Self.authenticationCode(of: url, key: key),
              expected.count == actual.count,
              zip(expected, actual).reduce(UInt8(0), { $0 | ($1.0 ^ $1.1) }) == 0 else {
            Self.discard(url)
            return nil
        }
        do {
            let (cache, metadata) = try loadPromptCache(url: url)
            guard cache.count == expectedLayers,
                  metadata["signature"] == signature,
                  metadata["tokenCount"] == String(tokens.count) else {
                Self.discard(url)
                return nil
            }
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
            return cache
        } catch {
            Self.discard(url)
            return nil
        }
    }

    func save(_ cache: [any KVCache], tokens: [Int]) {
        guard tokens.count >= Self.minimumTokens else { return }
        let url = fileURL(for: tokens)
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try savePromptCache(
                url: url,
                cache: cache,
                metadata: ["signature": signature, "tokenCount": String(tokens.count)]
            )
            guard let key = Self.installKey(), let tag = Self.authenticationCode(of: url, key: key) else {
                Self.discard(url)
                return
            }
            try tag.write(to: Self.tagURL(for: url), options: .atomic)
            for file in [url, Self.tagURL(for: url)] {
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            }
            evictOldFiles()
        } catch {
            // A failed save only costs a future prefill.
            Self.discard(url)
        }
    }

    // MARK: - Integrity

    static func tagURL(for cacheFile: URL) -> URL {
        cacheFile.appendingPathExtension("mac")
    }

    private static func discard(_ cacheFile: URL) {
        try? FileManager.default.removeItem(at: cacheFile)
        try? FileManager.default.removeItem(at: tagURL(for: cacheFile))
    }

    /// A random per-install key kept with the models in Application Support —
    /// not in Caches, so something that can only write cache files cannot forge
    /// a tag.
    static func installKey(root: URL = BuiltInModelStore.defaultModelsRoot()) -> SymmetricKey? {
        let url = root.appendingPathComponent(".prompt-cache-key")
        if let data = try? Data(contentsOf: url), data.count == 32 {
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return key
        } catch {
            return nil
        }
    }

    static func authenticationCode(of file: URL, key: SymmetricKey) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        var hmac = HMAC<SHA256>(key: key)
        while let chunk = try? handle.read(upToCount: 8 << 20), !chunk.isEmpty {
            hmac.update(data: chunk)
        }
        return Data(hmac.finalize())
    }

    private func evictOldFiles() {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else {
            return
        }
        let dated = files.filter { $0.pathExtension == "safetensors" }.map { url in
            (url, (try? url.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast)
        }
        for (url, _) in dated.sorted(by: { $0.1 > $1.1 }).dropFirst(Self.maximumFilesPerVariant) {
            Self.discard(url)
        }
    }
}
#endif
