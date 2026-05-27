import Foundation

public enum HypeDebugDirectory {
    public static func socketDirectory() throws -> URL {
        let fm = FileManager.default

        if let raw = ProcessInfo.processInfo.environment["HYPE_DEBUG_SOCKET_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            let url = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            return url
        }

        let repoRoot = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
        let repoLocal = repoRoot
            .appendingPathComponent(".hype", isDirectory: true)
            .appendingPathComponent("debug", isDirectory: true)
            .appendingPathComponent("sockets", isDirectory: true)
        do {
            try fm.createDirectory(at: repoLocal, withIntermediateDirectories: true)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: repoLocal.path)
            return repoLocal
        } catch {}

        let home = NSHomeDirectory()
        let appSupport = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/com.hype.app/debug/sockets", isDirectory: true)
        try fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: appSupport.path)
        return appSupport
    }
}