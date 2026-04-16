import Testing
import Foundation
@testable import HypeCore

// Tests for the HypeTalk property audit fixes: ensures every Part /
// SpriteAreaSpec / SceneSpec / HypeNodeSpec / ChartConfig property
// reachable from the model is also gettable and settable from
// HypeTalk with consistent property names across GET and SET.

@Suite("Property audit: image / video object parsing", .serialized)
struct ImageVideoObjectParsingTests {
    @Test("'image \"X\"' parses as an object reference")
    func parseImageObjectRef() {
        let script = """
        on mouseUp
          get the url of image "logo"
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

    @Test("'video \"X\"' parses as an object reference")
    func parseVideoObjectRef() {
        let script = """
        on mouseUp
          set the videourl of video "clip" to "http://example.com/clip.mp4"
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

    @Test("get the name of image \"logo\" returns the image part's name")
    func getImagePartName() {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let img = Part(partType: .image, cardId: cardId, name: "logo")
        doc.addPart(img)
        let field = Part(partType: .field, cardId: cardId, name: "output")
        doc.addPart(field)
        doc.cards[0].script = """
        on openCard
          put the name of image "logo" into field "output"
        end openCard
        """
        let result = MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        )
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        let out = result.modifiedDocument?.parts.first { $0.name == "output" }
        #expect(out?.textContent == "logo")
    }

    @Test("get the videourl of video \"clip\" returns the videoURL")
    func getVideoURL() {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var vid = Part(partType: .video, cardId: cardId, name: "clip")
        vid.videoURL = "http://example.com/movie.mp4"
        doc.addPart(vid)
        let field = Part(partType: .field, cardId: cardId, name: "output")
        doc.addPart(field)
        doc.cards[0].script = """
        on openCard
          put the videourl of video "clip" into field "output"
        end openCard
        """
        let result = MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        )
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        let out = result.modifiedDocument?.parts.first { $0.name == "output" }
        #expect(out?.textContent == "http://example.com/movie.mp4")
    }

    @Test("set the videourl of video \"clip\" writes the value")
    func setVideoURL() {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let vid = Part(partType: .video, cardId: cardId, name: "clip")
        doc.addPart(vid)
        doc.cards[0].script = """
        on openCard
          set the videourl of video "clip" to "http://example.com/new.mp4"
        end openCard
        """
        let result = MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        )
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        let newVid = result.modifiedDocument?.parts.first { $0.name == "clip" }
        #expect(newVid?.videoURL == "http://example.com/new.mp4")
    }
}

@Suite("Property audit: reachable Part properties", .serialized)
struct ReachablePartPropertyTests {
    @Test("popupitems is readable and writable on a button")
    func popupItemsReadWrite() {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let btn = Part(partType: .button, cardId: cardId, name: "menu")
        doc.addPart(btn)
        doc.cards[0].script = """
        on openCard
          set the popupitems of button "menu" to "Apple,Banana,Cherry"
        end openCard
        """
        let result = MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        )
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        let newBtn = result.modifiedDocument?.parts.first { $0.name == "menu" }
        #expect(newBtn?.popupItems == "Apple,Banana,Cherry")
    }

    @Test("htmlcontent is readable and writable on a field")
    func htmlContentReadWrite() {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let fld = Part(partType: .field, cardId: cardId, name: "html")
        doc.addPart(fld)
        doc.cards[0].script = """
        on openCard
          set the htmlcontent of field "html" to "<b>hi</b>"
        end openCard
        """
        let result = MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        )
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        let newFld = result.modifiedDocument?.parts.first { $0.name == "html" }
        #expect(newFld?.htmlContent == "<b>hi</b>")
    }

    @Test("linesize in SET is equivalent to strokewidth")
    func linesizeAliasInSet() {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let shape = Part(partType: .shape, cardId: cardId, name: "box")
        doc.addPart(shape)
        doc.cards[0].script = """
        on openCard
          set the linesize of shape "box" to 5
        end openCard
        """
        let result = MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        )
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        let newShape = result.modifiedDocument?.parts.first { $0.name == "box" }
        #expect(newShape?.strokeWidth == 5.0)
    }

    @Test("left_pos / top_pos aliases work in GET (mirror SET)")
    func leftTopPosAliasInGet() {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var btn = Part(partType: .button, cardId: cardId, name: "b")
        btn.left = 25
        btn.top = 40
        doc.addPart(btn)
        let out = Part(partType: .field, cardId: cardId, name: "out")
        doc.addPart(out)
        doc.cards[0].script = """
        on openCard
          put the left_pos of button "b" & "," & the top_pos of button "b" into field "out"
        end openCard
        """
        let result = MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        )
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        let outPart = result.modifiedDocument?.parts.first { $0.name == "out" }
        #expect(outPart?.textContent == "25,40")
    }

    @Test("fill_color underscore alias works in SET (no duplicate case)")
    func fillColorUnderscoreInSet() {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let shape = Part(partType: .shape, cardId: cardId, name: "s")
        doc.addPart(shape)
        doc.cards[0].script = """
        on openCard
          set the fill_color of shape "s" to "#FF0000"
        end openCard
        """
        let result = MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        )
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        let newShape = result.modifiedDocument?.parts.first { $0.name == "s" }
        #expect(newShape?.fillColor == "#FF0000")
    }
}

@Suite("Property audit: sprite-area (spritearea) properties", .serialized)
struct SpriteAreaPropertyTests {
    /// Build a sprite area part on the first card with a single scene.
    private func makeDoc() -> (HypeDocument, UUID) {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var area = Part(partType: .spriteArea, cardId: cardId, name: "arena")
        let spec = SpriteAreaSpec(
            defaultSceneNamed: "main",
            fallbackSize: SizeSpec(width: 400, height: 300)
        )
        area.setSpriteAreaSpec(spec)
        doc.addPart(area)
        let out = Part(partType: .field, cardId: cardId, name: "out")
        doc.addPart(out)
        return (doc, cardId)
    }

    @Test("scalemode is readable on spritearea")
    func getScaleMode() {
        var (doc, cardId) = makeDoc()
        doc.cards[0].script = """
        on openCard
          put the scalemode of spritearea "arena" into field "out"
        end openCard
        """
        let result = MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        )
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        let out = result.modifiedDocument?.parts.first { $0.name == "out" }
        #expect(out?.textContent == "aspectFit")
    }

    @Test("scalemode is writable on spritearea")
    func setScaleMode() {
        var (doc, cardId) = makeDoc()
        doc.cards[0].script = """
        on openCard
          set the scalemode of spritearea "arena" to "aspectFill"
        end openCard
        """
        let result = MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        )
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        let area = result.modifiedDocument?.parts.first { $0.name == "arena" }
        #expect(area?.spriteAreaSpecModel?.scaleMode == .aspectFill)
    }

    @Test("showsphysics is readable and writable")
    func showsPhysicsReadWrite() {
        var (doc, cardId) = makeDoc()
        doc.cards[0].script = """
        on openCard
          set the showsphysics of spritearea "arena" to "true"
        end openCard
        """
        let result = MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        )
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        let area = result.modifiedDocument?.parts.first { $0.name == "arena" }
        #expect(area?.spriteAreaSpecModel?.showsPhysics == true)
    }

    @Test("showsfps and showsnodecount round-trip")
    func showsFpsNodeCountRoundTrip() {
        var (doc, cardId) = makeDoc()
        doc.cards[0].script = """
        on openCard
          set the showsfps of spritearea "arena" to "true"
          set the showsnodecount of spritearea "arena" to "true"
        end openCard
        """
        let result = MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        )
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        let area = result.modifiedDocument?.parts.first { $0.name == "arena" }
        #expect(area?.spriteAreaSpecModel?.showsFPS == true)
        #expect(area?.spriteAreaSpecModel?.showsNodeCount == true)
    }

    @Test("scenecount returns number of scenes in sprite area")
    func sceneCount() {
        var (doc, cardId) = makeDoc()
        doc.cards[0].script = """
        on openCard
          put the scenecount of spritearea "arena" into field "out"
        end openCard
        """
        let result = MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        )
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        let out = result.modifiedDocument?.parts.first { $0.name == "out" }
        #expect(out?.textContent == "1")
    }

    @Test("activescene returns the active scene name")
    func activeSceneName() {
        var (doc, cardId) = makeDoc()
        doc.cards[0].script = """
        on openCard
          put the activescene of spritearea "arena" into field "out"
        end openCard
        """
        let result = MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        )
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        let out = result.modifiedDocument?.parts.first { $0.name == "out" }
        #expect(out?.textContent == "main")
    }
}

@Suite("Property audit: physics body SET coverage", .serialized)
struct PhysicsBodySetPropertyTests {
    /// Build a sprite area + scene + single sprite, then run `script` on the card.
    private func runScriptAgainstSprite(_ script: String) -> HypeDocument? {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var area = Part(partType: .spriteArea, cardId: cardId, name: "arena")
        var spec = SpriteAreaSpec(
            defaultSceneNamed: "main",
            fallbackSize: SizeSpec(width: 400, height: 300)
        )
        var scene = spec.activeScene ?? SceneSpec(
            size: spec.designSize,
            scaleMode: spec.scaleMode
        )
        scene.nodes.append(HypeNodeSpec(name: "ball", nodeType: .sprite))
        spec.setActiveScene(scene)
        area.setSpriteAreaSpec(spec)
        doc.addPart(area)
        doc.cards[0].script = "on openCard\n\(script)\nend openCard"
        let result = MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        )
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        return result.modifiedDocument
    }

    private func sprite(_ doc: HypeDocument?) -> HypeNodeSpec? {
        guard let area = doc?.parts.first(where: { $0.name == "arena" }),
              let spec = area.spriteAreaSpecModel,
              let scene = spec.activeScene else { return nil }
        return scene.nodes.first(where: { $0.name == "ball" })
    }

    @Test("set mass writes physics body mass")
    func setMass() {
        let doc = runScriptAgainstSprite("set the mass of sprite \"ball\" to 2.5")
        #expect(sprite(doc)?.physicsBody?.mass == 2.5)
    }

    @Test("set friction writes physics body friction")
    func setFriction() {
        let doc = runScriptAgainstSprite("set the friction of sprite \"ball\" to 0.7")
        #expect(sprite(doc)?.physicsBody?.friction == 0.7)
    }

    @Test("set restitution writes physics body restitution")
    func setRestitution() {
        let doc = runScriptAgainstSprite("set the restitution of sprite \"ball\" to 0.9")
        #expect(sprite(doc)?.physicsBody?.restitution == 0.9)
    }

    @Test("set bounce (alias for restitution) writes physics body restitution")
    func setBounce() {
        let doc = runScriptAgainstSprite("set the bounce of sprite \"ball\" to 0.5")
        #expect(sprite(doc)?.physicsBody?.restitution == 0.5)
    }

    @Test("set isdynamic writes physics body isDynamic (false)")
    func setIsDynamicFalse() {
        let doc = runScriptAgainstSprite("set the isdynamic of sprite \"ball\" to \"false\"")
        #expect(sprite(doc)?.physicsBody?.isDynamic == false)
    }

    @Test("set affectedbygravity writes physics body affectedByGravity")
    func setAffectedByGravity() {
        let doc = runScriptAgainstSprite("set the affectedbygravity of sprite \"ball\" to \"false\"")
        #expect(sprite(doc)?.physicsBody?.affectedByGravity == false)
    }

    @Test("set allowsrotation writes physics body allowsRotation")
    func setAllowsRotation() {
        let doc = runScriptAgainstSprite("set the allowsrotation of sprite \"ball\" to \"false\"")
        #expect(sprite(doc)?.physicsBody?.allowsRotation == false)
    }

    @Test("set categorybitmask writes physics body categoryBitmask")
    func setCategoryBitmask() {
        let doc = runScriptAgainstSprite("set the categorybitmask of sprite \"ball\" to 4")
        #expect(sprite(doc)?.physicsBody?.categoryBitmask == 4)
    }

    @Test("set collisionbitmask writes physics body collisionBitmask")
    func setCollisionBitmask() {
        let doc = runScriptAgainstSprite("set the collisionbitmask of sprite \"ball\" to 7")
        #expect(sprite(doc)?.physicsBody?.collisionBitmask == 7)
    }
}

@Suite("Property audit: scene width/height SET", .serialized)
struct SceneWidthHeightSetTests {
    @Test("set the width of scene updates size.width")
    func setSceneWidth() {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var area = Part(partType: .spriteArea, cardId: cardId, name: "arena")
        let spec = SpriteAreaSpec(
            defaultSceneNamed: "main",
            fallbackSize: SizeSpec(width: 400, height: 300)
        )
        area.setSpriteAreaSpec(spec)
        doc.addPart(area)
        doc.cards[0].script = """
        on openCard
          set the width of scene "main" to 800
        end openCard
        """
        let result = MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        )
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        let area2 = result.modifiedDocument?.parts.first { $0.name == "arena" }
        #expect(area2?.spriteAreaSpecModel?.activeScene?.size.width == 800)
    }

    @Test("set the height of scene updates size.height")
    func setSceneHeight() {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var area = Part(partType: .spriteArea, cardId: cardId, name: "arena")
        let spec = SpriteAreaSpec(
            defaultSceneNamed: "main",
            fallbackSize: SizeSpec(width: 400, height: 300)
        )
        area.setSpriteAreaSpec(spec)
        doc.addPart(area)
        doc.cards[0].script = """
        on openCard
          set the height of scene "main" to 600
        end openCard
        """
        let result = MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        )
        #expect(result.status == .completed, "Script error: \(result.error?.message ?? "")")
        let area2 = result.modifiedDocument?.parts.first { $0.name == "arena" }
        #expect(area2?.spriteAreaSpecModel?.activeScene?.size.height == 600)
    }
}
