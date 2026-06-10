#if canImport(AppKit)
import Foundation
import AppKit
import HypeCore

/// An `NSAlert`-based `NetworkPermissionPrompting` implementation for production
/// Hype builds on macOS.
///
/// # Approval contract
/// The prompter is responsible ONLY for asking the user whether to allow a
/// single network access.  It returns `true` (allow) or `false` (deny).
/// **The prompter does NOT persist the decision** — that is the responsibility of
/// `UserDefaultsNetworkPermissionStore`, which the `StackRuntime` calls
/// immediately after the prompter returns `true`.  This matches the existing
/// `ensureApproved` contract in `StackRuntime`:
///
/// ```
/// let approved = await approvalPrompter.requestApproval(for: access)
/// guard approved else { throw .permissionDenied }
/// permissionStore.approve(access)   // ← store persists, not the prompter
/// ```
///
/// # Actor safety
/// `requestApproval` is called from whatever actor the runtime is on at the
/// time (typically the `StackRuntime` actor).  This implementation hops to
/// `@MainActor` before presenting the `NSAlert`, satisfying AppKit's
/// requirement that all UI runs on the main thread.
///
/// # Security note (for reviewers)
/// This prompter is wired into production `runtimeConfiguration()` call sites
/// (both `MainContentView` and `CardCanvasView`).  The `AllowAllNetworkPermissionPrompter`
/// default in `StackRuntimeConfiguration.init` is intentionally left intact so
/// that headless test harnesses that construct `StackRuntimeConfiguration` without
/// an explicit prompter continue to work without UI.  **App code must always pass
/// an explicit prompter** — see the doc-comment on
/// `StackRuntimeConfiguration.approvalPrompter` for the invariant.
public struct AppKitNetworkPermissionPrompter: NetworkPermissionPrompting, Sendable {

    /// The display name of the stack that is requesting network access.
    /// Shown in the alert so the user understands which stack is asking.
    private let stackName: String

    /// Create a prompter tied to the given stack name.
    ///
    /// Pass the human-readable `.stack.name` value from the `HypeDocument`
    /// (or a suitable fallback) so the alert message can name the requesting
    /// stack.
    public init(stackName: String) {
        self.stackName = stackName
    }

    // MARK: - NetworkPermissionPrompting

    /// Present an `NSAlert` on the main actor asking the user to allow or deny
    /// a network access for the named stack.
    ///
    /// Returns `true` if the user clicks **Allow**, `false` otherwise.
    /// The runtime caller persists the decision via
    /// `UserDefaultsNetworkPermissionStore.approve(_:)` when this returns `true`.
    public func requestApproval(for access: NetworkAccessRequest) async -> Bool {
        await MainActor.run {
            Self.showAlert(for: access, stackName: stackName)
        }
    }

    // MARK: - Private

    @MainActor
    private static func showAlert(
        for access: NetworkAccessRequest,
        stackName: String
    ) -> Bool {
        let alert = NSAlert()

        // Title — short, action-oriented.
        alert.messageText = "Allow Network Access?"

        // Body — name the stack, the endpoint, and the kind of access.
        let directionLabel: String
        switch access.kind {
        case .inboundListener:
            directionLabel = "listen for incoming connections on"
        case .outboundRequest, .outboundConnection:
            directionLabel = "connect to"
        }

        // Format: scheme://host:port, e.g. "tcp://127.0.0.1:9000"
        let endpointDescription: String
        if access.port > 0 {
            endpointDescription = "\(access.scheme)://\(access.host):\(access.port)"
        } else {
            endpointDescription = "\(access.scheme)://\(access.host)"
        }

        let displayName = stackName.isEmpty ? "A Hype stack" : "\"\(stackName)\""
        alert.informativeText = """
        \(displayName) wants to \(directionLabel) \(endpointDescription).

        This allows the stack's scripts to communicate over the network. \
        You can revoke this permission by clearing the stack's network approvals \
        in Hype's preferences.
        """

        // Buttons — "Allow" is the first button (NSAlert.runModal returns
        // NSApplication.ModalResponse.alertFirstButtonReturn for it).
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Deny")

        alert.alertStyle = .warning

        // NSAlert.runModal() blocks the main thread until the user dismisses;
        // this is intentional for a synchronous permission gate.
        let response = alert.runModal()
        return response == .alertFirstButtonReturn
    }
}

#endif
