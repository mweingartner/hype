import Testing
import Foundation
@testable import HypeCore

@Suite("Stack-level property access", .serialized)
struct StackPropertyTests {
    @Test func userScriptParses() async {
        let script = """
        on mouseUp
          put the defaultFont of stack into f
          answer f
          pass mouseUp
        end mouseUp
        """
        var lexer = Lexer(source: script)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        do {
            let parsed = try parser.parse()
            #expect(parsed.handlers.count == 1)
            #expect(parsed.handlers[0].name == "mouseUp")
        } catch {
            Issue.record("Parse failed: \(error)")
        }
    }

    @Test func setDefaultFontOfStackParses() async {
        let script = """
        on mouseUp
          set the defaultFont of stack to "Menlo"
        end mouseUp
        """
        var lexer = Lexer(source: script)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        do {
            let parsed = try parser.parse()
            #expect(parsed.handlers.count == 1)
        } catch {
            Issue.record("Parse failed: \(error)")
        }
    }

    @Test func getDefaultFontOfStackReturnsValue() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var field = Part(partType: .field, cardId: cardId, name: "output")
        doc.addPart(field)
        doc.cards[0].script = """
        on openCard
          put the defaultFont of stack into field "output"
        end openCard
        """
        let result = await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        ) }
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        let output = result.modifiedDocument?.parts.first { $0.name == "output" }
        #expect(output?.textContent == "Apple Braille",
                "Expected 'Apple Braille' but got '\(output?.textContent ?? "nil")'")
    }

    @Test func setDefaultFontOfStackWorks() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        doc.cards[0].script = """
        on openCard
          set the defaultFont of stack to "Menlo"
        end openCard
        """
        let result = await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        ) }
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        #expect(result.modifiedDocument?.stack.defaultFont == "Menlo")
    }

    @Test func stackRuntimeModeAndWebAssetFlagsAreScriptable() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        doc.cards[0].script = """
        on openCard
          set the runtimeMode of stack to true
          set the webAssetsAllowed of stack to true
        end openCard
        """
        let result = await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        ) }
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        #expect(result.modifiedDocument?.stack.runtimeModeEnabled == true)
        #expect(result.modifiedDocument?.stack.webAssetsAllowed == true)
    }

    @Test func userLevelGlobalPropertyIsScriptable() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var field = Part(partType: .field, cardId: cardId, name: "output")
        doc.addPart(field)
        doc.cards[0].script = """
        on openCard
          set the userLevel to 2
          put the userLevel into field "output"
        end openCard
        """
        let result = await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        ) }
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        #expect(result.modifiedDocument?.stack.userLevel == HypeUserLevel.typing.rawValue)
        let output = result.modifiedDocument?.parts.first { $0.name == "output" }
        #expect(output?.textContent == "2")
    }

    @Test func userLevelStackPropertyAcceptsNames() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        doc.cards[0].script = """
        on openCard
          set the userLevel of stack to "painting"
        end openCard
        """
        let result = await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        ) }
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        #expect(result.modifiedDocument?.stack.userLevel == HypeUserLevel.painting.rawValue)
    }

    @Test func stackRuntimeAISettingsAreScriptable() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        doc.cards[0].script = """
        on openCard
          set the runtimeAIProviderPolicy of stack to "appleFoundationModels"
          set the runtimeAIToolsAllowed of stack to true
          set the runtimeAIAllowedTools of stack to "set_runtime_variable"
          set the runtimeAIPersistTranscript of stack to true
        end openCard
        """
        let result = await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        ) }
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        #expect(result.modifiedDocument?.stack.runtimeAISettings.providerPolicy == .appleFoundationModels)
        #expect(result.modifiedDocument?.stack.runtimeAISettings.allowRuntimeSideEffectTools == true)
        #expect(result.modifiedDocument?.stack.runtimeAISettings.allowedToolNames == ["set_runtime_variable"])
        #expect(result.modifiedDocument?.stack.runtimeAISettings.persistTranscript == true)
    }

    @Test func stackTargetLayoutPropertiesAreScriptable() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        doc.cards[0].script = """
        on openCard
          set the targetPlatforms of stack to "macOS,iPhone,iPad"
          set the primaryTargetPlatform of stack to "iPad"
          set the layoutPolicy of stack to "scaleToFit"
        end openCard
        """
        let result = await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        ) }
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        #expect(result.modifiedDocument?.stack.deploymentTargets.selectedPlatforms == [.macOS, .iPhone, .iPad])
        #expect(result.modifiedDocument?.stack.deploymentTargets.primaryPlatform == .iPad)
        #expect(result.modifiedDocument?.stack.deploymentTargets.layoutPolicy == .scaleToFit)
    }

    @Test func runtimeAIStatusPropertiesAndResetSessionParse() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var field = Part(partType: .field, cardId: cardId, name: "output")
        doc.addPart(field)
        doc.cards[0].script = """
        on openCard
          reset ai session
          put the aiProvider & "|" & the aiAvailable into field "output"
        end openCard
        """
        let result = await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId,
            aiProvider: StubAIScriptingProvider(model: "authoring-model", response: "authoring response")
        ) }
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        let output = result.modifiedDocument?.parts.first { $0.name == "output" }
        #expect(output?.textContent == "Authoring Provider|true")
    }
}
