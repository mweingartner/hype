import Foundation
import Testing

@Suite("CardCanvas music control interaction")
struct CardCanvasMusicControlTests {
    @Test("music-control drag playback is wired through mouseDragged")
    func musicControlDragPlaybackIsWired() throws {
        let source = try String(
            contentsOf: packageRoot()
                .appendingPathComponent("Sources/Hype/Views/CardCanvasView.swift"),
            encoding: .utf8
        )

        #expect(source.contains("activeMusicControlDragPartId"))
        #expect(source.contains("beginMusicControlDragIfNeeded(part: part, request: request, at: point)"))
        #expect(source.contains("performDraggedMusicControlAction(at: point)"))
        #expect(source.contains("dragPlaybackSamplePoints(from: lastMusicControlDragPoint, to: point, part: part)"))
        #expect(source.contains("part.partType == .pianoKeyboard || part.partType == .stepSequencer"))
        #expect(source.contains("dragTriggerPrefix(for: part)"))
        #expect(source.contains("trigger != lastMusicControlDragTriggerIdentifier"))
    }

    private func packageRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
