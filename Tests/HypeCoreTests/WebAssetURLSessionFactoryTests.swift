import Testing
import Foundation
@testable import HypeCore

/// Tests for `WebAssetURLSessionFactory`, `ssrfError`, and `boundedData`.
/// Covers Security Findings 1, D, and N-1/N-5.
@Suite("WebAssetURLSessionFactory — SSRF and HTTPS enforcement")
struct WebAssetURLSessionFactoryTests {

    // MARK: - ssrfError helper tests (pure unit tests, no network)

    @Test("ssrfError blocks IPv4 loopback 127.0.0.1")
    func ssrfBlocksLoopbackIPv4() {
        let result = ssrfError(for: "127.0.0.1", url: URL(string: "https://example.com")!)
        #expect(result != nil)
        if case .ssrfBlocked = result! { } else {
            Issue.record("Expected ssrfBlocked, got \(String(describing: result))")
        }
    }

    @Test("ssrfError blocks link-local 169.254.169.254 (AWS metadata endpoint)")
    func ssrfBlocksLinkLocalIPv4() {
        let result = ssrfError(for: "169.254.169.254", url: URL(string: "https://victim.com")!)
        #expect(result != nil)
        if case .ssrfBlocked = result! { } else {
            Issue.record("Expected ssrfBlocked, got \(String(describing: result))")
        }
    }

    @Test("ssrfError blocks 10.x.x.x private IPv4")
    func ssrfBlocksPrivateIPv4_10() {
        let result = ssrfError(for: "10.0.0.1", url: URL(string: "https://example.com")!)
        #expect(result != nil)
    }

    @Test("ssrfError blocks 172.16.x.x private IPv4 (start of range)")
    func ssrfBlocksPrivateIPv4_172_16() {
        let result = ssrfError(for: "172.16.0.1", url: URL(string: "https://example.com")!)
        #expect(result != nil)
    }

    @Test("ssrfError blocks 172.31.x.x private IPv4 (end of range)")
    func ssrfBlocksPrivateIPv4_172_31() {
        let result = ssrfError(for: "172.31.255.255", url: URL(string: "https://example.com")!)
        #expect(result != nil)
    }

    @Test("ssrfError does NOT block 172.15.x.x (just outside private range)")
    func ssrfAllows172_15() {
        let result = ssrfError(for: "172.15.255.255", url: URL(string: "https://example.com")!)
        #expect(result == nil)
    }

    @Test("ssrfError does NOT block 172.32.x.x (just outside private range)")
    func ssrfAllows172_32() {
        let result = ssrfError(for: "172.32.0.1", url: URL(string: "https://example.com")!)
        #expect(result == nil)
    }

    @Test("ssrfError blocks 192.168.x.x private IPv4")
    func ssrfBlocksPrivateIPv4_192_168() {
        let result = ssrfError(for: "192.168.1.1", url: URL(string: "https://example.com")!)
        #expect(result != nil)
    }

    @Test("ssrfError blocks 0.x.x.x null range")
    func ssrfBlocksNullRange() {
        let result = ssrfError(for: "0.0.0.0", url: URL(string: "https://example.com")!)
        #expect(result != nil)
    }

    @Test("ssrfError blocks 100.64.x.x shared address space")
    func ssrfBlocksSharedAddressSpace() {
        let result = ssrfError(for: "100.64.0.1", url: URL(string: "https://example.com")!)
        #expect(result != nil)
    }

    @Test("ssrfError does NOT block a routable public IPv4 address")
    func ssrfAllowsPublicIPv4() {
        // 8.8.8.8 is Google's DNS — a public routable address
        let result = ssrfError(for: "8.8.8.8", url: URL(string: "https://example.com")!)
        #expect(result == nil)
    }

    // MARK: - IPv6 SSRF checks

    @Test("ssrfError blocks IPv6 loopback ::1")
    func ssrfBlocksIPv6Loopback() {
        let result = ssrfError(for: "::1", url: URL(string: "https://example.com")!)
        #expect(result != nil)
    }

    @Test("ssrfError blocks IPv6 link-local fe80::1")
    func ssrfBlocksIPv6LinkLocal() {
        let result = ssrfError(for: "fe80::1", url: URL(string: "https://example.com")!)
        #expect(result != nil)
    }

    @Test("ssrfError blocks IPv6 ULA fc00::1")
    func ssrfBlocksIPv6ULA_fc() {
        let result = ssrfError(for: "fc00::1", url: URL(string: "https://example.com")!)
        #expect(result != nil)
    }

    @Test("ssrfError blocks IPv6 ULA fd00::1")
    func ssrfBlocksIPv6ULA_fd() {
        let result = ssrfError(for: "fd00::1", url: URL(string: "https://example.com")!)
        #expect(result != nil)
    }

    @Test("ssrfError does NOT block a public IPv6 address (2001:db8::1)")
    func ssrfAllowsPublicIPv6() {
        // 2001:db8::/32 is documentation range — treated as public for this test
        // Using a valid globally-routable address
        let result = ssrfError(for: "2607:f8b0:4004:c1b::66", url: URL(string: "https://example.com")!)
        #expect(result == nil)
    }

    // MARK: - IPv4-mapped IPv6 SSRF checks (Security Finding D)

    @Test("ssrfError blocks IPv4-mapped loopback ::ffff:127.0.0.1 (Finding D)")
    func ssrfBlocksIPv4MappedLoopback() {
        let result = ssrfError(for: "::ffff:127.0.0.1", url: URL(string: "https://example.com")!)
        #expect(result != nil, "::ffff:127.0.0.1 should be SSRF-blocked (Security Finding D)")
    }

    @Test("ssrfError blocks IPv4-mapped private ::ffff:10.0.0.1 (Finding D)")
    func ssrfBlocksIPv4MappedPrivate() {
        let result = ssrfError(for: "::ffff:10.0.0.1", url: URL(string: "https://example.com")!)
        #expect(result != nil, "::ffff:10.0.0.1 should be SSRF-blocked (Security Finding D)")
    }

    @Test("ssrfError blocks IPv4-mapped AWS metadata ::ffff:169.254.169.254 (Finding D)")
    func ssrfBlocksIPv4MappedLinkLocal() {
        let result = ssrfError(for: "::ffff:169.254.169.254", url: URL(string: "https://example.com")!)
        #expect(result != nil, "::ffff:169.254.169.254 should be SSRF-blocked (Security Finding D)")
    }

    @Test("ssrfError blocks IPv4-mapped private ::ffff:192.168.1.1 (Finding D)")
    func ssrfBlocksIPv4MappedClass_C() {
        let result = ssrfError(for: "::ffff:192.168.1.1", url: URL(string: "https://example.com")!)
        #expect(result != nil)
    }

    @Test("ssrfError allows IPv4-mapped public ::ffff:8.8.8.8")
    func ssrfAllowsIPv4MappedPublic() {
        let result = ssrfError(for: "::ffff:8.8.8.8", url: URL(string: "https://example.com")!)
        #expect(result == nil)
    }

    // MARK: - Empty / unparseable remote address

    @Test("ssrfError returns nil for empty string (fails parse, no block)")
    func ssrfEmptyStringReturnsNil() {
        let result = ssrfError(for: "", url: URL(string: "https://example.com")!)
        #expect(result == nil)
    }

    @Test("ssrfError returns nil for a hostname (not an IP address)")
    func ssrfHostnameReturnsNil() {
        // Hostnames are not blocked by ssrfError — only resolved IP addresses are.
        let result = ssrfError(for: "localhost", url: URL(string: "https://localhost")!)
        #expect(result == nil)
    }

    // MARK: - boundedData HTTPS enforcement (Security Finding N-5)

    @Test("boundedData rejects HTTP URL with httpOnly error before opening socket")
    func boundedDataRejectsHTTP() async throws {
        let factory = WebAssetURLSessionFactory()
        let session = factory.makeProviderSession()
        var request = URLRequest(url: URL(string: "http://example.com/image.png")!)
        request.httpMethod = "GET"

        await #expect(throws: WebAssetSearchError.self) {
            _ = try await session.boundedData(for: request)
        }
    }

    @Test("boundedData rejects HTTP URL — verifies the error is specifically httpOnly")
    func boundedDataHTTPIsHttpOnlyError() async throws {
        let factory = WebAssetURLSessionFactory()
        let session = factory.makeProviderSession()
        var request = URLRequest(url: URL(string: "http://example.com/asset.png")!)
        request.httpMethod = "GET"

        do {
            _ = try await session.boundedData(for: request)
            Issue.record("Expected error to be thrown but call succeeded")
        } catch let error as WebAssetSearchError {
            if case .httpOnly = error { /* correct */ } else {
                Issue.record("Expected httpOnly, got \(error)")
            }
        }
    }

    // MARK: - Factory session creation (smoke tests)

    @Test("makeProviderSession returns a URLSession with a delegate")
    func makeProviderSessionHasDelegate() {
        let factory = WebAssetURLSessionFactory()
        let session = factory.makeProviderSession()
        #expect(session.delegate != nil)
    }

    @Test("makeDownloadSession returns a URLSession with a delegate")
    func makeDownloadSessionHasDelegate() {
        let factory = WebAssetURLSessionFactory()
        let session = factory.makeDownloadSession()
        #expect(session.delegate != nil)
    }

    @Test("makeProviderSession delegate is WebAssetDownloadDelegate")
    func makeProviderSessionDelegateType() {
        let factory = WebAssetURLSessionFactory()
        let session = factory.makeProviderSession()
        #expect(session.delegate is WebAssetDownloadDelegate)
    }

    @Test("makeDownloadSession delegate is WebAssetDownloadDelegate")
    func makeDownloadSessionDelegateType() {
        let factory = WebAssetURLSessionFactory()
        let session = factory.makeDownloadSession()
        #expect(session.delegate is WebAssetDownloadDelegate)
    }

    // NOTE: The fatalError path in boundedData (calling it on a session without
    // a WebAssetDownloadDelegate) is intentionally untested. Swift's `fatalError`
    // terminates the process and cannot be caught by Swift Testing's `#expect(throws:)`.
    // The security guarantee is documented in the source and covered by code review:
    // any call site that uses URLSession.shared.boundedData would crash immediately
    // in debug/test builds, making the misconfiguration impossible to ship silently.

    // MARK: - Concurrent dispatch (lock coverage smoke test)

    @Test("concurrent factory calls do not crash (lock coverage)")
    func concurrentFactoryCallsNoCrash() async {
        let factory = WebAssetURLSessionFactory()
        // Fire off multiple concurrent factory calls to exercise the locking paths.
        // Each call creates a fresh session — we're testing that the factory itself
        // is safe to call from concurrent callers.
        await withTaskGroup(of: URLSession.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    factory.makeProviderSession()
                }
            }
            for await _ in group { /* discard */ }
        }
        // If we get here without crashing, the test passes.
    }

    @Test("concurrent download sessions do not crash (lock coverage)")
    func concurrentDownloadSessionsNoCrash() async {
        let factory = WebAssetURLSessionFactory()
        await withTaskGroup(of: URLSession.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    factory.makeDownloadSession()
                }
            }
            for await _ in group { /* discard */ }
        }
    }
}
