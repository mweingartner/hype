import CoreGraphics
import Foundation

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

    public init(
        value: Value = "",
        result: Value = "",
        modifiedDocument: HypeDocument? = nil,
        passMessage: Bool = false,
        diagnostic: String? = nil,
        runtimeGlobals: [String: String] = [:]
    ) {
        self.value = value
        self.result = result
        self.modifiedDocument = modifiedDocument
        self.passMessage = passMessage
        self.diagnostic = diagnostic
        self.runtimeGlobals = runtimeGlobals
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
            return HyperCardExternalResult(
                value: "",
                result: cursorName,
                runtimeGlobals: [
                    "hypercard.cursor.name": cursorName,
                    "hypercard.cursor.mode": cursorName.isEmpty ? "default" : "set"
                ]
            )
        })
        put(.xcmd, ["playQT", "PlayMovie", "Movie"], Entry(status: .emulated) { call, context in
            playQuickTime(call: call, context: context)
        })
        put(.xcmd, ["closemoovs", "closemovies", "closeQT"], Entry(status: .emulated) { _, context in
            closeQuickTimeMovies(context: context)
        })
        put(.xcmd, ["HTLock"], Entry(status: .emulated) { call, _ in
            lockScreenCompatibility(call: call)
        })
        put(.xcmd, ["HTVisual"], Entry(status: .emulated) { call, _ in
            visualEffectCompatibility(call: call)
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
        part.helpText = audioOnly ? "\(quickTimeCompatibilityMarker)\naudioOnly=true" : quickTimeCompatibilityMarker
        document.addPart(part)

        return HyperCardExternalResult(
            value: asset.name,
            result: asset.name,
            modifiedDocument: document,
            runtimeGlobals: [
                "hypercard.playqt.asset": asset.name,
                "hypercard.playqt.audioOnly": audioOnly ? "true" : "false",
                "hypercard.window.\(lookupKey).exists": "true",
                "hypercard.window.\(lookupKey).visible": audioOnly ? "false" : "true"
            ]
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
        for argument in arguments.dropFirst() {
            if let point = classicPoint(from: argument) {
                return point
            }
        }
        return nil
    }

    private static func lockScreenCompatibility(call: HyperCardExternalCall) -> HyperCardExternalResult {
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

    private static func visualEffectCompatibility(call: HyperCardExternalCall) -> HyperCardExternalResult {
        let effect = call.arguments.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let durationTicks = call.arguments.reversed().first { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) != nil } ?? ""
        var globals = [
            "hypercard.htvisual.effect": effect,
            "hypercard.htvisual.arguments": call.arguments.joined(separator: "\t")
        ]
        if let ticks = Double(durationTicks), ticks > 0 {
            globals["hypercard.htvisual.durationSeconds"] = String(ticks / 60.0)
        }
        return HyperCardExternalResult(value: effect, result: effect, runtimeGlobals: globals)
    }

    private static func cursorCompatibility(call: HyperCardExternalCall) -> HyperCardExternalResult {
        let mode = normalizedCursorMode(from: call.arguments)
        var globals = [
            "hypercard.decurse.mode": mode,
            "hypercard.decurse.arguments": call.arguments.joined(separator: "\t"),
            "hypercard.cursor.mode": mode
        ]
        if call.arguments.indices.contains(1) {
            globals["hypercard.decurse.resource"] = call.arguments[1]
        }
        if call.arguments.indices.contains(2) {
            globals["hypercard.decurse.kind"] = call.arguments[2]
        }
        return HyperCardExternalResult(value: mode, result: mode, runtimeGlobals: globals)
    }

    private static func moveCursorCompatibility(call: HyperCardExternalCall) -> HyperCardExternalResult {
        let values = classicNumberList(call.arguments.joined(separator: ","))
        let x = Int((values.first ?? 0).rounded())
        let y = Int((values.dropFirst().first ?? 0).rounded())
        let loc = "\(x),\(y)"
        return HyperCardExternalResult(
            value: loc,
            result: loc,
            runtimeGlobals: [
                "hypercard.movecursor.x": String(x),
                "hypercard.movecursor.y": String(y),
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
                "hypercard.xwindowframe.arguments": call.arguments.joined(separator: "\t")
            ]
        )
    }

    private static func aboutCompatibility(call: HyperCardExternalCall) -> HyperCardExternalResult {
        HyperCardExternalResult(
            runtimeGlobals: [
                "hypercard.xabout.invoked": "true",
                "hypercard.xabout.arguments": call.arguments.joined(separator: "\t")
            ]
        )
    }

    private static func memoryCompatibility(call: HyperCardExternalCall) -> HyperCardExternalResult {
        let memory = String(max(1, ProcessInfo.processInfo.physicalMemory / 1024))
        return HyperCardExternalResult(
            value: memory,
            result: memory,
            runtimeGlobals: [
                "hypercard.xmemory.value": memory,
                "hypercard.xmemory.arguments": call.arguments.joined(separator: "\t")
            ]
        )
    }

    private static func virtualMemoryCompatibility(call: HyperCardExternalCall) -> HyperCardExternalResult {
        HyperCardExternalResult(
            value: "0",
            result: "0",
            runtimeGlobals: [
                "hypercard.xvirtual.value": "0",
                "hypercard.xvirtual.arguments": call.arguments.joined(separator: "\t")
            ]
        )
    }

    private static func variantCompatibility(call: HyperCardExternalCall) -> HyperCardExternalResult {
        HyperCardExternalResult(
            value: "2.1",
            result: "",
            runtimeGlobals: [
                "hypercard.variant.value": "2.1",
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

    private static func displayDepthCompatibility(context: HyperCardExternalCallContext) -> HyperCardExternalResult {
        let depth = context.document.scriptGlobals["hypercard.display.depth"] ?? "8"
        return HyperCardExternalResult(value: depth, result: depth)
    }

    private static func setDisplayModeCompatibility(call: HyperCardExternalCall) -> HyperCardExternalResult {
        let mode = normalizedDisplayMode(from: call.arguments)
        let depth = normalizedClassicInteger(call.arguments.dropFirst().first, fallback: "8")
        let value = "\(mode),\(depth)"
        return HyperCardExternalResult(
            value: "",
            result: "",
            runtimeGlobals: [
                "hypercard.display.mode": mode,
                "hypercard.display.depth": depth,
                "hypercard.display.value": value,
                "hypercard.setmode.arguments": call.arguments.joined(separator: "\t")
            ]
        )
    }

    private static func getDisplayModeCompatibility(context: HyperCardExternalCallContext) -> HyperCardExternalResult {
        let mode = context.document.scriptGlobals["hypercard.display.mode"] ?? "c"
        let depth = context.document.scriptGlobals["hypercard.display.depth"] ?? "8"
        let value = "\(mode),\(depth)"
        return HyperCardExternalResult(value: value, result: value)
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
        return HyperCardExternalResult(value: volume, result: volume)
    }

    private static func normalizedHTLockMode(from arguments: [Value]) -> String {
        for argument in arguments {
            switch normalizedToken(argument) {
            case "lock", "locked", "on", "true", "1":
                return "lock"
            case "unlock", "unlocked", "off", "false", "0":
                return "unlock"
            default:
                continue
            }
        }
        return "lock"
    }

    private static func normalizedCursorMode(from arguments: [Value]) -> String {
        for argument in arguments {
            switch normalizedToken(argument) {
            case "remove", "delete", "clear", "off", "false", "0":
                return "remove"
            case "restore", "default", "reset":
                return "default"
            case "show", "on", "true", "1":
                return "show"
            case "hide":
                return "hide"
            default:
                continue
            }
        }
        return arguments.isEmpty ? "default" : "set"
    }

    private static func normalizedDisplayMode(from arguments: [Value]) -> String {
        guard let first = arguments.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !first.isEmpty else {
            return "c"
        }
        switch normalizedToken(first) {
        case "b", "bw", "blackwhite", "blackandwhite", "mono", "monochrome":
            return "b"
        default:
            return "c"
        }
    }

    private static func normalizedClassicInteger(
        _ rawValue: Value?,
        fallback: String,
        range: ClosedRange<Int>? = nil
    ) -> String {
        guard let rawValue,
              let numeric = Double(rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              numeric.isFinite else {
            return fallback
        }
        let value = Int(numeric.rounded())
        if let range {
            return String(min(max(value, range.lowerBound), range.upperBound))
        }
        return String(value)
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

    private static func classicNumberList(_ rawValue: Value) -> [Double] {
        rawValue
            .split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private static func classicPoint(from rawValue: Value?) -> CGPoint? {
        guard let rawValue else { return nil }
        let values = classicNumberList(rawValue)
        guard values.count >= 2 else { return nil }
        return CGPoint(x: values[0], y: values[1])
    }

    private static func normalizedToken(_ rawValue: Value) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static let quickTimeCompatibilityMarker = "hypercard-playqt"
}
