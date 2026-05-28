import CStackImport
import Foundation

/// Adapter for the stackimport C ABI.
///
/// The C importer is path-based and emits a generated `.xstk` directory. Hype's
/// document-open path can receive only a FileWrapper, so `importStack(data:)`
/// materializes the input bytes into a private temporary file before calling the
/// same C API used by `importStack(at:)`.
public struct StackImportCImporter: Sendable {
    public var options: HyperCardImportOptions

    public init(options: HyperCardImportOptions = HyperCardImportOptions()) {
        self.options = options
    }

    public func importStack(at sourceURL: URL) throws -> HyperCardImportResult {
        let package = try HyperCardInputNormalizer(options: options).normalize(url: sourceURL)
        let workspace = try makeWorkspace()
        defer { cleanup(workspace) }

        let outputURL = workspace.appendingPathComponent("Imported.xstk", isDirectory: true)
        let packageFiles = try runStackImport(inputPath: sourceURL.path, outputPath: outputURL.path)
        var result = try StackImportPackageConverter(options: options).convert(packageFiles: packageFiles, sourcePackage: package)
        result.document.legacyImport?.sourceFileName = sourceURL.lastPathComponent
        return result
    }

    public func importStack(data: Data, sourceFileName: String? = nil) throws -> HyperCardImportResult {
        let package = try HyperCardInputNormalizer(options: options).normalize(data: data)
        let workspace = try makeWorkspace()
        defer { cleanup(workspace) }

        let inputName = sanitizedFileName(sourceFileName ?? "Imported HyperCard Stack")
        let inputURL = workspace.appendingPathComponent(inputName)
        try data.write(to: inputURL, options: .atomic)

        let outputURL = workspace.appendingPathComponent("Imported.xstk", isDirectory: true)
        let packageFiles = try runStackImport(inputPath: inputURL.path, outputPath: outputURL.path)
        var result = try StackImportPackageConverter(options: options).convert(packageFiles: packageFiles, sourcePackage: package)
        result.document.legacyImport?.sourceFileName = sourceFileName
        return result
    }

    private func runStackImport(inputPath: String, outputPath: String) throws -> [String: Data] {
        let output = StackImportInMemoryOutput(rootPath: outputPath)
        let outputPointer = Unmanaged.passRetained(output).toOpaque()
        defer { Unmanaged<StackImportInMemoryOutput>.fromOpaque(outputPointer).release() }

        var platform = stackimport_platform()
        stackimport_platform_init(&platform)
        platform.open_file = stackImportOpenFile
        platform.write_file = stackImportWriteFile
        platform.close_file = stackImportCloseFile
        platform.make_directory = stackImportMakeDirectory
        platform.user_data = outputPointer
        var context: OpaquePointer?
        var status = stackimport_context_create_with_platform(&platform, &context)
        guard status == STACKIMPORT_STATUS_OK, let context else {
            throw HyperCardImportError.stackimportFailed(statusMessage(status))
        }
        defer { stackimport_context_destroy(context) }

        var importOptions = stackimport_import_options()
        stackimport_import_options_init(&importOptions)
        importOptions.flags = UInt32(STACKIMPORT_IMPORT_NO_STATUS.rawValue | STACKIMPORT_IMPORT_NO_PROGRESS.rawValue)

        status = inputPath.withCString { inputCString in
            outputPath.withCString { outputCString in
                importOptions.input_path = inputCString
                importOptions.output_package_path = outputCString
                return stackimport_import(context, &importOptions)
            }
        }
        guard status == STACKIMPORT_STATUS_OK else {
            throw HyperCardImportError.stackimportFailed(statusMessage(status))
        }
        var files = output.files
        for (path, data) in generatedFiles(at: URL(fileURLWithPath: outputPath)) where files[path] == nil {
            files[path] = data
        }
        return files
    }

    private func statusMessage(_ status: stackimport_status) -> String {
        guard let message = stackimport_status_string(status) else {
            return "unknown status \(status.rawValue)"
        }
        return String(cString: message)
    }

    private func makeWorkspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hype-stackimport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func sanitizedFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:")
        let cleaned = name
            .components(separatedBy: invalid)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Imported HyperCard Stack" : cleaned
    }

    private func generatedFiles(at packageURL: URL) -> [String: Data] {
        guard let enumerator = FileManager.default.enumerator(
            at: packageURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }

        var files: [String: Data] = [:]
        let root = packageURL.path + "/"
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  let data = try? Data(contentsOf: url) else { continue }
            let path = url.path
            let relative = path.hasPrefix(root) ? String(path.dropFirst(root.count)) : url.lastPathComponent
            files[relative] = data
        }
        return files
    }
}

private final class StackImportInMemoryOutput {
    let rootPath: String
    var files: [String: Data] = [:]

    init(rootPath: String) {
        self.rootPath = NSString(string: rootPath).standardizingPath
    }

    func relativePath(for path: String) -> String {
        let standardized = NSString(string: path).standardizingPath
        if standardized == rootPath {
            return URL(fileURLWithPath: standardized).lastPathComponent
        }
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if standardized.hasPrefix(rootPrefix) {
            return String(standardized.dropFirst(rootPrefix.count))
        }
        return URL(fileURLWithPath: standardized).lastPathComponent
    }
}

private final class StackImportInMemoryFile {
    let relativePath: String
    var data = Data()

    init(relativePath: String) {
        self.relativePath = relativePath
    }
}

private let stackImportOpenFile: stackimport_open_file_fn = { path, mode, userData in
    guard let path, let userData else { return nil }
    let modeString = mode.map { String(cString: $0) } ?? ""
    guard modeString.contains("w") else { return nil }
    let output = Unmanaged<StackImportInMemoryOutput>.fromOpaque(userData).takeUnretainedValue()
    let file = StackImportInMemoryFile(relativePath: output.relativePath(for: String(cString: path)))
    return Unmanaged.passRetained(file).toOpaque()
}

private let stackImportWriteFile: stackimport_write_file_fn = { file, data, size, _ in
    guard let file, let data else { return 0 }
    let outputFile = Unmanaged<StackImportInMemoryFile>.fromOpaque(file).takeUnretainedValue()
    outputFile.data.append(data.assumingMemoryBound(to: UInt8.self), count: size)
    return size
}

private let stackImportCloseFile: stackimport_close_file_fn = { file, userData in
    guard let file, let userData else { return -1 }
    let retained = Unmanaged<StackImportInMemoryFile>.fromOpaque(file)
    let outputFile = retained.takeUnretainedValue()
    let output = Unmanaged<StackImportInMemoryOutput>.fromOpaque(userData).takeUnretainedValue()
    output.files[outputFile.relativePath] = outputFile.data
    retained.release()
    return 0
}

private let stackImportMakeDirectory: stackimport_make_directory_fn = { path, _ in
    guard let path else { return -1 }
    do {
        try FileManager.default.createDirectory(atPath: String(cString: path), withIntermediateDirectories: true)
        return 0
    } catch {
        return -1
    }
}
