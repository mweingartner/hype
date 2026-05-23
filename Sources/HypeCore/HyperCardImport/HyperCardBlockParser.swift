import Foundation

public struct HyperCardBlock: Sendable, Equatable {
    public var type: String
    public var id: Int32
    public var offset: Int
    public var size: Int
    public var payload: Data

    public init(type: String, id: Int32, offset: Int, size: Int, payload: Data) {
        self.type = type
        self.id = id
        self.offset = offset
        self.size = size
        self.payload = payload
    }
}

public struct HyperCardBlockParser: Sendable {
    public var options: HyperCardImportOptions

    public init(options: HyperCardImportOptions = HyperCardImportOptions()) {
        self.options = options
    }

    public func parse(data: Data) throws -> [HyperCardBlock] {
        guard !data.isEmpty else { throw HyperCardImportError.emptyInput }
        guard data.count <= options.maxInputBytes else {
            throw HyperCardImportError.inputTooLarge(data.count)
        }

        let reader = HyperCardBinaryReader(data)
        var offset = 0
        var blocks: [HyperCardBlock] = []

        while offset < data.count {
            guard offset + 16 <= data.count else {
                throw HyperCardImportError.truncatedHeader(offset: offset)
            }
            guard let rawSize = reader.int32(at: offset),
                  let type = reader.fourCC(at: offset + 4),
                  let id = reader.int32(at: offset + 8)
            else {
                throw HyperCardImportError.truncatedHeader(offset: offset)
            }
            let size = Int(rawSize)
            guard size >= 16, offset + size <= data.count else {
                throw HyperCardImportError.invalidBlockSize(size, offset: offset)
            }
            guard size <= options.maxBlockBytes else {
                throw HyperCardImportError.blockTooLarge(size, type: type)
            }
            guard blocks.count < options.maxBlocks else {
                throw HyperCardImportError.tooManyBlocks(blocks.count)
            }

            let payloadStart = offset + 16
            let payloadEnd = offset + size
            let payload = data[(data.startIndex + payloadStart)..<(data.startIndex + payloadEnd)]
            blocks.append(HyperCardBlock(type: type, id: id, offset: offset, size: size, payload: Data(payload)))

            offset += size
            if type == "TAIL" { break }
        }

        guard let first = blocks.first, first.type == "STAK" else {
            throw HyperCardImportError.missingStackBlock
        }
        let stackReader = HyperCardBinaryReader(first.payload)
        guard let format = stackReader.int32(at: 0), (1...10).contains(format) else {
            throw HyperCardImportError.notHyperCardStack
        }

        return blocks
    }

    public static func summaries(for blocks: [HyperCardBlock]) -> [HyperCardBlockSummary] {
        let grouped = Dictionary(grouping: blocks, by: \.type)
        return grouped.keys.sorted().map { type in
            let matching = grouped[type] ?? []
            return HyperCardBlockSummary(
                type: type,
                count: matching.count,
                totalBytes: matching.reduce(0) { $0 + $1.size }
            )
        }
    }
}
