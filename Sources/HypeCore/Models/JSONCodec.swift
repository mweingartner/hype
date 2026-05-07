import Foundation

/// Shared JSON encoder / decoder pair for stored-as-string model
/// fields (`Part.sceneSpec`, `Part.chartData`, etc.).
///
/// Background — every `fromJSON` / `toJSON` in the model layer used
/// to allocate a fresh `JSONDecoder()` / `JSONEncoder()` per call.
/// `Part.spriteAreaSpecModel` alone has 65 callsites across the
/// app, several inside per-frame draw loops and per-tick idle
/// paths, so the per-call allocation showed up clearly in the
/// performance audit. Sharing a single decoder/encoder eliminates
/// that allocation cost; the underlying decode/encode work
/// (which is the unavoidable part) stays the same.
///
/// Thread safety — `JSONDecoder` and `JSONEncoder` are safe for
/// concurrent use as long as their *configuration* is read-only
/// after creation, which is the case for both shared instances
/// here. We never mutate `dateDecodingStrategy` etc. after the
/// `let`. The `nonisolated(unsafe)` annotation is the standard
/// pattern for this kind of always-immutable shared singleton.
public enum JSONCodec {
    nonisolated(unsafe) public static let decoder = JSONDecoder()
    nonisolated(unsafe) public static let encoder = JSONEncoder()

    /// Decode a model value from a JSON string. Returns nil on
    /// invalid UTF-8 or decode failure (callers already handle the
    /// nil case via `??` fallbacks).
    public static func decode<T: Decodable>(_ type: T.Type, from json: String) -> T? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    /// Encode a model value to a JSON string. Returns "{}" on
    /// failure to keep callers' string-handling code simple
    /// (matches the existing fallback in every site this
    /// replaces).
    public static func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? encoder.encode(value) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
