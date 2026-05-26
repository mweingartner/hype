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
        #expect(!source.contains("propertyRow(\"Instrument\", binding: bindPartString(part.id, \\.musicInstrumentName))"))
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
