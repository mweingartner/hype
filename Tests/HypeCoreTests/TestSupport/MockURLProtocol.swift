import Foundation
@testable import HypeCore
@_spi(Testing) import HypeCore

// MARK: - MockURLProtocol

/// A URLProtocol stub for intercepting network requests in tests.
///
/// Usage:
/// 1. Register a handler: `MockURLProtocol.requestHandler = { request in ... }`
/// 2. Create a session with this protocol registered.
/// 3. Make requests — the handler is called instead of real networking.
///
/// Thread-safety: `requestHandler` is a global — tests MUST run serially when
/// sharing this protocol. Use `@Suite(..., .serialized)` or set the handler
/// immediately before each test and clear it after.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {

    /// The handler to call when a request is made.
    /// Returns `(HTTPURLResponse, Data)` or throws to simulate errors.
    ///
    /// The `nonisolated(unsafe)` annotation acknowledges that access to this
    /// mutable global state is not protected by Swift's concurrency checks.
    /// Tests using this must run serially (via `.serialized` suite trait).
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        return true  // Intercept all requests
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError:
                NSError(domain: "MockURLProtocol", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "No handler set"]))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Per-suite mock subclasses
//
// When running multiple provider test suites concurrently (the default for
// Swift Testing), all suites that share `MockURLProtocol.requestHandler` race
// on that global variable. Using a distinct `URLProtocol` subclass per suite
// gives each suite its own independent handler storage, eliminating the race
// without requiring cross-suite serialization.

/// Dedicated mock URLProtocol for OpenverseProviderTests.
final class MockURLProtocolOpenverse: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = MockURLProtocolOpenverse.requestHandler else {
            client?.urlProtocol(self, didFailWithError:
                NSError(domain: "MockURLProtocolOpenverse", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "No handler set"]))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

/// Dedicated mock URLProtocol for WikimediaProviderTests.
final class MockURLProtocolWikimedia: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = MockURLProtocolWikimedia.requestHandler else {
            client?.urlProtocol(self, didFailWithError:
                NSError(domain: "MockURLProtocolWikimedia", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "No handler set"]))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

/// Dedicated mock URLProtocol for WebAssetImportPipelineTests.
final class MockURLProtocolPipeline: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = MockURLProtocolPipeline.requestHandler else {
            client?.urlProtocol(self, didFailWithError:
                NSError(domain: "MockURLProtocolPipeline", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "No handler set"]))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

/// Dedicated mock URLProtocol for PexelsProviderTests.
final class MockURLProtocolPexels: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = MockURLProtocolPexels.requestHandler else {
            client?.urlProtocol(self, didFailWithError:
                NSError(domain: "MockURLProtocolPexels", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "No handler set"]))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

// MARK: - TestSessionFactory

/// A `WebAssetURLSessionFactory` wrapper that injects `MockURLProtocol` into
/// the session configuration. Used to test provider and pipeline network paths.
///
/// Note: Because `WebAssetURLSessionFactory` is a value type and the sessions it
/// creates use `URLSessionConfiguration.ephemeral`, we cannot inject a URLProtocol
/// directly through the factory API. Instead, providers under test must be given a
/// factory that creates sessions registered with MockURLProtocol.
///
/// Since `WebAssetURLSessionFactory` is a concrete struct (not a protocol), we
/// create ephemeral sessions with the protocol injected via
/// `URLSessionConfiguration.ephemeral.protocolClasses`.
struct TestSessionFactory {

    /// Build a `URLSession` configured with `MockURLProtocol` and a
    /// `WebAssetDownloadDelegate`, matching the structure that providers expect.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        config.timeoutIntervalForRequest = 5
        let delegate = WebAssetDownloadDelegate()
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }
}
