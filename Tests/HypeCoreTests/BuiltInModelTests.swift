import CryptoKit
import Foundation
import Testing
@testable import HypeCore

// MARK: - Fixtures

private let gib: Int64 = 1 << 30

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("hype-builtin-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Creates a file of exactly `size` bytes without writing `size` bytes of real
/// data: APFS (and most modern filesystems) makes an extended-then-untouched
/// file sparse, so a multi-gigabyte fixture costs no real disk space. Used to
/// exercise "an installed real catalog variant" without downloading gigabytes
/// of weights in a unit test — content never matters because these fixtures
/// are never hashed (the tests using them never reach checksum verification).
private func writeSparseFile(size: Int64, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.truncate(atOffset: UInt64(size))
}

/// A tiny, seedable PRNG (splitmix64) so property/fuzz tests are reproducible:
/// a failure always replays with the same seed and the same generated inputs.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A tiny stand-in variant whose "weights" are a few bytes.
private func makeVariant(
    id: String = "test-variant",
    payloads: [String: Data] = ["config.json": Data("{}".utf8), "model.safetensors": Data("weights".utf8)],
    minimumGB: Int = 8,
    recommendedGB: Int = 8
) -> BuiltInModelVariant {
    BuiltInModelVariant(
        id: id,
        displayName: "Test Variant",
        summary: "fixture",
        tier: .standard,
        huggingFaceRepo: "hype-tests/\(id)",
        revision: "rev1",
        files: payloads.keys.sorted().map { path in
            BuiltInModelFile(path: path, size: Int64(payloads[path]!.count), sha256: sha256Hex(payloads[path]!))
        },
        license: "Apache-2.0",
        licenseURL: "https://example.invalid/license",
        kvBytesPerToken: 1024,
        fixedOverheadBytes: 1 << 20,
        nativeContextTokens: 262_144,
        minimumPhysicalMemoryGB: minimumGB,
        recommendedPhysicalMemoryGB: recommendedGB,
        supportsVision: false,
        thinkingControl: .none
    )
}

private func write(_ payloads: [String: Data], into directory: URL) throws {
    for (path, data) in payloads {
        let url = directory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
}

/// Records requests and replays a scripted result.
private actor FakeEngine: BuiltInModelEngine {
    private(set) var requests: [BuiltInGenerationRequest] = []
    private(set) var loads: [String] = []
    var result = BuiltInGenerationResult(text: "ok")
    var chunks: [String] = []
    var failure: BuiltInModelError?
    /// When set, `generate` never returns on its own: it spins checking for
    /// cancellation, the way the real MLX engine's token loop does, so tests
    /// can exercise `chatStream` cancellation deterministically.
    var hangsUntilCancelled = false
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var started = false

    func configure(
        result: BuiltInGenerationResult? = nil,
        chunks: [String]? = nil,
        failure: BuiltInModelError? = nil,
        hangsUntilCancelled: Bool = false
    ) {
        if let result { self.result = result }
        if let chunks { self.chunks = chunks }
        self.failure = failure
        self.hangsUntilCancelled = hangsUntilCancelled
    }

    /// Suspends until `generate` has recorded its request, so a test can wait
    /// for generation to truly be underway before cancelling.
    func waitUntilGenerateStarted() async {
        if started { return }
        await withCheckedContinuation { startedContinuation = $0 }
    }

    func load(variant: BuiltInModelVariant, from directory: URL) async throws {
        loads.append(variant.id)
    }

    func generate(
        _ request: BuiltInGenerationRequest,
        onText: (@Sendable (String) -> Void)?
    ) async throws -> BuiltInGenerationResult {
        requests.append(request)
        started = true
        startedContinuation?.resume()
        startedContinuation = nil
        if let failure { throw failure }
        if hangsUntilCancelled {
            while true {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 5_000_000)
            }
        }
        for chunk in chunks { onText?(chunk) }
        return result
    }

    func unload() async {}

    func status() async -> BuiltInEngineStatus { BuiltInEngineStatus() }
}

// MARK: - Catalog

@Suite("BuiltInModelCatalog")
struct BuiltInModelCatalogTests {
    @Test("ships one variant per memory tier with unique identifiers")
    func oneVariantPerTier() {
        let variants = BuiltInModelCatalog.variants
        #expect(Set(variants.map(\.id)).count == variants.count)
        #expect(Set(variants.map(\.tier)) == Set(BuiltInModelTier.allCases))
        #expect(BuiltInModelCatalog.variant(tier: .standard) != nil)
        #expect(BuiltInModelCatalog.variant(tier: .max) != nil)
    }

    @Test("untuned variants never claim the tuned-model name prefix")
    func variantIdentifiersAreNotTunedNames() {
        for variant in BuiltInModelCatalog.variants {
            #expect(!variant.id.lowercased().hasPrefix("hypetalk-"))
            #expect(variant.id != BuiltInModelCatalog.automaticVariantID)
        }
    }

    @Test("every pinned file is safe, hashed and downloadable over HTTPS from an allowed host")
    func manifestsArePinnedAndSafe() throws {
        for variant in BuiltInModelCatalog.variants {
            #expect(variant.revision.count == 40)
            #expect(variant.files.contains { $0.path == "config.json" })
            #expect(variant.files.contains { $0.path == "tokenizer.json" })
            #expect(variant.weightBytes > 1 * gib)
            for file in variant.files {
                #expect(BuiltInModelDownloader.isSafeRelativePath(file.path))
                #expect(file.size > 0)
                #expect(file.sha256.count == 64)
                #expect(file.sha256.allSatisfy { $0.isHexDigit && !$0.isUppercase })
                let url = try #require(variant.downloadURL(for: file))
                #expect(url.scheme == "https")
                #expect(BuiltInModelDownloader.isAllowed(host: url.host))
                #expect(url.path.contains(variant.revision))
            }
        }
    }
}

// MARK: - Memory fit

@Suite("BuiltInMemoryFitPolicy")
struct BuiltInMemoryFitPolicyTests {
    private let standard = BuiltInModelCatalog.variant(tier: .standard)!
    private let max = BuiltInModelCatalog.variant(tier: .max)!

    @Test("never hands the model the whole working set or the system reserve")
    func budgetStaysBelowCeiling() {
        let physical = 32 * gib
        let workingSet = 24 * gib
        let budget = BuiltInMemoryFitPolicy.budgetBytes(physicalMemoryBytes: physical, recommendedWorkingSetBytes: workingSet)
        #expect(budget < workingSet)
        #expect(budget <= physical - BuiltInMemoryFitPolicy.reservedForSystemBytes)
        #expect(BuiltInMemoryFitPolicy.budgetBytes(physicalMemoryBytes: 8 * gib, recommendedWorkingSetBytes: nil) == 0)
    }

    @Test("a 32 GB Mac runs Standard with room for Hype's long authoring prompt, and refuses Max")
    func thirtyTwoGigabyteMac() {
        let fit = BuiltInMemoryFitPolicy.evaluate(variant: standard, physicalMemoryBytes: 32 * gib, recommendedWorkingSetBytes: nil)
        #expect(fit.verdict != .insufficient)
        #expect(fit.contextTokenLimit >= BuiltInMemoryFitPolicy.comfortableContextTokens)
        #expect(fit.budgetBytes >= standard.weightBytes + standard.fixedOverheadBytes)

        let tooBig = BuiltInMemoryFitPolicy.evaluate(variant: max, physicalMemoryBytes: 32 * gib, recommendedWorkingSetBytes: nil)
        #expect(tooBig.verdict == .insufficient)

        let automatic = BuiltInMemoryFitPolicy.automaticVariant(physicalMemoryBytes: 32 * gib, recommendedWorkingSetBytes: nil)
        #expect(automatic?.tier == .standard)
    }

    @Test("a 128 GB Mac runs Max comfortably with full-precision KV")
    func oneTwentyEightGigabyteMac() {
        // Measured on an M5 Max: recommendedMaxWorkingSetSize = 115,448,725,504.
        let workingSet: Int64 = 115_448_725_504
        let fit = BuiltInMemoryFitPolicy.evaluate(variant: max, physicalMemoryBytes: 128 * gib, recommendedWorkingSetBytes: workingSet)
        #expect(fit.verdict == .comfortable)
        #expect(fit.kvCacheBits == nil)
        #expect(fit.contextTokenLimit == BuiltInMemoryFitPolicy.maximumContextTokens)

        let automatic = BuiltInMemoryFitPolicy.automaticVariant(physicalMemoryBytes: 128 * gib, recommendedWorkingSetBytes: workingSet)
        #expect(automatic?.tier == .max)
    }

    @Test("Macs below the floor get no Built-in model")
    func smallMacsAreRefused() {
        for gigabytes in [8, 16, 24] as [Int64] {
            let automatic = BuiltInMemoryFitPolicy.automaticVariant(physicalMemoryBytes: gigabytes * gib, recommendedWorkingSetBytes: nil)
            #expect(automatic == nil, "\(gigabytes) GB")
        }
    }

    @Test("a 64 GB Mac falls back to Standard")
    func sixtyFourGigabyteMac() {
        let automatic = BuiltInMemoryFitPolicy.automaticVariant(physicalMemoryBytes: 64 * gib, recommendedWorkingSetBytes: nil)
        #expect(automatic?.tier == .standard)
    }

    @Test("a user context override can only lower the cap")
    func contextOverrideOnlyLowers() {
        let base = BuiltInMemoryFitPolicy.evaluate(variant: standard, physicalMemoryBytes: 64 * gib, recommendedWorkingSetBytes: nil)
        let lowered = BuiltInMemoryFitPolicy.evaluate(variant: standard, physicalMemoryBytes: 64 * gib, recommendedWorkingSetBytes: nil, contextLimitOverride: 32_768)
        let raised = BuiltInMemoryFitPolicy.evaluate(variant: standard, physicalMemoryBytes: 64 * gib, recommendedWorkingSetBytes: nil, contextLimitOverride: 10_000_000)
        #expect(lowered.contextTokenLimit == 32_768)
        #expect(raised.contextTokenLimit == base.contextTokenLimit)
    }

    // MARK: Boundaries

    @Test("Standard's memory floor sits exactly at its declared minimum: 31 GB refuses it, 32 and 33 GB run it comfortably")
    func standardVariantMemoryBoundary() {
        let refused = BuiltInMemoryFitPolicy.evaluate(variant: standard, physicalMemoryBytes: 31 * gib, recommendedWorkingSetBytes: nil)
        #expect(refused.verdict == .insufficient)
        #expect(refused.contextTokenLimit == 0)

        for gigabytes in [32, 33] as [Int64] {
            let fit = BuiltInMemoryFitPolicy.evaluate(variant: standard, physicalMemoryBytes: gigabytes * gib, recommendedWorkingSetBytes: nil)
            #expect(fit.verdict == .comfortable, "\(gigabytes) GB")
        }
    }

    @Test("Max has a 96 GB floor: 95 GB is refused, 96 and 128 GB are comfortable")
    func maxVariantMemoryBoundary() {
        let refused = BuiltInMemoryFitPolicy.evaluate(variant: max, physicalMemoryBytes: 95 * gib, recommendedWorkingSetBytes: nil)
        #expect(refused.verdict == .insufficient)

        for gigabytes in [96, 128] as [Int64] {
            let fit = BuiltInMemoryFitPolicy.evaluate(variant: max, physicalMemoryBytes: gigabytes * gib, recommendedWorkingSetBytes: nil)
            #expect(fit.verdict == .comfortable, "\(gigabytes) GB")
        }
    }

    // MARK: Property tests (seeded, reproducible)

    @Test("budgetBytes never decreases as physical memory grows, for a fixed working set")
    func budgetMonotonicWithFixedWorkingSet() {
        var rng = SplitMix64(seed: 20_260_921)
        let workingSet: Int64 = 60 * gib
        let physicalValues = (0..<200).map { _ in Int64.random(in: gib...(512 * gib), using: &rng) }.sorted()
        var previousBudget: Int64 = 0
        for physical in physicalValues {
            let budget = BuiltInMemoryFitPolicy.budgetBytes(physicalMemoryBytes: physical, recommendedWorkingSetBytes: workingSet)
            #expect(budget >= 0)
            #expect(budget >= previousBudget, "budget decreased at \(physical) bytes")
            previousBudget = budget
        }
    }

    @Test("budgetBytes never decreases as physical memory grows, using the proportional fallback working set")
    func budgetMonotonicWithFallbackWorkingSet() {
        var rng = SplitMix64(seed: 848_210)
        let physicalValues = (0..<200).map { _ in Int64.random(in: gib...(512 * gib), using: &rng) }.sorted()
        var previousBudget: Int64 = 0
        for physical in physicalValues {
            let budget = BuiltInMemoryFitPolicy.budgetBytes(physicalMemoryBytes: physical, recommendedWorkingSetBytes: nil)
            #expect(budget >= 0)
            #expect(budget >= previousBudget, "budget decreased at \(physical) bytes")
            previousBudget = budget
        }
    }

    @Test("evaluate() never returns a context cap above native/maximum or a negative budget, across a fuzzed range of memory sizes")
    func contextCapStaysWithinCeilingsAndNonNegative() {
        var rng = SplitMix64(seed: 5_551_212)
        for variant in BuiltInModelCatalog.variants {
            for _ in 0..<300 {
                let physical = Int64.random(in: gib...(512 * gib), using: &rng)
                let workingSet: Int64? = Bool.random(using: &rng) ? nil : Int64.random(in: gib...physical, using: &rng)
                let fit = BuiltInMemoryFitPolicy.evaluate(variant: variant, physicalMemoryBytes: physical, recommendedWorkingSetBytes: workingSet)
                #expect(fit.budgetBytes >= 0)
                #expect(fit.contextTokenLimit >= 0)
                #expect(fit.contextTokenLimit <= min(variant.nativeContextTokens, BuiltInMemoryFitPolicy.maximumContextTokens))
            }
        }
    }

    @Test("8-bit KV is chosen exactly when 16-bit KV would fall short of the comfortable context size, never otherwise")
    func eightBitKVChosenOnlyWhenNeeded() {
        var rng = SplitMix64(seed: 90_210)
        for variant in BuiltInModelCatalog.variants {
            for _ in 0..<300 {
                let physical = Int64.random(in: gib...(512 * gib), using: &rng)
                let fit = BuiltInMemoryFitPolicy.evaluate(variant: variant, physicalMemoryBytes: physical, recommendedWorkingSetBytes: nil)
                // The (bits, start) pair is consistent on every path, refusals included.
                if fit.kvCacheBits == nil {
                    #expect(fit.kvQuantizationStartTokens == 0, "physical \(physical)")
                }
                guard fit.verdict != .insufficient else { continue }
                let forKV = fit.budgetBytes - variant.weightBytes - variant.fixedOverheadBytes
                let sixteenBitTokens = Int(forKV / Int64(Swift.max(variant.kvBytesPerToken, 1)))
                if fit.kvCacheBits == 8 {
                    #expect(sixteenBitTokens < BuiltInMemoryFitPolicy.comfortableContextTokens, "physical \(physical)")
                    // 16-bit is kept for as long as it fits, and never past its capacity.
                    #expect(fit.kvQuantizationStartTokens > 0, "physical \(physical)")
                    #expect(fit.kvQuantizationStartTokens < sixteenBitTokens, "physical \(physical)")
                    // One full reply plus a prefill chunk still fits at 16-bit.
                    #expect(
                        fit.kvQuantizationStartTokens + BuiltInMemoryFitPolicy.kvQuantizationHeadroomTokens
                            <= sixteenBitTokens, "physical \(physical)")
                    #expect(fit.kvQuantizationStartTokens < fit.contextTokenLimit, "physical \(physical)")
                } else {
                    #expect(fit.kvQuantizationStartTokens == 0, "physical \(physical)")
                    #expect(fit.kvCacheBits == nil, "physical \(physical)")
                    #expect(sixteenBitTokens >= BuiltInMemoryFitPolicy.comfortableContextTokens, "physical \(physical)")
                }
            }
        }
    }
}

// MARK: - Store

@Suite("BuiltInModelStore")
struct BuiltInModelStoreTests {
    private let payloads: [String: Data] = ["config.json": Data("{}".utf8), "model.safetensors": Data("weights".utf8)]

    @Test("a variant is installed only when every pinned file has the pinned size")
    func completenessRequiresEveryFile() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BuiltInModelStore(modelsRoot: root, huggingFaceHubRoot: nil)
        let variant = makeVariant(payloads: payloads)

        #expect(store.location(of: variant) == nil)
        #expect(throws: BuiltInModelError.notInstalled(variantName: variant.displayName)) {
            try store.installedDirectory(of: variant)
        }

        let directory = store.installDirectory(for: variant)
        try write(["config.json": payloads["config.json"]!], into: directory)
        #expect(store.location(of: variant) == nil)

        try write(["model.safetensors": Data("short".utf8)], into: directory)
        #expect(store.location(of: variant) == nil)

        try write(payloads, into: directory)
        #expect(store.location(of: variant) == .installed(directory))
    }

    @Test("adopts a complete Hugging Face cache snapshot through its symlinks and never removes it")
    func adoptsHuggingFaceCache() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let hub = root.appendingPathComponent("hub", isDirectory: true)
        let variant = makeVariant(payloads: payloads)
        let repoFolder = hub.appendingPathComponent("models--hype-tests--\(variant.id)", isDirectory: true)
        let blobs = repoFolder.appendingPathComponent("blobs", isDirectory: true)
        let snapshot = repoFolder.appendingPathComponent("snapshots/\(variant.revision)", isDirectory: true)
        try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        for (path, data) in payloads {
            let blob = blobs.appendingPathComponent(sha256Hex(data))
            try data.write(to: blob)
            try FileManager.default.createSymbolicLink(at: snapshot.appendingPathComponent(path), withDestinationURL: blob)
        }

        let store = BuiltInModelStore(modelsRoot: root.appendingPathComponent("Models"), huggingFaceHubRoot: hub)
        let location = try #require(store.location(of: variant))
        #expect(location == .huggingFaceCache(snapshot))
        #expect(!location.isRemovable)

        try store.remove(variant)
        #expect(store.location(of: variant) == .huggingFaceCache(snapshot))
    }

    @Test("remove deletes Hype's copy and its partial download")
    func removeDeletesOwnCopy() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BuiltInModelStore(modelsRoot: root, huggingFaceHubRoot: nil)
        let variant = makeVariant(payloads: payloads)
        try write(payloads, into: store.installDirectory(for: variant))
        try write(["model.safetensors": Data("we".utf8)], into: store.stagingDirectory(for: variant))
        #expect(store.diskUsageBytes(of: variant) > 0)

        try store.remove(variant)
        #expect(store.location(of: variant) == nil)
        #expect(!FileManager.default.fileExists(atPath: store.stagingDirectory(for: variant).path))
    }

    @Test("an incomplete Hugging Face cache snapshot (a partial `huggingface-cli download`) is ignored, not adopted")
    func incompleteHuggingFaceSnapshotIsIgnored() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let hub = root.appendingPathComponent("hub", isDirectory: true)
        let variant = makeVariant(payloads: payloads)
        let repoFolder = hub.appendingPathComponent("models--hype-tests--\(variant.id)", isDirectory: true)
        let blobs = repoFolder.appendingPathComponent("blobs", isDirectory: true)
        let snapshot = repoFolder.appendingPathComponent("snapshots/\(variant.revision)", isDirectory: true)
        try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        // Only one of the two pinned files is linked in the snapshot.
        let firstPath = try #require(payloads.keys.sorted().first)
        let data = try #require(payloads[firstPath])
        let blob = blobs.appendingPathComponent(sha256Hex(data))
        try data.write(to: blob)
        try FileManager.default.createSymbolicLink(at: snapshot.appendingPathComponent(firstPath), withDestinationURL: blob)

        let store = BuiltInModelStore(modelsRoot: root.appendingPathComponent("Models"), huggingFaceHubRoot: hub)
        #expect(store.location(of: variant) == nil)
        #expect(store.installedVariants().isEmpty)
    }

    @Test("a user-supplied model directory, recorded in a UserDefaults suite, takes precedence over both Hype's own copy and the Hugging Face cache")
    func userDirectoryOverrideTakesPrecedence() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let variant = makeVariant(payloads: payloads)

        // Hype's own (already installed) copy.
        try write(payloads, into: BuiltInModelStore(modelsRoot: root, huggingFaceHubRoot: nil).installDirectory(for: variant))

        // A directory the author pointed Hype at, e.g. a hand-quantized build.
        let userDirectory = root.appendingPathComponent("user-copy", isDirectory: true)
        try write(payloads, into: userDirectory)

        let suiteName = "hype.builtin.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(userDirectory.path, forKey: BuiltInModelSettings.modelDirectoryKeyPrefix + variant.id)

        let store = BuiltInModelStore(modelsRoot: root, huggingFaceHubRoot: nil, defaultsSuiteName: suiteName)
        let location = try #require(store.location(of: variant))
        #expect(location == .userDirectory(userDirectory))
        #expect(!location.isRemovable)

        // Clearing the override falls back to Hype's own installed copy.
        defaults.removeObject(forKey: BuiltInModelSettings.modelDirectoryKeyPrefix + variant.id)
        #expect(store.location(of: variant) == .installed(store.installDirectory(for: variant)))
    }

    @Test("diskUsageBytes counts installed and staged files together, and drops to zero after remove")
    func diskUsageAccounting() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BuiltInModelStore(modelsRoot: root, huggingFaceHubRoot: nil)
        let variant = makeVariant(payloads: payloads)
        #expect(store.diskUsageBytes(of: variant) == 0)

        try write(payloads, into: store.installDirectory(for: variant))
        let installedTotal = payloads.values.reduce(Int64(0)) { $0 + Int64($1.count) }
        let installedUsage = store.diskUsageBytes(of: variant)
        #expect(installedUsage >= installedTotal)

        let partial = Data(repeating: 1, count: 500)
        try write(["model.safetensors": partial], into: store.stagingDirectory(for: variant))
        #expect(store.diskUsageBytes(of: variant) >= installedUsage + Int64(partial.count))

        try store.remove(variant)
        #expect(store.diskUsageBytes(of: variant) == 0)
    }
}

// MARK: - Downloader

private final class BuiltInDownloadURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

/// Simulates an HTTP redirect: the first request to any host other than
/// `redirectTargetHost` is answered with a 3xx that points there, exercising
/// `URLSessionDataDelegate.willPerformHTTPRedirection` the same way a real CDN
/// redirect would.
private final class RedirectingURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var redirectTargetHost = "evil.example"
    nonisolated(unsafe) static var finalBody = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard request.url?.host != Self.redirectTargetHost else {
            // Only reached if the disallowed redirect was (incorrectly) followed.
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.finalBody)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        components.host = Self.redirectTargetHost
        let redirectedURL = components.url!
        let redirectResponse = HTTPURLResponse(
            url: request.url!, statusCode: 302, httpVersion: nil,
            headerFields: ["Location": redirectedURL.absoluteString])!
        var redirectedRequest = URLRequest(url: redirectedURL)
        redirectedRequest.httpMethod = request.httpMethod
        client?.urlProtocol(self, wasRedirectedTo: redirectedRequest, redirectResponse: redirectResponse)
    }

    override func stopLoading() {}
}

/// Streams a body a few bytes at a time with a delay in between, so a test can
/// cancel the download mid-flight and observe a genuinely partial file.
private final class SlowURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var chunkSize = 1000
    nonisolated(unsafe) static var totalChunks = 8
    nonisolated(unsafe) static var delayNanoseconds: UInt64 = 40_000_000

    private let stopped = LockedFlag()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        sendChunk(0)
    }

    private func sendChunk(_ index: Int) {
        guard !stopped.value else { return }
        if index >= Self.totalChunks {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        client?.urlProtocol(self, didLoad: Data(repeating: UInt8(index % 251), count: Self.chunkSize))
        DispatchQueue.global().asyncAfter(deadline: .now() + .nanoseconds(Int(Self.delayNanoseconds))) { [stopped] in
            guard !stopped.value else { return }
            self.sendChunk(index + 1)
        }
    }

    override func stopLoading() {
        stopped.value = true
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return flag }
        set { lock.lock(); flag = newValue; lock.unlock() }
    }
}

@Suite("BuiltInModelDownloader", .serialized)
struct BuiltInModelDownloaderTests {
    private let payloads: [String: Data] = [
        "config.json": Data(#"{"model_type":"test"}"#.utf8),
        "model.safetensors": Data((0..<4096).map { UInt8($0 % 251) }),
    ]

    private func makeDownloader(root: URL) -> (BuiltInModelDownloader, BuiltInModelStore) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BuiltInDownloadURLProtocol.self]
        let store = BuiltInModelStore(modelsRoot: root, huggingFaceHubRoot: nil)
        return (BuiltInModelDownloader(store: store, sessionConfiguration: configuration), store)
    }

    private func respond(_ request: URLRequest, status: Int, body: Data) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!, body)
    }

    @Test("downloads, verifies and activates a variant, reporting progress")
    func installsVerifiedVariant() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (downloader, store) = makeDownloader(root: root)
        let variant = makeVariant(payloads: payloads)
        let payloads = self.payloads
        BuiltInDownloadURLProtocol.handler = { request in
            let path = request.url!.lastPathComponent
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, payloads[path]!)
        }
        defer { BuiltInDownloadURLProtocol.handler = nil }

        let phases = PhaseRecorder()
        let directory = try await downloader.install(variant) { progress in phases.record(progress) }

        #expect(directory == store.installDirectory(for: variant))
        #expect(store.location(of: variant) == .installed(directory))
        #expect(try Data(contentsOf: directory.appendingPathComponent("model.safetensors")) == payloads["model.safetensors"])
        #expect(!FileManager.default.fileExists(atPath: store.stagingDirectory(for: variant).path))
        #expect(phases.last?.phase == .finished)
        #expect(phases.last?.fraction == 1)
    }

    @Test("a corrupted file is discarded and the variant stays uninstalled")
    func rejectsChecksumMismatch() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (downloader, store) = makeDownloader(root: root)
        let variant = makeVariant(payloads: payloads)
        let payloads = self.payloads
        BuiltInDownloadURLProtocol.handler = { request in
            let path = request.url!.lastPathComponent
            var body = payloads[path]!
            if path == "model.safetensors" { body[0] ^= 0xFF }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        defer { BuiltInDownloadURLProtocol.handler = nil }

        await #expect(throws: BuiltInModelDownloadError.checksumMismatch(path: "model.safetensors")) {
            try await downloader.install(variant) { _ in }
        }
        #expect(store.location(of: variant) == nil)
        let partial = store.stagingDirectory(for: variant).appendingPathComponent("model.safetensors")
        #expect(!FileManager.default.fileExists(atPath: partial.path))
    }

    @Test("a body larger than the pinned size is refused")
    func rejectsOversizedBody() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (downloader, store) = makeDownloader(root: root)
        let variant = makeVariant(payloads: payloads)
        let payloads = self.payloads
        BuiltInDownloadURLProtocol.handler = { request in
            let path = request.url!.lastPathComponent
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, payloads[path]! + Data(repeating: 0, count: 64))
        }
        defer { BuiltInDownloadURLProtocol.handler = nil }

        await #expect(throws: (any Error).self) {
            try await downloader.install(variant) { _ in }
        }
        #expect(store.location(of: variant) == nil)
    }

    @Test("resumes a partial file with a Range request")
    func resumesPartialDownload() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (downloader, store) = makeDownloader(root: root)
        let variant = makeVariant(payloads: payloads)
        let weights = payloads["model.safetensors"]!
        try write(["model.safetensors": weights.prefix(1000)], into: store.stagingDirectory(for: variant))

        let payloads = self.payloads
        let ranges = RangeRecorder()
        BuiltInDownloadURLProtocol.handler = { request in
            let path = request.url!.lastPathComponent
            if let range = request.value(forHTTPHeaderField: "Range") {
                ranges.record(range)
                let start = Int(range.dropFirst("bytes=".count).dropLast())!
                return (HTTPURLResponse(url: request.url!, statusCode: 206, httpVersion: nil, headerFields: nil)!, payloads[path]!.suffix(from: start))
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, payloads[path]!)
        }
        defer { BuiltInDownloadURLProtocol.handler = nil }

        let directory = try await downloader.install(variant) { _ in }
        #expect(ranges.values == ["bytes=1000-"])
        #expect(try Data(contentsOf: directory.appendingPathComponent("model.safetensors")) == weights)
    }

    @Test("a server that ignores the Range header and answers 200 restarts the file cleanly, not corruptly appended")
    func serverIgnoringRangeRestartsCleanly() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (downloader, store) = makeDownloader(root: root)
        let variant = makeVariant(payloads: payloads)
        let weights = payloads["model.safetensors"]!
        // A wrong prefix on disk: if the server's 200 response were naively
        // appended after it (instead of restarting), the file would come out
        // corrupt even though every byte of the "real" download was correct.
        try write(["model.safetensors": Data(repeating: 0xAA, count: 1000)], into: store.stagingDirectory(for: variant))

        let payloads = self.payloads
        BuiltInDownloadURLProtocol.handler = { request in
            let path = request.url!.lastPathComponent
            // Always answers 200 with the full body, ignoring any Range header.
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, payloads[path]!)
        }
        defer { BuiltInDownloadURLProtocol.handler = nil }

        let directory = try await downloader.install(variant) { _ in }
        #expect(try Data(contentsOf: directory.appendingPathComponent("model.safetensors")) == weights)
    }

    @Test("a file that is already fully staged is re-verified without a second network fetch")
    func reVerifiesAlreadyStagedFile() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (downloader, store) = makeDownloader(root: root)
        let variant = makeVariant(payloads: payloads)
        // config.json is already complete and correct in staging; only
        // model.safetensors should ever hit the network.
        try write(["config.json": payloads["config.json"]!], into: store.stagingDirectory(for: variant))

        let payloads = self.payloads
        let fetchedPaths = RangeRecorder()
        BuiltInDownloadURLProtocol.handler = { request in
            let path = request.url!.lastPathComponent
            fetchedPaths.record(path)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, payloads[path]!)
        }
        defer { BuiltInDownloadURLProtocol.handler = nil }

        let directory = try await downloader.install(variant) { _ in }
        #expect(store.location(of: variant) == .installed(directory))
        #expect(!fetchedPaths.values.contains("config.json"), "an already-complete staged file must not be re-downloaded")
        #expect(fetchedPaths.values.contains("model.safetensors"))
    }

    @Test("a zero-byte pinned file installs and verifies correctly")
    func zeroByteFileInstalls() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (downloader, store) = makeDownloader(root: root)
        let zeroBytePayloads: [String: Data] = ["config.json": Data(), "model.safetensors": payloads["model.safetensors"]!]
        let variant = makeVariant(payloads: zeroBytePayloads)
        BuiltInDownloadURLProtocol.handler = { request in
            let path = request.url!.lastPathComponent
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, zeroBytePayloads[path]!)
        }
        defer { BuiltInDownloadURLProtocol.handler = nil }

        let directory = try await downloader.install(variant) { _ in }
        #expect(store.location(of: variant) == .installed(directory))
        let configURL = directory.appendingPathComponent("config.json")
        #expect(FileManager.default.fileExists(atPath: configURL.path))
        #expect(BuiltInModelStore.fileSize(at: configURL) == 0)
    }

    @Test("a download that would exceed free disk space is refused before any network call")
    func insufficientDiskSpaceIsRefused() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (downloader, store) = makeDownloader(root: root)
        // Larger than any real disk, so the pre-flight free-space check must
        // refuse before a single byte is requested over the network.
        let variant = BuiltInModelVariant(
            id: "huge-variant",
            displayName: "Huge",
            summary: "fixture",
            tier: .standard,
            huggingFaceRepo: "hype-tests/huge",
            revision: "rev1",
            files: [BuiltInModelFile(path: "model.safetensors", size: Int64.max / 2, sha256: String(repeating: "0", count: 64))],
            license: "Apache-2.0",
            licenseURL: "https://example.invalid/license",
            kvBytesPerToken: 1024,
            fixedOverheadBytes: 1 << 20,
            nativeContextTokens: 262_144,
            minimumPhysicalMemoryGB: 8,
            recommendedPhysicalMemoryGB: 8,
            supportsVision: false,
            thinkingControl: .none
        )
        BuiltInDownloadURLProtocol.handler = { _ in throw URLError(.badServerResponse) }
        defer { BuiltInDownloadURLProtocol.handler = nil }

        do {
            _ = try await downloader.install(variant) { _ in }
            Issue.record("expected insufficientDiskSpace to be thrown")
        } catch let error as BuiltInModelDownloadError {
            guard case .insufficientDiskSpace(let required, let available) = error else {
                Issue.record("expected insufficientDiskSpace, got \(error)")
                return
            }
            #expect(required > available)
        }
        #expect(store.location(of: variant) == nil)
    }

    @Test("cancelling mid-download leaves a resumable partial file on disk and throws CancellationError")
    func cancellationLeavesResumablePartial() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SlowURLProtocol.self]
        let store = BuiltInModelStore(modelsRoot: root, huggingFaceHubRoot: nil)
        let downloader = BuiltInModelDownloader(store: store, sessionConfiguration: configuration)
        let fullSize = Int64(SlowURLProtocol.chunkSize * SlowURLProtocol.totalChunks)
        let variant = makeVariant(payloads: ["model.safetensors": Data(repeating: 0, count: Int(fullSize))])

        // Gate on the downloader's own progress callback (fired right after the
        // chunk is durably written via `FileSink.append`), not on the moment the
        // fake server hands data to URLLoading — that handoff is asynchronous and
        // can race ahead of the actual write, making the file still be 0 bytes.
        let gate = DownloadStartedGate()
        let task = Task {
            try await downloader.install(variant) { progress in
                if progress.completedBytes > 0 { Task { await gate.signal() } }
            }
        }
        await gate.waitForFirstChunk()
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }

        let partial = store.stagingDirectory(for: variant).appendingPathComponent("model.safetensors")
        let partialSize = BuiltInModelStore.fileSize(at: partial) ?? 0
        #expect(partialSize > 0, "a cancelled download should leave whatever was already written")
        #expect(partialSize < fullSize, "the file must not have been allowed to complete after cancellation")
    }

    @Test("a redirect to a host outside the Hugging Face allow-list is refused")
    func redirectToDisallowedHostIsRefused() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedirectingURLProtocol.self]
        let store = BuiltInModelStore(modelsRoot: root, huggingFaceHubRoot: nil)
        let downloader = BuiltInModelDownloader(store: store, sessionConfiguration: configuration)
        let variant = makeVariant(payloads: ["config.json": Data("{}".utf8)])
        RedirectingURLProtocol.redirectTargetHost = "evil.example"
        RedirectingURLProtocol.finalBody = Data("{}".utf8)

        do {
            _ = try await downloader.install(variant) { _ in }
            Issue.record("expected the redirect to a disallowed host to be refused")
        } catch let error as BuiltInModelDownloadError {
            guard case .disallowedHost(let host) = error else {
                Issue.record("expected disallowedHost, got \(error)")
                return
            }
            #expect(host == "evil.example")
        }
        #expect(store.location(of: variant) == nil)
    }

    @Test("HTTP failures surface with the file and status")
    func reportsHTTPFailure() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (downloader, _) = makeDownloader(root: root)
        let variant = makeVariant(payloads: payloads)
        BuiltInDownloadURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }
        defer { BuiltInDownloadURLProtocol.handler = nil }

        await #expect(throws: BuiltInModelDownloadError.unexpectedStatus(path: "config.json", status: 404)) {
            try await downloader.install(variant) { _ in }
        }
    }

    @Test("manifest paths cannot escape the model directory")
    func rejectsUnsafePaths() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (downloader, _) = makeDownloader(root: root)
        let variant = makeVariant(payloads: ["../escape.json": Data("x".utf8)])

        await #expect(throws: BuiltInModelDownloadError.invalidManifestPath("../escape.json")) {
            try await downloader.install(variant) { _ in }
        }
        for path in ["/etc/passwd", "a/../b", "a//b", "./a", "a\\b", ""] {
            #expect(!BuiltInModelDownloader.isSafeRelativePath(path), "\(path)")
        }
        #expect(BuiltInModelDownloader.isSafeRelativePath("nested/model-00001-of-00004.safetensors"))
    }

    @Test("only Hugging Face hosts are allowed, including after redirects")
    func hostAllowList() {
        for host in ["huggingface.co", "cdn-lfs.hf.co", "cas-bridge.xethub.hf.co", "CDN-LFS-US-1.HF.CO"] {
            #expect(BuiltInModelDownloader.isAllowed(host: host), "\(host)")
        }
        for host in ["evil.example", "huggingface.co.evil.example", "nothf.co", "xhuggingface.co", "", nil] as [String?] {
            #expect(!BuiltInModelDownloader.isAllowed(host: host), "\(host ?? "nil")")
        }
    }
}

private final class PhaseRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [BuiltInDownloadProgress] = []
    func record(_ value: BuiltInDownloadProgress) { lock.lock(); values.append(value); lock.unlock() }
    var last: BuiltInDownloadProgress? { lock.lock(); defer { lock.unlock() }; return values.last }
}

private final class RangeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    func record(_ value: String) { lock.lock(); recorded.append(value); lock.unlock() }
    var values: [String] { lock.lock(); defer { lock.unlock() }; return recorded }
}

/// Lets a test await "at least one chunk of the download has landed" instead
/// of guessing at a sleep duration, so the cancellation test cannot be flaky.
private actor DownloadStartedGate {
    private var armed = false
    private var continuation: CheckedContinuation<Void, Never>?

    func waitForFirstChunk() async {
        if armed { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func signal() {
        armed = true
        continuation?.resume()
        continuation = nil
    }
}

// MARK: - Client

@Suite("BuiltInModelClient", .serialized)
struct BuiltInModelClientTests {
    private let payloads: [String: Data] = ["config.json": Data("{}".utf8), "model.safetensors": Data("weights".utf8)]
    private let device = BuiltInDeviceProfile(physicalMemoryBytes: 64 * gib)

    private func makeInstalledClient(
        engine: FakeEngine,
        root: URL,
        thinking: Bool = false
    ) throws -> BuiltInModelClient {
        let store = BuiltInModelStore(modelsRoot: root, huggingFaceHubRoot: nil)
        let variant = makeVariant(payloads: payloads)
        try write(payloads, into: store.installDirectory(for: variant))
        return BuiltInModelClient(variant: variant, engine: engine, store: store, device: device, thinkingEnabled: thinking)
    }

    @Test("chat translates engine tool calls into Hype's chat vocabulary")
    func chatMapsToolCalls() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = FakeEngine()
        await engine.configure(result: BuiltInGenerationResult(
            text: "",
            thinking: "  ",
            toolCalls: [BuiltInToolCall(name: "create_button", arguments: ["name": "Go", "script": "go next"])]
        ))
        let client = try makeInstalledClient(engine: engine, root: root)
        let tool = OllamaTool(type: "function", function: OllamaFunction(
            name: "create_button",
            description: "Create a button",
            parameters: OllamaParameters(type: "object", properties: ["name": OllamaProperty(type: "string", description: "Name")], required: ["name"])
        ))

        let response = try await client.chat(
            messages: [OllamaMessage(role: "system", content: "rules"), OllamaMessage(role: "user", content: "add a Go button")],
            tools: [tool]
        )

        #expect(client.providerName == "built-in")
        #expect(client.modelName == "test-variant")
        #expect(response.done)
        #expect(response.message.role == "assistant")
        #expect(response.message.thinking == nil)
        let call = try #require(response.message.tool_calls?.first)
        #expect(call.function.name == "create_button")
        #expect(call.function.arguments == ["name": "Go", "script": "go next"])

        let request = try #require(await engine.requests.first)
        #expect(request.tools.map(\.function.name) == ["create_button"])
        #expect(request.messages.count == 2)
        #expect(request.enableThinking == false)
        #expect(request.contextTokenLimit >= BuiltInMemoryFitPolicy.minimumUsefulContextTokens)
        #expect(request.cacheBoundaryMarkers == ["CURRENT STATE:"])
        #expect(request.modelDirectory.lastPathComponent == "rev1")
    }

    @Test("generate sends system and user turns and returns plain text for `ask ai`")
    func generateBuildsMessages() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = FakeEngine()
        await engine.configure(result: BuiltInGenerationResult(text: "Paris"))
        let client = try makeInstalledClient(engine: engine, root: root)

        let answer = try await client.generate(prompt: "Capital of France?", model: "llama3.2", system: "Be brief.")

        #expect(answer == "Paris")
        let request = try #require(await engine.requests.first)
        #expect(request.messages.map(\.role) == ["system", "user"])
        #expect(request.messages.last?.content == "Capital of France?")
        #expect(request.tools.isEmpty)
        // A model name from another provider falls back to the selected variant.
        #expect(request.variant.id == "test-variant")
    }

    @Test("`ask ai … with model` can select another installed catalog variant, not just the one it was built with")
    func modelOverrideSelectsAnotherInstalledCatalogVariant() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BuiltInModelStore(modelsRoot: root, huggingFaceHubRoot: nil, integrity: .sizesOnly)

        // Install a real catalog variant under a different id than the client's
        // own (test-fixture) variant. Files are sparse, so this store checks
        // sizes only: no real disk space, no download, no meaningful hashes.
        let other = try #require(BuiltInModelCatalog.variant(tier: .standard))
        for file in other.files {
            try writeSparseFile(size: file.size, to: store.installDirectory(for: other).appendingPathComponent(file.path))
        }
        #expect(store.location(of: other) == .installed(store.installDirectory(for: other)))

        let engine = FakeEngine()
        await engine.configure(result: BuiltInGenerationResult(text: "from the other model"))
        let primary = makeVariant(id: "primary-test", payloads: payloads)
        // The primary variant is never installed: the override must resolve
        // and run entirely against `other` without touching primary's storage.
        let client = BuiltInModelClient(variant: primary, engine: engine, store: store, device: device)

        let answer = try await client.generate(prompt: "hi", model: other.id, system: nil)

        #expect(answer == "from the other model")
        #expect(client.modelName == "primary-test")
        let request = try #require(await engine.requests.first)
        #expect(request.variant.id == other.id)
    }

    @Test("structuredChat asks for the schema in the prompt and decodes tolerant JSON")
    func structuredChatDecodes() async throws {
        struct Plan: Decodable, Sendable, Equatable { let title: String }
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = FakeEngine()
        await engine.configure(result: BuiltInGenerationResult(text: "```json\n{\"title\": \"Maze\"}\n```"))
        let client = try makeInstalledClient(engine: engine, root: root)
        let schema = OllamaJSONSchema(object: [
            "type": "object",
            "properties": ["title": ["type": "string"]],
            "required": ["title"],
        ])

        let result: (response: OllamaChatResponse, decoded: Plan) = try await client.structuredChat(
            messages: [OllamaMessage(role: "user", content: "plan a game")],
            tools: [],
            format: .schema(schema)
        )

        #expect(result.decoded == Plan(title: "Maze"))
        let request = try #require(await engine.requests.first)
        let prompt = request.messages.compactMap(\.content).joined(separator: "\n")
        #expect(prompt.contains("title"))
        #expect(request.messages.count > 1)
    }

    @Test("structuredChat surfaces a decode failure when the reply cannot be parsed against the schema")
    func structuredChatDecodeFailure() async throws {
        struct Plan: Decodable, Sendable, Equatable { let title: String }
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = FakeEngine()
        await engine.configure(result: BuiltInGenerationResult(text: "That's a great question, but I won't answer in JSON."))
        let client = try makeInstalledClient(engine: engine, root: root)
        let schema = OllamaJSONSchema(object: [
            "type": "object",
            "properties": ["title": ["type": "string"]],
            "required": ["title"],
        ])

        await #expect(throws: OllamaError.self) {
            let _: (response: OllamaChatResponse, decoded: Plan) = try await client.structuredChat(
                messages: [OllamaMessage(role: "user", content: "plan a game")],
                tools: [],
                format: .schema(schema)
            )
        }
    }

    @Test("chatStream yields decoded text and reports failures as text")
    func chatStreamYieldsChunks() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = FakeEngine()
        await engine.configure(chunks: ["Hel", "lo"])
        let client = try makeInstalledClient(engine: engine, root: root)

        var received: [String] = []
        for await chunk in client.chatStream(messages: [OllamaMessage(role: "user", content: "hi")], tools: []) {
            received.append(chunk)
        }
        #expect(received == ["Hel", "lo"])

        await engine.configure(chunks: [], failure: .generationFailed("boom"))
        var failed: [String] = []
        for await chunk in client.chatStream(messages: [OllamaMessage(role: "user", content: "hi")], tools: []) {
            failed.append(chunk)
        }
        #expect(failed.joined().contains("boom"))
    }

    @Test("cancelling the consumer of chatStream stops generation without surfacing an error chunk")
    func chatStreamCancellation() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = FakeEngine()
        await engine.configure(hangsUntilCancelled: true)
        let client = try makeInstalledClient(engine: engine, root: root)

        let stream = client.chatStream(messages: [OllamaMessage(role: "user", content: "hi")], tools: [])
        let collector = Task {
            var received: [String] = []
            for await chunk in stream { received.append(chunk) }
            return received
        }
        await engine.waitUntilGenerateStarted()
        collector.cancel()
        let received = await collector.value

        #expect(received.isEmpty, "a cancelled stream must not surface a '[Built-in model error: …]' chunk")
        #expect(await engine.requests.count == 1)
    }

    @Test("an uninstalled variant explains where to download it and never reaches the engine")
    func uninstalledVariantIsReported() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = FakeEngine()
        let client = BuiltInModelClient(
            variant: makeVariant(payloads: payloads),
            engine: engine,
            store: BuiltInModelStore(modelsRoot: root, huggingFaceHubRoot: nil),
            device: device
        )

        await #expect(throws: BuiltInModelError.notInstalled(variantName: "Test Variant")) {
            _ = try await client.chat(messages: [OllamaMessage(role: "user", content: "hi")], tools: [])
        }
        #expect(await engine.requests.isEmpty)
        #expect(try await client.availableModels().isEmpty)
        #expect(BuiltInModelError.notInstalled(variantName: "X").errorDescription?.contains("Settings") == true)
    }

    @Test("a Mac below the variant's floor is refused before loading")
    func insufficientMemoryIsRefused() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = FakeEngine()
        let store = BuiltInModelStore(modelsRoot: root, huggingFaceHubRoot: nil)
        let variant = makeVariant(payloads: payloads, minimumGB: 96, recommendedGB: 128)
        try write(payloads, into: store.installDirectory(for: variant))
        let client = BuiltInModelClient(variant: variant, engine: engine, store: store, device: BuiltInDeviceProfile(physicalMemoryBytes: 32 * gib))

        await #expect(throws: BuiltInModelError.insufficientMemory(variantName: "Test Variant", requiredGB: 96, physicalGB: 32)) {
            try await client.preloadModel()
        }
        #expect(await engine.loads.isEmpty)
    }

    @Test("preloadModel loads the selected variant into the engine")
    func preloadLoadsVariant() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = FakeEngine()
        let client = try makeInstalledClient(engine: engine, root: root)
        try await client.preloadModel()
        #expect(await engine.loads == ["test-variant"])
    }
}

// MARK: - Provider wiring

@Suite("Built-in provider wiring", .serialized)
struct BuiltInProviderWiringTests {
    private func makeDefaults() throws -> UserDefaults {
        let name = "hype.builtin.tests.\(UUID().uuidString)"
        return try #require(UserDefaults(suiteName: name))
    }

    @Test("Built-in is a local provider: selectable and exempt from the cloud context opt-in")
    func providerIsLocal() {
        #expect(HypeAIProvider.builtIn.rawValue == "built-in")
        #expect(HypeAIProvider.allCases.contains(.builtIn))
        #expect(HypeAIProvider.builtIn.displayName == "Built-in (on-device)")
        #expect(HypeAIProvider.builtIn.requiresAIContextCloudOptIn == false)
    }

    @Test("Ollama stays the default provider")
    func defaultProviderUnchanged() throws {
        #expect(HypeAIConfiguration.selectedProvider(defaults: try makeDefaults()) == .ollama)
    }

    @Test("makeClient fails clearly when no engine is registered (CLI, tests)")
    func makeClientWithoutEngine() throws {
        let defaults = try makeDefaults()
        defaults.set(HypeAIProvider.builtIn.rawValue, forKey: HypeAIConfiguration.providerKey)
        BuiltInModelRuntime.register(engine: nil)

        #expect(throws: BuiltInModelError.engineUnavailable) {
            _ = try HypeAIConfiguration.makeClient(defaults: defaults)
        }
    }

    @Test("makeClient returns the Built-in client for an explicitly selected variant")
    func makeClientWithEngine() throws {
        let defaults = try makeDefaults()
        defaults.set(HypeAIProvider.builtIn.rawValue, forKey: HypeAIConfiguration.providerKey)
        let standard = try #require(BuiltInModelCatalog.variant(tier: .standard))
        defaults.set(standard.id, forKey: BuiltInModelSettings.variantKey)
        BuiltInModelRuntime.register(engine: FakeEngine())
        defer { BuiltInModelRuntime.register(engine: nil) }

        let client = try HypeAIConfiguration.makeClient(defaults: defaults)
        #expect(client.providerName == "built-in")
        #expect(client.modelName == standard.id)
        #expect(client.supportsChatStreaming)
    }

    @Test("an unknown variant identifier is rejected")
    func unknownVariant() {
        #expect(throws: BuiltInModelError.unknownVariant("nope")) {
            _ = try BuiltInModelClient.resolveVariant(
                id: "nope",
                store: BuiltInModelStore(modelsRoot: FileManager.default.temporaryDirectory, huggingFaceHubRoot: nil),
                device: BuiltInDeviceProfile(physicalMemoryBytes: 128 * gib)
            )
        }
    }

    @Test("Automatic names the variant for this Mac, or explains that the Mac is too small")
    func automaticVariantResolution() throws {
        let store = BuiltInModelStore(modelsRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), huggingFaceHubRoot: nil)
        let big = try BuiltInModelClient.resolveVariant(id: "auto", store: store, device: BuiltInDeviceProfile(physicalMemoryBytes: 128 * gib))
        #expect(big.tier == .max)
        let mid = try BuiltInModelClient.resolveVariant(id: "auto", store: store, device: BuiltInDeviceProfile(physicalMemoryBytes: 32 * gib))
        #expect(mid.tier == .standard)
        #expect(throws: BuiltInModelError.self) {
            _ = try BuiltInModelClient.resolveVariant(id: "auto", store: store, device: BuiltInDeviceProfile(physicalMemoryBytes: 16 * gib))
        }
    }

    @Test("SelectedAIScriptingProvider.currentModel() reports the Built-in provider's selected variant id, even an unknown one, without crashing")
    func selectedProviderCurrentModelForBuiltIn() throws {
        let defaults = try makeDefaults()
        defaults.set(HypeAIProvider.builtIn.rawValue, forKey: HypeAIConfiguration.providerKey)
        let provider = SelectedAIScriptingProvider(defaults: defaults)

        // An explicit, real catalog id resolves to itself regardless of this
        // test machine's memory or what is actually installed (`resolveVariant`
        // only checks fit/availability for the "auto" sentinel).
        let standard = try #require(BuiltInModelCatalog.variant(tier: .standard))
        defaults.set(standard.id, forKey: BuiltInModelSettings.variantKey)
        #expect(provider.currentModel() == standard.id)

        // A stale/unknown id (e.g. a variant retired from the catalog) must not
        // crash `currentModel()`; it is reported back as-is.
        defaults.set("not-a-real-variant", forKey: BuiltInModelSettings.variantKey)
        #expect(provider.currentModel() == "not-a-real-variant")
    }
}
