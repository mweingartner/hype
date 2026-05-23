import Foundation

public struct HyperCardImportPackage: Sendable {
    public var sourceURL: URL?
    public var dataFork: Data
    public var resourceFork: Data?

    public init(sourceURL: URL? = nil, dataFork: Data, resourceFork: Data? = nil) {
        self.sourceURL = sourceURL
        self.dataFork = dataFork
        self.resourceFork = resourceFork
    }
}

public struct HyperCardInputNormalizer: Sendable {
    public var options: HyperCardImportOptions

    public init(options: HyperCardImportOptions = HyperCardImportOptions()) {
        self.options = options
    }

    public func normalize(url: URL) throws -> HyperCardImportPackage {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        if values.isDirectory == true {
            throw HyperCardImportError.unsupportedArchive("directories and disk images must be mounted first")
        }
        if let size = values.fileSize, size > options.maxInputBytes {
            throw HyperCardImportError.inputTooLarge(size)
        }
        let dataFork = try Data(contentsOf: url, options: [.mappedIfSafe])
        let resourceFork = try readResourceForkIfPresent(for: url)
        return HyperCardImportPackage(sourceURL: url, dataFork: dataFork, resourceFork: resourceFork)
    }

    public func normalize(data: Data, sourceURL: URL? = nil, resourceFork: Data? = nil) throws -> HyperCardImportPackage {
        guard data.count <= options.maxInputBytes else {
            throw HyperCardImportError.inputTooLarge(data.count)
        }
        return HyperCardImportPackage(sourceURL: sourceURL, dataFork: data, resourceFork: resourceFork)
    }

    private func readResourceForkIfPresent(for url: URL) throws -> Data? {
        let resourceForkURL = URL(fileURLWithPath: url.path + "/..namedfork/rsrc")
        if FileManager.default.isReadableFile(atPath: resourceForkURL.path) {
            let data = try Data(contentsOf: resourceForkURL, options: [.mappedIfSafe])
            return data.isEmpty ? nil : data
        }

        let appleDoubleURL = url.deletingLastPathComponent().appendingPathComponent("._" + url.lastPathComponent)
        if FileManager.default.isReadableFile(atPath: appleDoubleURL.path) {
            let data = try Data(contentsOf: appleDoubleURL, options: [.mappedIfSafe])
            return Self.resourceForkFromAppleDouble(data)
        }
        return nil
    }

    /// Best-effort AppleDouble resource-fork extraction. This covers
    /// common ZIP/copy paths that preserve a classic Mac resource fork
    /// as a sibling `._Name` file. If parsing fails, the importer still
    /// converts the data fork and reports that resources are unavailable.
    private static func resourceForkFromAppleDouble(_ data: Data) -> Data? {
        let reader = HyperCardBinaryReader(data)
        guard data.count >= 26,
              reader.uint32(at: 0) == 0x00051607,
              let entryCount = reader.uint16(at: 24) else {
            return nil
        }
        for index in 0..<Int(entryCount) {
            let entry = 26 + index * 12
            guard let entryID = reader.uint32(at: entry),
                  let offset32 = reader.uint32(at: entry + 4),
                  let length32 = reader.uint32(at: entry + 8) else {
                return nil
            }
            if entryID == 2 {
                let offset = Int(offset32)
                let length = Int(length32)
                return reader.subdata(in: offset..<(offset + length))
            }
        }
        return nil
    }
}
