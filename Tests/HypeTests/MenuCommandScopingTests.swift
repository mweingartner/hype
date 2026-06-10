import Foundation
import Testing
@testable import Hype
@testable import HypeCore

/// Tests for `MenuCommandScoping` — the pure helper that gates which
/// document-level notification handler should accept a posted command.
///
/// These tests exercise the full decision matrix documented in `MenuCommandScoping`
/// and include a regression test for the P0 multi-document multi-fire bug.
@Suite("MenuCommandScoping")
struct MenuCommandScopingTests {

    // MARK: - shouldHandle decision matrix

    @Test("nil stack id + key document → handle (legacy unscoped post in key window)")
    func nilIdKeyDocumentAccepted() {
        #expect(
            MenuCommandScoping.shouldHandle(
                notificationStackId: nil,
                documentStackId: UUID(),
                isKeyDocument: true
            ) == true
        )
    }

    @Test("nil stack id + not key document → skip (legacy unscoped post in background window)")
    func nilIdNotKeyDocumentRejected() {
        #expect(
            MenuCommandScoping.shouldHandle(
                notificationStackId: nil,
                documentStackId: UUID(),
                isKeyDocument: false
            ) == false
        )
    }

    @Test("matching scoped id + key document → handle")
    func matchingIdKeyDocumentAccepted() {
        let id = UUID()
        #expect(
            MenuCommandScoping.shouldHandle(
                notificationStackId: id,
                documentStackId: id,
                isKeyDocument: true
            ) == true
        )
    }

    @Test("matching scoped id + NOT key document → still handle (scoped beats key status)")
    func matchingIdNotKeyDocumentAccepted() {
        // The key invariant: a scoped notification with the right id is
        // accepted even if the window is not currently key. This lets
        // scripts call doMenu("next card") on a background document window.
        let id = UUID()
        #expect(
            MenuCommandScoping.shouldHandle(
                notificationStackId: id,
                documentStackId: id,
                isKeyDocument: false
            ) == true
        )
    }

    @Test("mismatched scoped id + key document → skip (wrong document)")
    func mismatchedIdKeyDocumentRejected() {
        #expect(
            MenuCommandScoping.shouldHandle(
                notificationStackId: UUID(),
                documentStackId: UUID(),
                isKeyDocument: true
            ) == false
        )
    }

    @Test("mismatched scoped id + not key document → skip")
    func mismatchedIdNotKeyDocumentRejected() {
        #expect(
            MenuCommandScoping.shouldHandle(
                notificationStackId: UUID(),
                documentStackId: UUID(),
                isKeyDocument: false
            ) == false
        )
    }

    // MARK: - userInfo round-trip

    @Test("userInfo(stackId:) round-trips through a real Notification")
    func userInfoRoundTrip() throws {
        let id = UUID()
        let info = try #require(MenuCommandScoping.userInfo(stackId: id))

        // Simulate what NotificationCenter delivers.
        let notification = Notification(
            name: .navigateCard,
            object: nil,
            userInfo: info
        )

        let extracted = MenuCommandScoping.stackId(from: notification)
        #expect(extracted == id)
    }

    @Test("userInfo(stackId: nil) returns nil — no dict for unscoped posts")
    func userInfoNilStackIdReturnsNil() {
        #expect(MenuCommandScoping.userInfo(stackId: nil) == nil)
    }

    @Test("stackId(from:) returns nil for a notification with no userInfo")
    func stackIdNilForNoUserInfo() {
        let notification = Notification(name: .navigateCard, object: nil, userInfo: nil)
        #expect(MenuCommandScoping.stackId(from: notification) == nil)
    }

    @Test("stackId(from:) returns nil for a notification with unrelated userInfo")
    func stackIdNilForUnrelatedUserInfo() {
        let notification = Notification(
            name: .navigateCard,
            object: nil,
            userInfo: ["profileId": "some-profile"]
        )
        #expect(MenuCommandScoping.stackId(from: notification) == nil)
    }

    // MARK: - P0 regression: two stacks open, notification targets only one

    /// Regression test for the multi-document multi-fire bug.
    ///
    /// Scenario: stack A is focused. A scoped `.deleteCurrentCard` post
    /// carries stack A's id. Stack B's handler (simulated here by its
    /// `shouldHandle` call) must reject the notification even when B's
    /// window happens to be key — scoped id beats key-window status.
    @Test("P0 regression: scoped post for stack A is rejected by stack B even when B is key")
    func scopedPostTargetsOnlyOneDocument() {
        let stackAId = UUID()
        let stackBId = UUID()

        // Simulate a menu post that carries stack A's id.
        let userInfo = MenuCommandScoping.userInfo(stackId: stackAId)
        let notification = Notification(name: .deleteCurrentCard, object: nil, userInfo: userInfo)
        let notificationStackId = MenuCommandScoping.stackId(from: notification)

        // Stack A's handler accepts.
        #expect(
            MenuCommandScoping.shouldHandle(
                notificationStackId: notificationStackId,
                documentStackId: stackAId,
                isKeyDocument: false  // A might not be key; still accepted
            ) == true
        )

        // Stack B's handler rejects — even if B's window is key.
        #expect(
            MenuCommandScoping.shouldHandle(
                notificationStackId: notificationStackId,
                documentStackId: stackBId,
                isKeyDocument: true  // B is key window, but scoped id wins
            ) == false
        )
    }
}
