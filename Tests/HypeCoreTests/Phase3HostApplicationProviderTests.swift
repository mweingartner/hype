import Testing
import Foundation
@testable import HypeCore

// MARK: - Test spy

/// Recording spy for `HostApplicationProvider` — captures every call so tests
/// can assert the correct provider method was invoked with the right argument.
private final class SpyHostProvider: HostApplicationProvider, @unchecked Sendable {
    private let lock = NSLock()

    // Call-count tracking
    private var _lockScreenCalls: Int = 0
    private var _unlockScreenCalls: Int = 0
    private var _openStackPaths: [String] = []
    private var _saveStackCalls: Int = 0
    private var _closeWindowCalls: Int = 0
    private var _quitAppCalls: Int = 0
    private var _editScriptIds: [UUID?] = []
    private var _chosenTools: [String] = []
    private var _printTargets: [HostPrintTarget] = []
    private var _doMenuItems: [String] = []
    private var _doMenuResults: [String: Bool] = [:]

    /// Programmatically configure which `doMenu` items the spy reports as handled.
    func setDoMenuResult(_ result: Bool, forItem item: String) {
        lock.withLock { _doMenuResults[item.lowercased()] = result }
    }

    // Synchronous read-outs for assertions
    var lockScreenCalls: Int { lock.withLock { _lockScreenCalls } }
    var unlockScreenCalls: Int { lock.withLock { _unlockScreenCalls } }
    var openStackPaths: [String] { lock.withLock { _openStackPaths } }
    var saveStackCalls: Int { lock.withLock { _saveStackCalls } }
    var closeWindowCalls: Int { lock.withLock { _closeWindowCalls } }
    var quitAppCalls: Int { lock.withLock { _quitAppCalls } }
    var editScriptIds: [UUID?] { lock.withLock { _editScriptIds } }
    var chosenTools: [String] { lock.withLock { _chosenTools } }
    var printTargets: [HostPrintTarget] { lock.withLock { _printTargets } }
    var doMenuItems: [String] { lock.withLock { _doMenuItems } }

    // Protocol implementation

    func lockScreen() async {
        lock.withLock { _lockScreenCalls += 1 }
    }

    func unlockScreen() async {
        lock.withLock { _unlockScreenCalls += 1 }
    }

    func openStack(path: String) async {
        lock.withLock { _openStackPaths.append(path) }
    }

    func saveStack() async {
        lock.withLock { _saveStackCalls += 1 }
    }

    func closeWindow() async {
        lock.withLock { _closeWindowCalls += 1 }
    }

    func quitApp() async {
        lock.withLock { _quitAppCalls += 1 }
    }

    func editScript(ofObjectId objectId: UUID?) async {
        lock.withLock { _editScriptIds.append(objectId) }
    }

    func chooseTool(_ name: String) async -> Bool {
        lock.withLock { _chosenTools.append(name) }
        return true
    }

    func print(target: HostPrintTarget) async {
        lock.withLock { _printTargets.append(target) }
    }

    func doMenu(item: String) async -> Bool {
        lock.withLock { _doMenuItems.append(item) }
        let result = lock.withLock { _doMenuResults[item.lowercased()] ?? false }
        return result
    }
}

private final class SpyDrawingProvider: DrawingProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var _lines: [(from: (Int, Int), to: (Int, Int), radius: Int, colorHex: String)] = []

    var lines: [(from: (Int, Int), to: (Int, Int), radius: Int, colorHex: String)] {
        lock.withLock { _lines }
    }

    func drawLine(from: (Int, Int), to: (Int, Int), radius: Int, colorHex: String) {
        lock.withLock {
            _lines.append((from: from, to: to, radius: radius, colorHex: colorHex))
        }
    }
}

// MARK: - Test infrastructure

/// Build a minimal single-card document with one button.
private func makeDoc() -> (doc: HypeDocument, cardId: UUID, btnId: UUID) {
    var doc = HypeDocument.newDocument(name: "HostTest")
    let cardId = doc.sortedCards[0].id
    let btn = Part(partType: .button, cardId: cardId, name: "Btn",
                   left: 10, top: 10, width: 80, height: 30)
    doc.addPart(btn)
    return (doc, cardId, btn.id)
}

/// Dispatch a script through `MessageDispatcher` with a custom `hostProvider`.
private func dispatch(
    _ script: String,
    on doc: HypeDocument,
    cardId: UUID,
    targetId: UUID,
    host: SpyHostProvider,
    drawingProvider: DrawingProvider = StubDrawingProvider()
) async -> ExecutionResult {
    var d = doc
    d.updatePart(id: targetId) { $0.script = script }
    let dispatcher = MessageDispatcher()
    return await runOnLargeStack { [d] in
        dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: targetId,
            document: d,
            currentCardId: cardId,
            drawingProvider: drawingProvider,
            hostProvider: host
        )
    }
}

// MARK: - HostPrintTarget Equatable shim for assertions

extension HostPrintTarget: Equatable {
    public static func == (lhs: HostPrintTarget, rhs: HostPrintTarget) -> Bool {
        switch (lhs, rhs) {
        case (.card, .card): return true
        case (.field(let a), .field(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - Tests

@Suite("Phase 3 — HostApplicationProvider dispatch", .serialized)
struct Phase3HostApplicationProviderTests {

    // MARK: lock screen / unlock screen

    @Test("lock screen — calls provider.lockScreen()")
    func lockScreen() async {
        let (doc, cardId, btnId) = makeDoc()
        let host = SpyHostProvider()
        _ = await dispatch(
            "on mouseUp\n  lock screen\nend mouseUp",
            on: doc, cardId: cardId, targetId: btnId, host: host
        )
        #expect(host.lockScreenCalls == 1, "lock screen should call lockScreen once")
        #expect(host.unlockScreenCalls == 0)
    }

    @Test("unlock screen — calls provider.unlockScreen()")
    func unlockScreen() async {
        let (doc, cardId, btnId) = makeDoc()
        let host = SpyHostProvider()
        _ = await dispatch(
            "on mouseUp\n  unlock screen\nend mouseUp",
            on: doc, cardId: cardId, targetId: btnId, host: host
        )
        #expect(host.unlockScreenCalls == 1)
        #expect(host.lockScreenCalls == 0)
    }

    @Test("lock then unlock — calls both in order")
    func lockThenUnlock() async {
        let (doc, cardId, btnId) = makeDoc()
        let host = SpyHostProvider()
        _ = await dispatch(
            "on mouseUp\n  lock screen\n  unlock screen\nend mouseUp",
            on: doc, cardId: cardId, targetId: btnId, host: host
        )
        #expect(host.lockScreenCalls == 1)
        #expect(host.unlockScreenCalls == 1)
    }

    // MARK: open stack

    @Test("open stack — passes path to provider")
    func openStack() async {
        let (doc, cardId, btnId) = makeDoc()
        let host = SpyHostProvider()
        _ = await dispatch(
            "on mouseUp\n  open stack \"/tmp/test.hype\"\nend mouseUp",
            on: doc, cardId: cardId, targetId: btnId, host: host
        )
        #expect(host.openStackPaths == ["/tmp/test.hype"])
    }

    // MARK: save stack

    @Test("save stack — calls provider.saveStack()")
    func saveStack() async {
        let (doc, cardId, btnId) = makeDoc()
        let host = SpyHostProvider()
        _ = await dispatch(
            "on mouseUp\n  save stack\nend mouseUp",
            on: doc, cardId: cardId, targetId: btnId, host: host
        )
        #expect(host.saveStackCalls == 1)
    }

    // MARK: close window

    @Test("close window — calls provider.closeWindow()")
    func closeWindow() async {
        let (doc, cardId, btnId) = makeDoc()
        let host = SpyHostProvider()
        _ = await dispatch(
            "on mouseUp\n  close window\nend mouseUp",
            on: doc, cardId: cardId, targetId: btnId, host: host
        )
        #expect(host.closeWindowCalls == 1)
    }

    // MARK: quit

    @Test("quit — calls provider.quitApp()")
    func quit() async {
        let (doc, cardId, btnId) = makeDoc()
        let host = SpyHostProvider()
        _ = await dispatch(
            "on mouseUp\n  quit\nend mouseUp",
            on: doc, cardId: cardId, targetId: btnId, host: host
        )
        #expect(host.quitAppCalls == 1)
    }

    // MARK: print card / print field

    @Test("print (bare) — passes .card target to provider")
    func printCard() async {
        // HyperCard: `print` with no argument means "print the current card".
        // `print card` fails to parse because `card` keyword requires an
        // identifier argument — the bare-keyword grammar is a known pre-existing
        // parser limitation documented in StubsAndCompletionPlan §Phase 1.
        let (doc, cardId, btnId) = makeDoc()
        let host = SpyHostProvider()
        _ = await dispatch(
            "on mouseUp\n  print\nend mouseUp",
            on: doc, cardId: cardId, targetId: btnId, host: host
        )
        #expect(host.printTargets.count == 1)
        #expect(host.printTargets[0] == .card)
    }

    @Test("print field — passes .field(content) target to provider")
    func printField() async {
        // `print field "Notes"` evaluates the objectRef to the field's text content,
        // then routes through provider.print(target: .field(content)).
        var (doc, cardId, btnId) = makeDoc()
        // Add a Notes field with some content.
        var notesField = Part(partType: .field, cardId: cardId, name: "Notes",
                              left: 10, top: 50, width: 200, height: 50)
        notesField.textContent = "hello world"
        doc.addPart(notesField)
        let host = SpyHostProvider()
        _ = await dispatch(
            "on mouseUp\n  print field \"Notes\"\nend mouseUp",
            on: doc, cardId: cardId, targetId: btnId, host: host
        )
        #expect(host.printTargets.count == 1)
        // The objectRef evaluates to field text content
        #expect(host.printTargets[0] == .field("hello world"))
    }

    // MARK: doMenu — handled items

    @Test("doMenu Next — calls provider.doMenu with 'Next'")
    func doMenuNext() async {
        let (doc, cardId, btnId) = makeDoc()
        let host = SpyHostProvider()
        host.setDoMenuResult(true, forItem: "Next")
        _ = await dispatch(
            "on mouseUp\n  doMenu \"Next\"\nend mouseUp",
            on: doc, cardId: cardId, targetId: btnId, host: host
        )
        #expect(host.doMenuItems == ["Next"])
    }

    @Test("doMenu Prev — calls provider.doMenu with 'Prev'")
    func doMenuPrev() async {
        let (doc, cardId, btnId) = makeDoc()
        let host = SpyHostProvider()
        host.setDoMenuResult(true, forItem: "Prev")
        _ = await dispatch(
            "on mouseUp\n  doMenu \"Prev\"\nend mouseUp",
            on: doc, cardId: cardId, targetId: btnId, host: host
        )
        #expect(host.doMenuItems == ["Prev"])
    }

    @Test("doMenu First — calls provider.doMenu with 'First'")
    func doMenuFirst() async {
        let (doc, cardId, btnId) = makeDoc()
        let host = SpyHostProvider()
        host.setDoMenuResult(true, forItem: "First")
        _ = await dispatch(
            "on mouseUp\n  doMenu \"First\"\nend mouseUp",
            on: doc, cardId: cardId, targetId: btnId, host: host
        )
        #expect(host.doMenuItems == ["First"])
    }

    @Test("doMenu Last — calls provider.doMenu with 'Last'")
    func doMenuLast() async {
        let (doc, cardId, btnId) = makeDoc()
        let host = SpyHostProvider()
        host.setDoMenuResult(true, forItem: "Last")
        _ = await dispatch(
            "on mouseUp\n  doMenu \"Last\"\nend mouseUp",
            on: doc, cardId: cardId, targetId: btnId, host: host
        )
        #expect(host.doMenuItems == ["Last"])
    }

    @Test("doMenu Copy — calls provider.doMenu with 'Copy'")
    func doMenuCopy() async {
        let (doc, cardId, btnId) = makeDoc()
        let host = SpyHostProvider()
        host.setDoMenuResult(true, forItem: "Copy")
        _ = await dispatch(
            "on mouseUp\n  doMenu \"Copy\"\nend mouseUp",
            on: doc, cardId: cardId, targetId: btnId, host: host
        )
        #expect(host.doMenuItems == ["Copy"])
    }

    @Test("classic paint drag script parses and dispatches tool/menu/drag commands")
    func classicPaintDragScriptCompatibility() async {
        var (doc, cardId, btnId) = makeDoc()
        doc.stack.userLevel = HypeUserLevel.browsing.rawValue
        let host = SpyHostProvider()
        let drawing = SpyDrawingProvider()

        let result = await dispatch(
            """
            on mouseUp
              put the userLevel into saveLevel
              if the userLevel < 3 then set userLevel to 3 -- "Painting"
              if the userLevel < 3 then exit mouseUp
              choose select tool
              doMenu "Select All"
              doMenu "Select"
              set dragSpeed to 100
              drag from 256,171 to 150,171
              drag from 150,171 to 350,171
              drag from 350,171 to 256,171
              doMenu "Select All"
              doMenu "Revert"
              choose browse tool
              set userLevel to saveLevel
            end mouseUp
            """,
            on: doc,
            cardId: cardId,
            targetId: btnId,
            host: host,
            drawingProvider: drawing
        )

        #expect(result.status == .completed)
        #expect(result.modifiedDocument?.stack.userLevel == HypeUserLevel.browsing.rawValue)
        #expect(result.modifiedDocument?.scriptGlobals["dragspeed"] == "100")
        #expect(host.chosenTools == ["select", "browse"])
        #expect(host.doMenuItems == ["Select All", "Select", "Select All", "Revert"])
        #expect(drawing.lines.count == 3)
        #expect(drawing.lines[0].from == (256, 171))
        #expect(drawing.lines[0].to == (150, 171))
        #expect(drawing.lines[1].from == (150, 171))
        #expect(drawing.lines[1].to == (350, 171))
        #expect(drawing.lines[2].from == (350, 171))
        #expect(drawing.lines[2].to == (256, 171))
    }

    // MARK: doMenu — provider dispatch contract

    /// The spy provider records calls and returns its configured result. The
    /// production AppKit provider decides whether an item maps to a Hype command,
    /// a responder-chain command, or a real enabled menu item.

    @Test("doMenu 'Delete Card' — spy receives item name")
    func doMenuDeleteCardForwardsToProvider() async {
        let (doc, cardId, btnId) = makeDoc()
        let host = SpyHostProvider()
        _ = await dispatch(
            "on mouseUp\n  doMenu \"Delete Card\"\nend mouseUp",
            on: doc, cardId: cardId, targetId: btnId, host: host
        )
        #expect(host.doMenuItems == ["Delete Card"],
                "doMenu forwards the item name to the host provider")
    }

    @Test("doMenu 'Cut' — spy receives item name")
    func doMenuCutForwardsToProvider() async {
        let (doc, cardId, btnId) = makeDoc()
        let host = SpyHostProvider()
        _ = await dispatch(
            "on mouseUp\n  doMenu \"Cut\"\nend mouseUp",
            on: doc, cardId: cardId, targetId: btnId, host: host
        )
        #expect(host.doMenuItems == ["Cut"])
    }

    @Test("doMenu 'Clear' — spy receives item name")
    func doMenuClearForwardsToProvider() async {
        let (doc, cardId, btnId) = makeDoc()
        let host = SpyHostProvider()
        _ = await dispatch(
            "on mouseUp\n  doMenu \"Clear\"\nend mouseUp",
            on: doc, cardId: cardId, targetId: btnId, host: host
        )
        #expect(host.doMenuItems == ["Clear"])
    }
}

// MARK: - StubHostApplicationProvider unit tests
//
// These tests exercise the protocol's default no-op implementation. Production
// AppKit behavior is covered in HypeTests.

@Suite("StubHostApplicationProvider doMenu no-op", .serialized)
struct StubDoMenuNoOpTests {

    /// Use the `StubHostApplicationProvider` (no-op/false default) to verify
    /// the base-level guarantee: unknown items always return false.
    @Test("unknown item returns false from stub provider")
    func unknownItemReturnsFalse() async {
        let stub = StubHostApplicationProvider()
        let result = await stub.doMenu(item: "SomeRandomItem")
        #expect(result == false)
    }

    @Test("'Delete Card' returns false from stub provider")
    func deleteCardReturnsFalse() async {
        let stub = StubHostApplicationProvider()
        let result = await stub.doMenu(item: "Delete Card")
        #expect(result == false)
    }

    @Test("'Delete Stack' returns false from stub provider")
    func deleteStackReturnsFalse() async {
        let stub = StubHostApplicationProvider()
        let result = await stub.doMenu(item: "Delete Stack")
        #expect(result == false)
    }

    @Test("'Cut' returns false from stub provider")
    func cutReturnsFalse() async {
        let stub = StubHostApplicationProvider()
        let result = await stub.doMenu(item: "Cut")
        #expect(result == false)
    }

    @Test("'Clear' returns false from stub provider")
    func clearReturnsFalse() async {
        let stub = StubHostApplicationProvider()
        let result = await stub.doMenu(item: "Clear")
        #expect(result == false)
    }

    @Test("empty string returns false from stub provider")
    func emptyStringReturnsFalse() async {
        let stub = StubHostApplicationProvider()
        let result = await stub.doMenu(item: "")
        #expect(result == false)
    }
}

// MARK: - StubHostApplicationProvider no-op guarantee

@Suite("StubHostApplicationProvider — no-op contract")
struct StubHostApplicationProviderTests {

    @Test("all methods complete without error")
    func allMethodsNoOp() async {
        let stub = StubHostApplicationProvider()
        await stub.lockScreen()
        await stub.unlockScreen()
        await stub.openStack(path: "/some/path.hype")
        await stub.saveStack()
        await stub.closeWindow()
        await stub.quitApp()
        await stub.editScript(ofObjectId: nil)
        await stub.editScript(ofObjectId: UUID())
        await stub.print(target: .card)
        await stub.print(target: .field("Notes"))
        let handled = await stub.doMenu(item: "Next")
        #expect(handled == false, "Stub always returns false for doMenu")
    }
}
