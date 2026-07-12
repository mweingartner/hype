import AppKit

/// Persists and restores lightweight app-launch state — the last opened
/// stack file and its window frame — across process launches via
/// `UserDefaults`.
///
/// All window-frame logic here is pure value-type geometry (no `NSWindow`
/// or `NSScreen` access): callers pass in visible-screen rects rather than
/// live screens, which keeps this type headless-testable exactly like
/// today (see `Tests/HypeTests/AppLaunchStateTests.swift`).
struct AppLaunchState {
    enum Key {
        static let lastWindowX = "lastWindowX"
        static let lastWindowY = "lastWindowY"
        static let lastWindowWidth = "lastWindowWidth"
        static let lastWindowHeight = "lastWindowHeight"
        static let lastOpenedFilePath = "lastOpenedFilePath"
        /// `[String: [Double]]` — a stack file's canonical path
        /// (`frameKey(forFileAt:)`) to `[x, y, width, height,
        /// lastUsedEpochSeconds]`. Keeps one entry per stack so reopening
        /// stack A never applies stack B's frame. The legacy scalar keys
        /// above remain the untitled/global fallback and the
        /// backward-compatible read for stacks saved before this key
        /// existed.
        static let windowFramesByPath = "lastWindowFrameByPath"
    }

    /// Maximum number of per-stack frame entries retained under
    /// `Key.windowFramesByPath`. Once a save would exceed this cap, the
    /// least-recently-used entries are evicted first, so the stored
    /// dictionary stays small and bounded no matter how many different
    /// stacks a user has ever opened.
    static let maxStoredFrameEntries = 32

    /// Minimum width/height, in points, a stored or restored frame must
    /// exceed to be treated as a legitimate remembered size. Filters out
    /// degenerate/garbage values without imposing a real minimum window
    /// size anywhere else in the app.
    static let minimumRememberedDimension: Double = 100

    private let defaults: UserDefaults
    private let fileManager: FileManager

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
    }

    var lastOpenedFileURL: URL? {
        guard let path = defaults.string(forKey: Key.lastOpenedFilePath),
              !path.isEmpty,
              fileManager.fileExists(atPath: path) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    /// The canonical identity used to key a stack's per-path window frame:
    /// the standardized, symlink-resolved absolute path. Save and lookup
    /// always go through this so the same file reached via different
    /// routes (a symlink, a `..`-relative path) maps to the same entry.
    static func frameKey(forFileAt url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// The legacy global window frame (the four scalar `UserDefaults`
    /// keys), validated for finiteness and minimum size. This is both the
    /// storage for untitled (no file) windows and the backward-compatible
    /// fallback used when a stack has no per-path entry yet.
    var storedWindowFrame: NSRect? {
        let x = defaults.double(forKey: Key.lastWindowX)
        let y = defaults.double(forKey: Key.lastWindowY)
        let width = defaults.double(forKey: Key.lastWindowWidth)
        let height = defaults.double(forKey: Key.lastWindowHeight)
        guard Self.isValidRememberedFrame(x: x, y: y, width: width, height: height) else {
            return nil
        }
        return NSRect(x: x, y: y, width: width, height: height)
    }

    /// The saved window frame for the stack at `url`. Falls back to the
    /// legacy global frame when `url` is `nil` (untitled) or when no
    /// per-path entry has ever been recorded for it. A per-path entry
    /// that IS present but malformed (wrong shape, wrong arity, or a
    /// non-finite value) returns `nil` directly — it is never silently
    /// replaced by the legacy frame, which could belong to a different
    /// stack entirely. Performs no writes.
    func storedWindowFrame(forFileAt url: URL?) -> NSRect? {
        guard let url else { return storedWindowFrame }
        guard let entry = perPathFrames[Self.frameKey(forFileAt: url)] else {
            return storedWindowFrame
        }
        return Self.validatedFrame(from: entry)
    }

    /// The frame that should be applied at launch for the stack at `url`
    /// (or the untitled fallback when `url == nil`): the stored frame,
    /// clamped to the currently visible screens. Read-only — never
    /// mutates `UserDefaults`. Returns `nil` when there is no valid stored
    /// frame, or no screen it can be clamped onto.
    func restorableWindowFrame(forFileAt url: URL?, visibleScreenFrames: [NSRect]) -> NSRect? {
        guard let frame = storedWindowFrame(forFileAt: url) else { return nil }
        return Self.clamped(frame, toVisibleScreenFrames: visibleScreenFrames)
    }

    /// Fits `frame` fully inside one of `screens` (`NSScreen.visibleFrame`
    /// rects in the global bottom-left coordinate space; negative origins
    /// are expected for displays above/left of the main screen), preserving
    /// size whenever possible:
    ///
    /// 1. A non-finite frame, or one with width/height at or below
    ///    `minimumRememberedDimension`, is rejected (`nil`).
    /// 2. Screens with non-positive width/height are dropped before any
    ///    screen is chosen; if none remain, this is treated the same as an
    ///    empty screen list (`nil`).
    /// 3. A frame already fully contained in some screen is returned
    ///    unchanged.
    /// 4. Otherwise the screen with the largest intersection area is the
    ///    clamp target; if the frame intersects no screen at all
    ///    (disconnected display), the first screen is used instead.
    /// 5. The frame is shrunk only as needed to fit the target screen, then
    ///    translated fully inside it.
    static func clamped(_ frame: NSRect, toVisibleScreenFrames screens: [NSRect]) -> NSRect? {
        guard isValidRememberedFrame(x: frame.origin.x, y: frame.origin.y, width: frame.width, height: frame.height) else {
            return nil
        }

        // A screen with non-positive width/height can't host a window and
        // must never become the clamp target (Security condition: drop
        // degenerate screen rects before choosing one).
        let validScreens = screens.filter { $0.width > 0 && $0.height > 0 }
        guard !validScreens.isEmpty else { return nil }

        if validScreens.contains(where: { $0.contains(frame) }) {
            return frame
        }

        let bestScreen = validScreens.max { intersectionArea($0, frame) < intersectionArea($1, frame) } ?? validScreens[0]
        let targetScreen = intersectionArea(bestScreen, frame) > 0 ? bestScreen : validScreens[0]

        let width = min(frame.width, targetScreen.width)
        let height = min(frame.height, targetScreen.height)
        let x = min(max(frame.minX, targetScreen.minX), targetScreen.maxX - width)
        let y = min(max(frame.minY, targetScreen.minY), targetScreen.maxY - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    /// Always writes the four legacy scalar keys (the untitled/global
    /// fallback and the backward-compatible read). When `url` is non-nil,
    /// also upserts a per-path entry keyed by `frameKey(forFileAt:)` with
    /// `now` as its `lastUsed` timestamp, then prunes the least-recently-
    /// used entries until at most `maxStoredFrameEntries` remain.
    func save(windowFrame: NSRect, forFileAt url: URL?, now: Date = Date()) {
        defaults.set(windowFrame.origin.x, forKey: Key.lastWindowX)
        defaults.set(windowFrame.origin.y, forKey: Key.lastWindowY)
        defaults.set(windowFrame.size.width, forKey: Key.lastWindowWidth)
        defaults.set(windowFrame.size.height, forKey: Key.lastWindowHeight)

        guard let url else { return }

        var entries = perPathFrames
        entries[Self.frameKey(forFileAt: url)] = [
            windowFrame.origin.x,
            windowFrame.origin.y,
            windowFrame.size.width,
            windowFrame.size.height,
            now.timeIntervalSince1970,
        ]

        if entries.count > Self.maxStoredFrameEntries {
            let leastRecentlyUsedFirst = entries.keys.sorted {
                Self.lastUsed(of: entries[$0]) < Self.lastUsed(of: entries[$1])
            }
            for staleKey in leastRecentlyUsedFirst.prefix(entries.count - Self.maxStoredFrameEntries) {
                entries.removeValue(forKey: staleKey)
            }
        }

        defaults.set(entries, forKey: Key.windowFramesByPath)
    }

    func save(fileURL: URL) {
        defaults.set(fileURL.path, forKey: Key.lastOpenedFilePath)
    }

    func clearLastOpenedFile() {
        defaults.removeObject(forKey: Key.lastOpenedFilePath)
    }

    // MARK: - Private

    /// Raw per-path frame entries decoded from `UserDefaults`, tolerating
    /// any malformed shape. Decoding uses `as?` only at every level — the
    /// top-level dictionary, each entry's array, each element — never a
    /// forced cast:
    ///
    /// - When the stored value under `Key.windowFramesByPath` is not
    ///   itself a `[String: Any]` (or is absent), there is no per-path
    ///   data at all: every path's lookup falls back to the legacy global
    ///   frame, the same as a stack that has never been per-path-saved.
    /// - When the top level DOES decode, but one specific path's value is
    ///   not a numeric array of the original arity, that path is kept
    ///   present with an empty array — recognizably invalid — so its
    ///   lookup fails outright rather than silently borrowing the legacy
    ///   frame (per-stack identity: a corrupted entry for stack A must
    ///   never resolve to stack B's, or the untitled fallback's, frame).
    private var perPathFrames: [String: [Double]] {
        guard let raw = defaults.object(forKey: Key.windowFramesByPath) as? [String: Any] else {
            return [:]
        }
        var frames: [String: [Double]] = [:]
        for (path, value) in raw {
            guard let rawComponents = value as? [Any] else {
                frames[path] = []
                continue
            }
            let components = rawComponents.compactMap { $0 as? Double }
            frames[path] = components.count == rawComponents.count ? components : []
        }
        return frames
    }

    /// Validates a decoded per-path entry: exactly five finite elements
    /// (`x, y, width, height, lastUsed`) with width/height greater than
    /// `minimumRememberedDimension`. Any shape or value mismatch — wrong
    /// arity, a non-finite coordinate, or a non-finite `lastUsed`
    /// timestamp — returns `nil`; the read path never crashes on
    /// malformed stored data.
    private static func validatedFrame(from components: [Double]) -> NSRect? {
        guard components.count == 5 else { return nil }
        let (x, y, width, height, lastUsed) = (components[0], components[1], components[2], components[3], components[4])
        guard lastUsed.isFinite, isValidRememberedFrame(x: x, y: y, width: width, height: height) else {
            return nil
        }
        return NSRect(x: x, y: y, width: width, height: height)
    }

    /// Shared finiteness/size validation used by both the legacy 4-scalar
    /// read path and the per-path 5-element read path, so "what counts as
    /// a legitimate remembered frame" can never drift between them.
    private static func isValidRememberedFrame(x: Double, y: Double, width: Double, height: Double) -> Bool {
        x.isFinite && y.isFinite && width.isFinite && height.isFinite
            && width > minimumRememberedDimension
            && height > minimumRememberedDimension
    }

    /// The `lastUsed` component of a decoded entry, or the smallest
    /// possible value when the entry is malformed or its timestamp isn't
    /// finite. Treating a corrupted timestamp as "oldest" makes it the
    /// first candidate for LRU eviction instead of destabilizing the
    /// eviction order (a NaN `lastUsed` must not break the 32-entry cap).
    private static func lastUsed(of entry: [Double]?) -> Double {
        guard let entry, entry.count == 5, entry[4].isFinite else { return -Double.greatestFiniteMagnitude }
        return entry[4]
    }

    /// The overlap area between two rects, or `0` when they don't
    /// intersect at all.
    private static func intersectionArea(_ lhs: NSRect, _ rhs: NSRect) -> Double {
        let intersection = lhs.intersection(rhs)
        return Double(intersection.width * intersection.height)
    }
}
