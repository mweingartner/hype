import CStackImport
import Darwin
import Foundation

public struct StackImportLibraryStatus: Sendable, Equatable {
    public var isAvailable: Bool
    public var version: String?
    public var frameworkPath: String
    public var installCommand: String
    public var detail: String?

    public var aboutLine: String {
        if let version, isAvailable {
            return "StackImport library: \(version) (\(frameworkPath))"
        }
        if let version {
            return "StackImport library: unavailable (found \(version)). Install or update with `brew install stackimport`."
        }
        return "StackImport library: not found. Install with `brew install stackimport`."
    }
}

public enum StackImportRuntime {
    public static let frameworkPath = "/opt/homebrew/opt/stackimport/Frameworks/StackImport.framework"
    public static let installCommand = "brew install stackimport"

    public static var status: StackImportLibraryStatus {
        libraryStatus()
    }

    public static var isAvailable: Bool {
        library != nil
    }

    static func requireAvailable() throws -> StackImportLibrary {
        guard case .available(let library) = loadResult else {
            let status = libraryStatus()
            throw HyperCardImportError.stackimportUnavailable(status.detail ?? status.aboutLine)
        }
        return library
    }

    private static var library: StackImportLibrary? {
        if case .available(let library) = loadResult {
            return library
        }
        return nil
    }

    private static let loadResult: StackImportLoadResult = StackImportLibrary.load()

    private static func libraryStatus() -> StackImportLibraryStatus {
        if case .available(let library) = loadResult {
            return StackImportLibraryStatus(
                isAvailable: true,
                version: library.version,
                frameworkPath: library.frameworkPath,
                installCommand: installCommand,
                detail: nil
            )
        }

        let detail: String
        if case .unavailable(let unavailableDetail) = loadResult {
            detail = unavailableDetail
        } else {
            detail = "StackImport.framework was not found at \(frameworkPath). Install it with `\(installCommand)`."
        }
        return StackImportLibraryStatus(
            isAvailable: false,
            version: StackImportLibrary.frameworkVersion(at: frameworkPath),
            frameworkPath: frameworkPath,
            installCommand: installCommand,
            detail: detail
        )
    }
}

private enum StackImportLoadResult {
    case available(StackImportLibrary)
    case unavailable(String)
}

final class StackImportLibrary: @unchecked Sendable {
    private static let expectedVersionPacked =
        (UInt32(STACKIMPORT_VERSION_MAJOR) << 16) |
        (UInt32(STACKIMPORT_VERSION_MINOR) << 8) |
        UInt32(STACKIMPORT_VERSION_PATCH)
    private static let expectedVersionString =
        "\(STACKIMPORT_VERSION_MAJOR).\(STACKIMPORT_VERSION_MINOR).\(STACKIMPORT_VERSION_PATCH)"

    typealias ApiVersionFn = @convention(c) () -> UInt32
    typealias VersionStringFn = @convention(c) () -> UnsafePointer<CChar>?
    typealias VersionPackedFn = @convention(c) () -> UInt32
    typealias StatusStringFn = @convention(c) (stackimport_status) -> UnsafePointer<CChar>?
    typealias PlatformInitFn = @convention(c) (UnsafeMutablePointer<stackimport_platform>?) -> Void
    typealias ImportOptionsInitFn = @convention(c) (UnsafeMutablePointer<stackimport_import_options>?) -> Void
    typealias ContextCreateWithPlatformFn = @convention(c) (UnsafePointer<stackimport_platform>?, UnsafeMutablePointer<OpaquePointer?>?) -> stackimport_status
    typealias ContextDestroyFn = @convention(c) (OpaquePointer?) -> Void
    typealias ImportFn = @convention(c) (OpaquePointer?, UnsafePointer<stackimport_import_options>?) -> stackimport_status
    typealias SndToWavFn = @convention(c) (UnsafeRawPointer?, Int, UnsafeMutableRawPointer?, Int, UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> Int

    let version: String
    let versionPacked: UInt32
    let apiVersion: UInt32
    let frameworkPath: String
    let statusString: StatusStringFn
    let platformInit: PlatformInitFn
    let importOptionsInit: ImportOptionsInitFn
    let contextCreateWithPlatform: ContextCreateWithPlatformFn
    let contextDestroy: ContextDestroyFn
    let importStack: ImportFn
    let sndToWav: SndToWavFn

    private let handle: UnsafeMutableRawPointer

    private init(
        handle: UnsafeMutableRawPointer,
        version: String,
        versionPacked: UInt32,
        apiVersion: UInt32,
        frameworkPath: String,
        statusString: @escaping StatusStringFn,
        platformInit: @escaping PlatformInitFn,
        importOptionsInit: @escaping ImportOptionsInitFn,
        contextCreateWithPlatform: @escaping ContextCreateWithPlatformFn,
        contextDestroy: @escaping ContextDestroyFn,
        importStack: @escaping ImportFn,
        sndToWav: @escaping SndToWavFn
    ) {
        self.handle = handle
        self.version = version
        self.versionPacked = versionPacked
        self.apiVersion = apiVersion
        self.frameworkPath = frameworkPath
        self.statusString = statusString
        self.platformInit = platformInit
        self.importOptionsInit = importOptionsInit
        self.contextCreateWithPlatform = contextCreateWithPlatform
        self.contextDestroy = contextDestroy
        self.importStack = importStack
        self.sndToWav = sndToWav
    }

    deinit {
        dlclose(handle)
    }

    fileprivate static func load() -> StackImportLoadResult {
        let frameworkPath = StackImportRuntime.frameworkPath
        let executablePath = "\(frameworkPath)/StackImport"
        guard FileManager.default.fileExists(atPath: executablePath) else {
            return .unavailable("StackImport.framework was not found at \(frameworkPath). Install it with `\(StackImportRuntime.installCommand)`.")
        }
        guard let handle = dlopen(executablePath, RTLD_NOW | RTLD_LOCAL) else {
            return .unavailable("StackImport.framework exists at \(frameworkPath), but could not be loaded: \(dlerrorString()).")
        }

        guard
            let apiVersion: ApiVersionFn = symbol("stackimport_api_version", handle: handle),
            let versionString: VersionStringFn = symbol("stackimport_version_string", handle: handle),
            let versionPacked: VersionPackedFn = symbol("stackimport_version_packed", handle: handle),
            let statusString: StatusStringFn = symbol("stackimport_status_string", handle: handle),
            let platformInit: PlatformInitFn = symbol("stackimport_platform_init", handle: handle),
            let importOptionsInit: ImportOptionsInitFn = symbol("stackimport_import_options_init", handle: handle),
            let contextCreateWithPlatform: ContextCreateWithPlatformFn = symbol("stackimport_context_create_with_platform", handle: handle),
            let contextDestroy: ContextDestroyFn = symbol("stackimport_context_destroy", handle: handle),
            let importStack: ImportFn = symbol("stackimport_import", handle: handle),
            let sndToWav: SndToWavFn = symbol("stackimport_snd_to_wav", handle: handle)
        else {
            dlclose(handle)
            return .unavailable("StackImport.framework exists at \(frameworkPath), but required C API symbols could not be loaded.")
        }

        let loadedAPIVersion = apiVersion()
        guard loadedAPIVersion == STACKIMPORT_API_VERSION else {
            dlclose(handle)
            return .unavailable("StackImport.framework API version \(loadedAPIVersion) does not match Hype's expected API version \(STACKIMPORT_API_VERSION). Update StackImport with `\(StackImportRuntime.installCommand)`.")
        }

        let loadedVersionPacked = versionPacked()
        guard loadedVersionPacked == expectedVersionPacked else {
            dlclose(handle)
            let loadedVersion = versionString().map { String(cString: $0) } ?? "unknown"
            return .unavailable("StackImport.framework version \(loadedVersion) does not match Hype's expected version \(expectedVersionString). Update StackImport with `\(StackImportRuntime.installCommand)`.")
        }

        let loadedVersion = versionString().map { String(cString: $0) } ?? frameworkVersion(at: frameworkPath) ?? "unknown"
        return .available(StackImportLibrary(
            handle: handle,
            version: loadedVersion,
            versionPacked: loadedVersionPacked,
            apiVersion: loadedAPIVersion,
            frameworkPath: frameworkPath,
            statusString: statusString,
            platformInit: platformInit,
            importOptionsInit: importOptionsInit,
            contextCreateWithPlatform: contextCreateWithPlatform,
            contextDestroy: contextDestroy,
            importStack: importStack,
            sndToWav: sndToWav
        ))
    }

    private static func symbol<T>(_ name: String, handle: UnsafeMutableRawPointer) -> T? {
        guard let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    static func frameworkVersion(at frameworkPath: String) -> String? {
        guard let bundle = Bundle(path: frameworkPath),
              let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !version.isEmpty else {
            return nil
        }
        return version
    }

    private static func dlerrorString() -> String {
        guard let error = dlerror() else { return "unknown dynamic loader error" }
        return String(cString: error)
    }
}
