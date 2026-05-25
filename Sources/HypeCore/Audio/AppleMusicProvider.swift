import Foundation

public enum AppleMusicAuthorizationState: String, Codable, Sendable, Equatable, CaseIterable {
    case notDetermined
    case denied
    case restricted
    case authorized
    case unavailable
}

public enum AppleMusicPlaybackEngine: String, Codable, Sendable, Equatable, CaseIterable {
    /// Hype-owned playback queue. Preferred because it does not take over Music.app.
    case application
    /// System Music app queue. Useful when the stack intentionally controls the user's current music.
    case system
}

public enum AppleMusicItemKind: String, Codable, Sendable, Equatable, CaseIterable {
    case song
    case album
    case artist
    case playlist
    case station
    case musicVideo

    public var pluralName: String {
        switch self {
        case .song: return "songs"
        case .album: return "albums"
        case .artist: return "artists"
        case .playlist: return "playlists"
        case .station: return "stations"
        case .musicVideo: return "musicVideos"
        }
    }

    public static func parse(_ raw: String) -> AppleMusicItemKind? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "") {
        case "song", "songs", "track", "tracks": return .song
        case "album", "albums": return .album
        case "artist", "artists": return .artist
        case "playlist", "playlists": return .playlist
        case "station", "stations", "radio", "radios": return .station
        case "musicvideo", "musicvideos", "video", "videos": return .musicVideo
        default: return nil
        }
    }
}

public enum AppleMusicSearchScope: String, Codable, Sendable, Equatable, CaseIterable {
    case catalog
    case library
}

public enum MusicSourceKind: String, Codable, Sendable, Equatable, CaseIterable {
    /// Stack-contained Hype music patterns rendered through AudioKit.
    case hypePattern
    /// Apple Music catalog item. Requires MusicKit authorization and, for playback, a playable subscription.
    case appleMusicCatalog
    /// User library item. Requires explicit stack opt-in because library contents are personal data.
    case appleMusicLibrary
    /// User/catalog playlist reference.
    case appleMusicPlaylist
    /// Apple Music station/radio reference.
    case appleMusicStation

    public static func parse(_ raw: String) -> MusicSourceKind {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "") {
        case "applemusic", "applemusiccatalog", "catalog": return .appleMusicCatalog
        case "applemusiclibrary", "library", "mymusic": return .appleMusicLibrary
        case "applemusicplaylist", "playlist": return .appleMusicPlaylist
        case "applemusicstation", "station", "radio": return .appleMusicStation
        default: return .hypePattern
        }
    }
}

public struct AppleMusicCapabilities: Codable, Sendable, Equatable {
    public var authorization: AppleMusicAuthorizationState
    public var canPlayCatalogContent: Bool
    public var canBecomeSubscriber: Bool
    public var hasCloudLibraryEnabled: Bool
    public var supportsLibraryMutation: Bool
    public var storefront: String
    public var lastError: String

    public init(
        authorization: AppleMusicAuthorizationState = .unavailable,
        canPlayCatalogContent: Bool = false,
        canBecomeSubscriber: Bool = false,
        hasCloudLibraryEnabled: Bool = false,
        supportsLibraryMutation: Bool = false,
        storefront: String = "",
        lastError: String = ""
    ) {
        self.authorization = authorization
        self.canPlayCatalogContent = canPlayCatalogContent
        self.canBecomeSubscriber = canBecomeSubscriber
        self.hasCloudLibraryEnabled = hasCloudLibraryEnabled
        self.supportsLibraryMutation = supportsLibraryMutation
        self.storefront = storefront
        self.lastError = lastError
    }
}

public struct AppleMusicItemRef: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var kind: AppleMusicItemKind
    public var source: MusicSourceKind
    public var titleSnapshot: String
    public var artistSnapshot: String
    public var albumSnapshot: String
    public var artworkURLSnapshot: String
    public var durationSnapshot: Double?
    public var storefront: String

    public init(
        id: String,
        kind: AppleMusicItemKind,
        source: MusicSourceKind,
        titleSnapshot: String,
        artistSnapshot: String = "",
        albumSnapshot: String = "",
        artworkURLSnapshot: String = "",
        durationSnapshot: Double? = nil,
        storefront: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.source = source
        self.titleSnapshot = titleSnapshot
        self.artistSnapshot = artistSnapshot
        self.albumSnapshot = albumSnapshot
        self.artworkURLSnapshot = artworkURLSnapshot
        self.durationSnapshot = durationSnapshot
        self.storefront = storefront
    }

    public var encodedSource: String {
        "\(source.rawValue):\(kind.rawValue):\(id)"
    }

    public static func decodeSource(_ raw: String) -> AppleMusicItemRef? {
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3 else { return nil }
        let source = MusicSourceKind.parse(parts[0])
        guard source != .hypePattern,
              let kind = AppleMusicItemKind.parse(parts[1]) else { return nil }
        let id = parts.dropFirst(2).joined(separator: ":")
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return AppleMusicItemRef(id: id, kind: kind, source: source, titleSnapshot: id)
    }
}

public struct AppleMusicSearchRequest: Codable, Sendable, Equatable {
    public var term: String
    public var scope: AppleMusicSearchScope
    public var itemKinds: [AppleMusicItemKind]
    public var limit: Int

    public init(
        term: String,
        scope: AppleMusicSearchScope = .catalog,
        itemKinds: [AppleMusicItemKind] = [.song, .album, .artist, .playlist, .station],
        limit: Int = 10
    ) {
        self.term = term
        self.scope = scope
        self.itemKinds = itemKinds.isEmpty ? [.song, .album, .artist, .playlist, .station] : itemKinds
        self.limit = min(50, max(1, limit))
    }
}

public struct AppleMusicQueueSpec: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var items: [AppleMusicItemRef]
    public var shuffle: Bool
    public var repeatMode: String

    public init(
        id: UUID = UUID(),
        name: String,
        items: [AppleMusicItemRef] = [],
        shuffle: Bool = false,
        repeatMode: String = "none"
    ) {
        self.id = id
        self.name = name
        self.items = items
        self.shuffle = shuffle
        self.repeatMode = repeatMode
    }
}

public enum AppleMusicProviderError: Error, LocalizedError, Sendable, Equatable {
    case unavailable
    case notAuthorized
    case notConfigured
    case unsupported(String)
    case requestFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Apple Music is not available on this system."
        case .notAuthorized:
            return "Apple Music access is not authorized."
        case .notConfigured:
            return "Apple Music is disabled for this stack or in preferences."
        case .unsupported(let message):
            return message
        case .requestFailed(let message):
            return message
        }
    }
}

public protocol AppleMusicProviding: Sendable {
    var isAvailable: Bool { get }
    func authorizationStatus() async -> AppleMusicAuthorizationState
    func requestAuthorization() async -> AppleMusicAuthorizationState
    func capabilities() async -> AppleMusicCapabilities
    func search(_ request: AppleMusicSearchRequest) async throws -> [AppleMusicItemRef]
    func play(_ item: AppleMusicItemRef, engine: AppleMusicPlaybackEngine) async throws
    func playQueue(_ queue: AppleMusicQueueSpec, engine: AppleMusicPlaybackEngine) async throws
    func pause(engine: AppleMusicPlaybackEngine) async
    func resume(engine: AppleMusicPlaybackEngine) async throws
    func stop(engine: AppleMusicPlaybackEngine) async
    func skipToNext(engine: AppleMusicPlaybackEngine) async throws
    func skipToPrevious(engine: AppleMusicPlaybackEngine) async throws
    func currentPlaybackState(engine: AppleMusicPlaybackEngine) async -> String
    func rawAPIRequest(path: String, method: String, body: Data?) async throws -> Data
    func createPlaylist(name: String, description: String?, items: [AppleMusicItemRef]) async throws -> AppleMusicItemRef
    func add(_ item: AppleMusicItemRef, toPlaylist playlist: AppleMusicItemRef?) async throws
}

public struct StubAppleMusicProvider: AppleMusicProviding {
    public init() {}
    public var isAvailable: Bool { false }
    public func authorizationStatus() async -> AppleMusicAuthorizationState { .unavailable }
    public func requestAuthorization() async -> AppleMusicAuthorizationState { .unavailable }
    public func capabilities() async -> AppleMusicCapabilities { AppleMusicCapabilities() }
    public func search(_ request: AppleMusicSearchRequest) async throws -> [AppleMusicItemRef] { throw AppleMusicProviderError.unavailable }
    public func play(_ item: AppleMusicItemRef, engine: AppleMusicPlaybackEngine) async throws { throw AppleMusicProviderError.unavailable }
    public func playQueue(_ queue: AppleMusicQueueSpec, engine: AppleMusicPlaybackEngine) async throws { throw AppleMusicProviderError.unavailable }
    public func pause(engine: AppleMusicPlaybackEngine) async {}
    public func resume(engine: AppleMusicPlaybackEngine) async throws { throw AppleMusicProviderError.unavailable }
    public func stop(engine: AppleMusicPlaybackEngine) async {}
    public func skipToNext(engine: AppleMusicPlaybackEngine) async throws { throw AppleMusicProviderError.unavailable }
    public func skipToPrevious(engine: AppleMusicPlaybackEngine) async throws { throw AppleMusicProviderError.unavailable }
    public func currentPlaybackState(engine: AppleMusicPlaybackEngine) async -> String { "unavailable" }
    public func rawAPIRequest(path: String, method: String, body: Data?) async throws -> Data { throw AppleMusicProviderError.unavailable }
    public func createPlaylist(name: String, description: String?, items: [AppleMusicItemRef]) async throws -> AppleMusicItemRef { throw AppleMusicProviderError.unavailable }
    public func add(_ item: AppleMusicItemRef, toPlaylist playlist: AppleMusicItemRef?) async throws { throw AppleMusicProviderError.unavailable }
}

public enum AppleMusicConfiguration {
    public static let enabledKey = "hype.appleMusic.enabled"
    public static let playbackEngineKey = "hype.appleMusic.playbackEngine"
    public static let defaultPlaybackEngine = AppleMusicPlaybackEngine.application
}

public enum AppleMusicProviderFactory {
    public static func makeDefault() -> any AppleMusicProviding {
        #if canImport(MusicKit)
        return MusicKitAppleMusicProvider.shared
        #else
        return StubAppleMusicProvider()
        #endif
    }
}

#if canImport(MusicKit)
import MusicKit

public final class MusicKitAppleMusicProvider: AppleMusicProviding, @unchecked Sendable {
    public static let shared = MusicKitAppleMusicProvider()

    private init() {}

    public var isAvailable: Bool { true }

    public func authorizationStatus() async -> AppleMusicAuthorizationState {
        mapAuthorization(MusicAuthorization.currentStatus)
    }

    public func requestAuthorization() async -> AppleMusicAuthorizationState {
        mapAuthorization(await MusicAuthorization.request())
    }

    public func capabilities() async -> AppleMusicCapabilities {
        do {
            let subscription = try await MusicSubscription.current
            return AppleMusicCapabilities(
                authorization: mapAuthorization(MusicAuthorization.currentStatus),
                canPlayCatalogContent: subscription.canPlayCatalogContent,
                canBecomeSubscriber: subscription.canBecomeSubscriber,
                hasCloudLibraryEnabled: subscription.hasCloudLibraryEnabled,
                // MusicLibrary.add/createPlaylist are unavailable on macOS; use raw Apple Music API where allowed.
                supportsLibraryMutation: false,
                storefront: ""
            )
        } catch {
            return AppleMusicCapabilities(
                authorization: mapAuthorization(MusicAuthorization.currentStatus),
                lastError: error.localizedDescription
            )
        }
    }

    public func search(_ request: AppleMusicSearchRequest) async throws -> [AppleMusicItemRef] {
        guard await authorizationStatus() == .authorized else {
            throw AppleMusicProviderError.notAuthorized
        }
        switch request.scope {
        case .catalog:
            return try await searchCatalog(request)
        case .library:
            return try await searchLibrary(request)
        }
    }

    public func play(_ item: AppleMusicItemRef, engine: AppleMusicPlaybackEngine) async throws {
        guard await authorizationStatus() == .authorized else {
            throw AppleMusicProviderError.notAuthorized
        }
        try await setQueue([item], engine: engine)
        try await player(for: engine).play()
    }

    public func playQueue(_ queue: AppleMusicQueueSpec, engine: AppleMusicPlaybackEngine) async throws {
        guard await authorizationStatus() == .authorized else {
            throw AppleMusicProviderError.notAuthorized
        }
        try await setQueue(queue.items, engine: engine)
        try await player(for: engine).play()
    }

    public func pause(engine: AppleMusicPlaybackEngine) async {
        player(for: engine).pause()
    }

    public func resume(engine: AppleMusicPlaybackEngine) async throws {
        try await player(for: engine).play()
    }

    public func stop(engine: AppleMusicPlaybackEngine) async {
        player(for: engine).stop()
    }

    public func skipToNext(engine: AppleMusicPlaybackEngine) async throws {
        try await player(for: engine).skipToNextEntry()
    }

    public func skipToPrevious(engine: AppleMusicPlaybackEngine) async throws {
        try await player(for: engine).skipToPreviousEntry()
    }

    public func currentPlaybackState(engine: AppleMusicPlaybackEngine) async -> String {
        switch player(for: engine).state.playbackStatus {
        case .playing: return "playing"
        case .paused: return "paused"
        case .stopped: return "stopped"
        case .interrupted: return "interrupted"
        case .seekingForward: return "seekingForward"
        case .seekingBackward: return "seekingBackward"
        @unknown default: return "unknown"
        }
    }

    public func rawAPIRequest(path: String, method: String, body: Data?) async throws -> Data {
        guard await authorizationStatus() == .authorized else {
            throw AppleMusicProviderError.notAuthorized
        }
        let absoluteURL: URL?
        if let url = URL(string: path), url.scheme != nil {
            absoluteURL = url
        } else {
            let normalized = path.hasPrefix("/") ? path : "/\(path)"
            absoluteURL = URL(string: "https://api.music.apple.com\(normalized)")
        }
        guard let url = absoluteURL else {
            throw AppleMusicProviderError.requestFailed("Invalid Apple Music API path: \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method.isEmpty ? "GET" : method.uppercased()
        request.httpBody = body
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let response = try await MusicDataRequest(urlRequest: request).response()
        return response.data
    }

    public func createPlaylist(name: String, description: String?, items: [AppleMusicItemRef]) async throws -> AppleMusicItemRef {
        throw AppleMusicProviderError.unsupported("Creating Apple Music playlists through MusicKit is unavailable in the macOS MusicKit framework. Use appleMusic API request for permitted Apple Music API playlist endpoints.")
    }

    public func add(_ item: AppleMusicItemRef, toPlaylist playlist: AppleMusicItemRef?) async throws {
        throw AppleMusicProviderError.unsupported("Adding Apple Music items to a library or playlist through MusicKit is unavailable in the macOS MusicKit framework. Use appleMusic API request for permitted Apple Music API mutation endpoints.")
    }

    private func searchCatalog(_ request: AppleMusicSearchRequest) async throws -> [AppleMusicItemRef] {
        var catalogRequest = MusicCatalogSearchRequest(term: request.term, types: catalogSearchTypes(for: request.itemKinds))
        catalogRequest.limit = request.limit
        let response = try await catalogRequest.response()
        var refs: [AppleMusicItemRef] = []
        if request.itemKinds.contains(.song) { refs += response.songs.map { ref($0, source: .appleMusicCatalog) } }
        if request.itemKinds.contains(.album) { refs += response.albums.map { ref($0, source: .appleMusicCatalog) } }
        if request.itemKinds.contains(.artist) { refs += response.artists.map { ref($0, source: .appleMusicCatalog) } }
        if request.itemKinds.contains(.playlist) { refs += response.playlists.map { ref($0, source: .appleMusicCatalog) } }
        if request.itemKinds.contains(.station) { refs += response.stations.map { ref($0, source: .appleMusicStation) } }
        if request.itemKinds.contains(.musicVideo) { refs += response.musicVideos.map { ref($0, source: .appleMusicCatalog) } }
        return Array(refs.prefix(request.limit))
    }

    private func searchLibrary(_ request: AppleMusicSearchRequest) async throws -> [AppleMusicItemRef] {
        var libraryRequest = MusicLibrarySearchRequest(term: request.term, types: librarySearchTypes(for: request.itemKinds))
        libraryRequest.limit = request.limit
        let response = try await libraryRequest.response()
        var refs: [AppleMusicItemRef] = []
        if request.itemKinds.contains(.song) { refs += response.songs.map { ref($0, source: .appleMusicLibrary) } }
        if request.itemKinds.contains(.album) { refs += response.albums.map { ref($0, source: .appleMusicLibrary) } }
        if request.itemKinds.contains(.playlist) { refs += response.playlists.map { ref($0, source: .appleMusicLibrary) } }
        return Array(refs.prefix(request.limit))
    }

    private func setQueue(_ items: [AppleMusicItemRef], engine: AppleMusicPlaybackEngine) async throws {
        guard let first = items.first else {
            throw AppleMusicProviderError.requestFailed("Apple Music queue is empty.")
        }
        let player = player(for: engine)
        switch first.kind {
        case .song:
            if first.source == .appleMusicLibrary,
               let item = try await librarySong(first.id) {
                player.queue = [item]
            } else if let item = try await catalogSong(first.id) {
                player.queue = [item]
            } else {
                throw AppleMusicProviderError.requestFailed("Apple Music song '\(first.id)' was not found.")
            }
        case .album:
            if first.source == .appleMusicLibrary,
               let item = try await libraryAlbum(first.id) {
                player.queue = [item]
            } else if let item = try await catalogAlbum(first.id) {
                player.queue = [item]
            } else {
                throw AppleMusicProviderError.requestFailed("Apple Music album '\(first.id)' was not found.")
            }
        case .playlist:
            if first.source == .appleMusicLibrary,
               let item = try await libraryPlaylist(first.id) {
                player.queue = [item]
            } else if let item = try await catalogPlaylist(first.id) {
                player.queue = [item]
            } else {
                throw AppleMusicProviderError.requestFailed("Apple Music playlist '\(first.id)' was not found.")
            }
        case .station:
            if let item = try await catalogStation(first.id) {
                player.queue = [item]
            } else {
                throw AppleMusicProviderError.requestFailed("Apple Music station '\(first.id)' was not found.")
            }
        case .artist:
            throw AppleMusicProviderError.unsupported("Apple Music artist references are searchable but not directly playable. Select an album, song, playlist, or station.")
        case .musicVideo:
            throw AppleMusicProviderError.unsupported("Apple Music video references are searchable but not playable through Hype's music controls.")
        }
    }

    private func player(for engine: AppleMusicPlaybackEngine) -> ApplicationMusicPlayer {
        switch engine {
        case .application:
            return ApplicationMusicPlayer.shared
        case .system:
            // SystemMusicPlayer and ApplicationMusicPlayer share the MusicPlayer protocol, but
            // Hype currently uses ApplicationMusicPlayer for deterministic queue ownership on macOS.
            return ApplicationMusicPlayer.shared
        }
    }

    private func catalogSearchTypes(for kinds: [AppleMusicItemKind]) -> [any MusicCatalogSearchable.Type] {
        var types: [any MusicCatalogSearchable.Type] = []
        for kind in kinds {
            switch kind {
            case .song: types.append(Song.self)
            case .album: types.append(Album.self)
            case .artist: types.append(Artist.self)
            case .playlist: types.append(Playlist.self)
            case .station: types.append(Station.self)
            case .musicVideo: types.append(MusicVideo.self)
            }
        }
        return types.isEmpty ? [Song.self, Album.self, Artist.self, Playlist.self, Station.self] : types
    }

    private func librarySearchTypes(for kinds: [AppleMusicItemKind]) -> [any MusicLibrarySearchable.Type] {
        var types: [any MusicLibrarySearchable.Type] = []
        for kind in kinds {
            switch kind {
            case .song: types.append(Song.self)
            case .album: types.append(Album.self)
            case .playlist: types.append(Playlist.self)
            case .artist, .station, .musicVideo:
                break
            }
        }
        return types.isEmpty ? [Song.self, Album.self, Playlist.self] : types
    }

    private func catalogSong(_ id: String) async throws -> Song? {
        try await MusicCatalogResourceRequest<Song>(matching: \Song.FilterType.id, equalTo: MusicItemID(id)).response().items.first
    }

    private func catalogAlbum(_ id: String) async throws -> Album? {
        try await MusicCatalogResourceRequest<Album>(matching: \Album.FilterType.id, equalTo: MusicItemID(id)).response().items.first
    }

    private func catalogPlaylist(_ id: String) async throws -> Playlist? {
        try await MusicCatalogResourceRequest<Playlist>(matching: \Playlist.FilterType.id, equalTo: MusicItemID(id)).response().items.first
    }

    private func catalogStation(_ id: String) async throws -> Station? {
        try await MusicCatalogResourceRequest<Station>(matching: \Station.FilterType.id, equalTo: MusicItemID(id)).response().items.first
    }

    private func librarySong(_ id: String) async throws -> Song? {
        var request = MusicLibraryRequest<Song>()
        request.filter(matching: \Song.LibraryFilter.id, equalTo: MusicItemID(id))
        return try await request.response().items.first
    }

    private func libraryAlbum(_ id: String) async throws -> Album? {
        var request = MusicLibraryRequest<Album>()
        request.filter(matching: \Album.LibraryFilter.id, equalTo: MusicItemID(id))
        return try await request.response().items.first
    }

    private func libraryPlaylist(_ id: String) async throws -> Playlist? {
        var request = MusicLibraryRequest<Playlist>()
        request.filter(matching: \Playlist.LibraryFilter.id, equalTo: MusicItemID(id))
        return try await request.response().items.first
    }

    private func ref(_ song: Song, source: MusicSourceKind) -> AppleMusicItemRef {
        AppleMusicItemRef(
            id: song.id.rawValue,
            kind: .song,
            source: source,
            titleSnapshot: song.title,
            artistSnapshot: song.artistName,
            albumSnapshot: song.albumTitle ?? "",
            artworkURLSnapshot: song.artwork?.url(width: 300, height: 300)?.absoluteString ?? "",
            durationSnapshot: song.duration
        )
    }

    private func ref(_ album: Album, source: MusicSourceKind) -> AppleMusicItemRef {
        AppleMusicItemRef(
            id: album.id.rawValue,
            kind: .album,
            source: source,
            titleSnapshot: album.title,
            artistSnapshot: album.artistName,
            artworkURLSnapshot: album.artwork?.url(width: 300, height: 300)?.absoluteString ?? ""
        )
    }

    private func ref(_ artist: Artist, source: MusicSourceKind) -> AppleMusicItemRef {
        AppleMusicItemRef(
            id: artist.id.rawValue,
            kind: .artist,
            source: source,
            titleSnapshot: artist.name,
            artworkURLSnapshot: artist.artwork?.url(width: 300, height: 300)?.absoluteString ?? ""
        )
    }

    private func ref(_ playlist: Playlist, source: MusicSourceKind) -> AppleMusicItemRef {
        AppleMusicItemRef(
            id: playlist.id.rawValue,
            kind: .playlist,
            source: source == .appleMusicLibrary ? .appleMusicLibrary : .appleMusicPlaylist,
            titleSnapshot: playlist.name,
            artistSnapshot: playlist.curatorName ?? "",
            artworkURLSnapshot: playlist.artwork?.url(width: 300, height: 300)?.absoluteString ?? ""
        )
    }

    private func ref(_ station: Station, source: MusicSourceKind) -> AppleMusicItemRef {
        AppleMusicItemRef(
            id: station.id.rawValue,
            kind: .station,
            source: .appleMusicStation,
            titleSnapshot: station.name,
            artworkURLSnapshot: station.artwork?.url(width: 300, height: 300)?.absoluteString ?? ""
        )
    }

    private func ref(_ video: MusicVideo, source: MusicSourceKind) -> AppleMusicItemRef {
        AppleMusicItemRef(
            id: video.id.rawValue,
            kind: .musicVideo,
            source: source,
            titleSnapshot: video.title,
            artistSnapshot: video.artistName,
            artworkURLSnapshot: video.artwork?.url(width: 300, height: 300)?.absoluteString ?? "",
            durationSnapshot: video.duration
        )
    }

    private func mapAuthorization(_ status: MusicAuthorization.Status) -> AppleMusicAuthorizationState {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        case .authorized: return .authorized
        @unknown default: return .unavailable
        }
    }
}
#endif
