import Foundation
#if canImport(AppKit)
import AppKit

/// A bitmap paint layer for card-level drawing (pencil, shapes, etc.)
public final class PaintLayer: @unchecked Sendable {
    public let width: Int
    public let height: Int
    private var imageData: Data

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.imageData = Data(count: width * height * 4) // RGBA
    }

    /// Draw a pixel at (x, y) with the given color.
    public func plot(x: Int, y: Int, color: NSColor) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        let offset = (y * width + x) * 4
        guard offset + 3 < imageData.count else { return }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.usingColorSpace(.sRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        imageData[offset] = UInt8(r * 255)
        imageData[offset + 1] = UInt8(g * 255)
        imageData[offset + 2] = UInt8(b * 255)
        imageData[offset + 3] = UInt8(a * 255)
    }

    /// Draw a line from (x0, y0) to (x1, y1) using Bresenham's algorithm.
    public func drawLine(x0: Int, y0: Int, x1: Int, y1: Int, color: NSColor) {
        var x = x0, y = y0
        let dx = abs(x1 - x0), dy = abs(y1 - y0)
        let sx = x0 < x1 ? 1 : -1
        let sy = y0 < y1 ? 1 : -1
        var err = dx - dy

        while true {
            plot(x: x, y: y, color: color)
            if x == x1 && y == y1 { break }
            let e2 = 2 * err
            if e2 > -dy { err -= dy; x += sx }
            if e2 < dx { err += dx; y += sy }
        }
    }

    /// Render the paint layer onto a CGContext.
    public func render(into ctx: CGContext) {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: imageData as CFData),
              let cgImage = CGImage(
                width: width, height: height,
                bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil, shouldInterpolate: false,
                intent: .defaultIntent
              ) else { return }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    /// Clear the paint layer.
    public func clear() {
        imageData = Data(count: width * height * 4)
    }

    /// Check if the layer is entirely empty.
    public var isEmpty: Bool {
        imageData.allSatisfy { $0 == 0 }
    }
}
#endif
