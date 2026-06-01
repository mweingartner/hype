import CoreGraphics
import Foundation
import ImageIO

public struct HyperCardExternalCall: Sendable, Equatable {
    public var name: String
    public var kind: HyperCardExternalKind
    public var arguments: [Value]

    public init(name: String, kind: HyperCardExternalKind, arguments: [Value]) {
        self.name = name
        self.kind = kind
        self.arguments = arguments
    }
}

public struct HyperCardExternalCallContext: Sendable {
    public var targetId: UUID
    public var currentCardId: UUID
    public var document: HypeDocument

    public init(targetId: UUID, currentCardId: UUID, document: HypeDocument) {
        self.targetId = targetId
        self.currentCardId = currentCardId
        self.document = document
    }
}

public struct HyperCardExternalResult: Sendable {
    public var value: Value
    public var result: Value
    public var modifiedDocument: HypeDocument?
    public var passMessage: Bool
    public var diagnostic: String?
    public var runtimeGlobals: [String: String]
    public var visualEffect: String?
    public var visualEffectDuration: Double?

    public init(
        value: Value = "",
        result: Value = "",
        modifiedDocument: HypeDocument? = nil,
        passMessage: Bool = false,
        diagnostic: String? = nil,
        runtimeGlobals: [String: String] = [:],
        visualEffect: String? = nil,
        visualEffectDuration: Double? = nil
    ) {
        self.value = value
        self.result = result
        self.modifiedDocument = modifiedDocument
        self.passMessage = passMessage
        self.diagnostic = diagnostic
        self.runtimeGlobals = runtimeGlobals
        self.visualEffect = visualEffect
        self.visualEffectDuration = visualEffectDuration
    }
}

public struct HyperCardExternalRegistry: Sendable {
    public typealias Handler = @Sendable (HyperCardExternalCall, HyperCardExternalCallContext) async -> HyperCardExternalResult

    public struct Entry: Sendable {
        public var status: HyperCardExternalEmulationStatus
        public var handler: Handler?

        public init(status: HyperCardExternalEmulationStatus, handler: Handler? = nil) {
            self.status = status
            self.handler = handler
        }
    }

    public static let `default` = HyperCardExternalRegistry(entries: Self.defaultEntries)

    private let entries: [String: Entry]

    public init(entries: [String: Entry] = [:]) {
        self.entries = entries
    }

    public func status(for name: String, kind: HyperCardExternalKind) -> HyperCardExternalEmulationStatus {
        entries[key(name: name, kind: kind)]?.status ?? .unknown
    }

    public func invoke(
        _ call: HyperCardExternalCall,
        context: HyperCardExternalCallContext
    ) async -> HyperCardExternalResult {
        let lookupKey = key(name: call.name, kind: call.kind)
        guard let entry = entries[lookupKey] else {
            return unsupportedResult(for: call, status: .unknown)
        }
        guard let handler = entry.handler else {
            return unsupportedResult(for: call, status: entry.status)
        }
        return await handler(call, context)
    }

    private func unsupportedResult(
        for call: HyperCardExternalCall,
        status: HyperCardExternalEmulationStatus
    ) -> HyperCardExternalResult {
        let label = call.kind.rawValue
        let message: String
        switch status {
        case .knownUnsupported:
            message = "\(label) '\(call.name)' is known but is not emulated yet."
        case .unknown:
            message = "Can't Load External: \(label) '\(call.name)' is not available in Hype."
        case .emulated:
            message = "\(label) '\(call.name)' has no registered implementation."
        }
        HypeLogger.shared.warn(message, source: "HyperCardExternalRegistry")
        return HyperCardExternalResult(value: "", result: message, diagnostic: message)
    }

    private func key(name: String, kind: HyperCardExternalKind) -> String {
        "\(kind.rawValue):\(Self.normalizedName(name))"
    }

    private static func normalizedName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    private static var defaultEntries: [String: Entry] {
        var result: [String: Entry] = [:]
        func put(_ kind: HyperCardExternalKind, _ names: [String], _ entry: Entry) {
            for name in names {
                result["\(kind.rawValue):\(normalizedName(name))"] = entry
            }
        }

        put(.xcmd, ["SetCursor", "Cursor"], Entry(status: .emulated) { call, _ in
            let cursorName = call.arguments.first ?? ""
            return HyperCardExternalResult(value: "", result: cursorName)
        })
        put(.xcmd, ["playQT", "PlayMovie", "Movie"], Entry(status: .emulated) { call, context in
            playQuickTime(call: call, context: context)
        })
        put(.xcmd, ["closemoovs", "closemovies", "closeQT"], Entry(status: .emulated) { _, context in
            closeQuickTimeMovies(context: context)
        })
        put(.xcmd, ["HTLock"], Entry(status: .emulated) { call, context in
            lockScreenCompatibility(call: call, context: context)
        })
        put(.xcmd, ["HTVisual"], Entry(status: .emulated) { call, context in
            visualEffectCompatibility(call: call, context: context)
        })
        put(.xcmd, ["DeCurse"], Entry(status: .emulated) { call, _ in
            cursorCompatibility(call: call)
        })
        put(.xcmd, ["moveCursor"], Entry(status: .emulated) { call, _ in
            moveCursorCompatibility(call: call)
        })
        put(.xcmd, ["xWindowFrame"], Entry(status: .emulated) { call, _ in
            windowFrameCompatibility(call: call)
        })
        put(.xcmd, ["xAbout"], Entry(status: .emulated) { call, _ in
            aboutCompatibility(call: call)
        })
        put(.xcmd, ["xMemory"], Entry(status: .emulated) { call, _ in
            memoryCompatibility(call: call)
        })
        put(.xcmd, ["xSetSoundVol"], Entry(status: .emulated) { call, context in
            setSoundVolumeCompatibility(call: call, context: context)
        })
        put(.xcmd, ["SetMode"], Entry(status: .emulated) { call, _ in
            setDisplayModeCompatibility(call: call)
        })
        put(.xcmd, ["HTAddPict"], Entry(status: .emulated) { call, context in
            addPictureCompatibility(call: call, context: context, replacement: false)
        })
        put(.xcmd, ["HTChangePict"], Entry(status: .emulated) { call, context in
            addPictureCompatibility(call: call, context: context, replacement: true)
        })
        put(.xcmd, ["HTSavePict"], Entry(status: .emulated) { call, context in
            savePictureCompatibility(call: call, context: context)
        })
        put(.xcmd, ["HTRemove"], Entry(status: .emulated) { call, context in
            removeHyperTintCompatibility(call: call, context: context)
        })
        put(.xcmd, ["HTUDefPal"], Entry(status: .emulated) { call, context in
            userDefinedPaletteCompatibility(call: call, context: context)
        })
        put(.xcmd, ["HyperTint"], Entry(status: .emulated) { call, _ in
            hyperTintCompatibility(call: call)
        })
        put(.xcmd, ["xCIcon3"], Entry(status: .emulated) { call, context in
            colorIconCompatibility(call: call, context: context)
        })
        put(.xcmd, ["xClip"], Entry(status: .emulated) { call, _ in
            clipRectCompatibility(call: call)
        })
        put(.xcmd, ["xLine"], Entry(status: .emulated) { call, context in
            lineDrawCompatibility(call: call, context: context)
        })
        put(.xcmd, ["HTTB1TS"], Entry(status: .emulated) { call, context in
            hyperTintTempBufferToScreenCompatibility(call: call, context: context)
        })
        put(.xcmd, ["Picture"], Entry(status: .emulated) { call, context in
            pictureWindowCompatibility(call: call, context: context)
        })
        put(.xcmd, ["AddColor", "ColorizeCard", "ColorizeHC", "ColorTools"], Entry(status: .knownUnsupported))
        put(.xcmd, ["CompileIt", "CompileIt!"], Entry(status: .knownUnsupported))
        put(.xcmd, ["FullPrint", "PrintReport"], Entry(status: .knownUnsupported))
        put(.xcmd, ["ReadWrite", "FileIO", "OpenFile", "SaveFile"], Entry(status: .knownUnsupported))
        put(.xcmd, ["SerialPort", "Modem", "AppleEvents"], Entry(status: .knownUnsupported))

        put(.xfcn, ["ExternalVersion", "XCMDVersion", "HypeVersion"], Entry(status: .emulated) { _, _ in
            HyperCardExternalResult(value: "Hype HyperCard compatibility layer", result: "")
        })
        put(.xfcn, ["xMemory"], Entry(status: .emulated) { call, _ in
            memoryCompatibility(call: call)
        })
        put(.xfcn, ["xVirtual"], Entry(status: .emulated) { call, _ in
            virtualMemoryCompatibility(call: call)
        })
        put(.xfcn, ["xDepth"], Entry(status: .emulated) { _, context in
            displayDepthCompatibility(context: context)
        })
        put(.xfcn, ["variant"], Entry(status: .emulated) { call, _ in
            variantCompatibility(call: call)
        })
        put(.xfcn, ["movieInfo"], Entry(status: .emulated) { call, context in
            movieInfoCompatibility(call: call, context: context)
        })
        put(.xfcn, ["xSetSoundVol"], Entry(status: .emulated) { call, context in
            setSoundVolumeCompatibility(call: call, context: context)
        })
        put(.xfcn, ["xGetSoundVol"], Entry(status: .emulated) { _, context in
            getSoundVolumeCompatibility(context: context)
        })
        put(.xfcn, ["GetMode"], Entry(status: .emulated) { _, context in
            getDisplayModeCompatibility(context: context)
        })
        put(.xfcn, ["AddColorVersion"], Entry(status: .knownUnsupported))
        put(.xfcn, ["ReadFile", "WriteFile", "Directory"], Entry(status: .knownUnsupported))
        return result
    }

    private static func playQuickTime(
        call: HyperCardExternalCall,
        context: HyperCardExternalCallContext
    ) -> HyperCardExternalResult {
        guard let rawName = call.arguments.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawName.isEmpty else {
            return HyperCardExternalResult(result: "playQT requires a movie name")
        }
        guard let asset = context.document.assetRepository.asset(byClassicMediaName: rawName, kind: .videoClip) else {
            return HyperCardExternalResult(result: "QuickTime asset not found: \(rawName)")
        }

        var document = context.document
        let assetRef = document.assetRepository.assetRef(for: asset)
        let lookupKey = AssetRepository.classicMediaLookupKey(rawName)
        document.parts.removeAll { part in
            part.cardId == context.currentCardId &&
                part.partType == .video &&
                isQuickTimeCompatibilityPart(part) &&
                AssetRepository.classicMediaLookupKey(part.name) == lookupKey
        }

        let hasLoopArgument = call.arguments.dropFirst().contains { argument in
            AssetRepository.classicMediaLookupKey(argument).contains("loop")
        }
        let windowName = quickTimeWindowName(from: call)
        let audioOnly = isAudioOnlyQuickTimeAsset(asset)
        let moviePoint = quickTimePoint(from: call.arguments)
        var part = Part(
            partType: .video,
            cardId: context.currentCardId,
            name: rawName,
            left: moviePoint.map { Double($0.x) } ?? 0,
            top: moviePoint.map { Double($0.y) } ?? 0,
            width: audioOnly ? 1 : (moviePoint == nil ? Double(document.stack.width) : Double(max(asset.width, 1))),
            height: audioOnly ? 1 : (moviePoint == nil ? Double(document.stack.height) : Double(max(asset.height, 1)))
        )
        part.videoAssetRef = assetRef
        part.videoURL = "asset://\(asset.id.uuidString)"
        part.videoAutoplay = true
        part.videoLoop = hasLoopArgument
        part.videoVolume = normalizedClassicSoundVolume(
            context.document.scriptGlobals["hypercard.sound.volume"] ?? "255"
        )
        var markers = [quickTimeCompatibilityMarker]
        if let windowName {
            markers.append("window=\(windowName)")
        }
        if audioOnly {
            markers.append("audioOnly=true")
        }
        part.helpText = markers.joined(separator: "\n")
        document.addPart(part)

        var runtimeGlobals = [
            "hypercard.playqt.asset": asset.name,
            "hypercard.playqt.audioOnly": audioOnly ? "true" : "false"
        ]
        if let windowName {
            let windowKey = AssetRepository.classicMediaLookupKey(windowName)
            runtimeGlobals["hypercard.window.\(windowKey).movie"] = rawName
            runtimeGlobals["hypercard.window.\(windowKey).exists"] = "true"
        }

        return HyperCardExternalResult(
            value: asset.name,
            result: asset.name,
            modifiedDocument: document,
            runtimeGlobals: runtimeGlobals
        )
    }

    private static func closeQuickTimeMovies(context: HyperCardExternalCallContext) -> HyperCardExternalResult {
        var document = context.document
        let removedCount = document.parts.filter { part in
            part.cardId == context.currentCardId &&
                part.partType == .video &&
                isQuickTimeCompatibilityPart(part)
        }.count
        document.parts.removeAll { part in
            part.cardId == context.currentCardId &&
                part.partType == .video &&
                isQuickTimeCompatibilityPart(part)
        }
        return HyperCardExternalResult(
            value: String(removedCount),
            result: String(removedCount),
            modifiedDocument: document
        )
    }

    private static func quickTimePoint(from arguments: [Value]) -> CGPoint? {
        guard arguments.count >= 3 else { return nil }
        for argument in arguments.dropFirst(1) {
            if let point = classicPoint(from: argument) {
                return point
            }
        }
        return nil
    }

    private static func quickTimeWindowName(from call: HyperCardExternalCall) -> Value? {
        let commandName = normalizedName(call.name)
        guard commandName == "movie" || commandName == "playmovie" else { return nil }
        guard call.arguments.count >= 5 else { return nil }
        let candidate = call.arguments.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !candidate.isEmpty else { return nil }
        let normalizedCandidate = AssetRepository.classicMediaLookupKey(candidate)
        let optionNames = ["borderless", "visible", "invisible", "loop", "controller"]
        if optionNames.contains(normalizedCandidate) {
            return nil
        }
        if classicPoint(from: candidate) != nil {
            return nil
        }
        return candidate
    }

    private static func lockScreenCompatibility(
        call: HyperCardExternalCall,
        context: HyperCardExternalCallContext
    ) -> HyperCardExternalResult {
        let mode = normalizedHTLockMode(from: call.arguments)
        return HyperCardExternalResult(
            value: mode,
            result: mode,
            runtimeGlobals: [
                "hypercard.htlock.mode": mode,
                "hypercard.htlock.arguments": call.arguments.joined(separator: "\t")
            ]
        )
    }

    private static func visualEffectCompatibility(
        call: HyperCardExternalCall,
        context: HyperCardExternalCallContext
    ) -> HyperCardExternalResult {
        let effect = call.arguments.first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let duration = visualEffectDuration(from: call.arguments)
        return HyperCardExternalResult(
            value: effect,
            result: effect,
            runtimeGlobals: [
                "hypercard.htvisual.effect": effect,
                "hypercard.htvisual.arguments": call.arguments.joined(separator: "\t")
            ],
            visualEffect: effect.isEmpty ? nil : effect,
            visualEffectDuration: duration
        )
    }

    private static func cursorCompatibility(call: HyperCardExternalCall) -> HyperCardExternalResult {
        let mode = normalizedCursorMode(from: call.arguments)
        var runtimeGlobals = [
            "hypercard.decurse.mode": mode,
            "hypercard.decurse.arguments": call.arguments.joined(separator: "\t")
        ]
        if call.arguments.indices.contains(1) {
            runtimeGlobals["hypercard.decurse.resource"] = call.arguments[1]
        }
        if call.arguments.indices.contains(2) {
            runtimeGlobals["hypercard.decurse.kind"] = call.arguments[2]
        }
        if call.arguments.indices.contains(3) {
            runtimeGlobals["hypercard.decurse.options"] = call.arguments.dropFirst(3).joined(separator: "\t")
        }
        return HyperCardExternalResult(
            value: mode,
            result: mode,
            runtimeGlobals: runtimeGlobals
        )
    }

    private static func moveCursorCompatibility(call: HyperCardExternalCall) -> HyperCardExternalResult {
        let point = classicPoint(from: call.arguments.joined(separator: ",")) ?? CGPoint(
            x: Double(call.arguments.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0,
            y: Double(call.arguments.dropFirst().first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
        )
        let loc = "\(Int(point.x.rounded())),\(Int(point.y.rounded()))"
        return HyperCardExternalResult(
            value: loc,
            result: loc,
            runtimeGlobals: [
                "hypercard.movecursor.x": String(Int(point.x.rounded())),
                "hypercard.movecursor.y": String(Int(point.y.rounded())),
                "hypercard.movecursor.loc": loc,
                "hypercard.movecursor.arguments": call.arguments.joined(separator: "\t"),
                "hypercard.cursor.mode": "move"
            ]
        )
    }

    private static func windowFrameCompatibility(call: HyperCardExternalCall) -> HyperCardExternalResult {
        HyperCardExternalResult(
            value: "frame",
            result: "frame",
            runtimeGlobals: [
                "hypercard.window.frame.exists": "true",
                "hypercard.window.frame.visible": "true",
                "hypercard.window.frame.name": "frame",
                "hypercard.xwindowframe.arguments": call.arguments.joined(separator: "\t")
            ]
        )
    }

    private static func aboutCompatibility(call: HyperCardExternalCall) -> HyperCardExternalResult {
        HyperCardExternalResult(
            value: "",
            result: "",
            runtimeGlobals: [
                "hypercard.xabout.invoked": "true",
                "hypercard.xabout.arguments": call.arguments.joined(separator: "\t")
            ]
        )
    }

    private static func clipRectCompatibility(call: HyperCardExternalCall) -> HyperCardExternalResult {
        guard let rect = classicRect(from: call.arguments.first) else {
            return HyperCardExternalResult(
                result: "xClip requires a classic rect",
                runtimeGlobals: [
                    "hypercard.xclip.arguments": call.arguments.joined(separator: "\t")
                ]
            )
        }
        let rectValue = classicRectString(rect)
        return HyperCardExternalResult(
            value: rectValue,
            result: rectValue,
            runtimeGlobals: [
                "hypercard.xclip.rect": rectValue,
                "hypercard.quickdraw.clipRect": rectValue,
                "hypercard.xclip.arguments": call.arguments.joined(separator: "\t")
            ]
        )
    }

    private static func lineDrawCompatibility(
        call: HyperCardExternalCall,
        context: HyperCardExternalCallContext
    ) -> HyperCardExternalResult {
        let startPoint = classicPoint(from: call.arguments.first) ?? .zero
        let endPoint = classicPoint(from: call.arguments.dropFirst().first) ?? .zero
        let penSize = normalizedClassicInteger(call.arguments.dropFirst(2).first, fallback: "1")
        let color = normalizedClassicInteger(call.arguments.dropFirst(3).first, fallback: "0")
        let count = (Int(context.document.scriptGlobals["hypercard.xline.count"] ?? "0") ?? 0) + 1
        let startValue = classicPointString(startPoint)
        let endValue = classicPointString(endPoint)
        let value = "\(startValue),\(endValue),\(penSize),\(color)"
        var document = context.document
        let renderedPixels = renderQuickDrawLine(
            startPoint: startPoint,
            endPoint: endPoint,
            penSize: Int(penSize) ?? 1,
            color: Int(color) ?? 0,
            context: context,
            document: &document
        )
        return HyperCardExternalResult(
            value: value,
            result: value,
            modifiedDocument: renderedPixels > 0 ? document : nil,
            runtimeGlobals: [
                "hypercard.xline.count": String(count),
                "hypercard.xline.start": startValue,
                "hypercard.xline.end": endValue,
                "hypercard.xline.penSize": penSize,
                "hypercard.xline.color": color,
                "hypercard.xline.value": value,
                "hypercard.xline.renderedPixels": String(renderedPixels),
                "hypercard.xline.arguments": call.arguments.joined(separator: "\t")
            ]
        )
    }

    private static func renderQuickDrawLine(
        startPoint: CGPoint,
        endPoint: CGPoint,
        penSize: Int,
        color: Int,
        context: HyperCardExternalCallContext,
        document: inout HypeDocument
    ) -> Int {
        let width = max(1, document.stack.width)
        let height = max(1, document.stack.height)
        var layer = document.paintLayer(forCardId: context.currentCardId)
            ?? CardPaintLayer(
                cardId: context.currentCardId,
                width: width,
                height: height,
                rgbaData: Data(count: width * height * 4)
            )
        if layer.width != width || layer.height != height {
            layer = CardPaintLayer(
                cardId: context.currentCardId,
                width: width,
                height: height,
                rgbaData: Data(count: width * height * 4)
            )
        }
        let clipRect = classicRect(from: context.document.scriptGlobals["hypercard.quickdraw.clipRect"])
            ?? CGRect(x: 0, y: 0, width: width, height: height)
        var data = layer.normalizedRGBAData
        let brushSize = max(1, penSize)
        let brushOffset = brushSize / 2
        let rgba = classicQuickDrawRGBA(color, globals: context.document.scriptGlobals)
        var rendered = 0

        func plotBrush(x: Int, y: Int) {
            for dy in 0..<brushSize {
                for dx in 0..<brushSize {
                    let px = x + dx - brushOffset
                    let py = y + dy - brushOffset
                    guard px >= 0, py >= 0, px < width, py < height else { continue }
                    guard CGFloat(px) >= clipRect.minX,
                          CGFloat(py) >= clipRect.minY,
                          CGFloat(px) < clipRect.maxX,
                          CGFloat(py) < clipRect.maxY else { continue }
                    let offset = (py * width + px) * 4
                    guard offset + 3 < data.count else { continue }
                    if data[offset] != rgba.0 || data[offset + 1] != rgba.1 ||
                        data[offset + 2] != rgba.2 || data[offset + 3] != rgba.3 {
                        rendered += 1
                    }
                    data[offset] = rgba.0
                    data[offset + 1] = rgba.1
                    data[offset + 2] = rgba.2
                    data[offset + 3] = rgba.3
                }
            }
        }

        var x = Int(startPoint.x.rounded())
        var y = Int(startPoint.y.rounded())
        let x1 = Int(endPoint.x.rounded())
        let y1 = Int(endPoint.y.rounded())
        let dx = abs(x1 - x)
        let dy = abs(y1 - y)
        let sx = x < x1 ? 1 : -1
        let sy = y < y1 ? 1 : -1
        var err = dx - dy
        while true {
            plotBrush(x: x, y: y)
            if x == x1 && y == y1 { break }
            let e2 = 2 * err
            if e2 > -dy {
                err -= dy
                x += sx
            }
            if e2 < dx {
                err += dx
                y += sy
            }
        }

        guard rendered > 0 else { return 0 }
        document.setPaintLayer(CardPaintLayer(cardId: context.currentCardId, width: width, height: height, rgbaData: data))
        return rendered
    }

    private static func classicQuickDrawRGBA(
        _ color: Int,
        globals: [String: String] = [:]
    ) -> (UInt8, UInt8, UInt8, UInt8) {
        if let paletteColor = paletteRGBA(for: color, globals: globals) {
            return paletteColor
        }
        let gray = UInt8(max(0, min(255, color)))
        return (gray, gray, gray, 255)
    }

    private static func paletteRGBA(
        for colorIndex: Int,
        globals: [String: String]
    ) -> (UInt8, UInt8, UInt8, UInt8)? {
        guard colorIndex >= 0,
              let rawColors = globals["hypercard.htudefpal.colors"],
              !rawColors.isEmpty else {
            return nil
        }
        let colors = rawColors.split(separator: "\t", omittingEmptySubsequences: false)
        guard colors.indices.contains(colorIndex) else { return nil }
        return hexRGBA(String(colors[colorIndex]))
    }

    private static func hexRGBA(_ raw: String) -> (UInt8, UInt8, UInt8, UInt8)? {
        var hex = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }
        guard hex.count == 6,
              let value = Int(hex, radix: 16) else {
            return nil
        }
        return (
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff),
            255
        )
    }

    private static func hyperTintTempBufferToScreenCompatibility(
        call: HyperCardExternalCall,
        context: HyperCardExternalCallContext
    ) -> HyperCardExternalResult {
        let destinationRect = classicRect(from: call.arguments.first)
        let sourceRect = classicRect(from: call.arguments.dropFirst().first)
        let transferMode = pictureTransferMode(from: ["", ""] + call.arguments) ?? "srcCopy"
        let vblMode = hyperTintTempBufferVBLMode(from: call.arguments)
        let count = (Int(context.document.scriptGlobals["hypercard.httb1ts.count"] ?? "0") ?? 0) + 1
        var globals = [
            "hypercard.httb1ts.count": String(count),
            "hypercard.httb1ts.transferMode": transferMode,
            "hypercard.httb1ts.vbl": vblMode,
            "hypercard.httb1ts.arguments": call.arguments.joined(separator: "\t")
        ]
        if let destinationRect {
            globals["hypercard.httb1ts.destinationRect"] = classicRectString(destinationRect)
        }
        if let sourceRect {
            globals["hypercard.httb1ts.sourceRect"] = classicRectString(sourceRect)
        }
        let value = destinationRect.map(classicRectString) ?? ""
        return HyperCardExternalResult(
            value: value,
            result: value,
            runtimeGlobals: globals
        )
    }

    private static func pictureWindowCompatibility(
        call: HyperCardExternalCall,
        context: HyperCardExternalCallContext
    ) -> HyperCardExternalResult {
        let rawName = call.arguments.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawName.isEmpty else {
            return HyperCardExternalResult(result: "Picture requires a picture name")
        }
        guard let asset = pictureAsset(for: rawName, document: context.document) else {
            return HyperCardExternalResult(
                result: "Picture asset not found: \(rawName)",
                runtimeGlobals: pictureWindowRuntimeGlobals(call: call, assetName: "", windowName: rawName)
            )
        }

        var document = context.document
        let windowKey = AssetRepository.classicMediaLookupKey(rawName)
        document.parts.removeAll { part in
            part.cardId == context.currentCardId &&
                part.partType == .image &&
                part.helpText == pictureWindowMarker &&
                AssetRepository.classicMediaLookupKey(part.name) == windowKey
        }

        var part = Part(
            partType: .image,
            cardId: context.currentCardId,
            name: rawName,
            left: 0,
            top: 0,
            width: Double(max(asset.width, context.document.stack.width)),
            height: Double(max(asset.height, context.document.stack.height))
        )
        part.imageData = asset.data
        part.transparentBackground = false
        part.visible = pictureWindowStartsVisible(arguments: call.arguments)
        part.helpText = pictureWindowMarker
        document.addPart(part)

        return HyperCardExternalResult(
            value: "",
            result: "",
            modifiedDocument: document,
            runtimeGlobals: pictureWindowRuntimeGlobals(
                call: call,
                assetName: asset.name,
                windowName: rawName,
                visible: part.visible
            )
        )
    }

    private static func memoryCompatibility(call: HyperCardExternalCall) -> HyperCardExternalResult {
        let query = call.arguments.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "1"
        let value = "16777216"
        return HyperCardExternalResult(
            value: value,
            result: value,
            runtimeGlobals: [
                "hypercard.xmemory.query": query,
                "hypercard.xmemory.value": value,
                "hypercard.xmemory.arguments": call.arguments.joined(separator: "\t")
            ]
        )
    }

    private static func virtualMemoryCompatibility(call: HyperCardExternalCall) -> HyperCardExternalResult {
        let value = "0"
        return HyperCardExternalResult(
            value: value,
            result: value,
            runtimeGlobals: [
                "hypercard.xvirtual.value": value,
                "hypercard.xvirtual.arguments": call.arguments.joined(separator: "\t")
            ]
        )
    }

    private static func displayDepthCompatibility(context: HyperCardExternalCallContext) -> HyperCardExternalResult {
        let depth = normalizedDisplayDepth(context.document.scriptGlobals["hypercard.setmode.depth"])
        return HyperCardExternalResult(
            value: depth,
            result: depth,
            runtimeGlobals: [
                "hypercard.xdepth.value": depth,
                "hypercard.setmode.depth": depth
            ]
        )
    }

    private static func variantCompatibility(call: HyperCardExternalCall) -> HyperCardExternalResult {
        let value = "2.1"
        return HyperCardExternalResult(
            value: value,
            result: value,
            runtimeGlobals: [
                "hypercard.variant.value": value,
                "hypercard.variant.arguments": call.arguments.joined(separator: "\t")
            ]
        )
    }

    private static func movieInfoCompatibility(
        call: HyperCardExternalCall,
        context: HyperCardExternalCallContext
    ) -> HyperCardExternalResult {
        let rawPath = call.arguments.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawPath.isEmpty else {
            return HyperCardExternalResult(result: "movieInfo( <file path> ).")
        }
        let movieName = classicMovieName(from: rawPath)
        guard let asset = context.document.assetRepository.asset(byClassicMediaName: movieName, kind: .videoClip) else {
            return HyperCardExternalResult(
                value: "",
                result: "File not found.",
                runtimeGlobals: [
                    "hypercard.movieinfo.path": rawPath,
                    "hypercard.movieinfo.name": movieName,
                    "hypercard.movieinfo.found": "false"
                ]
            )
        }

        let infoLines = movieInfoLines(for: asset, requestedPath: rawPath, movieName: movieName)
        let value = infoLines.joined(separator: "\r")
        return HyperCardExternalResult(
            value: value,
            result: "",
            runtimeGlobals: [
                "hypercard.movieinfo.path": rawPath,
                "hypercard.movieinfo.name": movieName,
                "hypercard.movieinfo.found": "true",
                "hypercard.movieinfo.value": value
            ]
        )
    }

    private static func setSoundVolumeCompatibility(
        call: HyperCardExternalCall,
        context: HyperCardExternalCallContext
    ) -> HyperCardExternalResult {
        let rawValue = call.arguments.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallback = context.document.scriptGlobals["hypercard.sound.volume"] ?? "255"
        let volume = clampedClassicSoundVolume(rawValue, fallback: fallback)
        var document = context.document
        applyClassicSoundVolume(volume, currentCardId: context.currentCardId, to: &document)
        return HyperCardExternalResult(
            value: volume,
            result: volume,
            modifiedDocument: document,
            runtimeGlobals: [
                "hypercard.sound.volume": volume,
                "hypercard.xsetsoundvol.arguments": call.arguments.joined(separator: "\t")
            ]
        )
    }

    private static func getSoundVolumeCompatibility(context: HyperCardExternalCallContext) -> HyperCardExternalResult {
        let volume = clampedClassicSoundVolume(
            context.document.scriptGlobals["hypercard.sound.volume"] ?? "255",
            fallback: "255"
        )
        return HyperCardExternalResult(
            value: volume,
            result: volume,
            runtimeGlobals: [
                "hypercard.sound.volume": volume
            ]
        )
    }

    private static func setDisplayModeCompatibility(call: HyperCardExternalCall) -> HyperCardExternalResult {
        let mode = normalizedDisplayMode(call.arguments.first)
        let depth = normalizedDisplayDepth(call.arguments.dropFirst().first)
        let value = "\(mode),\(depth)"
        return HyperCardExternalResult(
            value: "",
            result: "",
            runtimeGlobals: [
                "hypercard.display.mode": mode,
                "hypercard.display.depth": depth,
                "hypercard.display.value": value,
                "hypercard.setmode.mode": mode,
                "hypercard.setmode.depth": depth,
                "hypercard.setmode.value": value,
                "hypercard.setmode.arguments": call.arguments.joined(separator: "\t")
            ]
        )
    }

    private static func getDisplayModeCompatibility(context: HyperCardExternalCallContext) -> HyperCardExternalResult {
        let mode = normalizedDisplayMode(
            context.document.scriptGlobals["hypercard.setmode.mode"] ??
                context.document.scriptGlobals["hypercard.display.mode"]
        )
        let depth = normalizedDisplayDepth(
            context.document.scriptGlobals["hypercard.setmode.depth"] ??
                context.document.scriptGlobals["hypercard.display.depth"]
        )
        let value = "\(mode),\(depth)"
        return HyperCardExternalResult(
            value: value,
            result: value,
            runtimeGlobals: [
                "hypercard.setmode.mode": mode,
                "hypercard.setmode.depth": depth,
                "hypercard.setmode.value": value
            ]
        )
    }

    private static func addPictureCompatibility(
        call: HyperCardExternalCall,
        context: HyperCardExternalCallContext,
        replacement: Bool
    ) -> HyperCardExternalResult {
        if pictureUsesClipboard(arguments: call.arguments) {
            return restorePictureClipboardCompatibility(call: call, context: context, replacement: replacement)
        }
        guard let asset = pictureAsset(for: call.arguments.first ?? "", document: context.document) else {
            return HyperCardExternalResult(
                result: "Picture asset not found: \(call.arguments.first ?? "")",
                runtimeGlobals: pictureRuntimeGlobals(call: call, assetName: "", replacement: replacement)
            )
        }
        var document = context.document
        if replacement {
            document.parts.removeAll { part in
                part.cardId == context.currentCardId &&
                    part.partType == .image &&
                    part.helpText == pictureReplacementMarker
            }
        }
        let rect = classicRect(from: call.arguments.dropFirst().first) ??
            CGRect(x: 0, y: 0, width: Double(document.stack.width), height: Double(document.stack.height))
        let sourceRect = pictureSourceRect(from: call.arguments)
        let transferMode = pictureTransferMode(from: call.arguments)
        let imageData = sourceRect.flatMap { croppedPNGData(from: asset.data, sourceRect: $0) } ?? asset.data
        var part = Part(
            partType: .image,
            cardId: context.currentCardId,
            name: "\(replacement ? "HTChangePict" : "HTAddPict") \(asset.name)",
            left: rect.origin.x,
            top: rect.origin.y,
            width: rect.width,
            height: rect.height
        )
        part.imageData = imageData
        part.transparentBackground = !replacement
        part.helpText = replacement ? pictureReplacementMarker : pictureOverlayMarker
        let compositedPixels = transferMode.flatMap { mode in
            compositePictureIntoPaintLayer(
                imageData: imageData,
                destinationRect: rect,
                transferMode: mode,
                currentCardId: context.currentCardId,
                document: &document
            )
        } ?? 0
        if compositedPixels > 0 {
            part.visible = false
        }
        document.addPart(part)

        return HyperCardExternalResult(
            value: asset.name,
            result: asset.name,
            modifiedDocument: document,
            runtimeGlobals: pictureRuntimeGlobals(
                call: call,
                assetName: asset.name,
                replacement: replacement,
                sourceRect: sourceRect,
                transferMode: transferMode,
                compositedPixelCount: compositedPixels
            )
        )
    }

    private static func savePictureCompatibility(
        call: HyperCardExternalCall,
        context: HyperCardExternalCallContext
    ) -> HyperCardExternalResult {
        let rect = classicRect(from: call.arguments.first)
        let destination = call.arguments.dropFirst().first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let transferMode = pictureTransferMode(from: ["", ""] + Array(call.arguments.dropFirst(2)))
        var globals = [
            "hypercard.htsavepict.destination": destination?.isEmpty == false ? destination! : "clipboard",
            "hypercard.htsavepict.arguments": call.arguments.joined(separator: "\t")
        ]
        if let rect {
            globals["hypercard.htsavepict.rect"] = classicRectString(rect)
        }
        if let transferMode {
            globals["hypercard.htsavepict.transferMode"] = transferMode
        }
        var document = context.document
        let destinationKey = AssetRepository.classicMediaLookupKey(globals["hypercard.htsavepict.destination"] ?? "")
        if destinationKey == "clipboard",
           let rect,
           let capture = clipboardPNGData(from: document.paintLayer(forCardId: context.currentCardId), rect: rect) {
            document.assetRepository.assets.removeAll { asset in
                asset.metadata.contains { entry in
                    entry.key == "hypercard_compatibility_role" && entry.value == "clipboard"
                }
            }
            let asset = Asset(
                name: "clipboard",
                kind: .imageTexture,
                mimeType: "image/png",
                data: capture.data,
                width: capture.width,
                height: capture.height,
                tags: ["hypercard", "clipboard"],
                metadata: [
                    AssetMetadataEntry(key: "classic_name", value: "clipboard"),
                    AssetMetadataEntry(key: "lookup_key", value: "clipboard"),
                    AssetMetadataEntry(key: "hypercard_compatibility_role", value: "clipboard"),
                    AssetMetadataEntry(key: "source_rect", value: classicRectString(rect))
                ]
            )
            document.assetRepository.addAsset(asset)
            globals["hypercard.htsavepict.captured"] = "true"
            globals["hypercard.htsavepict.asset"] = asset.name
            globals["hypercard.htsavepict.width"] = String(capture.width)
            globals["hypercard.htsavepict.height"] = String(capture.height)
        } else {
            globals["hypercard.htsavepict.captured"] = "false"
        }
        return HyperCardExternalResult(
            value: globals["hypercard.htsavepict.destination"] ?? "clipboard",
            result: "",
            modifiedDocument: globals["hypercard.htsavepict.captured"] == "true" ? document : nil,
            runtimeGlobals: globals
        )
    }

    private static func restorePictureClipboardCompatibility(
        call: HyperCardExternalCall,
        context: HyperCardExternalCallContext,
        replacement: Bool
    ) -> HyperCardExternalResult {
        var document = context.document
        let rect = classicRect(from: call.arguments.dropFirst().first) ??
            CGRect(x: 0, y: 0, width: Double(document.stack.width), height: Double(document.stack.height))
        let transferMode = pictureTransferMode(from: call.arguments)
        let removedCount = document.parts.filter { part in
            part.cardId == context.currentCardId &&
                part.partType == .image &&
                part.helpText == pictureOverlayMarker &&
                partRect(part).intersects(rect)
        }.count
        document.parts.removeAll { part in
            part.cardId == context.currentCardId &&
                part.partType == .image &&
                part.helpText == pictureOverlayMarker &&
                partRect(part).intersects(rect)
        }
        let clipboardAsset = pictureAsset(for: "clipboard", document: document)
        if let clipboardAsset {
            var part = Part(
                partType: .image,
                cardId: context.currentCardId,
                name: "\(replacement ? "HTChangePict" : "HTAddPict") Clipboard",
                left: rect.origin.x,
                top: rect.origin.y,
                width: rect.width,
                height: rect.height
            )
            part.imageData = clipboardAsset.data
            part.transparentBackground = false
            part.helpText = replacement ? pictureReplacementMarker : pictureOverlayMarker
            document.addPart(part)
        }
        return HyperCardExternalResult(
            value: "clipboard",
            result: "clipboard",
            modifiedDocument: document,
            runtimeGlobals: pictureRuntimeGlobals(
                call: call,
                assetName: clipboardAsset?.name ?? "clipboard",
                replacement: replacement,
                transferMode: transferMode,
                restoredClipboardRect: rect,
                removedOverlayCount: removedCount,
                restoredClipboardAsset: clipboardAsset?.name
            )
        )
    }

    private static func removeHyperTintCompatibility(
        call: HyperCardExternalCall,
        context: HyperCardExternalCallContext
    ) -> HyperCardExternalResult {
        var document = context.document
        let markers = Set([
            pictureOverlayMarker,
            pictureReplacementMarker,
            pictureWindowMarker,
            iconOverlayMarker,
            quickTimeCompatibilityMarker
        ])
        let removedCount = document.parts.filter { part in
            markers.contains(part.helpText)
        }.count
        document.parts.removeAll { part in
            markers.contains(part.helpText)
        }
        return HyperCardExternalResult(
            value: String(removedCount),
            result: String(removedCount),
            modifiedDocument: document,
            runtimeGlobals: [
                "hypercard.htremove.removedCount": String(removedCount),
                "hypercard.htremove.arguments": call.arguments.joined(separator: "\t")
            ]
        )
    }

    private static func userDefinedPaletteCompatibility(
        call: HyperCardExternalCall,
        context: HyperCardExternalCallContext
    ) -> HyperCardExternalResult {
        let paletteId = call.arguments.first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var globals = [
            "hypercard.htudefpal.palette": paletteId,
            "hypercard.htudefpal.arguments": call.arguments.joined(separator: "\t")
        ]
        if paletteId.isEmpty {
            globals["hypercard.htudefpal.status"] = "empty"
        } else if let asset = paletteAsset(for: paletteId, document: context.document) {
            globals["hypercard.htudefpal.status"] = "resolved"
            globals["hypercard.htudefpal.assetId"] = asset.id.uuidString
            globals["hypercard.htudefpal.assetName"] = asset.name
            appendPalettePayloadGlobals(from: asset, to: &globals)
            if let resourceType = asset.metadata.first(where: { $0.key.lowercased() == "resource_type" })?.value {
                globals["hypercard.htudefpal.resourceType"] = resourceType
            }
            if let resourcePath = asset.metadata.first(where: { $0.key.lowercased() == "resource_path" })?.value {
                globals["hypercard.htudefpal.resourcePath"] = resourcePath
            }
            if let artifactFormat = asset.metadata.first(where: { $0.key.lowercased() == "resource_artifact_format" })?.value {
                globals["hypercard.htudefpal.artifactFormat"] = artifactFormat
            }
        } else {
            globals["hypercard.htudefpal.status"] = "missing"
        }
        return HyperCardExternalResult(
            value: paletteId,
            result: "",
            runtimeGlobals: globals
        )
    }

    private static func hyperTintCompatibility(call: HyperCardExternalCall) -> HyperCardExternalResult {
        var globals = [
            "hypercard.hypertint.arguments": call.arguments.joined(separator: "\t")
        ]
        if let timing = call.arguments.first?.trimmingCharacters(in: .whitespacesAndNewlines),
           !timing.isEmpty {
            globals["hypercard.hypertint.timing"] = timing
        }
        if call.arguments.indices.contains(1) {
            globals["hypercard.hypertint.delay"] = call.arguments[1]
        }
        if call.arguments.count > 2 {
            globals["hypercard.hypertint.options"] = call.arguments.dropFirst(2).joined(separator: "\t")
        }
        return HyperCardExternalResult(
            value: "",
            result: "",
            runtimeGlobals: globals
        )
    }

    private static func colorIconCompatibility(
        call: HyperCardExternalCall,
        context: HyperCardExternalCallContext
    ) -> HyperCardExternalResult {
        let iconId = call.arguments.dropFirst().first ?? ""
        guard let asset = iconAsset(for: iconId, document: context.document) else {
            return HyperCardExternalResult(
                result: "Icon asset not found: \(iconId)",
                runtimeGlobals: [
                    "hypercard.xcicon3.icon": iconId,
                    "hypercard.xcicon3.arguments": call.arguments.joined(separator: "\t")
                ]
            )
        }
        var document = context.document
        let rect: CGRect
        if let loc = classicPoint(from: call.arguments.first) {
            rect = CGRect(
                x: loc.x - Double(max(asset.width, 1)) / 2.0,
                y: loc.y - Double(max(asset.height, 1)) / 2.0,
                width: Double(max(asset.width, 1)),
                height: Double(max(asset.height, 1))
            )
        } else {
            rect = CGRect(x: 0, y: 0, width: Double(max(asset.width, 1)), height: Double(max(asset.height, 1)))
        }
        var part = Part(
            partType: .image,
            cardId: context.currentCardId,
            name: "xCIcon3 \(asset.name)",
            left: rect.origin.x,
            top: rect.origin.y,
            width: rect.width,
            height: rect.height
        )
        part.imageData = asset.data
        part.transparentBackground = true
        part.helpText = iconOverlayMarker
        document.addPart(part)

        return HyperCardExternalResult(
            value: asset.name,
            result: asset.name,
            modifiedDocument: document,
            runtimeGlobals: [
                "hypercard.xcicon3.icon": iconId,
                "hypercard.xcicon3.asset": asset.name,
                "hypercard.xcicon3.arguments": call.arguments.joined(separator: "\t")
            ]
        )
    }

    private static func normalizedHTLockMode(from arguments: [Value]) -> Value {
        guard let first = arguments.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !first.isEmpty else {
            return "true"
        }
        switch first.lowercased() {
        case "0", "false", "off":
            return "false"
        case "unlock", "unlocked":
            return "unlock"
        case "1", "true", "on":
            return "true"
        case "lock", "locked":
            return "lock"
        case "bw", "nobw", "novbl", "forcefalse":
            return first.lowercased()
        default:
            return first
        }
    }

    private static func visualEffectDuration(from arguments: [Value]) -> Double? {
        for argument in arguments.dropFirst().reversed() {
            guard let value = Double(argument.trimmingCharacters(in: .whitespacesAndNewlines)),
                  value > 0 else {
                continue
            }
            return value / 60.0
        }
        return nil
    }

    private static func normalizedCursorMode(from arguments: [Value]) -> Value {
        guard let first = arguments.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !first.isEmpty else {
            return "remove"
        }
        switch first.lowercased() {
        case "remove", "clear", "default", "reset", "off":
            return "remove"
        case "override", "lock", "on":
            return "override"
        default:
            return first
        }
    }

    private static func clampedClassicSoundVolume(_ rawValue: Value, fallback: Value) -> Value {
        let source = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : rawValue
        let parsed = Double(source.trimmingCharacters(in: .whitespacesAndNewlines))
            ?? Double(fallback.trimmingCharacters(in: .whitespacesAndNewlines))
            ?? 255
        let rounded = Int(parsed.rounded())
        return String(min(255, max(0, rounded)))
    }

    private static func normalizedClassicSoundVolume(_ rawValue: Value) -> Double {
        (Double(clampedClassicSoundVolume(rawValue, fallback: "255")) ?? 255) / 255
    }

    private static func applyClassicSoundVolume(
        _ rawValue: Value,
        currentCardId: UUID,
        to document: inout HypeDocument
    ) {
        let volume = normalizedClassicSoundVolume(rawValue)
        for index in document.parts.indices where
            document.parts[index].cardId == currentCardId &&
            document.parts[index].partType == .video &&
            isQuickTimeCompatibilityPart(document.parts[index]) {
            document.parts[index].videoVolume = volume
        }
    }

    private static func isAudioOnlyQuickTimeAsset(_ asset: Asset) -> Bool {
        let ext = URL(fileURLWithPath: asset.name).pathExtension.lowercased()
        if asset.mimeType.lowercased().hasPrefix("audio/") { return true }
        if ["m4a", "wav", "aif", "aiff", "mp3"].contains(ext) { return true }
        return asset.metadata.contains { entry in
            entry.key.caseInsensitiveCompare("quicktime_audio_only") == .orderedSame &&
                entry.value.caseInsensitiveCompare("true") == .orderedSame
        }
    }

    private static func isQuickTimeCompatibilityPart(_ part: Part) -> Bool {
        part.helpText == quickTimeCompatibilityMarker ||
            part.helpText.hasPrefix("\(quickTimeCompatibilityMarker)\n")
    }

    private static func normalizedDisplayMode(_ rawValue: Value?) -> Value {
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "c" : trimmed.lowercased()
    }

    private static func normalizedDisplayDepth(_ rawValue: Value?) -> Value {
        let source = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let parsed = Double(source) else { return "8" }
        return String(max(1, Int(parsed.rounded())))
    }

    private static func normalizedClassicInteger(_ rawValue: Value?, fallback: Value) -> Value {
        let source = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parsed = Double(source) ?? Double(fallback.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        return String(Int(parsed.rounded()))
    }

    private static func classicMovieName(from rawPath: Value) -> Value {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let separators = CharacterSet(charactersIn: ":/")
        let lastComponent = trimmed.components(separatedBy: separators)
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? trimmed
        let nsName = lastComponent as NSString
        let stem = nsName.deletingPathExtension.isEmpty ? lastComponent : nsName.deletingPathExtension
        for suffix in ["-modern-av", "-modern"] where stem.lowercased().hasSuffix(suffix) {
            return String(stem.dropLast(suffix.count))
        }
        return stem
    }

    private static func movieInfoLines(
        for asset: Asset,
        requestedPath: Value,
        movieName: Value
    ) -> [Value] {
        let width = max(asset.width, 0)
        let height = max(asset.height, 0)
        let metadataSize = movieInfoMetadata(asset, "size")
        let byteCount = metadataSize.isEmpty ? String(asset.data.count) : metadataSize
        return [
            "name:\t\(movieName)",
            "asset:\t\(asset.name)",
            "path:\t\(requestedPath)",
            "type:\t\(asset.mimeType)",
            "bytes:\t\(byteCount)",
            "width:\t\(width)",
            "height:\t\(height)",
            "bounds:\t0,0,\(width),\(height)",
            "duration:\t0",
            "timescale:\t600"
        ]
    }

    private static func movieInfoMetadata(_ asset: Asset, _ key: Value) -> Value {
        asset.metadata.first { $0.key.lowercased() == key.lowercased() }?.value ?? ""
    }

    private static func pictureAsset(for rawName: Value, document: HypeDocument) -> Asset? {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return document.assetRepository.asset(byClassicMediaName: trimmed, kind: .imageTexture)
    }

    private static func iconAsset(for rawId: Value, document: HypeDocument) -> Asset? {
        let trimmed = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for candidate in ["cicn_\(trimmed)", "CICN_\(trimmed)", "ICON_\(trimmed)", "icon_\(trimmed)", trimmed] {
            if let asset = document.assetRepository.asset(byClassicMediaName: candidate, kind: .imageTexture) {
                return asset
            }
        }
        return document.assetRepository.assets.reversed().first { asset in
            asset.kind == .imageTexture &&
                asset.metadata.contains { entry in
                    entry.key == "resource_id" && entry.value == trimmed
                } &&
                asset.metadata.contains { entry in
                    entry.key == "resource_type" &&
                        ["cicn", "icon"].contains(entry.value.lowercased())
            }
        }
    }

    private static func paletteAsset(for rawId: Value, document: HypeDocument) -> Asset? {
        let trimmed = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let paletteResourceTypes: Set<String> = [
            "clut",
            "ctbl",
            "actb",
            "cctb",
            "dctb",
            "fctb",
            "wctb",
            "pltt",
            "plte"
        ]
        return document.assetRepository.assets.reversed().first { asset in
            asset.metadata.contains { entry in
                entry.key.lowercased() == "resource_id" &&
                    entry.value.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed
            } &&
            asset.metadata.contains { entry in
                entry.key.lowercased() == "resource_type" &&
                    paletteResourceTypes.contains(entry.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            }
        }
    }

    private struct StackImportPalettePayload: Decodable {
        var entries: [StackImportPaletteEntry]
    }

    private struct StackImportPaletteEntry: Decodable {
        var red: Int
        var green: Int
        var blue: Int
    }

    private static func appendPalettePayloadGlobals(
        from asset: Asset,
        to globals: inout [String: String]
    ) {
        guard let payload = try? JSONDecoder().decode(StackImportPalettePayload.self, from: asset.data) else {
            globals["hypercard.htudefpal.payloadStatus"] = asset.data.isEmpty ? "empty" : "unparsed"
            return
        }
        let colors = payload.entries.map(normalizedClassicPaletteHex)
        globals["hypercard.htudefpal.payloadStatus"] = "parsed"
        globals["hypercard.htudefpal.colorCount"] = String(colors.count)
        if let first = colors.first {
            globals["hypercard.htudefpal.firstColor"] = first
        }
        if let last = colors.last {
            globals["hypercard.htudefpal.lastColor"] = last
        }
        if !colors.isEmpty {
            globals["hypercard.htudefpal.colors"] = colors.joined(separator: "\t")
        }
    }

    private static func normalizedClassicPaletteHex(_ entry: StackImportPaletteEntry) -> String {
        "#\(classicRGB16ToHex(entry.red))\(classicRGB16ToHex(entry.green))\(classicRGB16ToHex(entry.blue))"
    }

    private static func classicRGB16ToHex(_ value: Int) -> String {
        let clamped = min(max(value, 0), 65_535)
        let eightBit = Int((Double(clamped) * 255.0 / 65_535.0).rounded())
        return String(format: "%02X", eightBit)
    }

    private static func classicRect(from rawValue: Value?) -> CGRect? {
        guard let rawValue else { return nil }
        let values = classicNumberList(rawValue)
        guard values.count >= 4 else { return nil }
        let left = values[0]
        let top = values[1]
        let right = values[2]
        let bottom = values[3]
        return CGRect(
            x: left,
            y: top,
            width: max(1, right - left),
            height: max(1, bottom - top)
        )
    }

    private static func classicPoint(from rawValue: Value?) -> CGPoint? {
        guard let rawValue else { return nil }
        let values = classicNumberList(rawValue)
        guard values.count >= 2 else { return nil }
        return CGPoint(x: values[0], y: values[1])
    }

    private static func pictureSourceRect(from arguments: [Value]) -> CGRect? {
        guard arguments.count >= 5 else { return nil }
        for index in arguments.indices.dropFirst(2)
            where arguments[index].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "srcrect" {
            let valueIndex = arguments.index(after: index)
            guard arguments.indices.contains(valueIndex) else { return nil }
            return classicRect(from: arguments[valueIndex])
        }
        return nil
    }

    private static func pictureUsesClipboard(arguments: [Value]) -> Bool {
        arguments.contains { argument in
            argument.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "clipboard"
        }
    }

    private static func pictureTransferMode(from arguments: [Value]) -> String? {
        guard arguments.count >= 3 else { return nil }
        for argument in arguments.dropFirst(2) {
            switch argument
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .filter({ $0.isLetter || $0.isNumber }) {
            case "srccopy":
                return "srcCopy"
            case "srcor":
                return "srcOr"
            case "srcxor":
                return "srcXor"
            case "notsrccopy":
                return "notSrcCopy"
            case "notsrcor":
                return "notSrcOr"
            case "notsrcxor":
                return "notSrcXor"
            case "notsrcbic":
                return "notSrcBic"
            case "blend":
                return "blend"
            default:
                continue
            }
        }
        return nil
    }

    private static func hyperTintTempBufferVBLMode(from arguments: [Value]) -> String {
        for argument in arguments {
            switch AssetRepository.classicMediaLookupKey(argument) {
            case "vbl":
                return "true"
            case "novbl":
                return "false"
            default:
                continue
            }
        }
        return "auto"
    }

    private static func pictureWindowStartsVisible(arguments: [Value]) -> Bool {
        !arguments.dropFirst().contains { argument in
            ["false", "invisible", "hidden"].contains(argument.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
    }

    private static func classicNumberList(_ rawValue: Value) -> [Double] {
        rawValue
            .split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private static func pictureRuntimeGlobals(
        call: HyperCardExternalCall,
        assetName: String,
        replacement: Bool,
        sourceRect: CGRect? = nil,
        transferMode: String? = nil,
        restoredClipboardRect: CGRect? = nil,
        removedOverlayCount: Int? = nil,
        restoredClipboardAsset: String? = nil,
        compositedPixelCount: Int? = nil
    ) -> [String: String] {
        let prefix = replacement ? "hypercard.htchangepict" : "hypercard.htaddpict"
        var globals = [
            "\(prefix).asset": assetName,
            "\(prefix).arguments": call.arguments.joined(separator: "\t")
        ]
        if let sourceRect {
            globals["\(prefix).sourceRect"] = classicRectString(sourceRect)
        }
        if let transferMode {
            globals["\(prefix).transferMode"] = transferMode
        }
        if let restoredClipboardRect {
            globals["\(prefix).clipboardRect"] = classicRectString(restoredClipboardRect)
        }
        if let removedOverlayCount {
            globals["\(prefix).removedOverlayCount"] = String(removedOverlayCount)
        }
        if let restoredClipboardAsset {
            globals["\(prefix).restoredClipboardAsset"] = restoredClipboardAsset
        }
        if let compositedPixelCount {
            globals["\(prefix).compositedPixels"] = String(compositedPixelCount)
        }
        return globals
    }

    private static func pictureWindowRuntimeGlobals(
        call: HyperCardExternalCall,
        assetName: String,
        windowName: String,
        visible: Bool = false
    ) -> [String: String] {
        let windowKey = AssetRepository.classicMediaLookupKey(windowName)
        var globals = [
            "hypercard.picture.asset": assetName,
            "hypercard.picture.window": windowName,
            "hypercard.picture.arguments": call.arguments.joined(separator: "\t"),
            "hypercard.window.\(windowKey).exists": assetName.isEmpty ? "false" : "true",
            "hypercard.window.\(windowKey).visible": visible ? "true" : "false",
            "hypercard.window.\(windowKey).scroll": "0,0"
        ]
        if call.arguments.indices.contains(1) {
            globals["hypercard.picture.source"] = call.arguments[1]
        }
        if call.arguments.indices.contains(3) {
            globals["hypercard.picture.visibleArgument"] = call.arguments[3]
        }
        if call.arguments.indices.contains(4) {
            globals["hypercard.picture.depth"] = call.arguments[4]
        }
        return globals
    }

    private static func partRect(_ part: Part) -> CGRect {
        CGRect(x: part.left, y: part.top, width: part.width, height: part.height)
    }

    private static func croppedPNGData(from imageData: Data, sourceRect: CGRect) -> Data? {
        guard let cgImage = cgImage(from: imageData) else { return nil }
        let bounded = sourceRect.integral.intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        guard !bounded.isNull, bounded.width > 0, bounded.height > 0,
              let cropped = cgImage.cropping(to: bounded) else {
            return nil
        }
        return pngData(from: cropped)
    }

    private static func compositePictureIntoPaintLayer(
        imageData: Data,
        destinationRect: CGRect,
        transferMode: String,
        currentCardId: UUID,
        document: inout HypeDocument
    ) -> Int? {
        guard let sourceImage = rgbaImageData(from: imageData) else { return nil }
        let width = max(1, document.stack.width)
        let height = max(1, document.stack.height)
        var layer = document.paintLayer(forCardId: currentCardId)
            ?? CardPaintLayer(
                cardId: currentCardId,
                width: width,
                height: height,
                rgbaData: Data(count: width * height * 4)
            )
        if layer.width != width || layer.height != height {
            layer = CardPaintLayer(
                cardId: currentCardId,
                width: width,
                height: height,
                rgbaData: Data(count: width * height * 4)
            )
        }

        let target = destinationRect.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !target.isNull, target.width > 0, target.height > 0 else { return 0 }
        let left = max(0, Int(target.minX))
        let top = max(0, Int(target.minY))
        let targetWidth = min(width - left, Int(target.width))
        let targetHeight = min(height - top, Int(target.height))
        guard targetWidth > 0, targetHeight > 0 else { return 0 }

        var layerData = layer.normalizedRGBAData
        var changed = 0
        for y in 0..<targetHeight {
            for x in 0..<targetWidth {
                let sourceX = min(sourceImage.width - 1, max(0, Int((Double(x) / Double(max(1, targetWidth))) * Double(sourceImage.width))))
                let sourceY = min(sourceImage.height - 1, max(0, Int((Double(y) / Double(max(1, targetHeight))) * Double(sourceImage.height))))
                let sourceOffset = (sourceY * sourceImage.width + sourceX) * 4
                let destinationOffset = ((top + y) * width + left + x) * 4
                guard sourceOffset + 3 < sourceImage.data.count,
                      destinationOffset + 3 < layerData.count else { continue }
                let src = (
                    sourceImage.data[sourceOffset],
                    sourceImage.data[sourceOffset + 1],
                    sourceImage.data[sourceOffset + 2],
                    sourceImage.data[sourceOffset + 3]
                )
                guard src.3 > 0 else { continue }
                let dst = (
                    layerData[destinationOffset],
                    layerData[destinationOffset + 1],
                    layerData[destinationOffset + 2],
                    layerData[destinationOffset + 3]
                )
                let out = compositeClassicPixel(source: src, destination: dst, transferMode: transferMode)
                if layerData[destinationOffset] != out.0 ||
                    layerData[destinationOffset + 1] != out.1 ||
                    layerData[destinationOffset + 2] != out.2 ||
                    layerData[destinationOffset + 3] != out.3 {
                    changed += 1
                }
                layerData[destinationOffset] = out.0
                layerData[destinationOffset + 1] = out.1
                layerData[destinationOffset + 2] = out.2
                layerData[destinationOffset + 3] = out.3
            }
        }

        guard changed > 0 else { return 0 }
        document.setPaintLayer(CardPaintLayer(cardId: currentCardId, width: width, height: height, rgbaData: layerData))
        return changed
    }

    private static func rgbaImageData(from imageData: Data) -> (data: Data, width: Int, height: Int)? {
        guard let cgImage = cgImage(from: imageData) else { return nil }
        let width = max(1, cgImage.width)
        let height = max(1, cgImage.height)
        var data = Data(count: width * height * 4)
        let rendered = data.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                return false
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return rendered ? (data, width, height) : nil
    }

    private static func cgImage(from imageData: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func pngData(from image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func compositeClassicPixel(
        source: (UInt8, UInt8, UInt8, UInt8),
        destination: (UInt8, UInt8, UInt8, UInt8),
        transferMode: String
    ) -> (UInt8, UInt8, UInt8, UInt8) {
        func blend(_ a: UInt8, _ b: UInt8) -> UInt8 {
            UInt8((Int(a) + Int(b)) / 2)
        }
        switch transferMode {
        case "srcOr":
            return (destination.0 | source.0, destination.1 | source.1, destination.2 | source.2, max(destination.3, source.3))
        case "srcXor":
            return (destination.0 ^ source.0, destination.1 ^ source.1, destination.2 ^ source.2, max(destination.3, source.3))
        case "notSrcCopy":
            return (~source.0, ~source.1, ~source.2, source.3)
        case "notSrcOr":
            return (destination.0 | ~source.0, destination.1 | ~source.1, destination.2 | ~source.2, max(destination.3, source.3))
        case "notSrcXor":
            return (destination.0 ^ ~source.0, destination.1 ^ ~source.1, destination.2 ^ ~source.2, max(destination.3, source.3))
        case "notSrcBic":
            return (destination.0 & source.0, destination.1 & source.1, destination.2 & source.2, max(destination.3, source.3))
        case "blend":
            return (blend(destination.0, source.0), blend(destination.1, source.1), blend(destination.2, source.2), max(destination.3, source.3))
        default:
            return source
        }
    }

    private static func clipboardPNGData(
        from layer: CardPaintLayer?,
        rect: CGRect
    ) -> (data: Data, width: Int, height: Int)? {
        guard let layer else { return nil }
        let source = rect.integral.intersection(CGRect(x: 0, y: 0, width: layer.width, height: layer.height))
        guard !source.isNull, source.width > 0, source.height > 0 else { return nil }
        let left = max(0, Int(source.minX))
        let top = max(0, Int(source.minY))
        let width = min(layer.width - left, Int(source.width))
        let height = min(layer.height - top, Int(source.height))
        guard width > 0, height > 0 else { return nil }

        let layerData = layer.normalizedRGBAData
        var cropped = Data(count: width * height * 4)
        for y in 0..<height {
            let sourceOffset = ((top + y) * layer.width + left) * 4
            let destinationOffset = y * width * 4
            let byteCount = width * 4
            guard sourceOffset + byteCount <= layerData.count,
                  destinationOffset + byteCount <= cropped.count else {
                return nil
            }
            cropped.replaceSubrange(
                destinationOffset..<(destinationOffset + byteCount),
                with: layerData[sourceOffset..<(sourceOffset + byteCount)]
            )
        }

        guard let png = PNGEncoding.rgbaDataToPNG(cropped, width: width, height: height) else { return nil }
        return (png, width, height)
    }

    private static func classicRectString(_ rect: CGRect) -> String {
        [
            rect.origin.x,
            rect.origin.y,
            rect.origin.x + rect.width,
            rect.origin.y + rect.height
        ].map(formatClassicNumber).joined(separator: ",")
    }

    private static func classicPointString(_ point: CGPoint) -> String {
        [point.x, point.y].map(formatClassicNumber).joined(separator: ",")
    }

    private static func formatClassicNumber(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.000_001 {
            return String(Int(rounded))
        }
        return String(value)
    }

    private static let quickTimeCompatibilityMarker = "hypercard-playqt"
    private static let pictureOverlayMarker = "hypercard-htaddpict"
    private static let pictureReplacementMarker = "hypercard-htchangepict"
    private static let pictureWindowMarker = "hypercard-picture"
    private static let iconOverlayMarker = "hypercard-xcicon3"
}
