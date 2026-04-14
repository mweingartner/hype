import AppKit

struct AppLaunchState {
    enum Key {
        static let lastWindowX = "lastWindowX"
        static let lastWindowY = "lastWindowY"
        static let lastWindowWidth = "lastWindowWidth"
        static let lastWindowHeight = "lastWindowHeight"
        static let lastOpenedFilePath = "lastOpenedFilePath"
    }

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

    var storedWindowFrame: NSRect? {
        let width = defaults.double(forKey: Key.lastWindowWidth)
        let height = defaults.double(forKey: Key.lastWindowHeight)
        guard width > 100, height > 100 else { return nil }
        let x = defaults.double(forKey: Key.lastWindowX)
        let y = defaults.double(forKey: Key.lastWindowY)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    func visibleWindowFrame(using visibleScreenFrames: [NSRect]) -> NSRect? {
        guard let frame = storedWindowFrame else { return nil }
        guard visibleScreenFrames.contains(where: { $0.intersects(frame) }) else { return nil }
        return frame
    }

    func save(windowFrame: NSRect) {
        defaults.set(windowFrame.origin.x, forKey: Key.lastWindowX)
        defaults.set(windowFrame.origin.y, forKey: Key.lastWindowY)
        defaults.set(windowFrame.size.width, forKey: Key.lastWindowWidth)
        defaults.set(windowFrame.size.height, forKey: Key.lastWindowHeight)
    }

    func save(fileURL: URL) {
        defaults.set(fileURL.path, forKey: Key.lastOpenedFilePath)
    }

    func clearLastOpenedFile() {
        defaults.removeObject(forKey: Key.lastOpenedFilePath)
    }
}
