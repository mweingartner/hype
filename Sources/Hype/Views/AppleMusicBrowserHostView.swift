import AppKit
import HypeCore

@MainActor
final class AppleMusicBrowserHostNSView: NSView {
    var onSearchConfigurationChange: ((String, AppleMusicSearchScope, AppleMusicItemKind) -> Void)?
    var onSelectionChange: ((AppleMusicItemRef) -> Void)?
    var onPlaybackPositionChange: ((Double) -> Void)?
    var onPlaybackEvent: ((String, [String]) -> Void)?

    private let provider: any AppleMusicProviding
    private var part: Part?
    private var stackAllowsAppleMusic = false
    private var preferencesAllowAppleMusic = false
    private var results: [AppleMusicItemRef] = []

    private let searchField = NSSearchField()
    private let scopePopup = NSPopUpButton()
    private let typePopup = NSPopUpButton()
    private let resultPopup = NSPopUpButton()
    private let authorizeButton = NSButton(title: "Authorize", target: nil, action: nil)
    private let searchButton = NSButton(title: "Search", target: nil, action: nil)
    private let playButton = NSButton(title: "Play", target: nil, action: nil)
    private let stopButton = NSButton(title: "Stop", target: nil, action: nil)
    private let positionSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "Apple Music is idle.")
    private let selectionLabel = NSTextField(labelWithString: "No Apple Music item selected.")

    init(frame frameRect: NSRect, provider: (any AppleMusicProviding)? = nil) {
        self.provider = provider ?? AppleMusicProviderFactory.makeDefault()
        super.init(frame: frameRect)
        buildUI()
    }

    required init?(coder: NSCoder) {
        self.provider = AppleMusicProviderFactory.makeDefault()
        super.init(coder: coder)
        buildUI()
    }

    func apply(part: Part, stackAllowsAppleMusic: Bool, preferencesAllowAppleMusic: Bool) {
        self.part = part
        self.stackAllowsAppleMusic = stackAllowsAppleMusic
        self.preferencesAllowAppleMusic = preferencesAllowAppleMusic

        if window?.firstResponder !== searchField.currentEditor() {
            searchField.stringValue = part.musicSearchTerm
        }
        selectScope(AppleMusicSearchScope(rawValue: part.musicSearchScope) ?? .catalog)
        selectKind(AppleMusicItemKind.parse(part.musicSourceType) ?? .song)
        updateSelectionLabel(from: part)
        updatePositionSlider(position: part.musicPosition, duration: part.musicDuration)
        updateEnabledState()
    }

    private func buildUI() {
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        searchField.placeholderString = "Search Apple Music"
        searchField.target = self
        searchField.action = #selector(searchClicked)

        scopePopup.addItem(withTitle: "Catalog")
        scopePopup.addItem(withTitle: "Library")
        scopePopup.target = self
        scopePopup.action = #selector(searchConfigurationChanged)

        for kind in [AppleMusicItemKind.song, .album, .artist, .playlist] {
            typePopup.addItem(withTitle: displayName(for: kind))
            typePopup.lastItem?.representedObject = kind.rawValue
        }
        typePopup.target = self
        typePopup.action = #selector(searchConfigurationChanged)

        resultPopup.addItem(withTitle: "No results")
        resultPopup.target = self
        resultPopup.action = #selector(resultSelectionChanged)

        authorizeButton.target = self
        authorizeButton.action = #selector(authorizeClicked)
        searchButton.target = self
        searchButton.action = #selector(searchClicked)
        playButton.target = self
        playButton.action = #selector(playClicked)
        stopButton.target = self
        stopButton.action = #selector(stopClicked)

        positionSlider.isContinuous = false
        positionSlider.target = self
        positionSlider.action = #selector(positionChanged)

        statusLabel.font = .systemFont(ofSize: 10)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        selectionLabel.font = .systemFont(ofSize: 11, weight: .medium)
        selectionLabel.lineBreakMode = .byTruncatingTail

        let pickers = NSStackView(views: [scopePopup, typePopup])
        pickers.orientation = .horizontal
        pickers.spacing = 6
        pickers.distribution = .fillEqually

        let searchRow = NSStackView(views: [searchField, searchButton])
        searchRow.orientation = .horizontal
        searchRow.spacing = 6

        let playbackRow = NSStackView(views: [authorizeButton, playButton, stopButton])
        playbackRow.orientation = .horizontal
        playbackRow.spacing = 6
        playbackRow.distribution = .fillEqually

        let root = NSStackView(views: [
            searchRow,
            pickers,
            resultPopup,
            selectionLabel,
            positionSlider,
            playbackRow,
            statusLabel
        ])
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .vertical
        root.spacing = 6
        root.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
    }

    @objc private func searchConfigurationChanged() {
        guard let part else { return }
        let term = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let scope = selectedScope()
        let kind = selectedKind()
        onSearchConfigurationChange?(term, scope, kind)
        self.part = updatedPart(part, term: term, scope: scope, kind: kind)
    }

    @objc private func authorizeClicked() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let status = await provider.requestAuthorization()
            statusLabel.stringValue = "Apple Music authorization: \(status.rawValue)"
        }
    }

    @objc private func searchClicked() {
        searchConfigurationChanged()
        guard stackAllowsAppleMusic, preferencesAllowAppleMusic else {
            statusLabel.stringValue = "Enable Apple Music in Preferences and for this stack."
            return
        }
        let term = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            statusLabel.stringValue = "Enter a search term first."
            return
        }
        statusLabel.stringValue = "Searching Apple Music..."
        resultPopup.removeAllItems()
        resultPopup.addItem(withTitle: "Searching...")
        let request = AppleMusicSearchRequest(term: term, scope: selectedScope(), itemKinds: [selectedKind()], limit: 12)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let found = try await provider.search(request)
                results = found
                populateResults(found)
                statusLabel.stringValue = found.isEmpty ? "No Apple Music results." : "Found \(found.count) Apple Music item(s)."
                onPlaybackEvent?("musicSearchCompleted", [term, String(found.count)])
            } catch {
                results = []
                populateResults([])
                statusLabel.stringValue = "Search failed: \(error.localizedDescription)"
            }
        }
    }

    @objc private func resultSelectionChanged() {
        let index = resultPopup.indexOfSelectedItem
        guard results.indices.contains(index) else { return }
        let ref = results[index]
        onSelectionChange?(ref)
        updateSelectionLabel(ref)
        updatePositionSlider(position: 0, duration: ref.durationSnapshot ?? 0)
        statusLabel.stringValue = "Selected \(displayName(for: ref.kind).lowercased()) '\(ref.titleSnapshot)'."
        onPlaybackEvent?("musicItemSelected", [ref.encodedSource])
    }

    @objc private func playClicked() {
        guard stackAllowsAppleMusic, preferencesAllowAppleMusic else {
            statusLabel.stringValue = "Enable Apple Music in Preferences and for this stack."
            return
        }
        guard let ref = selectedRef() else {
            statusLabel.stringValue = "Select an Apple Music item first."
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await provider.play(ref, engine: playbackEngine())
                statusLabel.stringValue = "Playing '\(ref.titleSnapshot)'."
                onPlaybackEvent?("playbackStarted", [ref.encodedSource])
            } catch {
                statusLabel.stringValue = "Playback failed: \(error.localizedDescription)"
            }
        }
    }

    @objc private func stopClicked() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await provider.stop(engine: playbackEngine())
            statusLabel.stringValue = "Stopped Apple Music."
            onPlaybackEvent?("playbackStopped", [])
        }
    }

    @objc private func positionChanged() {
        let seconds = max(0, positionSlider.doubleValue)
        onPlaybackPositionChange?(seconds)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await provider.seek(to: seconds, engine: playbackEngine())
                statusLabel.stringValue = "Position: \(formatSeconds(seconds))."
            } catch {
                statusLabel.stringValue = "Seek failed: \(error.localizedDescription)"
            }
        }
    }

    private func populateResults(_ refs: [AppleMusicItemRef]) {
        resultPopup.removeAllItems()
        guard !refs.isEmpty else {
            resultPopup.addItem(withTitle: "No results")
            return
        }
        for ref in refs {
            resultPopup.addItem(withTitle: menuTitle(for: ref))
        }
        resultPopup.selectItem(at: 0)
        resultSelectionChanged()
    }

    private func selectedRef() -> AppleMusicItemRef? {
        let index = resultPopup.indexOfSelectedItem
        if results.indices.contains(index) {
            return results[index]
        }
        guard let part,
              !part.musicSourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let kind = AppleMusicItemKind.parse(part.musicSourceType) else {
            return nil
        }
        return AppleMusicItemRef(
            id: part.musicSourceID,
            kind: kind,
            source: MusicSourceKind.parse(part.musicSourceKind),
            titleSnapshot: part.musicSourceTitle.isEmpty ? part.musicSourceID : part.musicSourceTitle,
            artistSnapshot: part.musicSourceArtist,
            albumSnapshot: part.musicSourceAlbum,
            artworkURLSnapshot: part.musicArtworkURL,
            durationSnapshot: part.musicDuration > 0 ? part.musicDuration : nil
        )
    }

    private func updateSelectionLabel(from part: Part) {
        guard !part.musicSourceID.isEmpty else {
            selectionLabel.stringValue = "No Apple Music item selected."
            return
        }
        selectionLabel.stringValue = "\(part.musicSourceTitle.isEmpty ? part.musicSourceID : part.musicSourceTitle)  \(part.musicSourceArtist)"
    }

    private func updateSelectionLabel(_ ref: AppleMusicItemRef) {
        selectionLabel.stringValue = "\(ref.titleSnapshot)  \(ref.artistSnapshot)"
    }

    private func updatePositionSlider(position: Double, duration: Double) {
        positionSlider.minValue = 0
        positionSlider.maxValue = max(1, duration)
        positionSlider.doubleValue = min(max(0, position), positionSlider.maxValue)
        positionSlider.isEnabled = duration > 0 && stackAllowsAppleMusic && preferencesAllowAppleMusic
        positionSlider.toolTip = duration > 0
            ? "Playback position: \(formatSeconds(position)) of \(formatSeconds(duration))"
            : "Select a song with a known duration to seek."
    }

    private func updateEnabledState() {
        let enabled = stackAllowsAppleMusic && preferencesAllowAppleMusic
        searchButton.isEnabled = enabled
        playButton.isEnabled = enabled
        stopButton.isEnabled = enabled
        authorizeButton.isEnabled = preferencesAllowAppleMusic
        if !enabled {
            statusLabel.stringValue = "Enable Apple Music in Preferences and for this stack."
        }
    }

    private func selectedScope() -> AppleMusicSearchScope {
        scopePopup.indexOfSelectedItem == 1 ? .library : .catalog
    }

    private func selectScope(_ scope: AppleMusicSearchScope) {
        scopePopup.selectItem(at: scope == .library ? 1 : 0)
    }

    private func selectedKind() -> AppleMusicItemKind {
        let raw = typePopup.selectedItem?.representedObject as? String
        return raw.flatMap(AppleMusicItemKind.parse) ?? .song
    }

    private func selectKind(_ kind: AppleMusicItemKind) {
        for index in 0..<typePopup.numberOfItems {
            if typePopup.item(at: index)?.representedObject as? String == kind.rawValue {
                typePopup.selectItem(at: index)
                return
            }
        }
        typePopup.selectItem(at: 0)
    }

    private func updatedPart(_ part: Part, term: String, scope: AppleMusicSearchScope, kind: AppleMusicItemKind) -> Part {
        var next = part
        next.musicSearchTerm = term
        next.musicSearchScope = scope.rawValue
        next.musicSourceType = kind.rawValue
        next.musicSourceKind = scope == .library ? MusicSourceKind.appleMusicLibrary.rawValue : MusicSourceKind.appleMusicCatalog.rawValue
        return next
    }

    private func playbackEngine() -> AppleMusicPlaybackEngine {
        let raw = UserDefaults.standard.string(forKey: AppleMusicConfiguration.playbackEngineKey)
        return raw.flatMap(AppleMusicPlaybackEngine.init(rawValue:)) ?? AppleMusicConfiguration.defaultPlaybackEngine
    }

    private func displayName(for kind: AppleMusicItemKind) -> String {
        switch kind {
        case .song: return "Song"
        case .album: return "Album"
        case .artist: return "Singer"
        case .playlist: return "Playlist"
        case .station: return "Station"
        case .musicVideo: return "Music Video"
        }
    }

    private func menuTitle(for ref: AppleMusicItemRef) -> String {
        let detail = [ref.artistSnapshot, ref.albumSnapshot]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " - ")
        return detail.isEmpty ? ref.titleSnapshot : "\(ref.titleSnapshot) - \(detail)"
    }

    private func formatSeconds(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}
