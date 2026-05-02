import Foundation
#if canImport(AppKit)
import AppKit

// MARK: - CardImageCapturer

/// Renders a Hype card to a PNG image and returns it as a base64-encoded string.
///
/// Used by `HypeToolExecutor` to satisfy `capture_card_image` tool calls. The capturer
/// delegates to `CardRenderer` for actual pixel rendering and handles size capping,
/// PNG encoding, and base64 conversion.
///
/// ## Main-actor requirement
/// All rendering must occur on the main actor because `CardRenderer.renderToImage` is
/// `@MainActor`. Mark call sites accordingly.
@MainActor
public struct CardImageCapturer: Sendable {

    // MARK: - Error types

    /// Errors that can occur during a card capture.
    public enum CaptureError: Error, Equatable {
        /// The document contains no cards.
        case noCardLoaded
        /// A named card was requested but not found (case-insensitive lookup).
        case cardNotFound(name: String)
        /// `CardRenderer.renderToImage` returned a degenerate image.
        case renderFailed
        /// PNG bitmap representation could not be produced from the rendered image.
        case encodingFailed
        /// The encoded PNG exceeds `CardCaptureResult.maxImageBytes` even after
        /// a resolution-reduction retry.
        case imageTooLarge(bytes: Int)
    }

    // MARK: - Initializer

    public init() {}

    // MARK: - Public API

    /// Render a card to a PNG and return base64-encoded image data plus metadata.
    ///
    /// - Parameters:
    ///   - cardName: Optional card name. When `nil` or empty, the `currentCardId` is used.
    ///               Card lookup is case-insensitive.
    ///   - document: The document containing the card to render.
    ///   - currentCardId: Fallback card UUID when `cardName` is nil or empty.
    ///   - maxLongEdge: Maximum dimension (width or height) of the rendered image in pixels.
    ///                  The image is scaled proportionally to fit within this constraint.
    ///                  Defaults to 1024.
    /// - Returns: A tuple of (cardId, cardName, pixelWidth, pixelHeight, imageBase64).
    ///   - `cardName` is the verbatim name from the document, or `""` if the card has no name.
    ///   - `imageBase64` is the raw base64 PNG string with no line breaks and no data: prefix.
    /// - Throws: `CaptureError` if the card cannot be found, rendered, or encoded.
    public func capture(
        cardName: String?,
        document: HypeDocument,
        currentCardId: UUID,
        maxLongEdge: Int = 1024
    ) throws -> (cardId: UUID, cardName: String, pixelWidth: Int, pixelHeight: Int, imageBase64: String) {
        // Resolve which card to capture.
        let resolvedCardId: UUID
        let resolvedCardName: String

        let trimmedName = cardName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedName.isEmpty {
            // No name specified — use the current card.
            guard !document.cards.isEmpty else { throw CaptureError.noCardLoaded }
            resolvedCardId = currentCardId
            resolvedCardName = document.cards.first(where: { $0.id == currentCardId })?.name ?? ""
        } else {
            // Find by case-insensitive name match.
            guard !document.cards.isEmpty else { throw CaptureError.noCardLoaded }
            guard let card = document.cards.first(where: { $0.name.lowercased() == trimmedName.lowercased() }) else {
                throw CaptureError.cardNotFound(name: trimmedName)
            }
            resolvedCardId = card.id
            resolvedCardName = card.name
        }

        // Compute scaled target size. Cap the long edge to maxLongEdge, preserve aspect ratio.
        let canvasWidth = Double(document.stack.width)
        let canvasHeight = Double(document.stack.height)
        let maxEdge = Double(maxLongEdge)

        let scale: Double
        if canvasWidth >= canvasHeight {
            scale = min(1.0, maxEdge / canvasWidth)
        } else {
            scale = min(1.0, maxEdge / canvasHeight)
        }

        let targetWidth = max(1, Int(canvasWidth * scale))
        let targetHeight = max(1, Int(canvasHeight * scale))
        let targetSize = NSSize(width: targetWidth, height: targetHeight)

        // Render the card to an NSImage.
        let renderer = CardRenderer()
        let nsImage = renderer.renderToImage(
            document: document,
            cardId: resolvedCardId,
            size: targetSize
        )

        // Verify the image is not degenerate.
        guard nsImage.size.width > 0, nsImage.size.height > 0 else {
            throw CaptureError.renderFailed
        }

        // Encode to PNG.
        let pngData = try encodeToPNG(nsImage)

        // Enforce size cap — retry once at lower resolution if needed.
        if pngData.count > CardCaptureResult.maxImageBytes {
            guard maxLongEdge > 768 else {
                throw CaptureError.imageTooLarge(bytes: pngData.count)
            }
            // Recursive retry at 768px long edge.
            return try capture(
                cardName: cardName,
                document: document,
                currentCardId: currentCardId,
                maxLongEdge: 768
            )
        }

        let imageBase64 = pngData.base64EncodedString(options: [])
        return (
            cardId: resolvedCardId,
            cardName: resolvedCardName,
            pixelWidth: targetWidth,
            pixelHeight: targetHeight,
            imageBase64: imageBase64
        )
    }

    // MARK: - Private helpers

    /// Convert an NSImage to PNG data.
    private func encodeToPNG(_ nsImage: NSImage) throws -> Data {
        guard let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw CaptureError.encodingFailed
        }
        return pngData
    }
}
#endif
