import Foundation
import Testing

@Suite("CardCanvas music control interaction")
struct CardCanvasMusicControlTests {
    @Test("piano keyboard drag playback is wired through mouseDragged")
    func pianoKeyboardDragPlaybackIsWired() throws {
        let source = try String(
            contentsOf: packageRoot()
                .appendingPathComponent("Sources/Hype/Views/CardCanvasView.swift"),
            encoding: .utf8
        )

        #expect(source.contains("activePianoKeyboardDragPartId"))
        #expect(source.contains("beginPianoKeyboardDragIfNeeded(part: part, request: request)"))
        #expect(source.contains("performDraggedPianoKeyboardAction(at: point)"))
        #expect(source.contains("lastPianoKeyboardDragTriggerIdentifier"))
        #expect(source.contains("trigger != lastPianoKeyboardDragTriggerIdentifier"))
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
