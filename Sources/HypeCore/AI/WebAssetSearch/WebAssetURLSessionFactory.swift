import Foundation

// MARK: - WebAssetURLSessionFactory

/// Builds hardened `URLSession` instances for web-asset provider and download calls.
///
/// All sessions produced by this factory enforce:
/// - HTTPS-only (HTTP rejected before URLSession dispatch)
/// - Redirect blocking (all redirects denied at the delegate layer)
/// - Resolved-IP SSRF defense (loopback / private / link-local ranges blocked)
/// - 50 MB per-asset byte ceiling (task cancelled by delegate when exceeded)
public struct WebAssetURLSessionFactory: Sendable {

    /// Optional URLProtocol classes injected into sessions for testing.
    /// In production this is always nil (no protocol injection).
    /// In test targets, use `WebAssetURLSessionFactory(testProtocolClasses: [MockURLProtocol.self])`
    /// to intercept network requests without changing production security guarantees.
    @_spi(Testing) public let testProtocolClasses: [AnyClass]?

    public init() {
        self.testProtocolClasses = nil
    }

    /// Testing seam: inject custom URLProtocol classes into sessions for unit tests.
    /// Only available to test targets via `@_spi(Testing)`. Not callable from
    /// production code (the `@_spi` attribute prevents accidental use outside tests).
    @_spi(Testing) public init(testProtocolClasses: [AnyClass]) {
        self.testProtocolClasses = testProtocolClasses
    }

    /// A session suitable for search/metadata API calls (provider endpoints).
    public func makeProviderSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.httpAdditionalHeaders = ["User-Agent": "Hype/1.0 (https://hype.app; webAssets)"]
        if let classes = testProtocolClasses {
            config.protocolClasses = classes
        }
        let delegate = WebAssetDownloadDelegate()
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    /// A session suitable for downloading image bytes (download endpoint).
    public func makeDownloadSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        config.httpAdditionalHeaders = ["User-Agent": "Hype/1.0 (https://hype.app; webAssets)"]
        if let classes = testProtocolClasses {
            config.protocolClasses = classes
        }
        let delegate = WebAssetDownloadDelegate()
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }
}

// MARK: - Delegate

/// Internal URLSession delegate that enforces byte ceiling, redirect blocking,
/// and resolved-IP SSRF defense for all web-asset sessions.
///
/// Thread-safety: ALL reads and writes to `bytesByTask` and `cancellationReason`
/// go through `lock.withLock { ... }`. The `@unchecked Sendable` conformance is
/// NOT a license to skip locking on reads — every read site is inside a lock block.
final class WebAssetDownloadDelegate: NSObject,
    URLSessionDataDelegate, URLSessionTaskDelegate, @unchecked Sendable {

    // Per-task byte counter. ALL reads AND writes go through `lock`.
    private var bytesByTask: [Int: Int64] = [:]
    // Per-task cancellation reason. ALL reads AND writes go through `lock`.
    private var cancellationReason: [Int: WebAssetSearchError] = [:]
    // Per-task accumulated response data. ALL reads AND writes go through `lock`.
    private var dataByTask: [Int: Data] = [:]
    // Per-task saved response. ALL reads AND writes go through `lock`.
    private var responseByTask: [Int: URLResponse] = [:]
    // Per-task continuation. ALL reads AND writes go through `lock`.
    private var continuationByTask: [Int: CheckedContinuation<(Data, URLResponse), Error>] = [:]

    private let lock = NSLock()

    static let maxBytesPerAsset: Int64 = 50 * 1024 * 1024  // 50 MB

    // MARK: - Async entry point

    /// Perform a hardened data fetch. Enforces SSRF, redirect blocking, and the
    /// byte ceiling. Throws `WebAssetSearchError` on any policy violation.
    func fetch(request: URLRequest, session: URLSession) async throws -> (Data, URLResponse) {
        return try await withCheckedThrowingContinuation { cont in
            let task = session.dataTask(with: request)
            let tid = task.taskIdentifier
            lock.withLock {
                continuationByTask[tid] = cont
                bytesByTask[tid] = 0
                dataByTask[tid] = Data()
            }
            task.resume()
        }
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        let tid = dataTask.taskIdentifier

        // Validate HTTPS
        if let http = response as? HTTPURLResponse,
           let url = http.url,
           url.scheme?.lowercased() != "https" {
            let err = WebAssetSearchError.httpOnly(url)
            lock.withLock { cancellationReason[tid] = err }
            completionHandler(.cancel)
            return
        }

        // Store response for later use
        lock.withLock { responseByTask[tid] = response }

        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        let tid = dataTask.taskIdentifier
        var shouldCancel = false

        lock.withLock {
            dataByTask[tid, default: Data()].append(data)
            bytesByTask[tid, default: 0] += Int64(data.count)
            let total = bytesByTask[tid]!
            if total > Self.maxBytesPerAsset {
                let url = dataTask.originalRequest?.url ?? URL(string: "https://unknown")!
                let err = WebAssetSearchError.payloadTooLarge(url, bytes: total)
                // Only set if not already set by a prior policy violation
                if cancellationReason[tid] == nil {
                    cancellationReason[tid] = err
                }
                shouldCancel = true
            }
        }

        if shouldCancel {
            dataTask.cancel()
        }
    }

    // MARK: - URLSessionTaskDelegate

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Block ALL redirects — SSRF defense.
        let tid = task.taskIdentifier
        let from = task.originalRequest?.url ?? URL(string: "https://unknown")!
        let to = request.url ?? URL(string: "https://unknown")!
        let err = WebAssetSearchError.redirectBlocked(from: from, to: to)
        lock.withLock {
            if cancellationReason[tid] == nil {
                cancellationReason[tid] = err
            }
        }
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        // SSRF resolved-IP check. Runs on the last transaction metric because
        // that's the one that reflects the actual connected address.
        guard let remoteAddress = metrics.transactionMetrics.last?.remoteAddress,
              !remoteAddress.isEmpty else { return }

        let tid = task.taskIdentifier

        // Check if already cancelled — don't overwrite a more-specific reason.
        let alreadyCancelled: Bool = lock.withLock { cancellationReason[tid] != nil }
        guard !alreadyCancelled else { return }

        if let ssrfErr = ssrfError(for: remoteAddress, url: task.originalRequest?.url) {
            lock.withLock {
                if cancellationReason[tid] == nil {
                    cancellationReason[tid] = ssrfErr
                }
            }
            task.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let tid = task.taskIdentifier

        let (data, response, reason, cont): (Data, URLResponse?, WebAssetSearchError?, CheckedContinuation<(Data, URLResponse), Error>?) = lock.withLock {
            let d = dataByTask[tid] ?? Data()
            let r = responseByTask[tid]
            let c = cancellationReason[tid]
            let cont = continuationByTask[tid]
            // Cleanup
            bytesByTask.removeValue(forKey: tid)
            dataByTask.removeValue(forKey: tid)
            responseByTask.removeValue(forKey: tid)
            cancellationReason.removeValue(forKey: tid)
            continuationByTask.removeValue(forKey: tid)
            return (d, r, c, cont)
        }

        guard let cont else { return }

        if let reason {
            cont.resume(throwing: reason)
            return
        }

        if let error {
            // Only wrap if it's not already a WebAssetSearchError
            if let waError = error as? WebAssetSearchError {
                cont.resume(throwing: waError)
            } else {
                cont.resume(throwing: WebAssetSearchError.networkFailure(error))
            }
            return
        }

        guard let response else {
            cont.resume(throwing: WebAssetSearchError.networkFailure(
                NSError(domain: "WebAsset", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response"])
            ))
            return
        }

        cont.resume(returning: (data, response))
    }
}

// MARK: - Hardened boundedData on URLSession

public extension URLSession {
    /// Perform a hardened web-asset data fetch using the session's
    /// `WebAssetDownloadDelegate`. The delegate enforces SSRF, redirect blocking,
    /// HTTPS, and the 50 MB byte ceiling. MUST be called on a session created by
    /// `WebAssetURLSessionFactory.makeProviderSession()` or `makeDownloadSession()`,
    /// which wires up the correct delegate.
    ///
    /// **Security-critical**: a fallback path here would silently bypass every
    /// protection — SSRF IP filtering, redirect blocking, byte ceiling, HTTPS
    /// enforcement. If the session doesn't have a `WebAssetDownloadDelegate`,
    /// the only safe response is to crash: either a test harness forgot to use
    /// the factory, or a future call site is about to ship an unguarded web
    /// fetch. `fatalError` makes that a build-time problem, not a silent
    /// production bypass. (Security Finding N-1, post-Builder code review.)
    ///
    /// Pre-flight HTTPS guard (Security Finding N-5): reject non-HTTPS at the
    /// extension boundary so every caller — including future ones that bypass
    /// `WebAssetImportPipeline.fetch` or individual provider `download()` —
    /// gets the scheme check before any socket is opened.
    func boundedData(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard request.url?.scheme?.lowercased() == "https" else {
            throw WebAssetSearchError.httpOnly(request.url ?? URL(string: "https://unknown")!)
        }
        guard let delegate = self.delegate as? WebAssetDownloadDelegate else {
            fatalError("""
                boundedData(for:) called on a URLSession not created by \
                WebAssetURLSessionFactory. This would bypass SSRF, redirect \
                blocking, byte ceiling, and HTTPS enforcement. Callers MUST \
                obtain their URLSession via WebAssetURLSessionFactory.\
                makeProviderSession() or makeDownloadSession(). If this is a \
                test, inject a mock through the factory — do NOT call \
                boundedData on URLSession.shared.
                """)
        }
        return try await delegate.fetch(request: request, session: self)
    }
}

// MARK: - SSRF IP classification

/// Returns a `WebAssetSearchError.ssrfBlocked` error if `remoteAddress` falls
/// in a private, loopback, or link-local IP range; otherwise returns nil.
///
/// Covers:
/// - IPv4: 127/8, 10/8, 172.16/12, 192.168/16, 169.254/16, 0/8
/// - IPv6: ::1, fc00::/7, fe80::/10
/// - **IPv4-mapped IPv6 (::ffff:0:0/96)**: unwrapped and checked as IPv4.
///   This closes the bypass where `::ffff:127.0.0.1` would otherwise pass
///   the ::1 / fc00::/7 / fe80::/10 checks (Security Finding D).
func ssrfError(for remoteAddress: String, url: URL?) -> WebAssetSearchError? {
    let target = url ?? URL(string: "https://unknown")!

    // Attempt to parse as IPv4 first (direct form like "127.0.0.1")
    if let ipv4 = parseIPv4(remoteAddress), isPrivateIPv4(ipv4) {
        return .ssrfBlocked(target)
    }

    // Attempt to parse as IPv6
    if let ipv6 = parseIPv6(remoteAddress) {
        // Check for IPv4-mapped ::ffff:0:0/96 — unwrap to IPv4 and check.
        // Pattern: first 10 bytes 0x00, bytes 10-11 0xFF 0xFF, then 4 bytes IPv4.
        if ipv6.count == 16 {
            let isAllZeroPrefix = ipv6[0..<10].allSatisfy { $0 == 0 }
            let isFFFF = ipv6[10] == 0xFF && ipv6[11] == 0xFF
            if isAllZeroPrefix && isFFFF {
                // Extract embedded IPv4
                let ipv4Bytes = (ipv6[12], ipv6[13], ipv6[14], ipv6[15])
                if isPrivateIPv4(ipv4Bytes) {
                    return .ssrfBlocked(target)
                }
            }
        }

        // Pure IPv6 checks
        if isPrivateIPv6(ipv6) {
            return .ssrfBlocked(target)
        }
    }

    return nil
}

// MARK: - IPv4 parsing + classification

/// Parse a dotted-decimal IPv4 string into a 4-tuple of bytes.
private func parseIPv4(_ s: String) -> (UInt8, UInt8, UInt8, UInt8)? {
    let parts = s.split(separator: ".").compactMap { UInt8($0) }
    guard parts.count == 4 else { return nil }
    return (parts[0], parts[1], parts[2], parts[3])
}

/// Returns `true` if the IPv4 address falls in a private/loopback/link-local range.
private func isPrivateIPv4(_ ip: (UInt8, UInt8, UInt8, UInt8)) -> Bool {
    let (a, b, _, _) = ip
    return a == 127                                     // 127.0.0.0/8 loopback
        || a == 10                                      // 10.0.0.0/8 private
        || (a == 172 && b >= 16 && b <= 31)             // 172.16.0.0/12 private
        || (a == 192 && b == 168)                       // 192.168.0.0/16 private
        || (a == 169 && b == 254)                       // 169.254.0.0/16 link-local / AWS metadata
        || a == 0                                       // 0.0.0.0/8 null
        || (a == 100 && b >= 64 && b <= 127)            // 100.64.0.0/10 shared address space
}

// MARK: - IPv6 parsing + classification

/// Parse an IPv6 address string into a 16-byte array. Returns nil on parse failure.
private func parseIPv6(_ s: String) -> [UInt8]? {
    // Use POSIX inet_pton for reliable parsing, including compressed forms.
    var addr = in6_addr()
    let result = s.withCString { ptr in
        inet_pton(AF_INET6, ptr, &addr)
    }
    guard result == 1 else { return nil }
    return withUnsafeBytes(of: addr) { Array($0) }
}

/// Returns `true` if the IPv6 address falls in a private/loopback/link-local range.
/// Note: IPv4-mapped addresses are handled separately by the caller before this function.
private func isPrivateIPv6(_ bytes: [UInt8]) -> Bool {
    guard bytes.count == 16 else { return false }

    // ::1 loopback
    if bytes == [0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,1] {
        return true
    }

    // fc00::/7 (ULA — Unique Local Addresses). High byte is 0xFC or 0xFD.
    if bytes[0] & 0xFE == 0xFC {
        return true
    }

    // fe80::/10 (link-local). High 10 bits are 1111111010.
    if bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80 {
        return true
    }

    return false
}
