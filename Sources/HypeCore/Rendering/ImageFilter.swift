import Foundation
#if canImport(AppKit)
import AppKit
import CoreImage

/// Applies a CoreImage filter to a `CGImage` based on a friendly
/// name from `Part.imageFilter`. Returns the original image
/// unchanged when the filter name is empty or unrecognized — never
/// crashes, never blocks. Cached per (image identity, filter name,
/// intensity) tuple so re-rendering on every `draw()` doesn't pay
/// the filter cost more than once per change.
public enum ImageFilter {

    /// Friendly names mapped to CIFilter names. Some entries are
    /// presets that bind a specific filter; others (sepia, blur,
    /// vignette) take an intensity parameter at apply time.
    public static let recognizedNames: Set<String> = [
        "", "none",
        "sepia", "blackwhite", "mono", "noir",
        "blur", "vignette",
        "invert", "posterize",
        "comic", "process", "transfer", "instant",
        "fade", "tonal", "chrome"
    ]

    /// Apply the named filter to `image`. `intensity` is 0..1 and
    /// affects sepia / blur / vignette / posterize. Returns the
    /// original image when the filter name isn't recognized.
    public static func apply(_ rawName: String, intensity: Double, to image: CGImage) -> CGImage {
        let name = rawName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != "none" else { return image }

        // Cache key.
        let key = CacheKey(
            objectId: ObjectIdentifier(image),
            name: name,
            intensity: Int(intensity * 1000)
        )
        if let cached = lookupCache(key) {
            return cached
        }

        let ci = CIImage(cgImage: image)
        let filterName = ciFilterName(for: name)
        guard let filter = CIFilter(name: filterName) else { return image }

        filter.setDefaults()
        filter.setValue(ci, forKey: kCIInputImageKey)

        // Bind intensity-style params per filter.
        let amount = max(0, min(1, intensity))
        switch name {
        case "sepia":
            filter.setValue(amount, forKey: kCIInputIntensityKey)
        case "blur":
            // Up to ~30 px radius at full intensity for a noticeable blur.
            filter.setValue(amount * 30, forKey: kCIInputRadiusKey)
        case "vignette":
            // Radius and intensity both move with `intensity`.
            filter.setValue(amount * 4, forKey: kCIInputIntensityKey)
            filter.setValue(amount * 30, forKey: kCIInputRadiusKey)
        case "posterize":
            // 2..10 levels — fewer = more posterized.
            filter.setValue(2 + (1 - amount) * 8, forKey: "inputLevels")
        default:
            break
        }

        guard let output = filter.outputImage else { return image }
        let context = sharedCIContext
        guard let result = context.createCGImage(output, from: output.extent) else {
            return image
        }
        storeInCache(key, result: result)
        return result
    }

    private static func ciFilterName(for friendlyName: String) -> String {
        switch friendlyName {
        case "sepia":         return "CISepiaTone"
        case "blackwhite":    return "CIPhotoEffectMono"
        case "mono":          return "CIPhotoEffectMono"
        case "noir":          return "CIPhotoEffectNoir"
        case "blur":          return "CIGaussianBlur"
        case "vignette":      return "CIVignette"
        case "invert":        return "CIColorInvert"
        case "posterize":     return "CIColorPosterize"
        case "comic":         return "CIComicEffect"
        case "process":       return "CIPhotoEffectProcess"
        case "transfer":      return "CIPhotoEffectTransfer"
        case "instant":       return "CIPhotoEffectInstant"
        case "fade":          return "CIPhotoEffectFade"
        case "tonal":         return "CIPhotoEffectTonal"
        case "chrome":        return "CIPhotoEffectChrome"
        default:              return ""
        }
    }

    // MARK: - Cache (small LRU)

    private struct CacheKey: Hashable {
        let objectId: ObjectIdentifier
        let name: String
        let intensity: Int
    }

    /// 32-entry LRU. Keyed by source-image pointer + filter + intensity.
    /// Reset across launches; transient CGImage identifiers shouldn't
    /// outlive the host process.
    ///
    /// Locked behind `cacheLock` rather than `@MainActor` so tests
    /// (and any non-main-thread renderer paths added in the future)
    /// don't trip a `MainActor.assumeIsolated` precondition crash
    /// when they call into the cache lazily.
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [CacheKey: CGImage] = [:]
    nonisolated(unsafe) private static var cacheOrder: [CacheKey] = []
    private static let cacheLimit = 32

    private static func lookupCache(_ key: CacheKey) -> CGImage? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let hit = cache[key] {
            if let idx = cacheOrder.firstIndex(of: key) {
                cacheOrder.remove(at: idx)
            }
            cacheOrder.append(key)
            return hit
        }
        return nil
    }

    private static func storeInCache(_ key: CacheKey, result: CGImage) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if cacheOrder.count >= cacheLimit, let oldest = cacheOrder.first {
            cacheOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }
        cache[key] = result
        cacheOrder.append(key)
    }

    /// Singleton CI context. Software-only — fast enough for 1024×768
    /// thumbnails and avoids allocating GPU resources for what may be
    /// only a one-frame filter pass.
    private static let sharedCIContext: CIContext = {
        let ctx = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            .priorityRequestLow: NSNumber(value: true)
        ])
        return ctx
    }()
}
#endif
