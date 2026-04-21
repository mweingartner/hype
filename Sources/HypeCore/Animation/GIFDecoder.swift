import Foundation
import ImageIO

/// Pure-function GIF decoder backed by the system `CGImageSource` API.
///
/// `decode(_:)` is safe to call from any thread (no shared state).
/// All resource limits are enforced **before** allocating frame
/// pixel buffers — the pixel-budget check reads frame dimensions
/// from the `CGImageSourceCopyPropertiesAtIndex` dictionary (a
/// metadata-only parse) and only proceeds to
/// `CGImageSourceCreateImageAtIndex` (the actual raster allocation)
/// when the running pixel total stays within `maxTotalPixels`.
///
/// Security Finding 1: `CopyPropertiesAtIndex` MUST come before
/// `CreateImageAtIndex` in the per-frame loop. Never reorder —
/// "check + allocate" prevents the 256 MB pre-allocation leak that
/// the "allocate + check" pattern would produce.
public enum GIFDecoder {

    /// Maximum number of frames that will be decoded from a single GIF.
    public static let maxFrameCount: Int = 500

    /// Maximum cumulative pixel count (width × height) across all
    /// decoded frames. 64 MP × 4 bytes/pixel ≈ 256 MB worst-case.
    public static let maxTotalPixels: Int = 64 * 1024 * 1024

    /// Frame delays below this threshold are treated as suspiciously
    /// fast and clamped to `clampedMinFrameDelay`.
    public static let minFrameDelay: Double = 0.020

    /// Replacement delay used when the source value is ≤ `minFrameDelay`.
    /// Matches the Blink/Gecko/WebKit 100 ms floor.
    public static let clampedMinFrameDelay: Double = 0.100

    /// Decode `data` as an animated GIF.
    ///
    /// Returns `nil` when:
    /// - The bytes are not a valid GIF (UTI check).
    /// - The source contains fewer than 2 frames (single-frame GIFs
    ///   use the static `NSImage` path; no animator needed).
    /// - The frame count exceeds `maxFrameCount`.
    /// - The cumulative pixel budget would exceed `maxTotalPixels`
    ///   (pixel check is done from metadata BEFORE allocating frames).
    public static func decode(_ data: Data) -> DecodedGIF? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        // Verify the source is a GIF — reject JPEG, PNG, and
        // anything else that might arrive in imageData.
        guard let uti = CGImageSourceGetType(source) as String?,
              uti == "com.compuserve.gif" else {
            return nil
        }

        let frameCount = CGImageSourceGetCount(source)

        // Single-frame GIF: hand off to the static NSImage path.
        guard frameCount >= 2 else {
            return nil
        }

        // Hard cap on frame count before doing any per-frame work.
        guard frameCount <= maxFrameCount else {
            return nil
        }

        // Read the top-level loop count from the GIF properties.
        let loopCount: Int
        if let topProps = CGImageSourceCopyProperties(source, nil) as? [CFString: Any],
           let gifDict = topProps[kCGImagePropertyGIFDictionary] as? [CFString: Any],
           let lc = gifDict[kCGImagePropertyGIFLoopCount] as? Int {
            loopCount = lc
        } else {
            loopCount = 0  // default: infinite loop
        }

        var frames: [CGImage] = []
        var frameDelays: [Double] = []
        frames.reserveCapacity(frameCount)
        frameDelays.reserveCapacity(frameCount)

        // Use Int64 for the running total to avoid any overflow risk
        // from crafted or corrupt dimensions (Security Finding M-4,
        // post-Builder code review). Max legitimate GIF dims per frame
        // are 65535×65535 ≈ 4.3B; 500 such frames max ≈ 2.1T, well
        // inside Int64. Negative values from bridging failures would
        // otherwise underflow and pass the budget guard.
        var runningPixels: Int64 = 0
        let budget64: Int64 = Int64(maxTotalPixels)

        for i in 0 ..< frameCount {
            // STEP 1 — read pixel dimensions from metadata.
            // CGImageSourceCopyPropertiesAtIndex only parses the frame
            // descriptor; it does NOT trigger raster decode / allocation.
            // This is INTENTIONALLY before CGImageSourceCreateImageAtIndex.
            guard let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any] else {
                return nil
            }

            let frameWidth  = (props[kCGImagePropertyPixelWidth]  as? Int) ?? 0
            let frameHeight = (props[kCGImagePropertyPixelHeight] as? Int) ?? 0
            // Reject non-positive dimensions defensively — they are
            // nonsensical and would let a crafted file slip past the
            // pixel budget with a zero or negative running total.
            guard frameWidth > 0, frameHeight > 0 else { return nil }
            let framePixels = Int64(frameWidth) * Int64(frameHeight)

            // STEP 2 — pixel-budget check BEFORE allocating the frame.
            runningPixels += framePixels
            guard runningPixels <= budget64 else {
                return nil
            }

            // STEP 3 — read per-frame delay from the same dictionary.
            let rawDelay: Double
            if let gifDict = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                // Prefer the unclamped value; fall back to the clamped one.
                if let unclamped = gifDict[kCGImagePropertyGIFUnclampedDelayTime] as? Double,
                   unclamped > 0 {
                    rawDelay = unclamped
                } else if let clamped = gifDict[kCGImagePropertyGIFDelayTime] as? Double {
                    rawDelay = clamped
                } else {
                    rawDelay = clampedMinFrameDelay
                }
            } else {
                rawDelay = clampedMinFrameDelay
            }

            // Apply the 100 ms floor for values at or below 20 ms.
            let delay = rawDelay <= minFrameDelay ? clampedMinFrameDelay : rawDelay

            // STEP 4 — allocate the raster only after the budget check passes.
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else {
                return nil
            }

            frames.append(cgImage)
            frameDelays.append(delay)
        }

        return DecodedGIF(frames: frames, frameDelays: frameDelays, loopCount: loopCount)
    }
}

/// The result of a successful GIF decode.
public struct DecodedGIF: Sendable {
    /// Decoded raster frames in display order.
    public let frames: [CGImage]
    /// Per-frame display duration in seconds, parallel to `frames`.
    public let frameDelays: [Double]
    /// Number of times to play the animation. `0` means loop forever.
    public let loopCount: Int

    public init(frames: [CGImage], frameDelays: [Double], loopCount: Int) {
        self.frames = frames
        self.frameDelays = frameDelays
        self.loopCount = loopCount
    }
}
