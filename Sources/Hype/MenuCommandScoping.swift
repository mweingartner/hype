import Foundation

/// Scopes document-mutating NotificationCenter commands to a single document.
///
/// Menu commands post with the focused document's stack id in userInfo;
/// programmatic posters (scripts via doMenu, panels) post their own document's
/// id. A handler accepts a notification only if it targets that handler's
/// document — or, for legacy unscoped posts, only in the key window, so a
/// broadcast can never mutate a background document.
///
/// ## Scoping decision matrix
///
/// | `notificationStackId` | `documentStackId` match | `isKeyDocument` | Result  |
/// |-----------------------|------------------------|-----------------|---------|
/// | matching UUID         | yes                     | any             | true    |
/// | mismatched UUID       | no                      | any             | false   |
/// | nil (legacy)          | n/a                     | true            | true    |
/// | nil (legacy)          | n/a                     | false           | false   |
///
/// The `nil`-id case is the backward-compatibility path: old posts that carry
/// no `userInfo` at all (tests, AX automation, anything that was not yet
/// updated) fall back to key-window-only delivery, which is strictly safer
/// than the current behaviour of firing in every open document simultaneously.
enum MenuCommandScoping {

    /// The userInfo key under which the target stack UUID is stored.
    static let stackIdKey = "hypeTargetStackId"

    /// Build the userInfo dictionary to attach to a scoped notification.
    ///
    /// Returns `nil` when `stackId` is `nil` (the caller has no document
    /// in focus and should not post the notification at all, or is posting
    /// to a global handler that ignores userInfo). The returned dictionary
    /// is non-nil only when a real UUID is provided.
    static func userInfo(stackId: UUID?) -> [AnyHashable: Any]? {
        guard let stackId else { return nil }
        return [stackIdKey: stackId]
    }

    /// Decide whether the receiving view/modifier should handle a notification.
    ///
    /// - Parameters:
    ///   - notificationStackId: The UUID extracted from the notification's
    ///     userInfo (via `stackId(from:)`). Pass `nil` for legacy unscoped
    ///     posts that carry no userInfo.
    ///   - documentStackId: The stack UUID of the document that owns the
    ///     receiving handler.
    ///   - isKeyDocument: Whether the receiving view's window is currently
    ///     the key window. Pass `true` when there is no window context
    ///     (headless tests, single-context hosting, unit tests) so that
    ///     legacy unscoped posts still reach their only subscriber.
    static func shouldHandle(
        notificationStackId: UUID?,
        documentStackId: UUID,
        isKeyDocument: Bool
    ) -> Bool {
        if let id = notificationStackId {
            // Scoped post: accept only if the id matches this document.
            return id == documentStackId
        } else {
            // Legacy unscoped post: accept only in the key window.
            // This is strictly safer than the previous behaviour (which
            // accepted in every open document) — a background document
            // can never be mutated by a broadcast post.
            return isKeyDocument
        }
    }

    /// Extract the target stack UUID from a notification's userInfo.
    ///
    /// Returns `nil` for legacy unscoped posts (no userInfo, or userInfo
    /// that predates the scoping keys).
    static func stackId(from notification: Notification) -> UUID? {
        notification.userInfo?[stackIdKey] as? UUID
    }
}
