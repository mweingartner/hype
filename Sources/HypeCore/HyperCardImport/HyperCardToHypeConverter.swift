import Foundation

public struct HyperCardImportResult: Sendable {
    public var document: HypeDocument
    public var report: HyperCardImportReport

    public init(document: HypeDocument, report: HyperCardImportReport) {
        self.document = document
        self.report = report
    }
}

public struct HyperCardToHypeConverter: Sendable {
    public var options: HyperCardImportOptions

    public init(options: HyperCardImportOptions = HyperCardImportOptions()) {
        self.options = options
    }

    public func convert(package: HyperCardImportPackage) throws -> HyperCardImportResult {
        let blocks = try HyperCardBlockParser(options: options).parse(data: package.dataFork)
        let resources: [MacResource]
        var warnings: [String] = []
        if let resourceFork = package.resourceFork, !resourceFork.isEmpty {
            do {
                resources = try MacResourceForkReader(maxResourceDataBytes: options.maxBlockBytes).parse(resourceFork)
            } catch {
                warnings.append("Resource fork could not be parsed: \(error.localizedDescription)")
                resources = []
            }
        } else {
            resources = []
            warnings.append("No resource fork was found. XCMD/XFCN, sounds, icons, PICTs, and AddColor resources may be unavailable.")
        }

        guard let stackBlock = blocks.first(where: { $0.type == "STAK" }) else {
            throw HyperCardImportError.missingStackBlock
        }

        var stackInfo = parseStack(block: stackBlock)
        if stackInfo.name == "Imported HyperCard Stack",
           let sourceName = package.sourceURL?.deletingPathExtension().lastPathComponent,
           !sourceName.isEmpty {
            stackInfo.name = sourceName
        }
        warnings.append(contentsOf: stackInfo.warnings)

        let fontTable = parseFontTable(blocks.first(where: { $0.type == "FTBL" }))
        let backgrounds = blocks.filter { $0.type == "BKGD" }.map { parseBackground(block: $0, fontTable: fontTable) }
        let cards = blocks.filter { $0.type == "CARD" }.map { parseCard(block: $0, fontTable: fontTable) }
        let defaultBackgroundLegacyID = backgrounds.first?.legacyID

        var document = HypeDocument.newDocument(name: stackInfo.name)
        document.stack.width = stackInfo.width
        document.stack.height = stackInfo.height
        document.stack.script = disabledLegacyScript(stackInfo.script)
        document.stack.defaultFont = fontTable.values.first ?? document.stack.defaultFont
        document.backgrounds = []
        document.cards = []
        document.parts = []
        document.paintLayers = []
        document.constraints = []

        var backgroundIdMap: [Int32: UUID] = [:]
        for (index, importedBackground) in backgrounds.enumerated() {
            let bg = Background(
                stackId: document.stack.id,
                name: importedBackground.name.isEmpty ? "Background \(index + 1)" : importedBackground.name,
                sortKey: String(format: "a%06d", index),
                script: disabledLegacyScript(importedBackground.script)
            )
            document.backgrounds.append(bg)
            backgroundIdMap[importedBackground.legacyID] = bg.id
        }
        if document.backgrounds.isEmpty {
            let bg = Background(stackId: document.stack.id, name: "Background 1")
            document.backgrounds.append(bg)
            warnings.append("The stack had no readable BKGD blocks; Hype created a default background.")
        }
        document.defaultBackgroundId = document.backgrounds.first?.id

        var cardIdMap: [Int32: UUID] = [:]
        let sortedCards = orderCards(cards, blocks: blocks)
        for (index, importedCard) in sortedCards.enumerated() {
            let bgId =
                backgroundIdMap[importedCard.backgroundID] ??
                defaultBackgroundLegacyID.flatMap { backgroundIdMap[$0] } ??
                document.backgrounds[0].id
            let card = Card(
                stackId: document.stack.id,
                backgroundId: bgId,
                name: importedCard.name.isEmpty ? "Card \(index + 1)" : importedCard.name,
                sortKey: String(format: "a%06d", index),
                marked: importedCard.marked,
                script: disabledLegacyScript(importedCard.script)
            )
            document.cards.append(card)
            cardIdMap[importedCard.legacyID] = card.id
        }
        if document.cards.isEmpty {
            let card = Card(stackId: document.stack.id, backgroundId: document.backgrounds[0].id, name: "Card 1")
            document.cards.append(card)
            warnings.append("The stack had no readable CARD blocks; Hype created a default card.")
        }

        var importedPartCount = 0
        for importedBackground in backgrounds {
            guard let bgId = backgroundIdMap[importedBackground.legacyID] else { continue }
            for importedPart in importedBackground.parts {
                document.parts.append(makeHypePart(from: importedPart, cardId: nil, backgroundId: bgId))
                importedPartCount += 1
            }
        }
        for importedCard in sortedCards {
            guard let cardId = cardIdMap[importedCard.legacyID] else { continue }
            for importedPart in importedCard.parts {
                document.parts.append(makeHypePart(from: importedPart, cardId: cardId, backgroundId: nil))
                importedPartCount += 1
            }
        }

        var unsupported: [String] = []
        if blocks.contains(where: { $0.type == "BMAP" }) {
            unsupported.append("BMAP paint layers are detected but WOBA bitmap decompression is not yet implemented; original bitmap blocks are preserved in legacy metadata.")
        }
        if resources.contains(where: { $0.type == "PICT" }) {
            unsupported.append("PICT resources are preserved but not converted to Hype image parts yet.")
        }
        if resources.contains(where: { $0.type == "snd " }) {
            let converted = convertSoundResources(resources, to: &document, warnings: &warnings)
            if converted == 0 {
                unsupported.append("Classic snd resources are preserved but could not be converted to Hype audio repository assets.")
            }
        }
        let externalResources = externalResources(from: resources)
        if !externalResources.isEmpty {
            unsupported.append("Original XCMD/XFCN native code is not executed. Hype uses a Swift emulation registry and reports unsupported externals at runtime.")
        }
        let allScripts = [document.stack.script] + document.backgrounds.map(\.script) + document.cards.map(\.script) + document.parts.map(\.script)
        if allScripts.contains(where: LegacyHyperTalkScript.isDisabledForHypeTalkRuntime) {
            warnings.append("Imported HyperCard scripts that are not valid HypeTalk are preserved as comments and disabled until translated.")
        }

        let importedScripts = allScripts.filter { !$0.isEmpty }.count

        let report = HyperCardImportReport(
            stackName: stackInfo.name,
            cardSize: HyperCardSize(width: stackInfo.width, height: stackInfo.height),
            blockSummary: HyperCardBlockParser.summaries(for: blocks),
            resourceSummary: MacResourceForkReader.summaries(for: resources),
            externalResources: externalResources,
            importedBackgrounds: document.backgrounds.count,
            importedCards: document.cards.count,
            importedParts: importedPartCount,
            importedScripts: importedScripts,
            warnings: stableUnique(warnings),
            unsupportedFeatures: stableUnique(unsupported)
        )

        let totalOriginalBytes = package.dataFork.count + (package.resourceFork?.count ?? 0)
        let embedOriginal = options.preserveOriginalForks && totalOriginalBytes <= options.maxEmbeddedOriginalBytes
        document.legacyImport = LegacyStackImportMetadata(
            sourceFileName: package.sourceURL?.lastPathComponent,
            dataForkSHA256: package.dataFork.hypeSHA256Hex,
            resourceForkSHA256: package.resourceFork?.hypeSHA256Hex,
            embeddedDataFork: embedOriginal ? package.dataFork : nil,
            embeddedResourceFork: embedOriginal ? package.resourceFork : nil,
            report: report
        )
        if options.preserveOriginalForks && !embedOriginal {
            document.legacyImport?.report.warnings.append(
                "Original forks were not embedded because their combined size (\(totalOriginalBytes) bytes) exceeds the configured limit."
            )
        }

        return HyperCardImportResult(document: document, report: document.legacyImport?.report ?? report)
    }

    public func convert(data: Data, sourceURL: URL? = nil, resourceFork: Data? = nil) throws -> HyperCardImportResult {
        let package = try HyperCardInputNormalizer(options: options).normalize(data: data, sourceURL: sourceURL, resourceFork: resourceFork)
        return try convert(package: package)
    }

    private func parseStack(block: HyperCardBlock) -> ImportedStackInfo {
        let reader = HyperCardBinaryReader(block.payload)
        var warnings: [String] = []
        let rawHeight = reader.uint16(at: 0x1A8).map(Int.init) ?? 0
        let rawWidth = reader.uint16(at: 0x1AA).map(Int.init) ?? 0
        let height = rawHeight == 0 ? 342 : rawHeight
        let width = rawWidth == 0 ? 512 : rawWidth
        var script = ""
        if let firstScriptByte = reader.uint8(at: 0x5F0), firstScriptByte == 0 {
            warnings.append("The stack script appears to be compiled OSA data; Hype preserved an empty stack script.")
        } else if let (text, _) = reader.cString(at: 0x5F0) {
            script = normalizeHyperTalkLineEndings(text)
        }
        return ImportedStackInfo(name: "Imported HyperCard Stack", width: width, height: height, script: script, warnings: warnings)
    }

    private func parseFontTable(_ block: HyperCardBlock?) -> [Int: String] {
        guard let block else { return [:] }
        let reader = HyperCardBinaryReader(block.payload)
        guard let count32 = reader.int32(at: 0), count32 >= 0 else { return [:] }
        var offset = 8
        var fonts: [Int: String] = [:]
        for _ in 0..<Int(count32) {
            guard let fontID = reader.int16(at: offset),
                  let (name, next) = reader.cString(at: offset + 2) else { break }
            fonts[Int(fontID)] = name
            offset = next
            if offset % 2 != 0 { offset += 1 }
        }
        return fonts
    }

    private func parseCard(block: HyperCardBlock, fontTable: [Int: String]) -> ImportedCard {
        let reader = HyperCardBinaryReader(block.payload)
        let flags = reader.uint16(at: 4) ?? 0
        let backgroundID = reader.int32(at: 20) ?? 0
        let partCount = Int(reader.uint16(at: 24) ?? 0)
        let partListSize = Int(reader.uint32(at: 28) ?? 0)
        let contentCount = Int(reader.uint16(at: 32) ?? 0)
        let contentListSize = Int(reader.uint32(at: 34) ?? 0)
        let partListOffset = 38
        let partListEnd = min(reader.count, partListOffset + max(0, partListSize))
        let parts = parseParts(
            reader: reader,
            partCount: partCount,
            partListOffset: partListOffset,
            partListEnd: partListEnd,
            contentCount: contentCount,
            contentListSize: contentListSize,
            fontTable: fontTable,
            isBackgroundPartList: false
        )
        let tailOffset = min(reader.count, partListEnd + max(0, contentListSize))
        let (name, afterName) = reader.cString(at: tailOffset) ?? ("", tailOffset)
        let (script, _) = reader.cString(at: afterName) ?? ("", afterName)
        return ImportedCard(
            legacyID: block.id,
            backgroundID: backgroundID,
            name: name,
            script: normalizeHyperTalkLineEndings(script),
            marked: (flags & 0x0800) != 0,
            parts: parts
        )
    }

    private func parseBackground(block: HyperCardBlock, fontTable: [Int: String]) -> ImportedBackground {
        let reader = HyperCardBinaryReader(block.payload)
        let partCount = Int(reader.uint16(at: 20) ?? 0)
        let partListSize = Int(reader.uint32(at: 24) ?? 0)
        let contentCount = Int(reader.uint16(at: 28) ?? 0)
        let contentListSize = Int(reader.uint32(at: 30) ?? 0)
        let partListOffset = 34
        let partListEnd = min(reader.count, partListOffset + max(0, partListSize))
        let parts = parseParts(
            reader: reader,
            partCount: partCount,
            partListOffset: partListOffset,
            partListEnd: partListEnd,
            contentCount: contentCount,
            contentListSize: contentListSize,
            fontTable: fontTable,
            isBackgroundPartList: true
        )
        let tailOffset = min(reader.count, partListEnd + max(0, contentListSize))
        let (name, afterName) = reader.cString(at: tailOffset) ?? ("", tailOffset)
        let (script, _) = reader.cString(at: afterName) ?? ("", afterName)
        return ImportedBackground(
            legacyID: block.id,
            name: name,
            script: normalizeHyperTalkLineEndings(script),
            parts: parts
        )
    }

    private func parseParts(
        reader: HyperCardBinaryReader,
        partCount: Int,
        partListOffset: Int,
        partListEnd: Int,
        contentCount: Int,
        contentListSize: Int,
        fontTable: [Int: String],
        isBackgroundPartList: Bool
    ) -> [ImportedPart] {
        var parts: [ImportedPart] = []
        var offset = partListOffset
        for index in 0..<partCount {
            guard offset + 32 <= partListEnd,
                  let size = reader.uint16(at: offset),
                  size >= 32 else { break }
            let entryEnd = min(partListEnd, offset + Int(size))
            let legacyID = Int(reader.int16(at: offset + 2) ?? Int16(index + 1))
            let rawType = Int(reader.uint8(at: offset + 4) ?? 1)
            let flags = reader.uint16(at: offset + 14) ?? 0
            let style = reader.uint8(at: offset + 15) ?? 0
            let top = Double(reader.int16(at: offset + 6) ?? 0)
            let left = Double(reader.int16(at: offset + 8) ?? 0)
            let bottom = Double(reader.int16(at: offset + 10) ?? 40)
            let right = Double(reader.int16(at: offset + 12) ?? 120)
            let fontID = Int(reader.int16(at: offset + 22) ?? -1)
            let textSize = Double(reader.int16(at: offset + 24) ?? 12)
            let textStyleByte = reader.uint8(at: offset + 26) ?? 0
            let (name, afterName) = reader.cString(at: offset + 30, limit: entryEnd) ?? ("", offset + 30)
            let scriptStart = min(entryEnd, afterName + 1)
            let script = reader.cString(at: scriptStart, limit: entryEnd)?.0 ?? ""
            let kind = ImportedPartKind(rawType: rawType)

            parts.append(ImportedPart(
                legacyID: legacyID,
                kind: kind,
                name: name,
                text: "",
                script: normalizeHyperTalkLineEndings(script),
                left: left,
                top: top,
                width: max(1, right - left),
                height: max(1, bottom - top),
                visible: (flags & 0x8000) == 0,
                enabled: (flags & 0x4000) == 0,
                style: Int(style),
                textFont: fontTable[fontID] ?? "",
                textSize: textSize > 0 ? textSize : 12,
                textStyle: hyperCardTextStyle(from: textStyleByte),
                isBackgroundPart: isBackgroundPartList
            ))
            offset = entryEnd
        }

        let contentOffset = partListEnd
        let contentEnd = min(reader.count, contentOffset + max(0, contentListSize))
        let contents = parsePartContents(reader: reader, offset: contentOffset, end: contentEnd, count: contentCount)
        guard !contents.isEmpty else { return parts }

        for index in parts.indices {
            let key = parts[index].isBackgroundPart ? parts[index].legacyID : -abs(parts[index].legacyID)
            if let text = contents[key] ?? contents[parts[index].legacyID] {
                parts[index].text = text
            }
        }
        return parts
    }

    private func parsePartContents(reader: HyperCardBinaryReader, offset: Int, end: Int, count: Int) -> [Int: String] {
        var result: [Int: String] = [:]
        var cursor = offset
        for _ in 0..<count {
            guard cursor + 4 <= end,
                  let rawSize = reader.uint16(at: cursor),
                  let rawPartID = reader.int16(at: cursor + 2),
                  rawSize >= 4 else { break }
            let entryEnd = min(end, cursor + Int(rawSize))
            let bodyStart = cursor + 4
            var textStart = bodyStart
            if reader.uint8(at: bodyStart) == 0 {
                textStart = bodyStart + 1
            } else if let styleSize = reader.uint16(at: bodyStart) {
                textStart = min(entryEnd, bodyStart + 2 + Int(styleSize & 0x7FFF))
            }
            if textStart < entryEnd {
                let payload = reader.subdata(in: textStart..<entryEnd) ?? Data()
                let text = String(data: payload, encoding: .macOSRoman) ?? ""
                result[Int(rawPartID)] = normalizeHyperTalkLineEndings(text.trimmingCharacters(in: CharacterSet(charactersIn: "\0")))
            }
            cursor = entryEnd
        }
        return result
    }

    private func makeHypePart(from imported: ImportedPart, cardId: UUID?, backgroundId: UUID?) -> Part {
        let partType: PartType = imported.kind == .field ? .field : .button
        var part = Part(
            partType: partType,
            cardId: cardId,
            backgroundId: backgroundId,
            name: imported.name.isEmpty ? "\(partType.rawValue) \(abs(imported.legacyID))" : imported.name,
            sortKey: String(format: "a%06d", abs(imported.legacyID)),
            left: imported.left,
            top: imported.top,
            width: imported.width,
            height: imported.height
        )
        part.visible = imported.visible
        part.enabled = imported.enabled
        part.textContent = imported.text
        if !imported.textFont.isEmpty { part.textFont = imported.textFont }
        part.textSize = imported.textSize
        part.textStyle = imported.textStyle
        part.script = disabledLegacyScript(imported.script)

        switch imported.kind {
        case .button:
            part.buttonStyle = hyperCardButtonStyle(from: imported.style)
            part.showName = true
        case .field:
            part.fieldStyle = hyperCardFieldStyle(from: imported.style)
            part.lockText = false
            part.dontWrap = false
            part.textAlign = .left
        }
        return part
    }

    private func disabledLegacyScript(_ script: String) -> String {
        LegacyHyperTalkScript.preparedForHypeTalkRuntime(script)
    }

    private func orderCards(_ cards: [ImportedCard], blocks: [HyperCardBlock]) -> [ImportedCard] {
        let cardByID = Dictionary(uniqueKeysWithValues: cards.map { ($0.legacyID, $0) })
        let orderedIDs = parseCardOrder(blocks: blocks)
        let ordered = orderedIDs.compactMap { cardByID[$0] }
        guard !ordered.isEmpty else { return cards }
        let remaining = cards.filter { !orderedIDs.contains($0.legacyID) }
        return ordered + remaining
    }

    private func parseCardOrder(blocks: [HyperCardBlock]) -> [Int32] {
        guard let list = blocks.first(where: { $0.type == "LIST" }) else { return [] }
        let reader = HyperCardBinaryReader(list.payload)
        guard let pageCount32 = reader.int32(at: 0), pageCount32 > 0 else { return [] }
        var pageIDs: [Int32] = []
        var offset = 0x20
        for _ in 0..<Int(pageCount32) {
            guard let pageID = reader.int32(at: offset) else { break }
            pageIDs.append(pageID)
            offset += 6
        }
        let pageByID = Dictionary(uniqueKeysWithValues: blocks.filter { $0.type == "PAGE" }.map { ($0.id, $0) })
        var cardIDs: [Int32] = []
        for pageID in pageIDs {
            guard let page = pageByID[pageID] else { continue }
            let pageReader = HyperCardBinaryReader(page.payload)
            var cursor = 8
            while cursor + 4 <= pageReader.count {
                guard let cardID = pageReader.int32(at: cursor), cardID != 0 else { break }
                cardIDs.append(cardID)
                cursor += 8
            }
        }
        return cardIDs
    }

    private func externalResources(from resources: [MacResource]) -> [HyperCardExternalResource] {
        resources.compactMap { resource in
            let kind: HyperCardExternalKind
            switch resource.type {
            case "XCMD": kind = .xcmd
            case "XFCN": kind = .xfcn
            default: return nil
            }
            let name = resource.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedName = (name?.isEmpty == false) ? name! : "\(resource.type) \(resource.id)"
            return HyperCardExternalResource(
                kind: kind,
                id: resource.id,
                name: resolvedName,
                byteCount: resource.data.count,
                emulationStatus: HyperCardExternalRegistry.default.status(for: resolvedName, kind: kind)
            )
        }
    }

    private func hyperCardTextStyle(from byte: UInt8) -> String {
        var styles: [String] = []
        if (byte & 0x01) != 0 { styles.append("bold") }
        if (byte & 0x02) != 0 { styles.append("italic") }
        if (byte & 0x04) != 0 { styles.append("underline") }
        if (byte & 0x08) != 0 { styles.append("outline") }
        if (byte & 0x10) != 0 { styles.append("shadow") }
        return styles.isEmpty ? "plain" : styles.joined(separator: ",")
    }

    private func hyperCardButtonStyle(from style: Int) -> ButtonStyle {
        switch style {
        case 1: return .transparent
        case 2: return .opaque
        case 3: return .roundRect
        case 4: return .shadow
        case 5: return .checkBox
        case 6: return .radio
        default: return .standard
        }
    }

    private func hyperCardFieldStyle(from style: Int) -> FieldStyle {
        switch style {
        case 1: return .transparent
        case 3: return .shadow
        case 4: return .scrolling
        default: return .rectangle
        }
    }

    private func normalizeHyperTalkLineEndings(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
    }

    private func stableUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            let key = value.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(value)
        }
        return result
    }

    private func convertSoundResources(
        _ resources: [MacResource],
        to document: inout HypeDocument,
        warnings: inout [String]
    ) -> Int {
        let soundResources = resources.filter { $0.type == "snd " }
        var importedNames = Set(
            document.assetRepository.assets
                .filter { $0.kind == .audioClip }
                .map { $0.name.lowercased() }
        )
        var converted = 0
        for sound in soundResources {
            let assetName = soundResourceName(sound)
            guard !importedNames.contains(assetName.lowercased()) else { continue }
            guard sound.data.count > 0 else { continue }

            guard let wavBuffer = convertSoundResource(sound, warnings: &warnings) else { continue }
            importedNames.insert(assetName.lowercased())
            document.assetRepository.addAsset(Asset(
                name: assetName,
                kind: .audioClip,
                mimeType: "audio/wav",
                data: wavBuffer,
                tags: ["hypercard-import", "sound-resource"]
            ))
            converted += 1
        }
        return converted
    }

    private func convertSoundResource(_ sound: MacResource, warnings: inout [String]) -> Data? {
        guard let stackImport = try? StackImportRuntime.requireAvailable() else {
            let status = StackImportRuntime.status
            warnings.append("Failed to convert snd resource #\(sound.id): \(status.detail ?? status.aboutLine)")
            return nil
        }
        var errorPtr: UnsafePointer<CChar>? = nil
        let required = sound.data.withUnsafeBytes { sndPtr in
            stackImport.sndToWav(
                sndPtr.baseAddress,
                sound.data.count,
                nil,
                0,
                &errorPtr
            )
        }
        guard required > 0 else {
            let detail = errorPtr.map { String(cString: $0) } ?? "conversion failed"
            warnings.append("Failed to convert snd resource #\(sound.id): \(detail)")
            return nil
        }
        guard required <= options.maxBlockBytes else {
            warnings.append("Failed to convert snd resource #\(sound.id): converted WAV is too large (\(required) bytes).")
            return nil
        }

        var wavBuffer = Data(count: required)
        let written = wavBuffer.withUnsafeMutableBytes { wavPtr in
            sound.data.withUnsafeBytes { sndPtr in
                stackImport.sndToWav(
                    sndPtr.baseAddress,
                    sound.data.count,
                    wavPtr.baseAddress,
                    required,
                    &errorPtr
                )
            }
        }
        guard written == required else {
            let detail = errorPtr.map { String(cString: $0) } ?? "conversion failed"
            warnings.append("Failed to convert snd resource #\(sound.id): \(detail)")
            return nil
        }
        return wavBuffer
    }

    private func soundResourceName(_ res: MacResource) -> String {
        if let name = res.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "Sound \(res.id)"
    }
}

private struct ImportedStackInfo: Sendable {
    var name: String
    var width: Int
    var height: Int
    var script: String
    var warnings: [String]
}

private struct ImportedBackground: Sendable {
    var legacyID: Int32
    var name: String
    var script: String
    var parts: [ImportedPart]
}

private struct ImportedCard: Sendable {
    var legacyID: Int32
    var backgroundID: Int32
    var name: String
    var script: String
    var marked: Bool
    var parts: [ImportedPart]
}

private enum ImportedPartKind: Sendable {
    case button
    case field

    init(rawType: Int) {
        // HyperCard stores button and field as compact numeric part
        // records. Public reverse-engineered docs agree on the record
        // shape but historical stacks vary in exact type codes; accept
        // the common odd/even split and fall back to button.
        switch rawType {
        case 2, 4, 6, 8:
            self = .field
        default:
            self = .button
        }
    }
}

private struct ImportedPart: Sendable {
    var legacyID: Int
    var kind: ImportedPartKind
    var name: String
    var text: String
    var script: String
    var left: Double
    var top: Double
    var width: Double
    var height: Double
    var visible: Bool
    var enabled: Bool
    var style: Int
    var textFont: String
    var textSize: Double
    var textStyle: String
    var isBackgroundPart: Bool
}
