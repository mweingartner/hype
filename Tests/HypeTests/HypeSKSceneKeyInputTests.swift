import AppKit
import Testing
@testable import Hype

@MainActor
@Suite("SpriteKit key input")
struct HypeSKSceneKeyInputTests {
    private final class EventRecorder: SpriteEventDelegate {
        var events: [SpriteEvent] = []

        func spriteScene(_ scene: HypeSKScene, didReceiveEvent event: SpriteEvent) {
            events.append(event)
        }
    }

    @Test("arrow keyDown is normalized to HypeTalk key names")
    func arrowKeyDownIsNormalized() throws {
        let scene = HypeSKScene(size: CGSize(width: 320, height: 240), sceneHeight: 240)
        let recorder = EventRecorder()
        scene.eventDelegate = recorder

        let rightArrow = String(UnicodeScalar(UInt32(NSRightArrowFunctionKey))!)
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: rightArrow,
            charactersIgnoringModifiers: rightArrow,
            isARepeat: false,
            keyCode: 124
        ))

        scene.keyDown(with: event)

        guard case .keyDown(let characters, let keyCode) = recorder.events.last else {
            Issue.record("Expected keyDown event")
            return
        }
        #expect(characters == "right")
        #expect(keyCode == 124)
    }

    @Test("letter keyDown ignores shift for script-friendly matching")
    func letterKeyDownIgnoresShift() throws {
        let scene = HypeSKScene(size: CGSize(width: 320, height: 240), sceneHeight: 240)
        let recorder = EventRecorder()
        scene.eventDelegate = recorder

        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "W",
            charactersIgnoringModifiers: "w",
            isARepeat: false,
            keyCode: 13
        ))

        scene.keyDown(with: event)

        guard case .keyDown(let characters, let keyCode) = recorder.events.last else {
            Issue.record("Expected keyDown event")
            return
        }
        #expect(characters == "w")
        #expect(keyCode == 13)
    }

    @Test("space keyDown is normalized to the script-friendly key name")
    func spaceKeyDownIsNormalized() throws {
        let scene = HypeSKScene(size: CGSize(width: 320, height: 240), sceneHeight: 240)
        let recorder = EventRecorder()
        scene.eventDelegate = recorder

        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: false,
            keyCode: 49
        ))

        scene.keyDown(with: event)

        guard case .keyDown(let characters, let keyCode) = recorder.events.last else {
            Issue.record("Expected keyDown event")
            return
        }
        #expect(characters == "space")
        #expect(keyCode == 49)
    }

    @Test("numeric keypad enter keyDown is normalized to enter")
    func keypadEnterKeyDownIsNormalized() throws {
        let scene = HypeSKScene(size: CGSize(width: 320, height: 240), sceneHeight: 240)
        let recorder = EventRecorder()
        scene.eventDelegate = recorder

        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 76
        ))

        scene.keyDown(with: event)

        guard case .keyDown(let characters, let keyCode) = recorder.events.last else {
            Issue.record("Expected keyDown event")
            return
        }
        #expect(characters == "enter")
        #expect(keyCode == 76)
    }

    @Test("arrow keyUp is normalized and delivered with key name")
    func arrowKeyUpIsNormalized() throws {
        let scene = HypeSKScene(size: CGSize(width: 320, height: 240), sceneHeight: 240)
        let recorder = EventRecorder()
        scene.eventDelegate = recorder

        let upArrow = String(UnicodeScalar(UInt32(NSUpArrowFunctionKey))!)
        let event = try #require(NSEvent.keyEvent(
            with: .keyUp,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: upArrow,
            charactersIgnoringModifiers: upArrow,
            isARepeat: false,
            keyCode: 126
        ))

        scene.keyUp(with: event)

        guard case .keyUp(let characters, let keyCode) = recorder.events.last else {
            Issue.record("Expected keyUp event")
            return
        }
        #expect(characters == "up")
        #expect(keyCode == 126)
    }
}
