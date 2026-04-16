import Testing
import Foundation
@testable import HypeCore

// Regression tests for the bug where AI-produced sprite scene
// additions silently disappeared. Root cause: the `repair` intent
// sends a `SceneRepairProposal` whose `diff.addNodes` is typed as
// `[HypeNodeSpec]`. The synthesized strict `Codable` on
// `HypeNodeSpec`, `ShapeNodeSpec`, and `PhysicsBodySpec` rejected
// any missing required field or unknown enum value — and because
// the outer `SceneRepairProposal.init(from:)` used `try? … ?? SceneDiff()`
// to read the diff, the entire set of additions collapsed to an
// empty diff with no user-visible error. The `wantsPhysicsBounce`
// normalizer then injected its own boundary walls and a default
// bounce node, which is why the user only saw boundary lines and
// not their red/blue/green shapes.
//
// The fix: tolerant `init(from:)` on `HypeNodeSpec`, `ShapeNodeSpec`,
// and `PhysicsBodySpec` with synonym-aware enum decoding so every
// node survives the round trip. These tests pin the behavior down.
@Suite("HypeNodeSpec lenient decoding — AI repair path")
struct HypeNodeSpecLenientDecodeTests {

    // MARK: - HypeNodeSpec

    @Test("HypeNodeSpec decodes with all required fields missing except nodeType")
    func decodesWithMostFieldsMissing() throws {
        let json = #"{"nodeType":"shape"}"#
        let node = try JSONDecoder().decode(HypeNodeSpec.self, from: json.data(using: .utf8)!)
        #expect(node.nodeType == .shape)
        #expect(node.name == "")
        #expect(node.position.x == 0)
        #expect(node.position.y == 0)
        #expect(node.zPosition == 0)
        #expect(node.alpha == 1)
        #expect(node.xScale == 1)
        #expect(node.yScale == 1)
        #expect(node.actions.isEmpty)
        #expect(node.children.isEmpty)
    }

    @Test("HypeNodeSpec accepts non-UUID id strings and mints a fresh UUID")
    func nonUUIDIdMintedFresh() throws {
        let json = #"{"id":"red_square","name":"Red","nodeType":"shape"}"#
        let node = try JSONDecoder().decode(HypeNodeSpec.self, from: json.data(using: .utf8)!)
        // Any valid UUID is fine — we just care that decoding succeeded
        // rather than throwing on the non-UUID string.
        #expect(node.name == "Red")
    }

    @Test("unknown nodeType 'triangle' maps to shape via the tolerant decoder")
    func triangleNodeTypeMapsToShape() throws {
        let json = #"{"name":"tri","nodeType":"triangle"}"#
        let node = try JSONDecoder().decode(HypeNodeSpec.self, from: json.data(using: .utf8)!)
        #expect(node.nodeType == .shape)
    }

    @Test("nodeType 'text' synonym maps to label")
    func textNodeTypeMapsToLabel() throws {
        let json = #"{"name":"greeting","nodeType":"text"}"#
        let node = try JSONDecoder().decode(HypeNodeSpec.self, from: json.data(using: .utf8)!)
        #expect(node.nodeType == .label)
    }

    @Test("nodeType 'particles' synonym maps to emitter")
    func particlesSynonymMapsToEmitter() throws {
        let json = #"{"name":"sparks","nodeType":"particles"}"#
        let node = try JSONDecoder().decode(HypeNodeSpec.self, from: json.data(using: .utf8)!)
        #expect(node.nodeType == .emitter)
    }

    @Test("sprite node with explicit shapeSpec promotes to .shape")
    func spriteWithShapeSpecPromotesToShape() throws {
        // Common AI failure mode: model outputs nodeType "sprite" but
        // also gives a shapeSpec. Without promotion the scene bridge
        // renders an empty sprite with no texture. The lenient decoder
        // catches this and changes nodeType to .shape.
        let json = """
        {
            "name": "ball",
            "nodeType": "sprite",
            "shapeSpec": {
                "shapeType": "circle",
                "fillColor": "#FF0000"
            }
        }
        """
        let node = try JSONDecoder().decode(HypeNodeSpec.self, from: json.data(using: .utf8)!)
        #expect(node.nodeType == .shape)
        #expect(node.shapeSpec?.shapeType == .circle)
        #expect(node.shapeSpec?.fillColor == "#FF0000")
    }

    // MARK: - ShapeNodeSpec

    @Test("ShapeNodeSpec unknown shapeType 'square' maps to rect")
    func shapeSquareMapsToRect() throws {
        let json = #"{"shapeType":"square"}"#
        let shape = try JSONDecoder().decode(ShapeNodeSpec.self, from: json.data(using: .utf8)!)
        #expect(shape.shapeType == .rect)
    }

    @Test("ShapeNodeSpec unknown shapeType 'triangle' maps to path")
    func shapeTriangleMapsToPath() throws {
        let json = #"{"shapeType":"triangle"}"#
        let shape = try JSONDecoder().decode(ShapeNodeSpec.self, from: json.data(using: .utf8)!)
        #expect(shape.shapeType == .path)
    }

    @Test("ShapeNodeSpec with no shapeType field defaults to rect")
    func shapeNoShapeTypeDefaultsToRect() throws {
        let json = ##"{"fillColor":"#FF0000"}"##
        let shape = try JSONDecoder().decode(ShapeNodeSpec.self, from: json.data(using: .utf8)!)
        #expect(shape.shapeType == .rect)
        #expect(shape.fillColor == "#FF0000")
    }

    // MARK: - PhysicsBodySpec

    @Test("PhysicsBodySpec unknown bodyType 'polygon' falls back to rect AABB")
    func physicsPolygonFallsBackToRect() throws {
        let json = #"{"bodyType":"polygon"}"#
        let body = try JSONDecoder().decode(PhysicsBodySpec.self, from: json.data(using: .utf8)!)
        #expect(body.bodyType == .rect)
    }

    @Test("PhysicsBodySpec decodes from an empty object using all defaults")
    func physicsEmptyObjectDefaults() throws {
        let body = try JSONDecoder().decode(PhysicsBodySpec.self, from: "{}".data(using: .utf8)!)
        #expect(body.bodyType == .rect)
        #expect(body.isDynamic == true)
        #expect(body.restitution == 0.2)
        #expect(body.friction == 0.2)
        #expect(body.affectedByGravity == true)
        #expect(body.allowsRotation == true)
    }

    @Test("PhysicsBodyType 'triangle' maps to rect so bouncing physics still works")
    func physicsTriangleMapsToRect() throws {
        let json = #"{"bodyType":"triangle","isDynamic":true,"restitution":0.9}"#
        let body = try JSONDecoder().decode(PhysicsBodySpec.self, from: json.data(using: .utf8)!)
        #expect(body.bodyType == .rect)
        #expect(body.restitution == 0.9)
    }

    // MARK: - End-to-end SceneRepairProposal path (the exact bug repro)

    @Test("SceneRepairProposal addNodes survives the full decode with mixed off-spec shapes")
    func repairProposalWithAIShapesDecodesCleanly() throws {
        // The exact shape of what a model emits for "add a red square,
        // blue circle, and green triangle with physics to bounce" —
        // including the off-spec `"nodeType": "sprite"` / `"shape"`,
        // `"shapeType": "triangle"`, non-UUID IDs, and missing scalar
        // fields. Before the fix this decoded to an empty diff, which
        // is why the user saw nothing happen.
        let json = """
        {
            "areaName": "bounder",
            "summary": "three shapes with physics",
            "issues": [],
            "diff": {
                "addNodes": [
                    {
                        "id": "red_square",
                        "name": "red_square",
                        "nodeType": "shape",
                        "position": { "x": 100, "y": 100 },
                        "size": { "width": 100, "height": 100 },
                        "shapeSpec": {
                            "shapeType": "square",
                            "fillColor": "#FF0000"
                        },
                        "physicsBody": {
                            "bodyType": "rect",
                            "isDynamic": true,
                            "restitution": 0.95,
                            "affectedByGravity": false,
                            "velocityX": 200,
                            "velocityY": 150
                        }
                    },
                    {
                        "id": "blue_circle",
                        "name": "blue_circle",
                        "nodeType": "sprite",
                        "position": { "x": 300, "y": 200 },
                        "size": { "width": 100, "height": 100 },
                        "shapeSpec": {
                            "shapeType": "circle",
                            "fillColor": "#0055FF"
                        },
                        "physicsBody": {
                            "bodyType": "circle",
                            "isDynamic": true,
                            "restitution": 0.9
                        }
                    },
                    {
                        "id": "green_triangle",
                        "name": "green_triangle",
                        "nodeType": "triangle",
                        "position": { "x": 450, "y": 350 },
                        "size": { "width": 100, "height": 100 },
                        "shapeSpec": {
                            "shapeType": "triangle",
                            "fillColor": "#00DD22"
                        },
                        "physicsBody": {
                            "bodyType": "polygon",
                            "isDynamic": true,
                            "restitution": 0.85
                        }
                    }
                ]
            }
        }
        """
        let proposal = try JSONDecoder().decode(
            SceneRepairProposal.self,
            from: json.data(using: .utf8)!
        )
        // The diff now survives; previously it was an empty SceneDiff().
        let nodes = proposal.diff.addNodes ?? []
        #expect(nodes.count == 3)

        // Red square: "square" → rect shape, rect physics body.
        let red = nodes[0]
        #expect(red.nodeType == .shape)
        #expect(red.shapeSpec?.shapeType == .rect)
        #expect(red.shapeSpec?.fillColor == "#FF0000")
        #expect(red.physicsBody?.bodyType == .rect)

        // Blue circle: sprite + circle shapeSpec → promoted to shape.
        let blue = nodes[1]
        #expect(blue.nodeType == .shape)
        #expect(blue.shapeSpec?.shapeType == .circle)
        #expect(blue.shapeSpec?.fillColor == "#0055FF")
        #expect(blue.physicsBody?.bodyType == .circle)

        // Green triangle: "triangle" nodeType → shape, "triangle"
        // shapeType → path, "polygon" bodyType → rect.
        let green = nodes[2]
        #expect(green.nodeType == .shape)
        #expect(green.shapeSpec?.shapeType == .path)
        #expect(green.shapeSpec?.fillColor == "#00DD22")
        #expect(green.physicsBody?.bodyType == .rect)
    }

    @Test("applying the repaired diff adds all three nodes to the scene")
    func applyRepairedDiffActuallyAddsShapes() throws {
        // Confirms the full create-to-apply round trip now works.
        let json = """
        {
            "areaName": "bounder",
            "summary": "",
            "issues": [],
            "diff": {
                "addNodes": [
                    {
                        "id": "red_square",
                        "name": "red_square",
                        "nodeType": "shape",
                        "shapeSpec": { "shapeType": "rect", "fillColor": "#FF0000" },
                        "physicsBody": { "bodyType": "rect", "isDynamic": true }
                    },
                    {
                        "id": "blue_circle",
                        "name": "blue_circle",
                        "nodeType": "sprite",
                        "shapeSpec": { "shapeType": "circle", "fillColor": "#0055FF" }
                    },
                    {
                        "id": "green_triangle",
                        "name": "green_triangle",
                        "nodeType": "shape",
                        "shapeSpec": { "shapeType": "triangle", "fillColor": "#00DD22" }
                    }
                ]
            }
        }
        """
        let proposal = try JSONDecoder().decode(
            SceneRepairProposal.self,
            from: json.data(using: .utf8)!
        )
        var scene = SceneSpec(name: "main", size: SizeSpec(width: 400, height: 300))
        proposal.diff.apply(to: &scene)
        #expect(scene.nodes.count == 3)
        let names = Set(scene.nodes.map { $0.name })
        #expect(names == ["red_square", "blue_circle", "green_triangle"])
    }
}
