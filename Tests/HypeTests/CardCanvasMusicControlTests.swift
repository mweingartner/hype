import AppKit
import Foundation
import HypeCore
import SwiftUI
import Testing
@testable import Hype

@Suite("CardCanvas music control interaction")
@MainActor
struct CardCanvasMusicControlTests {
    private final class CanvasState {
        var wrapper = HypeDocumentWrapper()
        var selectedPartIds: Set<UUID> = []

        init(document: HypeDocument) {
            wrapper.document = document
        }
    }

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

    @Test("browse mode plays a background piano keyboard after runtime toggle")
    func browseModePlaysBackgroundPianoKeyboard() throws {
        var document = HypeDocument.newDocument(name: "Background Keyboard")
        let cardId = document.sortedCards[0].id
        let backgroundId = try #require(document.cards.first(where: { $0.id == cardId })?.backgroundId)
        let size = PartCreationDefaults.defaultSize(for: .pianoKeyboard)
        let keyboard = Part(
            partType: .pianoKeyboard,
            backgroundId: backgroundId,
            name: "Keys",
            left: 10,
            top: 20,
            width: size.width,
            height: size.height
        )
        document.addPart(keyboard)

        let state = CanvasState(document: document)
        let canvasView = CardCanvasView(
            document: Binding(
                get: { state.wrapper },
                set: { state.wrapper = $0 }
            ),
            currentCardId: cardId,
            currentTool: .browse,
            selectedPartIds: Binding(
                get: { state.selectedPartIds },
                set: { state.selectedPartIds = $0 }
            ),
            editingBackground: false
        )
        let coordinator = CardCanvasView.Coordinator(parent: canvasView)
        let nsView = CardCanvasNSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        nsView.document = state.wrapper.document
        nsView.currentCardId = cardId
        nsView.currentTool = .browse
        nsView.editingBackground = false
        nsView.coordinator = coordinator
        coordinator.nsView = nsView
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = nsView

        var capturedRequests: [MusicControlPlaybackRequest] = []
        nsView.musicControlPlaybackHandler = { request, _ in
            capturedRequests.append(request)
        }

        let keyRect = MusicControlInteraction.keyboardRect(
            in: CGRect(x: keyboard.left, y: keyboard.top, width: keyboard.width, height: keyboard.height)
        )
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: nsView.convert(NSPoint(x: keyRect.minX + 4, y: keyRect.midY), to: nil),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))

        withExtendedLifetime((coordinator, window)) {
            nsView.mouseDown(with: event)
        }

        #expect(capturedRequests.count == 1)
        #expect(capturedRequests.first?.pattern.tracks.first?.noteString == "c4e")
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
