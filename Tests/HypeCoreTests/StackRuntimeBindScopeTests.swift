import Testing
import Foundation
@testable import HypeCore
#if canImport(Network)
import Network
#endif
#if canImport(Darwin)
import Darwin
#endif

// MARK: - Shared helpers (mirrored from StackRuntimeAsyncTests discipline)

// Serialization lock: same reasoning as in StackRuntimeAsyncTests — prevents
// two concurrent test threads from racing to claim the same loopback port
// in the OS-assigned port space.
private let _bindScopePortLock = NSLock()

/// Ask the kernel for an available loopback port by binding a probe socket to
/// port 0, reading the OS-assigned port, and closing the socket immediately.
/// Must be called while holding `_bindScopePortLock` (or its equivalent).
private func freeBoundLoopbackPort() -> Int {
    _bindScopePortLock.lock()
    defer { _bindScopePortLock.unlock() }

    let fd = socket(AF_INET, SOCK_STREAM, 0)
    precondition(fd >= 0, "socket() failed")
    defer { close(fd) }

    var reuseAddr: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))

    var addr = sockaddr_in()
    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = in_port_t(0).bigEndian
    addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

    let bindResult = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    precondition(bindResult == 0, "bind() failed")

    var bound = sockaddr_in()
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let nameResult = withUnsafeMutablePointer(to: &bound) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            getsockname(fd, $0, &length)
        }
    }
    precondition(nameResult == 0, "getsockname() failed")
    return Int(UInt16(bigEndian: bound.sin_port))
}

/// Convenience: build a runtime configuration that uses an isolated
/// UserDefaults suite so test approvals never bleed into production or
/// each other.
private func bindScopeRuntimeConfiguration() -> StackRuntimeConfiguration {
    StackRuntimeConfiguration(
        permissionStore: UserDefaultsNetworkPermissionStore(
            defaults: UserDefaults(suiteName: "StackRuntimeBindScopeTests.\(UUID().uuidString)")!
        )
    )
}

/// Enumerate all non-loopback, non-link-local IPv4 addresses on the machine
/// using `getifaddrs`.  Returns an empty array when no such interface exists
/// (e.g., a machine with only loopback networking active — common in CI).
private func nonLoopbackIPv4Addresses() -> [String] {
    var result: [String] = []
    var ifap: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifap) == 0, let base = ifap else { return [] }
    defer { freeifaddrs(base) }

    var cursor: UnsafeMutablePointer<ifaddrs>? = base
    while let iface = cursor {
        defer { cursor = iface.pointee.ifa_next }
        guard let addrPtr = iface.pointee.ifa_addr,
              addrPtr.pointee.sa_family == sa_family_t(AF_INET) else { continue }

        let sinPtr = addrPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0 }
        let addrBytes = sinPtr.pointee.sin_addr.s_addr

        // Skip loopback (127.x.x.x).
        let firstOctet = addrBytes & 0xFF
        if firstOctet == 127 { continue }

        // Skip link-local (169.254.x.x).
        let secondOctet = (addrBytes >> 8) & 0xFF
        if firstOctet == 169 && secondOctet == 254 { continue }

        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        var sin = sinPtr.pointee
        if inet_ntop(AF_INET, &sin.sin_addr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil {
            result.append(String(cString: buf))
        }
    }
    return result
}

/// Wait up to `timeout` seconds for `condition` to be true, polling every 50 ms.
private func waitUntilCondition(
    timeout: TimeInterval = 10,
    condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    return false
}

// MARK: - Bind-scope integration tests
//
// .serialized because each test binds a real NWListener on a port obtained
// via freeBoundLoopbackPort() — the TOCTOU window between port discovery
// and the listener start is small, but running tests in parallel widens
// it enough to cause spurious port collisions under load. Serialization
// also matches the discipline established in StackRuntimeAsyncTests.

@Suite("StackRuntime — bindScope enforces network interface restriction", .serialized)
struct StackRuntimeBindScopeTests {

    // MARK: - Test (a): loopback listener accepts a connection to 127.0.0.1

    /// Functional regression: a listener with `.loopback` bindScope accepts
    /// a real TCP connection from 127.0.0.1.  This verifies that the new
    /// `parameters.requiredLocalEndpoint` assignment does not break the
    /// existing autoStart flow.
    #if canImport(Network)
    @Test("loopback-scoped listener accepts a connection on 127.0.0.1")
    func loopbackListenerAcceptsLocalhost() async throws {
        let port = freeBoundLoopbackPort()
        let listener = SavedNetworkListener(
            name: "Scope Test TCP",
            transport: .tcp,
            port: port,
            host: "127.0.0.1",
            bindScope: .loopback,
            callbackMessage: "scopeEvent",
            autoStart: true
        )
        let (doc, _, _, fieldID) = makeScopeDocument(
            stackScript: """
            on scopeEvent connId, event
              if event is "data" then
                put the body of connection connId into field "output"
              end if
            end scopeEvent
            """,
            savedListeners: [listener]
        )

        let runtime = await StackRuntimeRegistry.shared.runtime(
            for: doc,
            configuration: bindScopeRuntimeConfiguration()
        )
        await runtime.syncDocument(doc)

        // Give the listener a moment to transition to .ready state before
        // attempting the connection.  Tight poll so the test stays fast.
        let listenerReady = await waitUntilCondition {
            let snapshot = await runtime.statusSnapshot()
            return snapshot.listeners.contains { $0.state == "ready" }
        }
        #expect(listenerReady, "listener should reach .ready before the connection attempt")

        // Connect from 127.0.0.1 — this MUST succeed for a .loopback listener.
        let client = NWConnection(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: UInt16(port))!,
            using: .tcp
        )
        defer { client.cancel() }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            client.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    client.stateUpdateHandler = nil
                    cont.resume()
                case .failed(let e):
                    client.stateUpdateHandler = nil
                    cont.resume(throwing: e)
                default:
                    break
                }
            }
            client.start(queue: .global())
        }

        // Send data so the stack's callback fires and we can verify end-to-end.
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            client.send(content: Data("loopback-probe".utf8), completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }

        let received = await waitUntilCondition {
            let updated = await runtime.currentDocument()
            return Self.outputText(from: updated, fieldID: fieldID) == "loopback-probe"
        }

        await StackRuntimeRegistry.shared.shutdown(stackID: doc.stack.id)
        #expect(received, "loopback listener must deliver data sent from 127.0.0.1")
    }

    // MARK: - Test (b): loopback listener REFUSES a non-loopback local IPv4

    /// Security regression: a listener bound with `.loopback` scope must NOT
    /// be reachable via a non-loopback local IPv4 address (e.g., a Wi-Fi or
    /// Ethernet interface address).
    ///
    /// If the machine has no non-loopback IPv4 address (common in CI
    /// environments that only expose loopback), this test returns early with
    /// a diagnostic comment rather than failing — the loopback-only fix is
    /// already exercised by the companion test above.
    @Test("loopback-scoped listener is unreachable from a non-loopback local IPv4")
    func loopbackListenerRefusesLANAddress() async throws {
        // Enumerate non-loopback interfaces.  If there are none, we cannot
        // probe, so skip gracefully rather than failing.
        let lanAddresses = nonLoopbackIPv4Addresses()
        guard let lanIP = lanAddresses.first else {
            // Machine has no non-loopback IPv4; the isolation property cannot
            // be probed here.  This is not a test failure — the CI environment
            // legitimately may have only loopback networking.
            return
        }

        let port = freeBoundLoopbackPort()
        let listener = SavedNetworkListener(
            name: "Scope Isolation Test",
            transport: .tcp,
            port: port,
            host: "127.0.0.1",
            bindScope: .loopback,
            callbackMessage: "isolationEvent",
            autoStart: true
        )
        let (doc, _, _, _) = makeScopeDocument(savedListeners: [listener])

        let runtime = await StackRuntimeRegistry.shared.runtime(
            for: doc,
            configuration: bindScopeRuntimeConfiguration()
        )
        await runtime.syncDocument(doc)

        // Wait for listener to reach .ready so we know it is actually bound.
        let listenerReady = await waitUntilCondition {
            let snapshot = await runtime.statusSnapshot()
            return snapshot.listeners.contains { $0.state == "ready" }
        }
        #expect(listenerReady, "listener must reach .ready before the LAN probe")

        // Attempt a TCP connection to the listener via the LAN IP.
        // A correctly scoped loopback listener must NOT reach .ready on this
        // connection — the OS should refuse or time out on the LAN interface.
        let probeResult = await lanConnectionAttempt(host: lanIP, port: port, timeout: 2.0)

        await StackRuntimeRegistry.shared.shutdown(stackID: doc.stack.id)

        // The connection from the LAN IP should fail (NWError.posix(.ECONNREFUSED)
        // or a similar OS-level rejection).  Any non-ready terminal state is
        // acceptable as evidence of isolation.
        #expect(
            probeResult == false,
            "loopback-scoped listener on 127.0.0.1:\(port) must be unreachable from LAN IP \(lanIP)"
        )
    }

    // MARK: - Test (c): .any-scope listener accepts 127.0.0.1 (no regression)

    /// Verify that a listener with `.any` bindScope still accepts a loopback
    /// connection after the bindScope fix.  The fix must not accidentally
    /// restrict wildcard-scope listeners.
    @Test("any-scoped listener still accepts a connection on 127.0.0.1")
    func anyListenerAcceptsLocalhost() async throws {
        let port = freeBoundLoopbackPort()
        let listener = SavedNetworkListener(
            name: "Any-Scope Test",
            transport: .tcp,
            port: port,
            host: "0.0.0.0",
            bindScope: .any,
            callbackMessage: "anyEvent",
            autoStart: true
        )
        let (doc, _, _, fieldID) = makeScopeDocument(
            stackScript: """
            on anyEvent connId, event
              if event is "data" then
                put the body of connection connId into field "output"
              end if
            end anyEvent
            """,
            savedListeners: [listener]
        )

        let runtime = await StackRuntimeRegistry.shared.runtime(
            for: doc,
            configuration: bindScopeRuntimeConfiguration()
        )
        await runtime.syncDocument(doc)

        let listenerReady = await waitUntilCondition {
            let snapshot = await runtime.statusSnapshot()
            return snapshot.listeners.contains { $0.state == "ready" }
        }
        #expect(listenerReady, "any-scope listener should reach .ready")

        let client = NWConnection(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: UInt16(port))!,
            using: .tcp
        )
        defer { client.cancel() }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            client.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    client.stateUpdateHandler = nil
                    cont.resume()
                case .failed(let e):
                    client.stateUpdateHandler = nil
                    cont.resume(throwing: e)
                default:
                    break
                }
            }
            client.start(queue: .global())
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            client.send(content: Data("any-probe".utf8), completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }

        let received = await waitUntilCondition {
            let updated = await runtime.currentDocument()
            return Self.outputText(from: updated, fieldID: fieldID) == "any-probe"
        }

        await StackRuntimeRegistry.shared.shutdown(stackID: doc.stack.id)
        #expect(received, "any-scope listener must accept loopback connections (no regression)")
    }

    #endif // canImport(Network)

    // MARK: - Private helpers

    /// Build a minimal `HypeDocument` suitable for listener scope testing.
    /// Mirrors `makeRuntimeDocument` in `StackRuntimeAsyncTests`.
    private func makeScopeDocument(
        stackScript: String = "",
        savedListeners: [SavedNetworkListener] = []
    ) -> (HypeDocument, UUID, UUID, UUID) {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        doc.stack.networkManifest = StackNetworkManifest(
            outboundHostRules: [],
            savedListeners: savedListeners
        )
        doc.stack.script = stackScript

        var button = Part(partType: .button, cardId: cardId, name: "Runner")
        button.script = ""
        doc.addPart(button)

        let field = Part(partType: .field, cardId: cardId, name: "output")
        doc.addPart(field)

        return (doc, cardId, button.id, field.id)
    }

    private static func outputText(from document: HypeDocument, fieldID: UUID) -> String {
        document.parts.first(where: { $0.id == fieldID })?.textContent ?? ""
    }

    #if canImport(Network)
    /// Attempt a TCP connection to `host:port` with a `timeout` deadline.
    /// Returns `true` if the connection reaches `.ready`; `false` if it fails
    /// or times out.  A `.false` result is the expected outcome for a
    /// loopback-scoped listener probed from a non-loopback address.
    private func lanConnectionAttempt(
        host: String,
        port: Int,
        timeout: TimeInterval
    ) async -> Bool {
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: UInt16(port))!,
            using: .tcp
        )
        defer { connection.cancel() }

        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let resolver = OnceResolver(cont)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.stateUpdateHandler = nil
                    resolver.resolve(true)
                case .failed, .cancelled:
                    connection.stateUpdateHandler = nil
                    resolver.resolve(false)
                default:
                    break
                }
            }
            connection.start(queue: .global())

            // Enforce the caller's timeout: if neither .ready nor .failed
            // fires within the deadline, treat the connection as refused.
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                connection.cancel()
                resolver.resolve(false)
            }
        }
    }
    #endif
}

/// Resumes a continuation exactly once across racing Network callbacks
/// (state handler vs. timeout); lock-guarded so the racing closures can be
/// `@Sendable` under strict concurrency.
private final class OnceResolver: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func resolve(_ success: Bool) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(returning: success)
    }
}
