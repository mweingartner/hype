import Foundation
@testable import HypeCore

// MARK: - MockURLSession

/// A `URLSessionProviding` stub for testing `fetch_url` and similar URL-fetching
/// code paths without making real network requests.
///
/// Configure the response before each test:
/// ```swift
/// let session = MockURLSession()
/// session.responseData = Data("Hello".utf8)
/// session.responseStatusCode = 200
/// ```
/// Or simulate an error:
/// ```swift
/// session.responseError = URLError(.networkConnectionLost)
/// ```
package final class MockURLSession: URLSessionProviding, @unchecked Sendable {

    private let lock = NSLock()

    // MARK: - Configuration

    /// Data to return from `data(from:)`. Defaults to empty data.
    package var responseData: Data = Data()
    /// HTTP status code for the synthetic response. Defaults to 200.
    package var responseStatusCode: Int = 200
    /// If set, `data(from:)` throws this error instead of returning a response.
    package var responseError: Error?

    // MARK: - Observation

    /// The most-recently-requested URL.
    package var lastRequestedURL: URL?

    package init() {}

    // MARK: - URLSessionProviding

    package func data(from url: URL) async throws -> (Data, URLResponse) {
        lock.withLock { lastRequestedURL = url }
        if let error = lock.withLock({ responseError }) {
            throw error
        }
        let data = lock.withLock { responseData }
        let statusCode = lock.withLock { responseStatusCode }
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (data, response)
    }
}
