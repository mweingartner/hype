import Foundation
import CryptoKit

package struct HyperCardBinaryReader {
    package let data: Data

    package init(_ data: Data) {
        self.data = data
    }

    package var count: Int { data.count }

    package func contains(range: Range<Int>) -> Bool {
        range.lowerBound >= 0 && range.upperBound <= data.count && range.lowerBound <= range.upperBound
    }

    package func uint8(at offset: Int) -> UInt8? {
        guard contains(range: offset..<(offset + 1)) else { return nil }
        return data[data.startIndex + offset]
    }

    package func int16(at offset: Int) -> Int16? {
        guard let value = uint16(at: offset) else { return nil }
        return Int16(bitPattern: value)
    }

    package func uint16(at offset: Int) -> UInt16? {
        guard contains(range: offset..<(offset + 2)) else { return nil }
        var result: UInt16 = 0
        for i in 0..<2 {
            result = (result << 8) | UInt16(data[data.startIndex + offset + i])
        }
        return result
    }

    package func int32(at offset: Int) -> Int32? {
        guard let value = uint32(at: offset) else { return nil }
        return Int32(bitPattern: value)
    }

    package func uint32(at offset: Int) -> UInt32? {
        guard contains(range: offset..<(offset + 4)) else { return nil }
        var result: UInt32 = 0
        for i in 0..<4 {
            result = (result << 8) | UInt32(data[data.startIndex + offset + i])
        }
        return result
    }

    package func fourCC(at offset: Int) -> String? {
        guard contains(range: offset..<(offset + 4)) else { return nil }
        let slice = data[(data.startIndex + offset)..<(data.startIndex + offset + 4)]
        return String(bytes: slice, encoding: .macOSRoman)
    }

    package func subdata(in range: Range<Int>) -> Data? {
        guard contains(range: range) else { return nil }
        return data[(data.startIndex + range.lowerBound)..<(data.startIndex + range.upperBound)]
    }

    package func cString(at offset: Int, limit: Int? = nil) -> (String, Int)? {
        guard offset >= 0, offset < data.count else { return nil }
        let maxEnd = min(data.count, limit ?? data.count)
        var end = offset
        while end < maxEnd {
            if data[data.startIndex + end] == 0 { break }
            end += 1
        }
        guard end <= maxEnd else { return nil }
        let bytes = data[(data.startIndex + offset)..<(data.startIndex + end)]
        let text = String(data: Data(bytes), encoding: .macOSRoman) ?? String(decoding: bytes, as: UTF8.self)
        let next = end < maxEnd ? end + 1 : end
        return (text, next)
    }

    package func pascalString(at offset: Int, limit: Int? = nil) -> (String, Int)? {
        guard let lengthByte = uint8(at: offset) else { return nil }
        let length = Int(lengthByte)
        let start = offset + 1
        let end = start + length
        guard contains(range: start..<end), end <= (limit ?? data.count) else { return nil }
        let bytes = data[(data.startIndex + start)..<(data.startIndex + end)]
        let text = String(data: Data(bytes), encoding: .macOSRoman) ?? String(decoding: bytes, as: UTF8.self)
        return (text, end)
    }
}

package extension Data {
    var hypeSHA256Hex: String {
        let digest = SHA256.hash(data: self)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
