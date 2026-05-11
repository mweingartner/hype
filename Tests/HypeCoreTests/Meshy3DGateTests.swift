import Foundation
import Testing
@testable import HypeCore

/// Tests for `Meshy3DGate.status(for:keyIsSet:)`.
///
/// The gate is a pure function of the document's `meshyEnabled` flag and a
/// pre-fetched `keyIsSet` Bool — these tests verify the decision logic
/// without touching the real Keychain.
@Suite("Meshy3DGate")
struct Meshy3DGateTests {

    private func makeDocument(meshyEnabled: Bool) -> HypeDocument {
        var stack = Stack()
        stack.meshyEnabled = meshyEnabled
        return HypeDocument(stack: stack)
    }

    // MARK: (a) .ready when stack enabled AND key present

    @Test(".ready when stack.meshyEnabled true and keyIsSet true")
    func readyWhenEnabledAndKeySet() {
        let doc = makeDocument(meshyEnabled: true)
        let status = Meshy3DGate.status(for: doc, keyIsSet: true)
        #expect(status == .ready)
    }

    // MARK: (b) .stackDisabled when stack not enabled

    @Test(".stackDisabled when stack.meshyEnabled false")
    func stackDisabledWhenNotEnabled() {
        let doc = makeDocument(meshyEnabled: false)
        let status = Meshy3DGate.status(for: doc, keyIsSet: true)
        #expect(status == .stackDisabled)
    }

    @Test(".stackDisabled takes precedence over missing key")
    func stackDisabledTakesPrecedence() {
        let doc = makeDocument(meshyEnabled: false)
        let status = Meshy3DGate.status(for: doc, keyIsSet: false)
        #expect(status == .stackDisabled)
    }

    // MARK: (c) .apiKeyMissing when key absent but stack enabled

    @Test(".apiKeyMissing when stack enabled but key not set")
    func apiKeyMissingWhenKeyAbsent() {
        let doc = makeDocument(meshyEnabled: true)
        let status = Meshy3DGate.status(for: doc, keyIsSet: false)
        #expect(status == .apiKeyMissing)
    }
}
