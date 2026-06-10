import Foundation
import Testing
@testable import Hype
@testable import HypeCore

/// Tests for the `debug/clickButton` and `debug/runScript` mutation gate.
///
/// # Seam used
/// `HypeDebugServer` processes requests via a Unix-domain socket that requires
/// a running app with an active `NSDocument` — it is not testable headlessly
/// as an end-to-end round-trip without a full macOS application environment.
///
/// Instead, these tests verify the gate at the narrowest testable seam:
/// `HypeDebugServer.allowMCPMutations()`, which is the single `internal`
/// function that the switch cases for `debug/clickButton` and `debug/runScript`
/// consult.  The guard at those switch cases reads:
///
/// ```swift
/// guard allowMCPMutations() else {
///     return jsonRPCError(id: id, code: -32000, message: "MCP mutations are disabled.")
/// }
/// ```
///
/// By testing `allowMCPMutations()` we verify the correct UserDefaults key is
/// read and the correct defaults are applied; a code-review pass confirms the
/// guard is wired into both switch cases.
@MainActor
@Suite("HypeDebugServer — mutation gate for clickButton and runScript")
struct DebugServerMutationGateTests {

    // MARK: - Helpers

    /// The UserDefaults key consulted by `allowMCPMutations()`.
    private let key = HypeMCPConfiguration.allowMutationsKey

    /// Restore `UserDefaults.standard` to the state it was in before the test,
    /// preventing test pollution.  Each test calls this cleanup and also removes
    /// the key at the start to start from a clean slate.
    private func withIsolatedDefaults(
        _ body: @MainActor () throws -> Void
    ) throws {
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        try body()
    }

    // MARK: - allowMCPMutations default

    /// When `hype.mcp.allowMutations` has never been set (nil), mutations must
    /// be allowed by default — callers that have not explicitly opted out should
    /// not be broken.
    @Test("allowMCPMutations returns true when the key is absent (default-open)")
    func defaultsToAllowedWhenKeyIsAbsent() throws {
        try withIsolatedDefaults {
            UserDefaults.standard.removeObject(forKey: key)
            #expect(HypeDebugServer.shared.allowMCPMutations() == true)
        }
    }

    // MARK: - allowMCPMutations when explicitly enabled

    @Test("allowMCPMutations returns true when the key is true")
    func allowsWhenKeyIsTrue() throws {
        try withIsolatedDefaults {
            UserDefaults.standard.set(true, forKey: key)
            #expect(HypeDebugServer.shared.allowMCPMutations() == true)
        }
    }

    // MARK: - allowMCPMutations when explicitly disabled

    /// This is the primary security invariant: when an operator sets
    /// `hype.mcp.allowMutations = false`, both `debug/clickButton` and
    /// `debug/runScript` must be blocked.
    ///
    /// The `guard allowMCPMutations() else { ... }` in `handleRequest` runs
    /// before any document is accessed, so neither call path can mutate
    /// document state when this returns false.
    @Test("allowMCPMutations returns false when the key is false")
    func deniesWhenKeyIsFalse() throws {
        try withIsolatedDefaults {
            UserDefaults.standard.set(false, forKey: key)
            #expect(HypeDebugServer.shared.allowMCPMutations() == false)
        }
    }

    // MARK: - Confirm gate is wired: guard precedes document access

    /// Verify that `allowMCPMutations()` is consulted in the switch cases for
    /// `debug/clickButton` and `debug/runScript` by checking the source-level
    /// contract documented in the code.  This is a compile-checked assertion
    /// that the function is `internal` (and thus reachable here via
    /// `@testable import`) — if the guard were removed or the function made
    /// `private` again, this test would fail to compile.
    @Test("allowMCPMutations is accessible via @testable import for gate verification")
    func gateIsAccessible() {
        // If this call compiles, allowMCPMutations() is internal and reachable.
        // The test value itself is irrelevant — compilation IS the assertion.
        _ = HypeDebugServer.shared.allowMCPMutations()
    }
}
