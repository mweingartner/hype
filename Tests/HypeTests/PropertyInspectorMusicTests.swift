import Foundation
import Testing

@Suite("Property Inspector — music controls")
struct PropertyInspectorMusicTests {
    @Test("Music instrument uses catalog-backed picker, not free-form text")
    func musicInstrumentUsesPicker() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources/Hype/Views/PropertyInspector.swift"), encoding: .utf8)

        #expect(source.contains("Picker(\"Instrument\", selection: bindMusicInstrumentName(part.id))"))
        #expect(source.contains("ForEach(MusicInstrumentCatalog.instruments, id: \\.name)"))
        #expect(source.contains("MusicInstrumentCatalog.resolve(newValue).name"))
        #expect(source.contains("Toggle(\"Control Type\", isOn: bindPartBool(part.id, \\.musicShowControlType))"))
        #expect(source.contains("Toggle(\"Pattern\", isOn: bindPartBool(part.id, \\.musicShowPattern))"))
        #expect(source.contains("Toggle(\"Instrument Popup\", isOn: bindPartBool(part.id, \\.musicShowInstrument))"))
        #expect(source.contains("Toggle(\"Tempo\", isOn: bindPartBool(part.id, \\.musicShowTempo))"))
        #expect(source.contains("Picker(\"Keys\", selection: bindMusicKeyCount(part.id))"))
        #expect(source.contains("ForEach(MusicKeyboardKeyCount.supportedValues, id: \\.self)"))
        #expect(source.contains("MusicKeyboardKeyCount.normalize(newValue)"))
        #expect(source.contains("Slider("))
        #expect(source.contains("TextField(\"BPM\", value: bindMusicTempoInt(part.id), format: .number)"))
        #expect(source.contains("Double(MusicTempo.minimum)...Double(MusicTempo.maximum)"))
        #expect(!source.contains("propertyRow(\"Instrument\", binding: bindPartString(part.id, \\.musicInstrumentName))"))
        #expect(!source.contains("Stepper(\"\\(Int(part.musicTempo.rounded())) BPM\""))
    }

    @Test("Piano keyboard and step sequencer browse mode use live instrument popup host")
    func audioKitControlsUseLiveInstrumentPopupHost() throws {
        let canvasSource = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources/Hype/Views/CardCanvasView.swift"), encoding: .utf8)
        let hostSource = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources/Hype/Views/MusicInstrumentPopupHostView.swift"), encoding: .utf8)

        #expect(canvasSource.contains("updateMusicInstrumentPopupViews()"))
        #expect(canvasSource.contains("($0.partType == .pianoKeyboard || $0.partType == .stepSequencer) && $0.visible && $0.musicShowInstrument"))
        #expect(canvasSource.contains("liveInstrumentPopupPartIds"))
        #expect(canvasSource.contains("musicControlRenderOptions: musicControlRenderOptions"))
        #expect(canvasSource.contains("setPartMusicInstrumentName(id: partId, instrument: instrument)"))
        #expect(hostSource.contains("NSPopUpButton()"))
        #expect(hostSource.contains("MusicInstrumentCatalog.instruments"))
    }

    @Test("MusicKit inspector exposes search, selection, playback, and position")
    func musicKitInspectorExposesSearchSelectionPlaybackAndPosition() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources/Hype/Views/PropertyInspector.swift"), encoding: .utf8)

        #expect(source.contains("Button(\"Search\") { searchAppleMusicFromInspector(part: part) }"))
        #expect(source.contains("Button(\"Use Selected Item\")"))
        #expect(source.contains("propertyRow(\"Selected ID\", binding: bindPartString(part.id, \\.musicSourceID))"))
        #expect(source.contains("propertyRow(\"Position Seconds\", binding: bindPartDoubleString(part.id, \\.musicPosition))"))
        #expect(source.contains("propertyRow(\"Duration Seconds\", binding: bindPartDoubleString(part.id, \\.musicDuration))"))
        #expect(source.contains("Button(\"Play\") { playAppleMusicFromInspector(part: part) }"))
        #expect(source.contains("Button(\"Seek\") { seekAppleMusicFromInspector(part: part) }"))
        #expect(source.contains("AppleMusicProviderFactory.makeDefault().search"))
    }

    private func packageRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
