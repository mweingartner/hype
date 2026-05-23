import Foundation

public struct MacResource: Sendable, Equatable {
    public var type: String
    public var id: Int
    public var name: String?
    public var attributes: UInt8
    public var data: Data

    public init(type: String, id: Int, name: String?, attributes: UInt8, data: Data) {
        self.type = type
        self.id = id
        self.name = name
        self.attributes = attributes
        self.data = data
    }
}

public struct MacResourceForkReader: Sendable {
    public var maxResourceDataBytes: Int
    public var maxResources: Int

    public init(maxResourceDataBytes: Int = 128 * 1024 * 1024, maxResources: Int = 100_000) {
        self.maxResourceDataBytes = maxResourceDataBytes
        self.maxResources = maxResources
    }

    public func parse(_ data: Data) throws -> [MacResource] {
        guard data.count >= 16 else {
            throw HyperCardImportError.malformedResourceFork("header is shorter than 16 bytes")
        }
        let reader = HyperCardBinaryReader(data)
        guard let dataOffset32 = reader.uint32(at: 0),
              let mapOffset32 = reader.uint32(at: 4),
              let dataLength32 = reader.uint32(at: 8),
              let mapLength32 = reader.uint32(at: 12)
        else {
            throw HyperCardImportError.malformedResourceFork("header fields are truncated")
        }
        let dataOffset = Int(dataOffset32)
        let mapOffset = Int(mapOffset32)
        let dataLength = Int(dataLength32)
        let mapLength = Int(mapLength32)
        guard reader.contains(range: dataOffset..<(dataOffset + dataLength)),
              reader.contains(range: mapOffset..<(mapOffset + mapLength)) else {
            throw HyperCardImportError.malformedResourceFork("data or map range points outside the fork")
        }
        guard mapLength >= 30 else {
            throw HyperCardImportError.malformedResourceFork("resource map is too short")
        }

        guard let typeListOffset = reader.uint16(at: mapOffset + 24),
              let nameListOffset = reader.uint16(at: mapOffset + 26) else {
            throw HyperCardImportError.malformedResourceFork("type/name list offsets are truncated")
        }
        let typeListStart = mapOffset + Int(typeListOffset)
        let nameListStart = mapOffset + Int(nameListOffset)
        guard reader.contains(range: typeListStart..<(typeListStart + 2)),
              nameListStart >= mapOffset,
              nameListStart <= mapOffset + mapLength else {
            throw HyperCardImportError.malformedResourceFork("type or name list is outside the map")
        }

        guard let typeCountMinusOne = reader.int16(at: typeListStart) else {
            throw HyperCardImportError.malformedResourceFork("resource type count is missing")
        }
        let typeCount = Int(typeCountMinusOne) + 1
        guard typeCount >= 0 else {
            throw HyperCardImportError.malformedResourceFork("negative resource type count")
        }

        var resources: [MacResource] = []
        for typeIndex in 0..<typeCount {
            let typeEntry = typeListStart + 2 + typeIndex * 8
            guard reader.contains(range: typeEntry..<(typeEntry + 8)),
                  let type = reader.fourCC(at: typeEntry),
                  let resourceCountMinusOne = reader.int16(at: typeEntry + 4),
                  let refListOffset = reader.uint16(at: typeEntry + 6)
            else {
                throw HyperCardImportError.malformedResourceFork("resource type entry \(typeIndex) is truncated")
            }
            let resourceCount = Int(resourceCountMinusOne) + 1
            let refListStart = typeListStart + Int(refListOffset)
            guard resourceCount >= 0 else {
                throw HyperCardImportError.malformedResourceFork("negative resource count for type \(type)")
            }
            for resourceIndex in 0..<resourceCount {
                guard resources.count < maxResources else {
                    throw HyperCardImportError.malformedResourceFork("resource count exceeds safety limit")
                }
                let refEntry = refListStart + resourceIndex * 12
                guard reader.contains(range: refEntry..<(refEntry + 12)),
                      let id = reader.int16(at: refEntry),
                      let nameOffsetRaw = reader.int16(at: refEntry + 2),
                      let attrs = reader.uint8(at: refEntry + 4)
                else {
                    throw HyperCardImportError.malformedResourceFork("resource reference entry is truncated")
                }

                let relativeDataOffset =
                    (Int(reader.uint8(at: refEntry + 5) ?? 0) << 16) |
                    (Int(reader.uint8(at: refEntry + 6) ?? 0) << 8) |
                    Int(reader.uint8(at: refEntry + 7) ?? 0)
                let dataEntry = dataOffset + relativeDataOffset
                guard let resourceLength32 = reader.uint32(at: dataEntry) else {
                    throw HyperCardImportError.malformedResourceFork("resource data length is truncated")
                }
                let resourceLength = Int(resourceLength32)
                guard resourceLength <= maxResourceDataBytes else {
                    throw HyperCardImportError.malformedResourceFork("resource \(type) \(id) exceeds safety limit")
                }
                let resourceStart = dataEntry + 4
                let resourceEnd = resourceStart + resourceLength
                guard reader.contains(range: resourceStart..<resourceEnd) else {
                    throw HyperCardImportError.malformedResourceFork("resource \(type) \(id) data points outside the fork")
                }

                let name: String?
                if nameOffsetRaw >= 0 {
                    let nameOffset = nameListStart + Int(nameOffsetRaw)
                    name = reader.pascalString(at: nameOffset, limit: mapOffset + mapLength)?.0
                } else {
                    name = nil
                }

                let payload = data[(data.startIndex + resourceStart)..<(data.startIndex + resourceEnd)]
                resources.append(MacResource(type: type, id: Int(id), name: name, attributes: attrs, data: Data(payload)))
            }
        }
        return resources
    }

    public static func summaries(for resources: [MacResource]) -> [MacResourceSummary] {
        let grouped = Dictionary(grouping: resources, by: \.type)
        return grouped.keys.sorted().map { type in
            let matching = grouped[type] ?? []
            return MacResourceSummary(
                type: type,
                count: matching.count,
                totalBytes: matching.reduce(0) { $0 + $1.data.count }
            )
        }
    }
}
