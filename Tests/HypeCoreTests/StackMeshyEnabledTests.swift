import Foundation
import Testing
@testable import HypeCore

/// Tests for `Stack.meshyEnabled` backward-compatible decoding.
@Suite("Stack.meshyEnabled — backward compat")
struct StackMeshyEnabledTests {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    @Test("pre-Meshy JSON without meshyEnabled key decodes to false")
    func preMeshyJSONDefaultsFalse() throws {
        // Encode a stack without meshyEnabled in the JSON.
        let stack = Stack(meshyEnabled: false)
        var json = try JSONSerialization.jsonObject(
            with: encoder.encode(stack)
        ) as! [String: Any]
        json.removeValue(forKey: "meshyEnabled")
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try decoder.decode(Stack.self, from: data)
        #expect(decoded.meshyEnabled == false)
    }

    @Test("explicit null decodes to false")
    func explicitNullDefaultsFalse() throws {
        let stack = Stack(meshyEnabled: false)
        var json = try JSONSerialization.jsonObject(
            with: encoder.encode(stack)
        ) as! [String: Any]
        json["meshyEnabled"] = NSNull()
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try decoder.decode(Stack.self, from: data)
        #expect(decoded.meshyEnabled == false)
    }

    @Test("Stack(meshyEnabled: true) round-trips")
    func meshyEnabledRoundTrip() throws {
        let original = Stack(meshyEnabled: true)
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Stack.self, from: data)
        #expect(decoded.meshyEnabled == true)
    }

    @Test("Stack(meshyEnabled: false) round-trips")
    func meshyDisabledRoundTrip() throws {
        let original = Stack(meshyEnabled: false)
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Stack.self, from: data)
        #expect(decoded.meshyEnabled == false)
    }
}
