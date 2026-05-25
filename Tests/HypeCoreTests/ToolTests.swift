import Testing
import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import HypeCore

@Suite("ToolState Tests")
struct ToolStateTests {

    @Test func browseToolCategoryIsBrowse() {
        let state = ToolState(currentTool: "browse")
        #expect(state.category == .browse)
        #expect(state.isEditMode == false)
    }

    @Test func buttonToolCategoryIsEdit() {
        let state = ToolState(currentTool: "button")
        #expect(state.category == .edit)
        #expect(state.isEditMode == true)
    }

    @Test func fieldToolCategoryIsEdit() {
        let state = ToolState(currentTool: "field")
        #expect(state.category == .edit)
    }

    @Test func shapeToolCategoryIsEdit() {
        let state = ToolState(currentTool: "shape")
        #expect(state.category == .edit)
    }

    @Test func webpageToolCategoryIsEdit() {
        let state = ToolState(currentTool: "webpage")
        #expect(state.category == .edit)
    }

    @Test func selectToolCategoryIsEdit() {
        let state = ToolState(currentTool: "select")
        #expect(state.category == .edit)
    }

    @Test func pencilToolCategoryIsPaint() {
        let state = ToolState(currentTool: "pencil")
        #expect(state.category == .paint)
        #expect(state.isEditMode == true)
    }

    @Test func unknownToolCategoryIsPaint() {
        let state = ToolState(currentTool: "spray")
        #expect(state.category == .paint)
    }

    @Test func selectToolClearsSelectedPart() {
        var state = ToolState(currentTool: "browse")
        state.selectedPartId = UUID()
        state.selectTool("button")
        #expect(state.currentTool == "button")
        #expect(state.selectedPartId == nil)
    }

    @Test func defaultToolIsBrowse() {
        let state = ToolState()
        #expect(state.currentTool == "browse")
        #expect(state.selectedPartId == nil)
    }
}

#if canImport(CoreGraphics)
@Suite("MouseHandler Tests")
struct MouseHandlerTests {

    let handler = MouseHandler()

    @Test func browseMouseDownOnPartSendsMessage() {
        let part = Part(partType: .button, cardId: UUID())
        let tool = ToolState(currentTool: "browse")
        let result = handler.handleMouseDown(tool: tool, hitPart: part, point: .zero)
        if case .sendMessage(let id, let msg) = result {
            #expect(id == part.id)
            #expect(msg == "mouseDown")
        } else {
            Issue.record("Expected sendMessage, got \(result)")
        }
    }

    @Test func browseMouseDownOnEmptyReturnsNone() {
        let tool = ToolState(currentTool: "browse")
        let result = handler.handleMouseDown(tool: tool, hitPart: nil, point: .zero)
        if case .none = result {
            // expected
        } else {
            Issue.record("Expected none, got \(result)")
        }
    }

    @Test func selectToolMouseDownOnPartSelectsPart() {
        let part = Part(partType: .button, cardId: UUID())
        let tool = ToolState(currentTool: "select")
        let result = handler.handleMouseDown(tool: tool, hitPart: part, point: .zero)
        if case .selectPart(let id) = result {
            #expect(id == part.id)
        } else {
            Issue.record("Expected selectPart, got \(result)")
        }
    }

    @Test func selectToolMouseDownOnEmptyDeselectsAll() {
        let tool = ToolState(currentTool: "select")
        let result = handler.handleMouseDown(tool: tool, hitPart: nil, point: .zero)
        if case .deselectAll = result {
            // expected
        } else {
            Issue.record("Expected deselectAll, got \(result)")
        }
    }

    @Test func buttonToolMouseDownBeginsDrag() {
        let tool = ToolState(currentTool: "button")
        let point = CGPoint(x: 100, y: 200)
        let result = handler.handleMouseDown(tool: tool, hitPart: nil, point: point)
        if case .beginDrag(let sx, let sy) = result {
            #expect(sx == 100)
            #expect(sy == 200)
        } else {
            Issue.record("Expected beginDrag, got \(result)")
        }
    }

    @Test func paintToolMouseDownBeginsDrag() {
        let tool = ToolState(currentTool: "pencil")
        let result = handler.handleMouseDown(tool: tool, hitPart: nil, point: CGPoint(x: 50, y: 50))
        if case .beginDrag = result {
            // expected
        } else {
            Issue.record("Expected beginDrag, got \(result)")
        }
    }

    @Test func editToolMouseUpCreatesButtonPart() {
        let tool = ToolState(currentTool: "button")
        let start = CGPoint(x: 10, y: 20)
        let end = CGPoint(x: 110, y: 80)
        let result = handler.handleMouseUp(tool: tool, hitPart: nil, dragStart: start, point: end)
        if case .createPart(let partType, let rect, _) = result {
            #expect(partType == .button)
            #expect(rect.origin.x == 8)
            #expect(rect.origin.y == 24)
            #expect(rect.size.width == 104)
            #expect(rect.size.height == 64)
        } else {
            Issue.record("Expected createPart, got \(result)")
        }
    }

    @Test func editToolMouseUpWithFineControlDoesNotSnap() {
        let tool = ToolState(currentTool: "button")
        let start = CGPoint(x: 10, y: 20)
        let end = CGPoint(x: 110, y: 80)
        let result = handler.handleMouseUp(tool: tool, hitPart: nil, dragStart: start, point: end, fineControl: true)
        if case .createPart(let partType, let rect, _) = result {
            #expect(partType == .button)
            #expect(rect.origin.x == 10)
            #expect(rect.origin.y == 20)
            #expect(rect.size.width == 100)
            #expect(rect.size.height == 60)
        } else {
            Issue.record("Expected createPart, got \(result)")
        }
    }

    @Test func editToolMouseUpTinyDragCreatesDefaultSizedPart() {
        let tool = ToolState(currentTool: "button")
        let start = CGPoint(x: 10, y: 20)
        let end = CGPoint(x: 12, y: 22)
        let result = handler.handleMouseUp(tool: tool, hitPart: nil, dragStart: start, point: end)
        if case .createPart(let partType, let rect, _) = result {
            #expect(partType == .button)
            #expect(rect.origin.x == 16)
            #expect(rect.origin.y == 24)
            #expect(rect.size.width == 88)
            #expect(rect.size.height == 24)
        } else {
            Issue.record("Expected default-sized createPart for tiny drag, got \(result)")
        }
    }

    @Test func shapeToolMouseUpIncludesShapeTypeExtra() {
        let tool = ToolState(currentTool: "shape")
        let start = CGPoint(x: 0, y: 0)
        let end = CGPoint(x: 50, y: 50)
        let result = handler.handleMouseUp(tool: tool, hitPart: nil, dragStart: start, point: end)
        if case .createPart(let partType, _, let extras) = result {
            #expect(partType == .shape)
            #expect(extras["shapeType"] == "rectangle")
        } else {
            Issue.record("Expected createPart with shape type, got \(result)")
        }
    }

    @Test func selectToolMouseUpReturnsNone() {
        let tool = ToolState(currentTool: "select")
        let result = handler.handleMouseUp(tool: tool, hitPart: nil, dragStart: CGPoint(x: 0, y: 0), point: CGPoint(x: 100, y: 100))
        if case .none = result {
            // expected
        } else {
            Issue.record("Expected none for select tool mouseUp, got \(result)")
        }
    }

    @Test func browseMouseUpOnPartSendsMouseUp() {
        let part = Part(partType: .field, cardId: UUID())
        let tool = ToolState(currentTool: "browse")
        let result = handler.handleMouseUp(tool: tool, hitPart: part, dragStart: nil, point: .zero)
        if case .sendMessage(let id, let msg) = result {
            #expect(id == part.id)
            #expect(msg == "mouseUp")
        } else {
            Issue.record("Expected sendMessage mouseUp, got \(result)")
        }
    }

    @Test func mouseUpWithNoDragStartReturnsNone() {
        let tool = ToolState(currentTool: "field")
        let result = handler.handleMouseUp(tool: tool, hitPart: nil, dragStart: nil, point: CGPoint(x: 50, y: 50))
        if case .none = result {
            // expected
        } else {
            Issue.record("Expected none with nil dragStart, got \(result)")
        }
    }
}
#endif
