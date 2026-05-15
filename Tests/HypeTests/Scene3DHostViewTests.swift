import AppKit
import Foundation
import Testing
@testable import Hype
@testable import HypeCore

@MainActor
@Suite("Scene3D host view")
struct Scene3DHostViewTests {
    @Test("host loads repository GLB through its USDZ companion")
    func hostLoadsRepositoryGLBThroughUSDZCompanion() async throws {
        let usdzData = try Self.makeMinimalUSDZData()
        let glb = SpriteAsset(
            name: "robot.glb",
            kind: .model3D,
            mimeType: "model/gltf-binary",
            data: Data([0x67, 0x6C, 0x54, 0x46]),
            width: 0,
            height: 0
        )
        let usdz = SpriteAsset(
            name: "robot.usdz",
            kind: .model3D,
            mimeType: "model/vnd.usdz+zip",
            data: usdzData,
            width: 0,
            height: 0
        )
        let repository = SpriteRepository(assets: [glb, usdz])
        var part = Part(partType: .scene3D, name: "Viewer")
        part.scene3DAssetRef = repository.assetRef(for: glb)

        let host = Scene3DHostNSView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        var failure: String?
        host.onLoadFailed = { failure = $0 }
        host.apply(part, repository: repository)

        try await Self.waitUntil(timeoutSeconds: 2) {
            host.scnView.scene != nil || failure != nil
        }

        #expect(failure == nil)
        #expect(host.scnView.scene != nil)
        #expect(host.scnView.scene?.rootNode.childNodes.isEmpty == false)
    }

    private static func waitUntil(
        timeoutSeconds: TimeInterval,
        condition: @MainActor @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private static func makeMinimalUSDZData() throws -> Data {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("hype-usdz-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let usdaURL = root.appendingPathComponent("robot.usda")
        let usdzURL = root.appendingPathComponent("robot.usdz")
        let usda = """
        #usda 1.0
        (
            defaultPrim = "Robot"
            metersPerUnit = 1
            upAxis = "Y"
        )

        def Xform "Robot"
        {
            def Cube "Mesh"
            {
                double size = 1
            }
        }
        """
        try usda.write(to: usdaURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/usdzip")
        process.arguments = [usdzURL.path, usdaURL.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = (process.standardError as? Pipe)?.fileHandleForReading.readDataToEndOfFile() ?? Data()
            let message = String(data: data, encoding: .utf8) ?? "usdzip failed"
            throw NSError(domain: "Scene3DHostViewTests", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }

        return try Data(contentsOf: usdzURL)
    }
}
