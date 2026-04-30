import Foundation

#if canImport(AppKit)
import AppKit
import CoreGraphics

/// Auto-detects an image's "background color" from its corner
/// pixels and produces a copy with that color masked out to alpha
/// zero. Used by `ImageRenderer` when `Part.transparentBackground`
/// is `true` so JPGs and indexed-GIFs (which carry no alpha
/// channel) can show whatever's behind them on the card.
///
/// **Algorithm**
/// 1. Sample the four corner pixels (1px in from each edge to
///    avoid sub-pixel anti-aliasing artifacts at the very edge).
/// 2. Pick the color that appears in the most corners — usually
///    that's the dominant background. If all four differ, fall
///    back to the top-left corner.
/// 3. Walk every pixel of the image. For each pixel whose RGB
///    distance to the key color is below `tolerance`, set its
///    alpha component to 0. Other pixels keep their original
///    alpha (so semi-transparent edges from a real PNG alpha
///    channel are preserved).
/// 4. Return a new `CGImage` backed by the modified pixel buffer.
///
/// **Caching** — chroma-keying is O(N) in pixels, expensive for
/// large images and per-frame for animated GIFs. We cache the
/// produced image keyed on `(sourceCGImage.address, tolerance,
/// keyHint)` so subsequent renders of the same source skip the
/// pixel walk. The cache is bounded to ~64 entries via LRU
/// eviction so memory doesn't grow unboundedly across long
/// authoring sessions.
public enum ImageChromaKey {

    /// Color-distance tolerance (sum of |dR|+|dG|+|dB|, each
    /// channel 0-255). 24 ≈ allows ~8 levels of variation per
    /// channel — generous enough for JPEG compression noise but
    /// tight enough not to bleed into similar-looking content
    /// (e.g. a logo on a white background where the logo has
    /// nearly-white highlights).
    public static let defaultTolerance: Int = 24

    /// Mask out the dominant corner color of `source` to alpha 0.
    /// Returns the cached or freshly-computed transparent image.
    /// Returns the original on any failure (no exceptions thrown).
    public static func apply(
        to source: CGImage,
        tolerance: Int = defaultTolerance
    ) -> CGImage {
        // Cache key uses the CGImage's pointer identity, which is
        // stable while the image is held alive (CGImage is
        // reference-counted under the hood). Different decodes of
        // the same byte buffer get different pointers — we treat
        // them as distinct cache entries; the worst case is one
        // extra computation per re-decode, never wrong output.
        let key = CacheKey(
            ptr: ObjectIdentifier(source as AnyObject),
            tolerance: tolerance
        )
        return cache.value(forKey: key) ?? {
            let result = compute(source: source, tolerance: tolerance) ?? source
            cache.set(result, forKey: key)
            return result
        }()
    }

    /// Drop the cached transparent image for `source` — call this
    /// when an image's data changes underneath us so a stale
    /// version doesn't keep rendering. (Currently uncalled; placed
    /// here for future use if `Part.imageData` setters want to
    /// force a refresh.)
    public static func invalidate(_ source: CGImage) {
        let key = CacheKey(
            ptr: ObjectIdentifier(source as AnyObject),
            tolerance: defaultTolerance
        )
        cache.remove(forKey: key)
    }

    // MARK: - Implementation

    private static func compute(source: CGImage, tolerance: Int) -> CGImage? {
        let width = source.width
        let height = source.height
        guard width > 0, height > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        let bitmapInfo: UInt32 = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue

        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        ctx.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let buffer = ctx.data else { return nil }

        let pixels = buffer.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)

        // Pick the key color from the most-common corner.
        let corners: [(Int, Int)] = [
            (1, 1),
            (width - 2, 1),
            (1, height - 2),
            (width - 2, height - 2),
        ].map { ($0.0.clamped(0, width - 1), $0.1.clamped(0, height - 1)) }

        var samples: [(r: UInt8, g: UInt8, b: UInt8)] = []
        for (x, y) in corners {
            let i = y * bytesPerRow + x * 4
            samples.append((pixels[i], pixels[i + 1], pixels[i + 2]))
        }
        let key = mostCommon(samples)
        let kr = Int(key.r), kg = Int(key.g), kb = Int(key.b)

        // Walk every pixel, zero alpha where (r,g,b) ~ key.
        // Premultiplied-alpha buffer: when alpha=0, all channels
        // must be 0 to avoid visual artifacts during compositing.
        for y in 0..<height {
            let rowStart = y * bytesPerRow
            for x in 0..<width {
                let i = rowStart + x * 4
                let dr = abs(Int(pixels[i]) - kr)
                let dg = abs(Int(pixels[i + 1]) - kg)
                let db = abs(Int(pixels[i + 2]) - kb)
                if dr + dg + db <= tolerance {
                    pixels[i] = 0
                    pixels[i + 1] = 0
                    pixels[i + 2] = 0
                    pixels[i + 3] = 0
                }
            }
        }

        return ctx.makeImage()
    }

    private static func mostCommon(_ samples: [(r: UInt8, g: UInt8, b: UInt8)])
        -> (r: UInt8, g: UInt8, b: UInt8)
    {
        guard !samples.isEmpty else { return (255, 255, 255) }
        var counts: [SIMD3<UInt8>: Int] = [:]
        for s in samples {
            let key = SIMD3<UInt8>(s.r, s.g, s.b)
            counts[key, default: 0] += 1
        }
        let winner = counts.max { $0.value < $1.value }!.key
        return (winner.x, winner.y, winner.z)
    }

    // MARK: - Bounded cache

    private struct CacheKey: Hashable {
        let ptr: ObjectIdentifier
        let tolerance: Int
    }

    /// Bounded LRU cache backed by an array for eviction order.
    /// 64 entries is plenty for typical authoring sessions; large
    /// stacks with hundreds of distinct images will see eviction
    /// but never unbounded memory growth.
    private final class LRUCache<K: Hashable, V> {
        private var storage: [K: V] = [:]
        private var order: [K] = []
        private let capacity: Int
        private let lock = NSLock()

        init(capacity: Int) { self.capacity = capacity }

        func value(forKey key: K) -> V? {
            lock.lock(); defer { lock.unlock() }
            guard let v = storage[key] else { return nil }
            // Move to most-recently-used.
            if let i = order.firstIndex(of: key) {
                order.remove(at: i)
                order.append(key)
            }
            return v
        }

        func set(_ v: V, forKey key: K) {
            lock.lock(); defer { lock.unlock() }
            if storage[key] == nil {
                order.append(key)
            } else if let i = order.firstIndex(of: key) {
                order.remove(at: i)
                order.append(key)
            }
            storage[key] = v
            while order.count > capacity {
                let evict = order.removeFirst()
                storage.removeValue(forKey: evict)
            }
        }

        func remove(forKey key: K) {
            lock.lock(); defer { lock.unlock() }
            storage.removeValue(forKey: key)
            order.removeAll { $0 == key }
        }
    }

    nonisolated(unsafe) private static let cache = LRUCache<CacheKey, CGImage>(capacity: 64)
}

private extension Int {
    func clamped(_ low: Int, _ high: Int) -> Int {
        Swift.min(Swift.max(self, low), high)
    }
}

#endif
