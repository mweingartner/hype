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

    /// Draw a filled or stroked rectangle.
    public func drawRect(x: Int, y: Int, width w: Int, height h: Int, color: NSColor, filled: Bool) {
        if filled {
            for py in y..<(y + h) {
                for px in x..<(x + w) {
                    plot(x: px, y: py, color: color)
                }
            }
        } else {
            drawLine(x0: x, y0: y, x1: x + w, y1: y, color: color)
            drawLine(x0: x + w, y0: y, x1: x + w, y1: y + h, color: color)
            drawLine(x0: x + w, y0: y + h, x1: x, y1: y + h, color: color)
            drawLine(x0: x, y0: y + h, x1: x, y1: y, color: color)
        }
    }

    /// Draw a filled or stroked oval.
    public func drawOval(cx: Int, cy: Int, rx: Int, ry: Int, color: NSColor, filled: Bool) {
        // Draw outline using parametric sampling
        for angle in stride(from: 0.0, to: Double.pi * 2, by: 0.01) {
            let px = cx + Int(Double(rx) * cos(angle))
            let py = cy + Int(Double(ry) * sin(angle))
            plot(x: px, y: py, color: color)
        }
        if filled {
            for y in (cy - ry)...(cy + ry) {
                let dy = Double(y - cy)
                let denom = Double(ry * ry)
                guard denom > 0 else { continue }
                let halfWidth = Double(rx) * sqrt(max(0, 1.0 - (dy * dy) / denom))
                for x in (cx - Int(halfWidth))...(cx + Int(halfWidth)) {
                    plot(x: x, y: y, color: color)
                }
            }
        }
    }

    /// Draw a rounded rectangle.
    public func drawRoundRect(x: Int, y: Int, width w: Int, height h: Int, radius r: Int, color: NSColor, filled: Bool) {
        if filled {
            // Fill the body
            for py in (y + r)..<(y + h - r) {
                for px in x..<(x + w) {
                    plot(x: px, y: py, color: color)
                }
            }
            // Fill corners with arc
            drawOval(cx: x + r, cy: y + r, rx: r, ry: r, color: color, filled: true)
            drawOval(cx: x + w - r, cy: y + r, rx: r, ry: r, color: color, filled: true)
            drawOval(cx: x + w - r, cy: y + h - r, rx: r, ry: r, color: color, filled: true)
            drawOval(cx: x + r, cy: y + h - r, rx: r, ry: r, color: color, filled: true)
            // Fill top/bottom strips
            for py in y..<(y + r) {
                for px in (x + r)..<(x + w - r) {
                    plot(x: px, y: py, color: color)
                }
            }
            for py in (y + h - r)..<(y + h) {
                for px in (x + r)..<(x + w - r) {
                    plot(x: px, y: py, color: color)
                }
            }
        } else {
            drawLine(x0: x + r, y0: y, x1: x + w - r, y1: y, color: color)
            drawLine(x0: x + w, y0: y + r, x1: x + w, y1: y + h - r, color: color)
            drawLine(x0: x + w - r, y0: y + h, x1: x + r, y1: y + h, color: color)
            drawLine(x0: x, y0: y + h - r, x1: x, y1: y + r, color: color)
        }
    }

    /// Spray random dots in a radius (like a spray can).
    public func spray(cx: Int, cy: Int, radius: Int, density: Int, color: NSColor) {
        for _ in 0..<density {
            let angle = Double.random(in: 0..<Double.pi * 2)
            let dist = Double.random(in: 0..<Double(radius))
            let px = cx + Int(dist * cos(angle))
            let py = cy + Int(dist * sin(angle))
            plot(x: px, y: py, color: color)
        }
    }

    /// Erase a circular area (set pixels to transparent).
    public func erase(cx: Int, cy: Int, radius: Int) {
        for dy in -radius...radius {
            for dx in -radius...radius {
                if dx * dx + dy * dy <= radius * radius {
                    let px = cx + dx
                    let py = cy + dy
                    guard px >= 0, py >= 0, px < width, py < height else { continue }
                    let offset = (py * width + px) * 4
                    guard offset + 3 < imageData.count else { continue }
                    imageData[offset] = 0
                    imageData[offset + 1] = 0
                    imageData[offset + 2] = 0
                    imageData[offset + 3] = 0
                }
            }
        }
    }

    /// Flood fill from a point with the given color.
    public func floodFill(x: Int, y: Int, color: NSColor) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        let targetOffset = (y * width + x) * 4
        guard targetOffset + 3 < imageData.count else { return }
        let targetR = imageData[targetOffset]
        let targetG = imageData[targetOffset + 1]
        let targetB = imageData[targetOffset + 2]
        let targetA = imageData[targetOffset + 3]

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.usingColorSpace(.sRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        let newR = UInt8(r * 255), newG = UInt8(g * 255), newB = UInt8(b * 255), newA = UInt8(a * 255)

        // Don't fill if already the target color
        if targetR == newR && targetG == newG && targetB == newB && targetA == newA { return }

        var stack: [(Int, Int)] = [(x, y)]
        var visited = Set<Int>()

        while let (cx, cy) = stack.popLast() {
            let key = cy * width + cx
            guard cx >= 0, cy >= 0, cx < width, cy < height else { continue }
            guard !visited.contains(key) else { continue }

            let off = key * 4
            guard off + 3 < imageData.count else { continue }
            guard imageData[off] == targetR && imageData[off + 1] == targetG &&
                  imageData[off + 2] == targetB && imageData[off + 3] == targetA else { continue }

            visited.insert(key)
            imageData[off] = newR
            imageData[off + 1] = newG
            imageData[off + 2] = newB
            imageData[off + 3] = newA

            stack.append((cx + 1, cy))
            stack.append((cx - 1, cy))
            stack.append((cx, cy + 1))
            stack.append((cx, cy - 1))
        }
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
