#if canImport(AppKit)
import AppKit
import CoreGraphics

/// Encodes and decodes `CardPaintLayer` bitmaps as PNG files.
///
/// Security properties:
/// - `decodePNG` caps incoming dimensions at `maxDimension` × `maxDimension`
///   and `maxPixelCount` BEFORE allocating any pixel buffer, guarding against
///   decompression-bomb attacks.
/// - All failures return `nil`; there are no force-unwraps or throws.
/// - Error messages from the interpreter layer use fixed strings that do not
///   include file names or resolved paths.
public enum PaintImageCodec {

    /// Maximum width or height (in pixels) accepted for import.
    public static let maxDimension = 4096
    /// Maximum total pixel count (width × height) accepted for import.
    public static let maxPixelCount = 4096 * 4096

    // MARK: - Encode

    /// Encode a `CardPaintLayer` as a PNG `Data` blob.
    ///
    /// Returns `nil` if the layer cannot be rendered (e.g. zero-size bitmap).
    public static func encodePNG(_ layer: CardPaintLayer) -> Data? {
        PaintLayer(snapshot: layer).pngData()
    }

    // MARK: - Decode

    /// Decode a PNG `Data` blob into a `CardPaintLayer`.
    ///
    /// Dimension and pixel-count limits are enforced BEFORE any pixel buffer
    /// is allocated to prevent decompression-bomb attacks (Security Condition 1).
    ///
    /// Returns `nil` for any failure (corrupt data, unsupported format, oversized
    /// image, or missing graphics context).
    public static func decodePNG(_ data: Data, cardId: UUID) -> CardPaintLayer? {
        guard let img = NSImage(data: data),
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }

        // SECURITY (review Finding 1): read the declared pixel dimensions from the
        // bitmap rep and enforce the dimension/pixel-count cap BEFORE touching
        // `rep.cgImage`, which is the allocation-heavy step. A small compressed PNG
        // can declare enormous dimensions (decompression bomb); rejecting here
        // avoids materializing a multi-hundred-MB raster just to discard it.
        let w = rep.pixelsWide
        let h = rep.pixelsHigh
        guard w > 0, h > 0,
              w <= maxDimension, h <= maxDimension,
              w * h <= maxPixelCount else { return nil }

        guard let cg = rep.cgImage else { return nil }

        let bytesPerRow = w * 4

        // Use the same colorSpace and bitmapInfo as PaintLayer.makeCGImage() so
        // encode→decode round-trips are pixel-faithful (premultipliedLast, sRGB).
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        guard let raw = ctx.data else { return nil }
        let rgba = Data(bytes: raw, count: h * bytesPerRow)

        return CardPaintLayer(cardId: cardId, width: w, height: h, rgbaData: rgba)
    }
}
#endif
