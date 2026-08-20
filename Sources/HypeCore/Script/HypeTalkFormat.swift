import Foundation

/// Single canon for HypeTalk's number formatting, string→number
/// coercion, and truthiness rules (design.md D2, turtle-graphics).
///
/// `Interpreter.formatNumber` / `Interpreter.toNumber` / `Interpreter.isTruthy`
/// delegate to this type (bodies moved verbatim, byte-identical
/// behavior) so the turtle engine, the `draw_with_turtle` AI tool
/// summary, and the interpreter can never fork on these rules.
public enum HypeTalkFormat {
    /// Format a number, dropping `.0` for integers.
    ///
    /// Uses `Int(exactly:)` so that integral doubles outside Int64
    /// range (e.g. 1e30) fall through to `String(n)` ("1e+30") rather
    /// than trapping. Behavior for all in-range values matches classic
    /// HypeTalk number display.
    public static func number(_ n: Double) -> String {
        if n == n.rounded(.towardZero) && !n.isInfinite && !n.isNaN {
            if let i = Int(exactly: n.rounded(.towardZero)) {
                return String(i)
            }
        }
        return String(n)
    }

    /// Convert a HypeTalk value to a number. Non-numeric strings become 0.
    public static func number(from value: String) -> Double {
        Double(value) ?? 0
    }

    /// Check if a HypeTalk value is truthy.
    ///
    /// Classic HyperCard truth: only `"true"` (case-insensitive) and any
    /// non-zero number are truthy. `"yes"`, `"on"`, and other English
    /// affirmatives are FALSY. This matches the HypeTalk guide and
    /// classic HyperCard behaviour.
    public static func isTruthy(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower == "true" || (Double(value).map { $0 != 0 } ?? false)
    }
}
