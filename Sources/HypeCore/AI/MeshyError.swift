import Foundation

/// Typed error hierarchy for the Meshy.ai stack.
///
/// All `errorDescription` strings are pre-sanitised:
/// - The API key value NEVER appears.
/// - Raw HTTP response bodies are never included beyond 200 chars of
///   a `MeshyErrorEnvelope.message`.
/// - The user's prompt text is only included in `.validationFailed`
///   errors and only when it was the source of the error.
public enum MeshyError: Error, LocalizedError, Sendable, Equatable {
    case noAPIKey
    /// Shouldn't fire in practice — defensive.
    case invalidURL
    /// HTTP succeeded but JSON shape was wrong.
    case invalidResponse
    /// 4xx / 5xx from Meshy — message is pre-sanitised (max 200 chars,
    /// no raw body, no key).
    case requestFailed(statusCode: Int, message: String)
    /// HTTP 429. `retryAfterSeconds` is parsed from the `Retry-After`
    /// header when present.
    case rateLimited(retryAfterSeconds: Int?)
    /// HTTP 402 or a Meshy-specific "insufficient credits" response.
    case insufficientCredits
    /// Meshy returned `status == FAILED`. `message` comes from
    /// `task_error.message`, truncated to 200 chars.
    case taskFailed(taskId: String, message: String)
    /// User requested cancel; DELETE was issued.
    case taskCancelled(taskId: String)
    /// Wall-clock timeout hit (30 min cap). `afterSeconds` is always 1800.
    case timedOut(taskId: String, afterSeconds: Int)
    /// Download of `model_urls.*` failed.
    case modelDownloadFailed(String)
    /// Downloaded bytes exceeded the 50 MB cap.
    case modelTooLarge(bytes: Int, capBytes: Int)
    /// Download Content-Type wasn't in the allowed list for the format.
    case unsupportedContentType(String)
    /// Generic URLError wrapper.
    case networkError
    /// JSONDecoder threw on a Meshy response.
    case decodingFailed
    /// Pre-flight validation failure (empty prompt, prompt too long, etc.).
    case validationFailed(field: String, reason: String)

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "Set your Meshy API key in Preferences → Meshy.ai."
        case .invalidURL, .invalidResponse:
            return "Unexpected response from Meshy. Try again."
        case .requestFailed(let code, let message) where code == 401 || code == 403:
            _ = message  // message deliberately discarded for auth failures
            return "Meshy authentication failed. Check your API key."
        case .requestFailed(_, let message):
            return "Meshy error: \(String(message.prefix(200)))."
        case .rateLimited(let seconds):
            if let s = seconds {
                return "Meshy rate limit reached. Try again in ~\(s) seconds."
            }
            return "Meshy rate limit reached. Try again shortly."
        case .insufficientCredits:
            return "Not enough Meshy credits. Add credits in your Meshy dashboard."
        case .taskFailed(_, let message):
            return "Generation failed: \(String(message.prefix(200)))."
        case .taskCancelled:
            return "Cancelled."
        case .timedOut:
            return "Generation timed out after 30 minutes."
        case .modelDownloadFailed(let msg):
            return "Couldn't download the generated model. \(String(msg.prefix(200)))."
        case .modelTooLarge(let bytes, let cap):
            return "Downloaded model is too large (\(bytes / 1_048_576) MB). Maximum supported size is \(cap / 1_048_576) MB."
        case .unsupportedContentType:
            return "Downloaded model isn't a recognised 3D format."
        case .networkError:
            return "Network error. Check your connection."
        case .decodingFailed:
            return "Unexpected response from Meshy. Try again."
        case .validationFailed(_, let reason):
            return reason
        }
    }
}
