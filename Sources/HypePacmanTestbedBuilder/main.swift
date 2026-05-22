import Foundation
import HypeCore

private enum TestbedError: Error, CustomStringConvertible {
    case missingSpriteArea

    var description: String {
        switch self {
        case .missingSpriteArea:
            return "Pac-Man sprite area was not created."
        }
    }
}

private func makePacmanAccessibilityTestbed() throws -> HypeDocument {
    var document = HypeDocument.newDocument(name: "Pac-Man Accessibility Testbed")
    let cardId = document.sortedCards[0].id

    var title = Part(
        partType: .field,
        cardId: cardId,
        name: "instructions",
        left: 24,
        top: 18,
        width: 520,
        height: 38
    )
    title.textContent = "Pac-Man testbed: verify canvas, sprite scene, maze, player, ghosts, and pellets via Accessibility."
    title.lockText = true
    title.fieldStyle = .transparent
    document.addPart(title)

    var startButton = Part(
        partType: .button,
        cardId: cardId,
        name: "startGame",
        left: 568,
        top: 18,
        width: 112,
        height: 38
    )
    startButton.textContent = "Start"
    startButton.script = """
    on mouseUp
      send "sceneDidLoad" to spriteArea "pacmanArea"
    end mouseUp
    """
    document.addPart(startButton)

    let spriteArea = Part(
        partType: .spriteArea,
        cardId: cardId,
        name: "pacmanArea",
        left: 24,
        top: 72,
        width: SpriteGameTemplateBuilder.defaultPacmanSceneSize.width,
        height: SpriteGameTemplateBuilder.defaultPacmanSceneSize.height
    )
    document.addPart(spriteArea)

    guard let areaIndex = document.parts.firstIndex(where: { $0.id == spriteArea.id }) else {
        throw TestbedError.missingSpriteArea
    }
    _ = try SpriteGameTemplateBuilder.applyPacmanTemplate(
        to: &document,
        partIndex: areaIndex,
        spriteAreaName: "pacmanArea"
    )

    return document
}

private func write(_ document: HypeDocument, to url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(document)
    try data.write(to: url, options: [.atomic])
}

let outputPath = CommandLine.arguments.dropFirst().first
    ?? "TestStacks/PacmanAccessibilityTestbed.hype"
let outputURL = URL(fileURLWithPath: outputPath, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
let document = try makePacmanAccessibilityTestbed()
try write(document, to: outputURL)
print("Wrote \(outputURL.path)")
