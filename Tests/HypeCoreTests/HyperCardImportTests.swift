import Foundation
import Testing
@testable import HypeCore

@Suite("HyperCard import and XCMD/XFCN emulation")
struct HyperCardImportTests {

    @Test("block parser accepts a minimal HyperCard stack")
    func blockParserAcceptsMinimalStack() throws {
        let data = makeSyntheticHyperCardStack()
        let blocks = try HyperCardBlockParser().parse(data: data)

        #expect(blocks.map(\.type).contains("STAK"))
        #expect(blocks.map(\.type).contains("BKGD"))
        #expect(blocks.map(\.type).contains("CARD"))
        #expect(blocks.last?.type == "TAIL")
    }

    @Test("converter imports cards, backgrounds, parts, scripts, and original fork metadata")
    func converterImportsSyntheticStack() throws {
        let data = makeSyntheticHyperCardStack()
        let result = try HyperCardToHypeConverter().convert(data: data)
        let document = result.document

        #expect(document.stack.width == 640)
        #expect(document.stack.height == 480)
        #expect(document.backgrounds.count == 1)
        #expect(document.cards.count == 1)
        #expect(document.parts.count == 2)
        #expect(document.stack.script.contains("on openStack"))
        #expect(document.cards[0].script.contains("on openCard"))
        #expect(document.parts.contains { $0.name == "Card Field" && $0.textContent == "hello from card" })
        #expect(document.parts.contains { $0.name == "BG Button" && $0.script.contains("on mouseUp") })
        #expect(document.legacyImport?.embeddedDataFork == data)
        #expect(result.report.importedScripts >= 3)
    }

    @Test("resource fork parser discovers XCMD resources")
    func resourceForkParserDiscoversXCMD() throws {
        let fork = makeSyntheticResourceFork()
        let resources = try MacResourceForkReader().parse(fork)

        let xcmd = try #require(resources.first(where: { $0.type == "XCMD" }))
        #expect(xcmd.name == "AddColor")
        #expect(xcmd.id == 128)
        #expect(xcmd.data == Data([1, 2, 3]))
    }

    @Test("converter records XCMD resources as non-native emulation targets")
    func converterRecordsExternalResources() throws {
        let result = try HyperCardToHypeConverter().convert(
            data: makeSyntheticHyperCardStack(),
            resourceFork: makeSyntheticResourceFork()
        )

        let external = try #require(result.report.externalResources.first)
        #expect(external.kind == .xcmd)
        #expect(external.name == "AddColor")
        #expect(external.emulationStatus == .knownUnsupported)
        #expect(result.report.unsupportedFeatures.contains { $0.contains("XCMD/XFCN") })
    }

    @Test("parser accepts classic XCMD command syntax")
    func parserAcceptsExternalCommandSyntax() throws {
        let script = try parse("""
        on mouseUp
          SetCursor "watch"
          AddColor "card", "indexed"
        end mouseUp
        """)

        #expect(script.handlers.count == 1)
        #expect(script.handlers[0].body.count == 2)
        guard case .externalCommand(let name, let arguments) = script.handlers[0].body[0] else {
            Issue.record("Expected external command statement")
            return
        }
        #expect(name == "SetCursor")
        #expect(arguments.count == 1)
    }

    @Test("interpreter routes emulated XFCN function calls through registry")
    func interpreterRoutesEmulatedXFCN() async throws {
        var document = HypeDocument.newDocument(name: "External Test")
        let cardId = try #require(document.cards.first?.id)
        document.addPart(Part(partType: .field, cardId: cardId, name: "out"))
        let handler = try parse("""
        on mouseUp
          put HypeVersion() into field "out"
        end mouseUp
        """).handlers[0]

        let result = await Interpreter().executeAsync(
            handler: handler,
            params: [],
            context: ExecutionContext(targetId: cardId, currentCardId: cardId, document: document)
        )

        #expect(result.status == .completed)
        let modified = try #require(result.modifiedDocument)
        let out = try #require(modified.parts.first(where: { $0.name == "out" }))
        #expect(out.textContent == "Hype HyperCard compatibility layer")
    }

    @Test("unknown XCMD does not crash and sets the result diagnostic")
    func unknownXCMDDegradesToDiagnostic() async throws {
        var document = HypeDocument.newDocument(name: "External Test")
        let cardId = try #require(document.cards.first?.id)
        document.addPart(Part(partType: .field, cardId: cardId, name: "out"))
        let handler = try parse("""
        on mouseUp
          MissingClassicExternal "x"
          put the result into field "out"
        end mouseUp
        """).handlers[0]

        let result = await Interpreter().executeAsync(
            handler: handler,
            params: [],
            context: ExecutionContext(targetId: cardId, currentCardId: cardId, document: document)
        )

        #expect(result.status == .completed)
        let modified = try #require(result.modifiedDocument)
        let out = try #require(modified.parts.first(where: { $0.name == "out" }))
        #expect(out.textContent.contains("Can't Load External"))
        #expect(out.textContent.contains("MissingClassicExternal"))
    }

    private func parse(_ source: String) throws -> Script {
        var lexer = Lexer(source: source)
        var parser = Parser(tokens: lexer.tokenize())
        return try parser.parse()
    }
}

private func makeSyntheticHyperCardStack() -> Data {
    var data = Data()
    data.append(hcBlock(type: "STAK", id: 1, payload: makeStackPayload()))
    data.append(hcBlock(type: "BKGD", id: 100, payload: makeBackgroundPayload()))
    data.append(hcBlock(type: "CARD", id: 200, payload: makeCardPayload()))
    data.append(hcBlock(type: "TAIL", id: 0, payload: Data()))
    return data
}

private func makeStackPayload() -> Data {
    var payload = Data(repeating: 0, count: 0x620)
    payload.setInt32BE(2, at: 0)
    payload.setUInt16BE(480, at: 0x1A8)
    payload.setUInt16BE(640, at: 0x1AA)
    payload.writeCString("on openStack\n  pass openStack\nend openStack", at: 0x5F0)
    return payload
}

private func makeBackgroundPayload() -> Data {
    let part = makePartRecord(id: 1, rawType: 1, name: "BG Button", text: "", script: "on mouseUp\n  answer \"hi\"\nend mouseUp", rect: (20, 20, 120, 60))
    let content = makePartContent(partId: 1, text: "")
    var payload = Data(repeating: 0, count: 34)
    payload.setUInt16BE(1, at: 20)
    payload.setUInt32BE(UInt32(part.count), at: 24)
    payload.setUInt16BE(1, at: 28)
    payload.setUInt32BE(UInt32(content.count), at: 30)
    payload.append(part)
    payload.append(content)
    payload.appendMacRomanCString("Main Background")
    payload.appendMacRomanCString("on openBackground\n  pass openBackground\nend openBackground")
    return payload
}

private func makeCardPayload() -> Data {
    let part = makePartRecord(id: 2, rawType: 2, name: "Card Field", text: "hello from card", script: "", rect: (40, 60, 260, 100))
    let content = makePartContent(partId: -2, text: "hello from card")
    var payload = Data(repeating: 0, count: 38)
    payload.setInt32BE(100, at: 20)
    payload.setUInt16BE(1, at: 24)
    payload.setUInt32BE(UInt32(part.count), at: 28)
    payload.setUInt16BE(1, at: 32)
    payload.setUInt32BE(UInt32(content.count), at: 34)
    payload.append(part)
    payload.append(content)
    payload.appendMacRomanCString("First Card")
    payload.appendMacRomanCString("on openCard\n  put \"opened\" into field \"Card Field\"\nend openCard")
    return payload
}

private func makePartRecord(
    id: Int,
    rawType: UInt8,
    name: String,
    text: String,
    script: String,
    rect: (left: Int16, top: Int16, right: Int16, bottom: Int16)
) -> Data {
    var record = Data(repeating: 0, count: 30)
    record.setInt16BE(Int16(id), at: 2)
    record[record.startIndex + 4] = rawType
    record.setInt16BE(rect.top, at: 6)
    record.setInt16BE(rect.left, at: 8)
    record.setInt16BE(rect.bottom, at: 10)
    record.setInt16BE(rect.right, at: 12)
    record[record.startIndex + 15] = rawType == 2 ? 2 : 3
    record.setInt16BE(-1, at: 22)
    record.setInt16BE(12, at: 24)
    record.appendMacRomanCString(name)
    record.append(0)
    record.appendMacRomanCString(script)
    record.setUInt16BE(UInt16(record.count), at: 0)
    _ = text
    return record
}

private func makePartContent(partId: Int, text: String) -> Data {
    var content = Data()
    let textData = text.data(using: .macOSRoman) ?? Data()
    let size = UInt16(4 + 1 + textData.count)
    content.appendUInt16BE(size)
    content.appendInt16BE(Int16(partId))
    content.append(0)
    content.append(textData)
    return content
}

private func hcBlock(type: String, id: Int32, payload: Data) -> Data {
    var data = Data()
    data.appendInt32BE(Int32(payload.count + 16))
    data.append(type.data(using: .macOSRoman)!)
    data.appendInt32BE(id)
    data.append(contentsOf: [0, 0, 0, 0])
    data.append(payload)
    return data
}

private func makeSyntheticResourceFork() -> Data {
    let resourcePayload = Data([1, 2, 3])
    let dataOffset = 0x100
    let mapOffset = 0x200
    let typeListOffset = 28
    let refListOffset = 10
    let nameListOffset = typeListOffset + refListOffset + 12
    let mapLength = nameListOffset + 1 + "AddColor".count
    let dataLength = 4 + resourcePayload.count

    var fork = Data(repeating: 0, count: mapOffset + mapLength)
    fork.setUInt32BE(UInt32(dataOffset), at: 0)
    fork.setUInt32BE(UInt32(mapOffset), at: 4)
    fork.setUInt32BE(UInt32(dataLength), at: 8)
    fork.setUInt32BE(UInt32(mapLength), at: 12)
    fork.setUInt32BE(UInt32(resourcePayload.count), at: dataOffset)
    fork.replaceSubrange((dataOffset + 4)..<(dataOffset + 4 + resourcePayload.count), with: resourcePayload)

    fork.setUInt16BE(UInt16(typeListOffset), at: mapOffset + 24)
    fork.setUInt16BE(UInt16(nameListOffset), at: mapOffset + 26)
    let typeListStart = mapOffset + typeListOffset
    fork.setInt16BE(0, at: typeListStart)
    fork.replaceSubrange((typeListStart + 2)..<(typeListStart + 6), with: "XCMD".data(using: .macOSRoman)!)
    fork.setInt16BE(0, at: typeListStart + 6)
    fork.setUInt16BE(UInt16(refListOffset), at: typeListStart + 8)
    let refStart = typeListStart + refListOffset
    fork.setInt16BE(128, at: refStart)
    fork.setInt16BE(0, at: refStart + 2)
    fork[refStart + 4] = 0
    fork[refStart + 5] = 0
    fork[refStart + 6] = 0
    fork[refStart + 7] = 0
    let nameStart = mapOffset + nameListOffset
    fork[nameStart] = UInt8("AddColor".count)
    fork.replaceSubrange((nameStart + 1)..<(nameStart + 1 + "AddColor".count), with: "AddColor".data(using: .macOSRoman)!)
    return fork
}

private extension Data {
    mutating func appendUInt16BE(_ value: UInt16) {
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    mutating func appendInt16BE(_ value: Int16) {
        appendUInt16BE(UInt16(bitPattern: value))
    }

    mutating func appendUInt32BE(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    mutating func appendInt32BE(_ value: Int32) {
        appendUInt32BE(UInt32(bitPattern: value))
    }

    mutating func setUInt16BE(_ value: UInt16, at offset: Int) {
        self[startIndex + offset] = UInt8((value >> 8) & 0xFF)
        self[startIndex + offset + 1] = UInt8(value & 0xFF)
    }

    mutating func setInt16BE(_ value: Int16, at offset: Int) {
        setUInt16BE(UInt16(bitPattern: value), at: offset)
    }

    mutating func setUInt32BE(_ value: UInt32, at offset: Int) {
        self[startIndex + offset] = UInt8((value >> 24) & 0xFF)
        self[startIndex + offset + 1] = UInt8((value >> 16) & 0xFF)
        self[startIndex + offset + 2] = UInt8((value >> 8) & 0xFF)
        self[startIndex + offset + 3] = UInt8(value & 0xFF)
    }

    mutating func setInt32BE(_ value: Int32, at offset: Int) {
        setUInt32BE(UInt32(bitPattern: value), at: offset)
    }

    mutating func appendMacRomanCString(_ value: String) {
        append(value.data(using: .macOSRoman) ?? Data())
        append(0)
    }

    mutating func writeCString(_ value: String, at offset: Int) {
        let bytes = value.data(using: .macOSRoman) ?? Data()
        replaceSubrange(offset..<(offset + bytes.count), with: bytes)
        self[offset + bytes.count] = 0
    }
}
