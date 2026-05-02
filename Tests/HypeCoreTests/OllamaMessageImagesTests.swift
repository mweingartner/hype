import Testing
import Foundation
@testable import HypeCore

/// Unit tests for `OllamaMessage` — verifying that the custom Codable implementation
/// correctly handles the `images` field, especially the "nil omits key" contract.
@Suite("OllamaMessage images encoding/decoding")
struct OllamaMessageImagesTests {

    // MARK: - Helpers

    /// Decode the raw JSON encoded bytes to a flat key → Any dictionary for key-presence inspection.
    private func decodeToDict(_ msg: OllamaMessage) throws -> [String: Any] {
        let encoder = JSONEncoder()
        let data = try encoder.encode(msg)
        let obj = try JSONSerialization.jsonObject(with: data)
        guard let dict = obj as? [String: Any] else {
            Issue.record("Expected JSON object at top level")
            return [:]
        }
        return dict
    }

    // MARK: - Encoding

    @Test("OllamaMessage with images: nil encodes WITHOUT the images key")
    func encodeNilImages_omitsKey() throws {
        let msg = OllamaMessage(role: "user", content: "Hello", images: nil)
        let dict = try decodeToDict(msg)
        #expect(!dict.keys.contains("images"), "images key must be absent when nil")
    }

    @Test("OllamaMessage with images: [] encodes WITH the images key as an empty array")
    func encodeEmptyImages_presentsKey() throws {
        let msg = OllamaMessage(role: "user", content: "Hello", images: [])
        let dict = try decodeToDict(msg)
        // An empty array is technically present — this documents the current behavior.
        // The important invariant is that nil → absent, not nil → null.
        if let imagesValue = dict["images"] {
            let arr = imagesValue as? [Any]
            #expect(arr?.isEmpty == true)
        }
        // Key is present (empty array) — not null.
        #expect(dict["images"] != nil)
    }

    @Test("OllamaMessage with images: [b64] encodes the images key as a JSON array of strings")
    func encodeImages_presentsArrayOfStrings() throws {
        let b64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAA"
        let msg = OllamaMessage(role: "user", content: "See image", images: [b64])
        let dict = try decodeToDict(msg)
        #expect(dict.keys.contains("images"), "images key must be present")
        let arr = dict["images"] as? [String]
        #expect(arr?.count == 1)
        #expect(arr?.first == b64)
    }

    // MARK: - Decoding

    @Test("Round-trip encode → decode preserves images array")
    func roundTrip_preservesImages() throws {
        let b64a = "abc123"
        let b64b = "xyz789"
        let original = OllamaMessage(role: "user", content: "two images", images: [b64a, b64b])
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(OllamaMessage.self, from: data)
        #expect(decoded.role == original.role)
        #expect(decoded.content == original.content)
        #expect(decoded.images?.count == 2)
        #expect(decoded.images?[0] == b64a)
        #expect(decoded.images?[1] == b64b)
    }

    @Test("Round-trip encode → decode preserves nil images as nil")
    func roundTrip_nilImages_remainsNil() throws {
        let original = OllamaMessage(role: "assistant", content: "No image", images: nil)
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(OllamaMessage.self, from: data)
        #expect(decoded.images == nil)
    }

    @Test("Round-trip preserves role, content, and tool_calls when images is nil")
    func roundTrip_preservesOtherFields() throws {
        let call = OllamaToolCall(function: OllamaToolCallFunction(name: "create_card", arguments: ["name": "Home"]))
        let original = OllamaMessage(role: "assistant", content: nil, tool_calls: [call], images: nil)
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(OllamaMessage.self, from: data)
        #expect(decoded.role == "assistant")
        #expect(decoded.content == nil)
        #expect(decoded.tool_calls?.count == 1)
        #expect(decoded.tool_calls?.first?.function.name == "create_card")
        #expect(decoded.images == nil)
    }

    // MARK: - JSON null safety

    @Test("Decoding JSON with explicit null images field yields nil images")
    func decode_explicitNullImages_yieldsNil() throws {
        let json = """
        {"role": "user", "content": "hello", "images": null}
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let msg = try decoder.decode(OllamaMessage.self, from: data)
        #expect(msg.images == nil)
    }

    @Test("Decoding JSON without images key yields nil images")
    func decode_missingImagesKey_yieldsNil() throws {
        let json = """
        {"role": "tool", "content": "result"}
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let msg = try decoder.decode(OllamaMessage.self, from: data)
        #expect(msg.images == nil)
    }
}
