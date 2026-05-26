import Testing
import Foundation
@testable import HypeCore

/// Tests for `Stack` backward-compatibility and round-trip Codable behavior.
/// Verifies that pre-v2 `.hype` JSON without newer opt-in flags defaults safely,
/// and that added stack fields round-trip correctly.
@Suite("Stack — CodingKeys round-trip and backward compatibility")
struct StackCodingKeysRoundTripTests {

    // MARK: - Pre-v2 backward compatibility

    @Test("pre-v2 JSON without webAssetsAllowed defaults to false")
    func preV2JSONDefaultsWebAssetsAllowedToFalse() throws {
        let preV2JSON = """
        {
            "id": "12345678-1234-1234-1234-123456789ABC",
            "name": "My Stack",
            "width": 800,
            "height": 600,
            "createdAt": "2024-01-01T00:00:00Z",
            "modifiedAt": "2024-01-01T00:00:00Z",
            "script": "",
            "defaultFont": "Apple Braille",
            "networkManifest": { "outboundHostRules": [], "savedListeners": [] }
        }
        """
        let data = preV2JSON.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let stack = try decoder.decode(Stack.self, from: data)
        #expect(stack.webAssetsAllowed == false)
        #expect(stack.aiContextCloudSharingAllowed == false)
        #expect(stack.runtimeModeEnabled == false)
        #expect(stack.runtimeAISettings.providerPolicy == .automatic)
        #expect(stack.name == "My Stack")
    }

    @Test("pre-v2 JSON with explicit null webAssetsAllowed defaults to false")
    func preV2JSONNullWebAssetsAllowedDefaultsFalse() throws {
        let json = """
        {
            "id": "12345678-1234-1234-1234-123456789ABC",
            "name": "Stack",
            "width": 800,
            "height": 600,
            "createdAt": "2024-01-01T00:00:00Z",
            "modifiedAt": "2024-01-01T00:00:00Z",
            "script": "",
            "defaultFont": "Apple Braille",
            "networkManifest": { "outboundHostRules": [], "savedListeners": [] },
            "webAssetsAllowed": null
        }
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let stack = try decoder.decode(Stack.self, from: data)
        // null decodeIfPresent → nil → ?? false
        #expect(stack.webAssetsAllowed == false)
        #expect(stack.aiContextCloudSharingAllowed == false)
        #expect(stack.runtimeModeEnabled == false)
    }

    // MARK: - All 9 pre-existing fields decode correctly

    @Test("all 9 pre-existing Stack fields decode from JSON")
    func allNinePreExistingFieldsDecode() throws {
        let json = """
        {
            "id": "AAAAAAAA-1234-1234-1234-123456789ABC",
            "name": "Test Document",
            "width": 1024,
            "height": 768,
            "createdAt": "2025-01-15T10:30:00Z",
            "modifiedAt": "2025-06-20T14:45:00Z",
            "script": "on mouseUp\\n  put 1\\nend mouseUp",
            "defaultFont": "Helvetica",
            "networkManifest": { "outboundHostRules": [], "savedListeners": [] }
        }
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let stack = try decoder.decode(Stack.self, from: data)

        #expect(stack.id == UUID(uuidString: "AAAAAAAA-1234-1234-1234-123456789ABC")!)
        #expect(stack.name == "Test Document")
        #expect(stack.width == 1024)
        #expect(stack.height == 768)
        #expect(stack.script == "on mouseUp\n  put 1\nend mouseUp")
        #expect(stack.defaultFont == "Helvetica")
        // webAssetsAllowed defaults to false when absent
        #expect(stack.webAssetsAllowed == false)
        #expect(stack.aiContextCloudSharingAllowed == false)
        #expect(stack.runtimeModeEnabled == false)
    }

    // MARK: - Full round-trip with webAssetsAllowed = true

    @Test("Stack with webAssetsAllowed=true round-trips through JSON")
    func stackWithWebAssetsAllowedRoundTrips() throws {
        let original = Stack(
            id: UUID(uuidString: "12345678-ABCD-ABCD-ABCD-123456789ABC")!,
            name: "My Game",
            width: 800,
            height: 600,
            createdAt: Date(timeIntervalSince1970: 1700000000),
            modifiedAt: Date(timeIntervalSince1970: 1700001000),
            script: "-- comment",
            defaultFont: "Menlo",
            networkManifest: StackNetworkManifest(),
            webAssetsAllowed: true,
            aiContextCloudSharingAllowed: true,
            runtimeModeEnabled: true,
            deploymentTargets: StackDeploymentTargets(
                selectedPlatforms: [.macOS, .iPad],
                primaryPlatform: .iPad,
                selectionPromptAcknowledged: true,
                supportedOrientations: [.resizable, .portrait, .landscape],
                layoutPolicy: .scaleToFit
            ),
            runtimeAISettings: RuntimeAISettings(
                providerPolicy: .appleFoundationModels,
                allowRuntimeSideEffectTools: true,
                allowedToolNames: ["set_runtime_variable"],
                persistTranscript: true
            )
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Stack.self, from: encoded)

        #expect(decoded.id == original.id)
        #expect(decoded.name == "My Game")
        #expect(decoded.width == 800)
        #expect(decoded.height == 600)
        #expect(decoded.script == "-- comment")
        #expect(decoded.defaultFont == "Menlo")
        #expect(decoded.webAssetsAllowed == true)
        #expect(decoded.aiContextCloudSharingAllowed == true)
        #expect(decoded.runtimeModeEnabled == true)
        #expect(decoded.deploymentTargets.selectedPlatforms == [.macOS, .iPad])
        #expect(decoded.deploymentTargets.primaryPlatform == .iPad)
        #expect(decoded.deploymentTargets.layoutPolicy == .scaleToFit)
        #expect(decoded.runtimeAISettings.providerPolicy == .appleFoundationModels)
        #expect(decoded.runtimeAISettings.allowRuntimeSideEffectTools)
        #expect(decoded.runtimeAISettings.allowedToolNames == ["set_runtime_variable"])
        #expect(decoded.runtimeAISettings.persistTranscript)
    }

    @Test("Stack with webAssetsAllowed=false round-trips through JSON")
    func stackWithWebAssetsDisabledRoundTrips() throws {
        let original = Stack(
            name: "No Web Assets",
            webAssetsAllowed: false,
            aiContextCloudSharingAllowed: false
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Stack.self, from: encoded)
        #expect(decoded.webAssetsAllowed == false)
        #expect(decoded.aiContextCloudSharingAllowed == false)
        #expect(decoded.runtimeModeEnabled == false)
    }

    // MARK: - Default init

    @Test("Stack default init sets webAssetsAllowed to false")
    func defaultInitWebAssetsAllowedFalse() {
        let stack = Stack()
        #expect(stack.webAssetsAllowed == false)
        #expect(stack.aiContextCloudSharingAllowed == false)
        #expect(stack.runtimeModeEnabled == false)
        #expect(stack.runtimeAISettings.providerPolicy == .automatic)
    }

    @Test("Stack default init sets all other fields to expected defaults")
    func defaultInitAllDefaults() {
        let stack = Stack()
        #expect(stack.name == "Untitled")
        #expect(stack.width == 800)
        #expect(stack.height == 600)
        #expect(stack.script == "")
        #expect(stack.defaultFont == "Apple Braille")
    }

    // MARK: - Missing optional fields fall back gracefully

    @Test("Stack JSON with missing optional name falls back to 'Untitled'")
    func missingNameFallsBackToUntitled() throws {
        let json = """
        {
            "id": "12345678-1234-1234-1234-123456789ABC",
            "networkManifest": { "outboundHostRules": [], "savedListeners": [] }
        }
        """
        let data = json.data(using: .utf8)!
        let stack = try JSONDecoder().decode(Stack.self, from: data)
        #expect(stack.name == "Untitled")
        #expect(stack.width == 800)
        #expect(stack.height == 600)
        #expect(stack.script == "")
        #expect(stack.defaultFont == "Apple Braille")
        #expect(stack.webAssetsAllowed == false)
        #expect(stack.aiContextCloudSharingAllowed == false)
        #expect(stack.runtimeModeEnabled == false)
    }
}
