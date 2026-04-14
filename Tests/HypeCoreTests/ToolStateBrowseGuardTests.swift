import Testing
import Foundation
@testable import HypeCore

/// Regression tests for the invariant that the `.select` tool sits
/// in the `.edit` category — and therefore halts the idle timer.
///
/// Background: a user reported that a buggy `on idle` handler
/// triggered a runtime error every 500 ms (the idle timer
/// interval), opening a fresh script editor window each time
/// until the only escape was to force-quit the app.
///
/// Two layered fixes were added in response:
///
/// 1. `openScriptEditorWindow` is now idempotent per
///    `ScriptTarget` — a second open call for the same target
///    reuses the existing window.
///
/// 2. The `.showScriptError` observer in `MainContentView` flips
///    `currentTool` to `.select` before opening the editor.
///    `CardCanvasNSView.startIdleTimer` only dispatches idle
///    when `ToolState(currentTool: ...).category == .browse`, so
///    switching out of browse mode immediately stops every
///    subsequent tick.
///
/// These tests pin the half of the contract that lives in
/// HypeCore (the `ToolState` category model). The window-dedup
/// half lives in the Hype executable target and isn't directly
/// reachable from a HypeCore test — it's covered by manual
/// install verification.
@Suite("Tool state browse-mode guard")
struct ToolStateBrowseGuardTests {

    @Test("the `browse` tool sits in the .browse category")
    func browseToolIsBrowseCategory() {
        let s = ToolState(currentTool: "browse")
        #expect(s.category == .browse)
        #expect(s.isEditMode == false)
    }

    @Test("the `select` tool sits in the .edit category — this is what stops the idle timer on script errors")
    func selectToolIsEditCategory() {
        let s = ToolState(currentTool: "select")
        // Critical invariant: switching to .select on a runtime
        // error has to land in a non-.browse category, because
        // CardCanvasNSView.startIdleTimer's `category == .browse`
        // guard is the only thing that stops the idle timer from
        // re-firing the buggy handler.
        #expect(s.category == .edit)
        #expect(s.isEditMode == true)
    }

    @Test("every part-creation tool also sits in the .edit category")
    func editToolsAreEditCategory() {
        let editTools = ["button", "field", "shape", "webpage", "image", "video", "chart", "spriteArea", "select"]
        for name in editTools {
            let s = ToolState(currentTool: name)
            #expect(s.category == .edit, "tool '\(name)' should be in .edit category, got \(s.category)")
            #expect(s.isEditMode == true, "tool '\(name)' should be edit mode")
        }
    }

    @Test("only `browse` returns the .browse category")
    func onlyBrowseIsBrowseCategory() {
        // Sanity: any non-browse tool name (recognised or not)
        // must NOT report .browse, otherwise the idle timer keeps
        // firing on script errors and the fix breaks.
        let nonBrowse = ["select", "button", "field", "shape", "pencil", "spray", "bucket", "eraser", "text"]
        for name in nonBrowse {
            #expect(ToolState(currentTool: name).category != .browse,
                    "tool '\(name)' must not report .browse category")
        }
    }

    @Test("paint tools sit in the .paint category, also non-browse")
    func paintToolsArePaintCategory() {
        let paintTools = ["pencil", "line", "rect", "oval", "spray", "bucket", "eraser", "text"]
        for name in paintTools {
            let s = ToolState(currentTool: name)
            #expect(s.category == .paint, "tool '\(name)' should be in .paint category")
            // isEditMode is true for both .edit and .paint (it just
            // means "not browse"), which is what gates the idle
            // timer.
            #expect(s.isEditMode == true)
        }
    }
}
