import Foundation

// MARK: - Protocol

/// Protocol that the HTTP client and test stubs conform to.
///
/// **Phase 3 breaking change:** `fetchTask(taskId:)` is replaced by
/// `fetchTaskFact(taskId:kind:)` which returns the kind-normalised
/// `MeshyPolledFact` instead of a raw `MeshyTaskResponse`. All
/// conformers (live client and every test stub) MUST implement the new
/// signature. No `default:` in `cancelTask` switches — the compiler
/// enforces updates when new `MeshyTaskKind` cases land.
public protocol MeshyClient: Sendable {
    func createTextTo3DTask(_ request: MeshyTextTo3DRequest) async throws -> String
    func createImageTo3DTask(_ request: MeshyImageTo3DRequest) async throws -> String
    func createMultiImageTo3DTask(_ request: MeshyMultiImageTo3DRequest) async throws -> String
    /// Phase 3: create a rigging task.
    func createRiggingTask(_ request: MeshyRiggingRequest) async throws -> String
    /// Phase 3: create an animation task.
    func createAnimationTask(_ request: MeshyAnimationRequest) async throws -> String
    /// Phase 4: create a remesh task.
    func createRemeshTask(_ request: MeshyRemeshRequest) async throws -> String
    /// Phase 4: create a retexture task.
    func createRetextureTask(_ request: MeshyRetextureRequest) async throws -> String
    /// Phase 3: fetch task status, routed by kind, returning a normalised fact.
    ///
    /// Endpoint routing:
    /// - `.textTo3D` → GET `/openapi/v2/text-to-3d/<id>`
    /// - `.imageTo3D` → GET `/openapi/v1/image-to-3d/<id>`
    /// - `.multiImageTo3D` → GET `/openapi/v1/multi-image-to-3d/<id>`
    /// - `.rigging` → GET `/openapi/v1/rigging/<id>`
    /// - `.animation` → GET `/openapi/v1/animations/<id>`
    func fetchTaskFact(taskId: String, kind: MeshyTaskKind) async throws -> MeshyPolledFact
    /// Cancel a Meshy task.
    ///
    /// **Security (H1):** all five kinds MUST be listed explicitly.
    /// No `default:` or `@unknown default:` is permitted — the compiler
    /// must force updates when new `MeshyTaskKind` cases land.
    ///
    /// Endpoint routing:
    /// - `.textTo3D` → `/openapi/v2/text-to-3d/<id>`
    /// - `.imageTo3D` → `/openapi/v1/image-to-3d/<id>`
    /// - `.multiImageTo3D` → `/openapi/v1/multi-image-to-3d/<id>`
    /// - `.rigging` → `/openapi/v1/rigging/<id>`
    /// - `.animation` → `/openapi/v1/animations/<id>`
    func cancelTask(taskId: String, kind: MeshyTaskKind) async throws
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

    /// Fetch the status of a Meshy task, routing to the correct endpoint by kind.
    ///
    /// Returns a `MeshyPolledFact` that normalises all five response shapes
    /// into one type for `MeshyTaskMonitor` to consume.
    ///
    /// **Security (H3):** URL fields in the returned fact are sanitised via
    /// `MeshyPolledFact.sanitizedMeshyURL` — non-Meshy URLs become `nil`.
    public func fetchTaskFact(taskId: String, kind: MeshyTaskKind) async throws -> MeshyPolledFact {
        let encodedId = taskId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? taskId
        switch kind {
        case .textTo3D:
            let path = "/openapi/v2/text-to-3d/\(encodedId)"
            let resp = try await fetchAndDecode(path: path, as: MeshyTaskResponse.self, endpoint: "/openapi/v2/text-to-3d/:id")
            return MeshyPolledFact.fromTextOrImageTo3D(resp, kind: .textTo3D)
        case .imageTo3D:
            let path = "/openapi/v1/image-to-3d/\(encodedId)"
            let resp = try await fetchAndDecode(path: path, as: MeshyTaskResponse.self, endpoint: "/openapi/v1/image-to-3d/:id")
            return MeshyPolledFact.fromTextOrImageTo3D(resp, kind: .imageTo3D)
        case .multiImageTo3D:
            let path = "/openapi/v1/multi-image-to-3d/\(encodedId)"
            let resp = try await fetchAndDecode(path: path, as: MeshyTaskResponse.self, endpoint: "/openapi/v1/multi-image-to-3d/:id")
            return MeshyPolledFact.fromTextOrImageTo3D(resp, kind: .multiImageTo3D)
        case .rigging:
            let path = "/openapi/v1/rigging/\(encodedId)"
            let resp = try await fetchAndDecode(path: path, as: MeshyRiggingTaskResponse.self, endpoint: "/openapi/v1/rigging/:id")
            return MeshyPolledFact.fromRigging(resp)
        case .animation:
            let path = "/openapi/v1/animations/\(encodedId)"
            let resp = try await fetchAndDecode(path: path, as: MeshyAnimationTaskResponse.self, endpoint: "/openapi/v1/animations/:id")
            return MeshyPolledFact.fromAnimation(resp)
        case .remesh:
            let path = "/openapi/v1/remesh/\(encodedId)"
            let resp = try await fetchAndDecode(path: path, as: MeshyRemeshTaskResponse.self, endpoint: "/openapi/v1/remesh/:id")
            return MeshyPolledFact.fromRemesh(resp)
        case .retexture:
            let path = "/openapi/v1/retexture/\(encodedId)"
            let resp = try await fetchAndDecode(path: path, as: MeshyRetextureTaskResponse.self, endpoint: "/openapi/v1/retexture/:id")
            return MeshyPolledFact.fromRetexture(resp)
        }
    }

    /// Generic GET + JSON decode helper used by `fetchTaskFact`.
    private func fetchAndDecode<T: Decodable>(
        path: String,
        as type: T.Type,
        endpoint: String
    ) async throws -> T {
        let urlReq = authorizedRequest(path: path, method: "GET")
        let (data, response) = try await sessionData(for: urlReq, endpoint: endpoint)
        guard let http = response as? HTTPURLResponse else { throw MeshyError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw mapHTTPError(statusCode: http.statusCode, body: data)
        }
        return try decodeJSON(type, from: data)
    }

    /// DELETE the appropriate Meshy endpoint based on `kind`. Tolerates 404
    /// (task already finished) by returning normally.
    ///
    /// **Security (C1/H1):** all seven `MeshyTaskKind` cases are named explicitly.
    /// This switch has NO `default:` so the compiler fails the build when a
    /// new kind is added without updating this method.
    ///
    /// Endpoint routing:
    /// - `.textTo3D` → `/openapi/v2/text-to-3d/<id>`
    /// - `.imageTo3D` → `/openapi/v1/image-to-3d/<id>`
    /// - `.multiImageTo3D` → `/openapi/v1/multi-image-to-3d/<id>`
    /// - `.rigging` → `/openapi/v1/rigging/<id>`
    /// - `.animation` → `/openapi/v1/animations/<id>`
    /// - `.remesh` → `/openapi/v1/remesh/<id>`
    /// - `.retexture` → `/openapi/v1/retexture/<id>`
    public func cancelTask(taskId: String, kind: MeshyTaskKind) async throws {
        let encodedId = taskId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? taskId
        let (basePath, logEndpoint): (String, String) = switch kind {
        case .textTo3D:
            ("/openapi/v2/text-to-3d/\(encodedId)", "/openapi/v2/text-to-3d/:id DELETE")
        case .imageTo3D:
            ("/openapi/v1/image-to-3d/\(encodedId)", "/openapi/v1/image-to-3d/:id DELETE")
        case .multiImageTo3D:
            ("/openapi/v1/multi-image-to-3d/\(encodedId)", "/openapi/v1/multi-image-to-3d/:id DELETE")
        case .rigging:
            ("/openapi/v1/rigging/\(encodedId)", "/openapi/v1/rigging/:id DELETE")
        case .animation:
            ("/openapi/v1/animations/\(encodedId)", "/openapi/v1/animations/:id DELETE")
        case .remesh:
            ("/openapi/v1/remesh/\(encodedId)", "/openapi/v1/remesh/:id DELETE")
        case .retexture:
            ("/openapi/v1/retexture/\(encodedId)", "/openapi/v1/retexture/:id DELETE")
        }
        let urlReq = authorizedRequest(path: basePath, method: "DELETE")

        let (data, response) = try await sessionData(for: urlReq, endpoint: logEndpoint)
        guard let http = response as? HTTPURLResponse else { throw MeshyError.invalidResponse }
        // 404 means the task already finished — not an error from our perspective.
        if http.statusCode == 404 { return }
        guard (200..<300).contains(http.statusCode) else {
            throw mapHTTPError(statusCode: http.statusCode, body: data)
        }
    }

    /// POST `/openapi/v1/image-to-3d` and return the task id.
    ///
    /// - Throws: `MeshyError.validationFailed` if `imageData` is not a data URI.
    /// - Returns: The non-empty task id string.
    public func createImageTo3DTask(_ request: MeshyImageTo3DRequest) async throws -> String {
        // Pre-flight validation: image_url must be a data URI (or a public
        // HTTPS URL, which Phase 2 doesn't currently send).
        guard request.imageData.hasPrefix("data:image/") else {
            throw MeshyError.validationFailed(field: "image_url", reason: "Image must be a data URI.")
        }

        var urlReq = authorizedRequest(path: "/openapi/v1/image-to-3d", method: "POST")
        urlReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlReq.httpBody = try JSONEncoder().encode(request)

        // Log only the character count of the image data, never the bytes themselves.
        logger.aiInput(
            "POST /openapi/v1/image-to-3d model=\(request.aiModel.rawValue) image_url:\(request.imageData.count) chars",
            source: "Meshy"
        )

        let (data, response) = try await sessionData(for: urlReq, endpoint: "/openapi/v1/image-to-3d")
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

    /// POST `/openapi/v1/multi-image-to-3d` and return the task id.
    ///
    /// Enforces the 2..4 image constraint before sending.
    /// - Throws: `MeshyError.validationFailed` for count violations or non-data-URI entries.
    /// - Returns: The non-empty task id string.
    public func createMultiImageTo3DTask(_ request: MeshyMultiImageTo3DRequest) async throws -> String {
        // Pre-flight validation: 2..4 images.
        guard (2...4).contains(request.imageData.count) else {
            throw MeshyError.validationFailed(
                field: "image_urls",
                reason: "Multi-image generation requires 2 to 4 images."
            )
        }
        // Each entry must be a data URI.
        for (idx, uri) in request.imageData.enumerated() {
            guard uri.hasPrefix("data:image/") else {
                throw MeshyError.validationFailed(
                    field: "image_urls[\(idx)]",
                    reason: "Image \(idx + 1) must be a data URI."
                )
            }
        }

        // Defense-in-depth: combined encoded-body cap. 40 MB raw → ~53 MB
        // base64-encoded → cap at 57 MB string length to be generous. The
        // primary M2 enforcement lives in `Generate3DJob`, but any future
        // call site that builds `MeshyMultiImageTo3DRequest` directly hits
        // this gate too. (Security review Phase 2 Defect 2.)
        let totalEncodedChars = request.imageData.map(\.count).reduce(0, +)
        let combinedCap = 57 * 1024 * 1024
        guard totalEncodedChars <= combinedCap else {
            throw MeshyError.validationFailed(
                field: "image_urls",
                reason: "Total image size exceeds the 40 MB combined limit."
            )
        }

        var urlReq = authorizedRequest(path: "/openapi/v1/multi-image-to-3d", method: "POST")
        urlReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlReq.httpBody = try JSONEncoder().encode(request)

        logger.aiInput(
            "POST /openapi/v1/multi-image-to-3d model=\(request.aiModel.rawValue) images=\(request.imageData.count)",
            source: "Meshy"
        )

        let (data, response) = try await sessionData(for: urlReq, endpoint: "/openapi/v1/multi-image-to-3d")
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

    /// POST `/openapi/v1/rigging` and return the task id.
    ///
    /// - Throws: `MeshyError.validationFailed` if `inputTaskId` is empty or
    ///   `heightMeters` is out of the supported range (0…100 m).
    /// - Returns: The non-empty rigging task id string.
    public func createRiggingTask(_ request: MeshyRiggingRequest) async throws -> String {
        let trimmedId = request.inputTaskId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else {
            throw MeshyError.validationFailed(field: "input_task_id", reason: "Input task id must not be empty.")
        }
        if let h = request.heightMeters {
            guard h > 0 && h <= 100 else {
                throw MeshyError.validationFailed(
                    field: "height_meters",
                    reason: "Character height must be between 0 and 100 m (got \(h))."
                )
            }
        }

        var urlReq = authorizedRequest(path: "/openapi/v1/rigging", method: "POST")
        urlReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlReq.httpBody = try JSONEncoder().encode(request)

        logger.aiInput(
            "POST /openapi/v1/rigging input_task_id=\(trimmedId) height=\(request.heightMeters ?? 1.7)",
            source: "Meshy"
        )

        let (data, response) = try await sessionData(for: urlReq, endpoint: "/openapi/v1/rigging")
        guard let http = response as? HTTPURLResponse else { throw MeshyError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw mapHTTPError(statusCode: http.statusCode, body: data)
        }
        let decoded = try decodeJSON(MeshyCreateTaskResponse.self, from: data)
        guard !decoded.result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MeshyError.invalidResponse
        }
        logger.aiOutput("rigging task_id=\(decoded.result)", source: "Meshy")
        return decoded.result
    }

    /// POST `/openapi/v1/animations` and return the task id.
    ///
    /// **Security (M1):** `actionId.value` is pre-validated in `MeshyActionId.init(_:)`
    /// to be in 0…1000. This method adds a secondary guard for defense-in-depth.
    ///
    /// - Throws: `MeshyError.validationFailed` if `rigTaskId` is empty.
    /// - Returns: The non-empty animation task id string.
    public func createAnimationTask(_ request: MeshyAnimationRequest) async throws -> String {
        let trimmedRig = request.rigTaskId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRig.isEmpty else {
            throw MeshyError.validationFailed(field: "rig_task_id", reason: "Rig task id must not be empty.")
        }
        // Secondary defense-in-depth check (primary is in MeshyActionId.init).
        guard request.actionId.value >= 0 && request.actionId.value <= 1000 else {
            throw MeshyError.validationFailed(
                field: "action_id",
                reason: "Action id must be between 0 and 1000 (got \(request.actionId.value))."
            )
        }

        var urlReq = authorizedRequest(path: "/openapi/v1/animations", method: "POST")
        urlReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlReq.httpBody = try JSONEncoder().encode(request)

        logger.aiInput(
            "POST /openapi/v1/animations rig_task_id=\(trimmedRig) action_id=\(request.actionId.value)",
            source: "Meshy"
        )

        let (data, response) = try await sessionData(for: urlReq, endpoint: "/openapi/v1/animations")
        guard let http = response as? HTTPURLResponse else { throw MeshyError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw mapHTTPError(statusCode: http.statusCode, body: data)
        }
        let decoded = try decodeJSON(MeshyCreateTaskResponse.self, from: data)
        guard !decoded.result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MeshyError.invalidResponse
        }
        logger.aiOutput("animation task_id=\(decoded.result)", source: "Meshy")
        return decoded.result
    }

    /// POST `/openapi/v1/remesh` and return the task id.
    ///
    /// **Security (C5):** validates `targetPolycount` is in 100…300_000.
    /// **Security (C2):** `MeshyRemeshRequest` never encodes `model_url`.
    ///
    /// - Throws: `MeshyError.validationFailed` if `inputTaskId` is empty or
    ///   `targetPolycount` is outside 100…300_000.
    /// - Returns: The non-empty remesh task id string.
    public func createRemeshTask(_ request: MeshyRemeshRequest) async throws -> String {
        let trimmedId = request.inputTaskId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else {
            throw MeshyError.validationFailed(field: "input_task_id", reason: "Input task id must not be empty.")
        }
        guard (100...300_000).contains(request.targetPolycount) else {
            throw MeshyError.validationFailed(
                field: "target_polycount",
                reason: "Target polycount must be between 100 and 300,000 (got \(request.targetPolycount))."
            )
        }

        var urlReq = authorizedRequest(path: "/openapi/v1/remesh", method: "POST")
        urlReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlReq.httpBody = try JSONEncoder().encode(request)

        logger.aiInput(
            "POST /openapi/v1/remesh input_task_id=\(trimmedId) target_polycount=\(request.targetPolycount)",
            source: "Meshy"
        )

        let (data, response) = try await sessionData(for: urlReq, endpoint: "/openapi/v1/remesh")
        guard let http = response as? HTTPURLResponse else { throw MeshyError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw mapHTTPError(statusCode: http.statusCode, body: data)
        }
        let decoded = try decodeJSON(MeshyCreateTaskResponse.self, from: data)
        guard !decoded.result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MeshyError.invalidResponse
        }
        logger.aiOutput("remesh task_id=\(decoded.result)", source: "Meshy")
        return decoded.result
    }

    /// POST `/openapi/v1/retexture` and return the task id.
    ///
    /// **Security (C6):** validates `textStylePrompt` is not empty; truncation
    /// to 600 chars is applied in `MeshyRetextureRequest.init`.
    /// **Security (C3):** `MeshyRetextureRequest` never encodes `model_url` or
    /// `image_style_url`.
    ///
    /// - Throws: `MeshyError.validationFailed` if `inputTaskId` or
    ///   `textStylePrompt` is empty.
    /// - Returns: The non-empty retexture task id string.
    public func createRetextureTask(_ request: MeshyRetextureRequest) async throws -> String {
        let trimmedId = request.inputTaskId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else {
            throw MeshyError.validationFailed(field: "input_task_id", reason: "Input task id must not be empty.")
        }
        let trimmedPrompt = request.textStylePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            throw MeshyError.validationFailed(field: "text_style_prompt", reason: "Style prompt must not be empty.")
        }

        var urlReq = authorizedRequest(path: "/openapi/v1/retexture", method: "POST")
        urlReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlReq.httpBody = try JSONEncoder().encode(request)

        logger.aiInput(
            "POST /openapi/v1/retexture input_task_id=\(trimmedId) prompt:\(trimmedPrompt.prefix(80))",
            source: "Meshy"
        )

        let (data, response) = try await sessionData(for: urlReq, endpoint: "/openapi/v1/retexture")
        guard let http = response as? HTTPURLResponse else { throw MeshyError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw mapHTTPError(statusCode: http.statusCode, body: data)
        }
        let decoded = try decodeJSON(MeshyCreateTaskResponse.self, from: data)
        guard !decoded.result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MeshyError.invalidResponse
        }
        logger.aiOutput("retexture task_id=\(decoded.result)", source: "Meshy")
        return decoded.result
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
            guard Self.modelBytes(data, match: allowedFormat) else {
                throw MeshyError.modelDownloadFailed("downloaded bytes do not match \(allowedFormat.rawValue) signature")
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

    /// Lightweight magic-byte validation before Hype stores downloaded 3D
    /// bytes as document assets. This complements MIME checks, which Meshy/CDN
    /// may legitimately serve as application/octet-stream.
    private static func modelBytes(_ data: Data, match format: MeshyOutputFormat) -> Bool {
        switch format {
        case .glb:
            guard data.count >= 12 else { return false }
            return data[0] == 0x67 && data[1] == 0x6C && data[2] == 0x54 && data[3] == 0x46
        case .usdz:
            guard data.count >= 4 else { return false }
            return data[0] == 0x50 && data[1] == 0x4B &&
                ((data[2] == 0x03 && data[3] == 0x04) ||
                 (data[2] == 0x05 && data[3] == 0x06) ||
                 (data[2] == 0x07 && data[3] == 0x08))
        case .fbx:
            guard !data.isEmpty else { return false }
            let binaryPrefix = Data("Kaydara FBX Binary  \u{00}".utf8)
            if data.count >= binaryPrefix.count && data.prefix(binaryPrefix.count) == binaryPrefix {
                return true
            }
            if let prefix = String(data: data.prefix(128), encoding: .utf8) {
                return prefix.contains("FBX") || prefix.contains("; FBX")
            }
            return false
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
