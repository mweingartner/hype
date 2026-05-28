import CStackImport
import AppKit
import Foundation

/// Adapter for the stackimport C ABI.
///
/// The C importer is path-based and emits a generated `.xstk` directory. Hype's
/// document-open path can receive only a FileWrapper, so `importStack(data:)`
/// materializes the input bytes into a private temporary file before calling the
/// same C API used by `importStack(at:)`.
///
/// Converted resource payloads (e.g. snd-to-WAV) are captured through the C API's
/// `resource_wants`/`resource_payload` callbacks, avoiding unnecessary disk I/O.
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
        let stackImport = try StackImportRuntime.requireAvailable()
        let output = StackImportInMemoryOutput(rootPath: outputPath)
        let outputPointer = Unmanaged.passRetained(output).toOpaque()
        defer { Unmanaged<StackImportInMemoryOutput>.fromOpaque(outputPointer).release() }

        let resourceCollector = StackImportResourceCollector()
        let collectorPointer = Unmanaged.passRetained(resourceCollector).toOpaque()
        defer { Unmanaged<StackImportResourceCollector>.fromOpaque(collectorPointer).release() }

        var platform = stackimport_platform()
        stackImport.platformInit(&platform)
        platform.message = stackImportMessage
        platform.open_file = stackImportOpenFile
        platform.read_file = stackImportReadFile
        platform.write_file = stackImportWriteFile
        platform.close_file = stackImportCloseFile
        platform.make_directory = stackImportMakeDirectory
        platform.user_data = outputPointer
        var context: OpaquePointer?
        var status = stackImport.contextCreateWithPlatform(&platform, &context)
        guard status == STACKIMPORT_STATUS_OK, let context else {
            throw HyperCardImportError.stackimportFailed(statusMessage(status, stackImport: stackImport))
        }
        defer { stackImport.contextDestroy(context) }

        var importOptions = stackimport_import_options()
        stackImport.importOptionsInit(&importOptions)
        importOptions.flags = UInt32(STACKIMPORT_IMPORT_NO_STATUS.rawValue | STACKIMPORT_IMPORT_NO_PROGRESS.rawValue)
        importOptions.resource_payload_flags = UInt32(STACKIMPORT_RESOURCE_PAYLOADS_CONVERTED.rawValue)
        importOptions.resource_wants = stackImportResourceWants
        importOptions.resource_payload = stackImportResourcePayload
        importOptions.resource_user_data = collectorPointer

        status = inputPath.withCString { inputCString in
            outputPath.withCString { outputCString in
                importOptions.input_path = inputCString
                importOptions.output_package_path = outputCString
                return stackImport.importStack(context, &importOptions)
            }
        }
        guard status == STACKIMPORT_STATUS_OK else {
            throw HyperCardImportError.stackimportFailed(statusMessage(status, stackImport: stackImport))
        }
        var files = output.files
        for (path, data) in generatedFiles(at: URL(fileURLWithPath: outputPath)) where files[path] == nil {
            files[path] = data
        }
        for (path, data) in resourceCollector.files where files[path] == nil && !hasExistingPayload(data, in: files) {
            files[path] = data
        }
        return files
    }

    private func statusMessage(_ status: stackimport_status, stackImport: StackImportLibrary) -> String {
        guard let message = stackImport.statusString(status) else {
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

    private func hasExistingPayload(_ data: Data, in files: [String: Data]) -> Bool {
        files.contains { _, existingData in existingData == data }
    }
}

/// Collects converted resource payloads delivered through the C API's streaming callbacks.
private final class StackImportResourceCollector {
    private static let maxPayloadBytes = 64 * 1024 * 1024
    var files: [String: Data] = [:]

    func resourcePath(for payload: stackimport_resource_payload) -> String {
        let type = sanitizedResourceName(resourceTypeString(payload.type))
        let ext = fileExtension(for: payload)
        let namePart: String
        if let namePtr = payload.name, payload.name_size > 0 {
            namePart = String(
                data: Data(bytes: namePtr, count: Int(payload.name_size)),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } else {
            namePart = ""
        }
        let base = namePart.isEmpty ? "\(type)_\(payload.id)" : "\(type)_\(payload.id)_\(sanitizedResourceName(namePart))"
        let variant = payload.variant_index > 0 ? "_\(String(format: "%02d", payload.variant_index))" : ""
        let folder: String
        switch ext {
        case "wav", "aiff", "mp3", "m4a":
            folder = "sounds"
        case "json":
            folder = "resource-metadata"
        case "txt":
            folder = "resource-text"
        default:
            folder = "resources"
        }
        return "\(folder)/\(base)\(variant).\(ext)"
    }

    func data(for payload: stackimport_resource_payload, bytes: UnsafeRawPointer, size: Int) -> Data? {
        guard size > 0 else {
            logWarning("Skipping empty stackimport resource payload for \(payloadDescription(payload))")
            return nil
        }
        guard size <= Self.maxPayloadBytes else {
            logWarning("Skipping oversized stackimport resource payload for \(payloadDescription(payload)): \(size) bytes")
            return nil
        }
        if payload.format == UInt32(STACKIMPORT_RESOURCE_PAYLOAD_RGBA32.rawValue) {
            guard let png = pngData(forRGBA32Payload: payload, bytes: bytes, size: size) else {
                logWarning("Could not encode RGBA stackimport resource payload for \(payloadDescription(payload))")
                return nil
            }
            return png
        }
        if fileExtension(for: payload) == "bin" {
            logWarning("Received unhandled converted stackimport resource payload for \(payloadDescription(payload)); preserving as binary package artifact")
        }
        return Data(bytes: bytes, count: size)
    }

    private func pngData(forRGBA32Payload payload: stackimport_resource_payload, bytes: UnsafeRawPointer, size: Int) -> Data? {
        let width = Int(payload.width)
        let height = Int(payload.height)
        guard width > 0, height > 0 else { return nil }
        let rowBytes = Int(payload.row_bytes == 0 ? UInt32(width * 4) : payload.row_bytes)
        guard rowBytes >= width * 4, size >= rowBytes * height else { return nil }
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        ), let bitmapData = rep.bitmapData else { return nil }

        let source = bytes.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            bitmapData.advanced(by: y * width * 4).update(from: source.advanced(by: y * rowBytes), count: width * 4)
        }
        return rep.representation(using: .png, properties: [:])
    }

    private func fileExtension(for payload: stackimport_resource_payload) -> String {
        if payload.format == UInt32(STACKIMPORT_RESOURCE_PAYLOAD_RGBA32.rawValue) {
            return "png"
        }
        guard let mediaTypeC = payload.media_type,
              let mediaTypeString = String(cString: mediaTypeC, encoding: .utf8) else {
            return "bin"
        }
        let mediaType = mediaTypeString.lowercased()
        switch mediaType {
        case "application/json": return "json"
        case "text/plain": return "txt"
        case "audio/wav", "audio/wave", "audio/x-wav": return "wav"
        case "image/png": return "png"
        case "video/mp4": return "mp4"
        case "video/quicktime": return "mov"
        default:
            return mediaType.components(separatedBy: "/").last?.split(separator: "+").first.map(String.init) ?? "bin"
        }
    }

    private func resourceTypeString(_ tuple: (Int8, Int8, Int8, Int8)) -> String {
        let scalars = [tuple.0, tuple.1, tuple.2, tuple.3].map { value -> UInt8 in
            let byte = UInt8(bitPattern: value)
            return (byte >= 0x20 && byte <= 0x7e) ? byte : UInt8(ascii: "_")
        }
        return String(bytes: scalars, encoding: .ascii) ?? "RSRC"
    }

    private func payloadDescription(_ payload: stackimport_resource_payload) -> String {
        let mediaType = payload.media_type.flatMap { String(cString: $0, encoding: .utf8) } ?? "unknown"
        return "\(resourceTypeString(payload.type)) \(payload.id), mediaType='\(mediaType)', format=\(payload.format)"
    }

    private func logWarning(_ message: String) {
        HypeLogger.shared.warn(message, source: "HyperCardImport")
    }

    private func sanitizedResourceName(_ name: String) -> String {
        let valid = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !valid.isEmpty else { return "resource" }
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return valid.components(separatedBy: invalid).joined(separator: "_")
    }
}

private let stackImportResourceWants: stackimport_resource_wants_fn = { payload, userData in
    guard let payload, let userData else { return 0 }
    _ = Unmanaged<StackImportResourceCollector>.fromOpaque(userData).takeUnretainedValue()
    return payload.pointee.format == UInt32(STACKIMPORT_RESOURCE_PAYLOAD_NATIVE.rawValue) ? 0 : 1
}

private let stackImportResourcePayload: stackimport_resource_payload_fn = { payload, data, size, userData in
    guard let payload, let data, let userData, size > 0 else { return 1 }
    let p = payload.pointee
    let collector = Unmanaged<StackImportResourceCollector>.fromOpaque(userData).takeUnretainedValue()

    guard let payloadData = collector.data(for: p, bytes: data, size: size) else { return 1 }
    let path = collector.resourcePath(for: p)
    collector.files[path] = payloadData
    return 1
}

private let stackImportMessage: stackimport_message_fn = { severity, message, _ in
    guard let message else { return }
    let text = String(cString: message)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }

    switch severity {
    case UInt32(STACKIMPORT_MESSAGE_FATAL.rawValue), UInt32(STACKIMPORT_MESSAGE_ERROR.rawValue):
        HypeLogger.shared.error(text, source: "StackImport")
    case UInt32(STACKIMPORT_MESSAGE_WARNING.rawValue):
        HypeLogger.shared.warn(text, source: "StackImport")
    default:
        HypeLogger.shared.info(text, source: "StackImport")
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

private class StackImportPlatformFile {}

private final class StackImportInputFile: StackImportPlatformFile {
    let data: Data
    var offset = 0

    init(data: Data) {
        self.data = data
    }
}

private final class StackImportInMemoryFile: StackImportPlatformFile {
    let relativePath: String
    var data = Data()

    init(relativePath: String) {
        self.relativePath = relativePath
    }
}

private let stackImportOpenFile: stackimport_open_file_fn = { path, mode, userData in
    guard let path, let userData else { return nil }
    let modeString = mode.map { String(cString: $0) } ?? ""
    let filePath = String(cString: path)
    if modeString.contains("w") {
        let output = Unmanaged<StackImportInMemoryOutput>.fromOpaque(userData).takeUnretainedValue()
        let file = StackImportInMemoryFile(relativePath: output.relativePath(for: filePath))
        return Unmanaged.passRetained(file).toOpaque()
    }
    guard modeString.contains("r"), let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else {
        return nil
    }
    return Unmanaged.passRetained(StackImportInputFile(data: data)).toOpaque()
}

private let stackImportReadFile: stackimport_read_file_fn = { file, data, size, _ in
    guard let file, let data, size > 0 else { return 0 }
    guard let inputFile = Unmanaged<StackImportPlatformFile>.fromOpaque(file).takeUnretainedValue() as? StackImportInputFile else {
        return 0
    }
    let remaining = inputFile.data.count - inputFile.offset
    guard remaining > 0 else { return 0 }
    let count = min(size, remaining)
    inputFile.data.copyBytes(to: data.assumingMemoryBound(to: UInt8.self), from: inputFile.offset..<(inputFile.offset + count))
    inputFile.offset += count
    return count
}

private let stackImportWriteFile: stackimport_write_file_fn = { file, data, size, _ in
    guard let file, let data else { return 0 }
    guard let outputFile = Unmanaged<StackImportPlatformFile>.fromOpaque(file).takeUnretainedValue() as? StackImportInMemoryFile else {
        return 0
    }
    outputFile.data.append(data.assumingMemoryBound(to: UInt8.self), count: size)
    return size
}

private let stackImportCloseFile: stackimport_close_file_fn = { file, userData in
    guard let file, let userData else { return -1 }
    let retained = Unmanaged<StackImportPlatformFile>.fromOpaque(file)
    if let outputFile = retained.takeUnretainedValue() as? StackImportInMemoryFile {
        let output = Unmanaged<StackImportInMemoryOutput>.fromOpaque(userData).takeUnretainedValue()
        output.files[outputFile.relativePath] = outputFile.data
    }
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
