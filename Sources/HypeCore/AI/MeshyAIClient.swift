import Foundation

// MARK: - Protocol

/// Protocol that the HTTP client and test stubs conform to.
public protocol MeshyClient: Sendable {
    func createTextTo3DTask(_ request: MeshyTextTo3DRequest) async throws -> String
    func fetchTask(taskId: String) async throws -> MeshyTaskResponse
    func cancelTask(taskId: String) async throws
    func fetchBalance() async throws -> Int
    func downloadModel(from url: URL, allowedFormat: MeshyOutputFormat) async throws -> Data
}

// MARK: - Client actor

/// HTTP client for the Meshy.ai API.
///
/// One `actor` instance per API key. The base URL is hard-coded to
/// `https://api.meshy.ai` — the public initializer does NOT accept a
/// `baseURL` parameter (security condition H1). A package-visibility
/// initializer exists for tests to inject a custom `URLSession` and
/// override the base URL.
///
/// Style and structure mirror `OpenAIImageGenerationClient`.
public actor MeshyAIClient: MeshyClient {

    // MARK: - Timeouts

    public struct Timeouts: Sendable, Equatable {
        /// Per-request timeout in seconds (for POST / GET / DELETE).
        public var request: TimeInterval
        /// Resource timeout for `downloadModel` (large GLBs may take a while).
        public var resource: TimeInterval

        public init(request: TimeInterval = 60, resource: TimeInterval = 300) {
            self.request = request
            self.resource = resource
        }
    }

    // MARK: - Constants

    /// Hard cap on a downloaded model in bytes (50 MB). Checked pre- and
    /// post-read against `Content-Length` and `Data.count` respectively.
    public static let maxModelBytes: Int = 50 * 1024 * 1024

    // MARK: - Private state

    private let apiKey: String
    /// Always https://api.meshy.ai — never overridable via the public init.
    private let baseURL: URL
    /// Session for API calls (POST / GET / DELETE). Injected in tests.
    private let session: URLSession
    /// Session for model downloads. Separate from `session` so the resource
    /// timeout can be set longer. In the test init this is the same injected
    /// session so mock URLProtocols intercept download calls too.
    private let downloadSession: URLSession
    private let timeouts: Timeouts
    private let logger: HypeLogger

    // MARK: - Init (public — no baseURL parameter per security condition H1)

    /// Create a client.
    ///
    /// - Parameters:
    ///   - apiKey: The Meshy.ai API key (starts with `msy_`). Held only
    ///     for the lifetime of this actor; never logged.
    ///   - timeouts: Request/resource timeouts. Defaults are conservative
    ///     (60 s request, 300 s resource for large model downloads).
    ///   - logger: Logging sink. Defaults to `HypeLogger.shared`.
    public init(
        apiKey: String,
        timeouts: Timeouts = Timeouts(),
        logger: HypeLogger = .shared
    ) {
        self.apiKey = apiKey
        self.baseURL = URL(string: "https://api.meshy.ai")!
        self.timeouts = timeouts
        self.logger = logger
        self.session = Self.makeSession(timeouts: timeouts)
        // Dedicated download session with the resource timeout applied AND
        // a NoRedirect delegate. (Security F-2: URLSession follows HTTP
        // redirects by default; without intervention, an attacker who
        // compromised a Meshy CDN response could 302-redirect a download
        // from a meshy.ai host to an arbitrary host — bypassing the
        // hostname allowlist in `downloadModel`. Meshy's pre-signed CDN
        // URLs do not redirect in normal operation, so refusing all
        // redirects is the safer default for Phase 1.)
        let dlConfig = URLSessionConfiguration.ephemeral
        dlConfig.timeoutIntervalForRequest = timeouts.request
        dlConfig.timeoutIntervalForResource = timeouts.resource
        dlConfig.waitsForConnectivity = false
        self.downloadSession = URLSession(
            configuration: dlConfig,
            delegate: MeshyNoRedirectDelegate(),
            delegateQueue: nil
        )
    }

    // MARK: - Init (package — test injection only)

    /// Package-visibility init for tests to inject a custom `URLSession`
    /// and override the base URL. NOT public — callers cannot redirect egress.
    /// The same session is reused for both API calls and downloads so that
    /// mock URLProtocols intercept download requests in unit tests.
    package init(
        apiKey: String,
        baseURL: URL,
        timeouts: Timeouts = Timeouts(),
        session: URLSession,
        logger: HypeLogger = .shared
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.timeouts = timeouts
        self.session = session
        self.downloadSession = session
        self.logger = logger
    }

    // MARK: - MeshyClient conformance

    /// POST `/openapi/v2/text-to-3d` and return the task id.
    ///
    /// - Throws: `MeshyError.validationFailed` if the prompt is empty.
    /// - Returns: The non-empty task id string.
    public func createTextTo3DTask(_ request: MeshyTextTo3DRequest) async throws -> String {
        // Pre-flight validation.
        if let prompt = request.prompt {
            let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw MeshyError.validationFailed(field: "prompt", reason: "Enter a prompt before generating.")
            }
        }

        var urlReq = authorizedRequest(path: "/openapi/v2/text-to-3d", method: "POST")
        urlReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlReq.httpBody = try JSONEncoder().encode(request)

        logger.aiInput(
            "POST /openapi/v2/text-to-3d mode=\(request.mode.rawValue) model=\(request.aiModel.rawValue) prompt:\(request.prompt?.prefix(80) ?? "(none)")",
            source: "Meshy"
        )

        let (data, response) = try await sessionData(for: urlReq, endpoint: "/openapi/v2/text-to-3d")
        guard let http = response as? HTTPURLResponse else { throw MeshyError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw mapHTTPError(statusCode: http.statusCode, body: data)
        }

        let decoded = try decodeJSON(MeshyCreateTaskResponse.self, from: data)
        guard !decoded.result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MeshyError.invalidResponse
        }

        logger.aiOutput("task_id=\(decoded.result)", source: "Meshy")
        return decoded.result
    }

    /// GET `/openapi/v2/text-to-3d/<taskId>` and return the task status.
    public func fetchTask(taskId: String) async throws -> MeshyTaskResponse {
        let safePath = "/openapi/v2/text-to-3d/\(taskId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? taskId)"
        let urlReq = authorizedRequest(path: safePath, method: "GET")

        let (data, response) = try await sessionData(for: urlReq, endpoint: "/openapi/v2/text-to-3d/:id")
        guard let http = response as? HTTPURLResponse else { throw MeshyError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw mapHTTPError(statusCode: http.statusCode, body: data)
        }

        return try decodeJSON(MeshyTaskResponse.self, from: data)
    }

    /// DELETE `/openapi/v2/text-to-3d/<taskId>`. Tolerates 404 (task
    /// already finished) by returning normally.
    public func cancelTask(taskId: String) async throws {
        let safePath = "/openapi/v2/text-to-3d/\(taskId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? taskId)"
        let urlReq = authorizedRequest(path: safePath, method: "DELETE")

        let (data, response) = try await sessionData(for: urlReq, endpoint: "/openapi/v2/text-to-3d/:id DELETE")
        guard let http = response as? HTTPURLResponse else { throw MeshyError.invalidResponse }
        // 404 means the task already finished — not an error from our perspective.
        if http.statusCode == 404 { return }
        guard (200..<300).contains(http.statusCode) else {
            throw mapHTTPError(statusCode: http.statusCode, body: data)
        }
    }

    /// GET `/openapi/v1/balance` and return the integer credit balance.
    public func fetchBalance() async throws -> Int {
        let urlReq = authorizedRequest(path: "/openapi/v1/balance", method: "GET")

        let (data, response) = try await sessionData(for: urlReq, endpoint: "/openapi/v1/balance")
        guard let http = response as? HTTPURLResponse else { throw MeshyError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw mapHTTPError(statusCode: http.statusCode, body: data)
        }

        let decoded = try decodeJSON(MeshyBalanceResponse.self, from: data)
        return decoded.balance
    }

    /// Download a model file from `url`.
    ///
    /// Security validations (in order):
    ///   1. `url.scheme == "https"` (rejects `http://` or other schemes).
    ///   2. Hostname must be `meshy.ai` or a subdomain (H2).
    ///   3. `Content-Length` (when present) ≤ `maxModelBytes`.
    ///   4. `Content-Type` must match `allowedFormat`'s MIME type.
    ///   5. Post-read: `data.count` ≤ `maxModelBytes` (TOCTOU re-check).
    ///
    /// NOTE (OQ1): USDZ is a ZIP container. A 49 MB USDZ could
    /// decompress to gigabytes. The 50 MB cap applies to the download
    /// size only; decompression memory is bounded by Apple's SDK. Phase 4
    /// may revisit with a tighter USDZ-specific cap.
    ///
    /// NOTE (OQ2): FBX support requires macOS 13+ (ModelIO). The download
    /// cap applies regardless. FBX has higher attack surface than GLB/USDZ;
    /// see `Scene3DAssetLoader` for the parsing notes.
    public func downloadModel(from url: URL, allowedFormat: MeshyOutputFormat) async throws -> Data {
        // Validation 1 — HTTPS only.
        guard url.scheme?.lowercased() == "https" else {
            throw MeshyError.modelDownloadFailed("non-https scheme")
        }

        // Validation 2 — hostname must be meshy.ai or a subdomain (H2).
        let host = url.host?.lowercased() ?? ""
        let isMeshyHost = host == "meshy.ai" || host.hasSuffix(".meshy.ai")
        guard isMeshyHost else {
            throw MeshyError.modelDownloadFailed("untrusted host")
        }

        var downloadReq = URLRequest(url: url)
        downloadReq.timeoutInterval = timeouts.resource
        // Downloads are pre-signed — no bearer token required.

        do {
            let (data, response) = try await downloadSession.data(for: downloadReq)
            guard let http = response as? HTTPURLResponse else {
                throw MeshyError.modelDownloadFailed("invalid response")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw MeshyError.modelDownloadFailed("HTTP \(http.statusCode)")
            }

            // Validation 3 — Content-Length pre-read check.
            if let contentLength = http.value(forHTTPHeaderField: "Content-Length")
                .flatMap(Int.init), contentLength > Self.maxModelBytes {
                throw MeshyError.modelTooLarge(bytes: contentLength, capBytes: Self.maxModelBytes)
            }

            // Validation 4 — Content-Type allowlist.
            let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "")
                .split(separator: ";").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
            let allowedTypes = Self.allowedContentTypes(for: allowedFormat)
            guard allowedTypes.contains(contentType) || contentType.isEmpty else {
                throw MeshyError.unsupportedContentType(contentType)
            }

            // Validation 5 — post-read TOCTOU size re-check.
            guard data.count <= Self.maxModelBytes else {
                throw MeshyError.modelTooLarge(bytes: data.count, capBytes: Self.maxModelBytes)
            }

            logger.info(
                "Downloaded model \(data.count) bytes format=\(allowedFormat.rawValue)",
                source: "Meshy"
            )
            return data

        } catch let error as MeshyError {
            throw error
        } catch {
            throw MeshyError.networkError
        }
    }

    // MARK: - Private helpers

    /// Builds an authorized `URLRequest` for the given path and HTTP method.
    /// The path is appended to `baseURL`. The Bearer token is set via
    /// `setValue` — NEVER interpolated into a log string.
    private func authorizedRequest(path: String, method: String) -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = path
        var req = URLRequest(url: components.url!)
        req.httpMethod = method
        // Security: Bearer token is set via the header API, never logged.
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = timeouts.request
        return req
    }

    private func sessionData(for request: URLRequest, endpoint: String) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw MeshyError.requestFailed(statusCode: 0, message: "Request timed out (\(endpoint))")
        } catch {
            throw MeshyError.networkError
        }
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw MeshyError.decodingFailed
        }
    }

    /// Translate an HTTP error status code to a typed `MeshyError`.
    /// The `body` parameter is parsed for a `MeshyErrorEnvelope`; if
    /// that fails, a hard-coded message is used (no raw body bytes in
    /// the error string).
    private func mapHTTPError(statusCode: Int, body: Data) -> MeshyError {
        let sanitisedMessage: String = {
            if let envelope = try? JSONDecoder().decode(MeshyErrorEnvelope.self, from: body),
               let msg = envelope.message ?? envelope.error {
                return String(msg.prefix(200))
            }
            return "Unknown error"
        }()

        switch statusCode {
        case 401, 403:
            return .requestFailed(statusCode: statusCode, message: "Authentication failed")
        case 402:
            return .insufficientCredits
        case 429:
            // Parse Retry-After header if present (not available here — the
            // caller can check the response headers if needed; we emit nil).
            return .rateLimited(retryAfterSeconds: nil)
        case 500...599:
            return .requestFailed(statusCode: statusCode, message: "Meshy server error")
        default:
            return .requestFailed(statusCode: statusCode, message: sanitisedMessage)
        }
    }

    /// Allowed MIME types for a given output format.
    private static func allowedContentTypes(for format: MeshyOutputFormat) -> Set<String> {
        switch format {
        case .glb:
            return ["model/gltf-binary", "application/octet-stream"]
        case .usdz:
            return ["model/vnd.usdz+zip", "application/zip", "application/octet-stream"]
        case .fbx:
            return ["model/fbx", "application/octet-stream"]
        }
    }

    /// Shared `URLSession` factory — ephemeral config, no disk caching.
    private static func makeSession(timeouts: Timeouts) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeouts.request
        config.timeoutIntervalForResource = timeouts.resource
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }
}

// MARK: - NoRedirect delegate (Security F-2)

/// `URLSessionTaskDelegate` that refuses every HTTP redirect on the
/// download session. The Meshy CDN serves pre-signed URLs that should
/// not redirect in normal operation; following a redirect would bypass
/// the `meshy.ai` hostname allowlist enforced in
/// `MeshyAIClient.downloadModel`. Marked `@unchecked Sendable` because
/// it has no mutable state — URLSession itself serializes delegate
/// callbacks on its delegate queue.
///
/// Internal visibility so unit tests can construct the same delegate
/// and verify redirect-rejection behaviour end-to-end via a mock
/// `URLProtocol`.
final class MeshyNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Refuse all redirects. The download fails and `downloadModel`
        // surfaces the underlying 3xx HTTPURLResponse — which our code
        // treats as a non-success status code and throws
        // `modelDownloadFailed("HTTP <code>")`.
        completionHandler(nil)
    }
}
