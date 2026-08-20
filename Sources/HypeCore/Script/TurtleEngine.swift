import Foundation

/// Pure, `Sendable` turtle-graphics (Logo/Python-turtle style) engine
/// shared by every HypeTalk front end — the interpreter and the
/// `draw_with_turtle` AI tool (design.md D1, turtle-graphics).
///
/// `TurtleEngine` owns every piece of turtle geometry, state transition,
/// flush decision, per-run limit, and error string. It imports only
/// Foundation and same-module models (`PathPoint`, `HexColor`,
/// `HypeTalkFormat`) — never the parser, interpreter, or AI executor —
/// so a second geometry implementation can never appear on another
/// surface (Condition 1, Condition 10).
public struct TurtleEngine: Sendable {

    // MARK: - Canvas

    /// The card the turtle draws on. Determines home position (card
    /// center) for `home` / `clearScreen` / `resetTurtle`.
    public struct Canvas: Sendable, Equatable {
        public var width: Double
        public var height: Double

        public init(width: Double, height: Double) {
            self.width = width
            self.height = height
        }
    }

    // MARK: - ScalarState

    /// Scalar turtle state — the only thing that survives a run (R6).
    /// Buffers (open stroke, open fill) and per-run counters never
    /// survive; they live only inside a live `TurtleEngine` instance.
    public struct ScalarState: Sendable, Equatable {
        public var x: Double
        public var y: Double
        public var heading: Double
        public var penDown: Bool
        /// Normalized "#RRGGBB[AA]" pen (stroke) color.
        public var penColor: String
        /// Clamped to [0.5, 100].
        public var penWidth: Double
        /// Normalized "#RRGGBB[AA]" fill color.
        public var fillColor: String

        public init(x: Double, y: Double, heading: Double, penDown: Bool, penColor: String, penWidth: Double, fillColor: String) {
            self.x = x
            self.y = y
            self.heading = heading
            self.penDown = penDown
            self.penColor = penColor
            self.penWidth = penWidth
            self.fillColor = fillColor
        }

        /// Defaults per §4.2: home position (card center), heading 0
        /// (up), pen down, black pen at width 2, black fill.
        public static func defaults(canvas: Canvas) -> ScalarState {
            ScalarState(
                x: canvas.width / 2,
                y: canvas.height / 2,
                heading: 0,
                penDown: true,
                penColor: "#000000",
                penWidth: 2,
                fillColor: "#000000"
            )
        }

        private static let encodingVersion = "v1"
        private static let fieldSeparator: Character = "|"

        /// `"v1|x|y|heading|penDownFlag|penWidth|penColor|fillColor"`.
        /// Numbers encode via `String(Double)` (full precision, unlike
        /// `HypeTalkFormat.number` which drops `.0`); the pen-down flag
        /// is `"1"`/`"0"`. This is the only turtle state ever written
        /// into `document.scriptGlobals` (Condition 9) — never the
        /// `.hype` document itself.
        public var encoded: String {
            [
                Self.encodingVersion,
                String(x), String(y), String(heading),
                penDown ? "1" : "0",
                String(penWidth),
                penColor, fillColor,
            ].joined(separator: String(Self.fieldSeparator))
        }

        /// Decodes `encoded`. Returns `nil` on any malformed input —
        /// the caller falls back to `defaults(canvas:)`. Session
        /// globals are a soft channel; a hand-edited or corrupted value
        /// must never crash a run.
        public init?(encoded: String) {
            let fields = encoded.split(separator: Self.fieldSeparator, omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 8, fields[0] == Self.encodingVersion,
                  let x = Double(fields[1]), let y = Double(fields[2]),
                  let heading = Double(fields[3]),
                  let penWidth = Double(fields[5]) else {
                return nil
            }
            self.x = x
            self.y = y
            self.heading = heading
            self.penDown = fields[4] == "1"
            self.penWidth = penWidth
            self.penColor = fields[6]
            self.fillColor = fields[7]
        }
    }

    // MARK: - Command

    public enum Command: Sendable, Equatable {
        case forward(Double)
        case back(Double)
        case right(Double)
        case left(Double)
        case setHeading(Double)
        case setPos(x: Double, y: Double)
        case home
        case penUp
        case penDown
        case setPenColor(String)
        case setPenWidth(Double)
        case setFillColor(String)
        case beginFill
        case endFill
        case circle(radius: Double)
        case arc(degrees: Double, radius: Double)
        /// `nil` diameter → engine default `max(2·penWidth, 4)`.
        case dot(diameter: Double?)
        case clean
        case clearScreen
        case resetTurtle
    }

    // MARK: - Emission

    public struct FrameRect: Sendable, Equatable {
        public var left: Double
        public var top: Double
        public var width: Double
        public var height: Double

        public init(left: Double, top: Double, width: Double, height: Double) {
            self.left = left
            self.top = top
            self.width = width
            self.height = height
        }
    }

    /// One shape ready to become a `Part` (via `TurtlePartApplier`).
    public struct Emission: Sendable, Equatable {
        public enum Kind: String, Sendable {
            case path, fill, dot
        }

        public var kind: Kind
        /// Absolute card coordinates, draw order. Empty for `.dot`.
        public var pathData: [PathPoint]
        /// §5.1 frame math, computed by the engine.
        public var frame: FrameRect
        /// `""` for stroke (`.path`) emissions.
        public var fillColor: String
        public var strokeColor: String
        public var strokeWidth: Double

        public init(kind: Kind, pathData: [PathPoint], frame: FrameRect, fillColor: String, strokeColor: String, strokeWidth: Double) {
            self.kind = kind
            self.pathData = pathData
            self.frame = frame
            self.fillColor = fillColor
            self.strokeColor = strokeColor
            self.strokeWidth = strokeWidth
        }
    }

    /// The result of `perform(_:)` / `endRun()`: zero or more shapes to
    /// apply, whether existing turtle-named parts should be deleted
    /// first (`clean` / `clearScreen`), and an optional note for
    /// `the result` (E6 / E7).
    public struct Outcome: Sendable {
        public var emissions: [Emission]
        public var deletesTurtleParts: Bool
        public var resultNote: String?

        public init(emissions: [Emission] = [], deletesTurtleParts: Bool = false, resultNote: String? = nil) {
            self.emissions = emissions
            self.deletesTurtleParts = deletesTurtleParts
            self.resultNote = resultNote
        }

        public static let empty = Outcome()
    }

    /// `LocalizedError` with `errorDescription == message` (the
    /// `PartPropertyError` precedent, `PartPropertyRegistry.swift`) so
    /// the message survives any generic `catch` byte-identically.
    public struct TurtleError: Error, LocalizedError, Sendable, Equatable {
        public let message: String
        public var errorDescription: String? { message }

        public init(_ message: String) {
            self.message = message
        }
    }

    // MARK: - Error copy (single owner — Condition 3)

    /// Every turtle error string, in one place. Nothing else may
    /// compose turtle error text; the interpreter and the AI executor
    /// surface these verbatim.
    enum ErrorCopy {
        /// Raw user input embedded in an error message is capped so a
        /// pathological script value can't blow up the message
        /// (`PartPropertyRegistry` echoed-input precedent).
        static let maxEchoedInputLength = 200

        /// E1.
        static func notAColor(_ raw: String) -> String {
            "turtle: \"\(clip(raw))\" isn't a color — use #RRGGBB, #RRGGBBAA, or a name like red, blue, orange."
        }

        /// E2 (`circle`/`arc` radius).
        static func needsPositiveRadius(shape: String, got: Double) -> String {
            "turtle: \(shape) needs a radius greater than 0 (got \(HypeTalkFormat.number(got)))."
        }

        /// E2 (`dot` diameter).
        static func needsPositiveDiameter(got: Double) -> String {
            "turtle: dot needs a diameter greater than 0 (got \(HypeTalkFormat.number(got)))."
        }

        /// E4.
        static let alreadyFilling = "turtle: already filling — call endFill before starting another fill."
        /// E5.
        static let endFillWithoutBeginFill = "turtle: endFill without beginFill — nothing to fill."
        /// E6 (resultNote).
        static let fillTooFewPoints = "turtle: fill needs at least 3 points — nothing drawn."
        /// E7 (resultNote).
        static let unclosedFill = "turtle: beginFill was never closed — no fill drawn."
        /// E8.
        static let drawingLimitReached = "turtle: drawing limit reached — a single run may draw at most 200 shapes and 50000 points."

        /// E9 (composed by `TurtleProgramValidator`, P3).
        static func notATurtleCommand(line: Int, text: String) -> String {
            "turtle: line \(line) isn't a turtle command (\"\(clip(text))\") — draw_with_turtle accepts only turtle commands and repeat loops."
        }

        /// Property SET on `xcor`/`ycor`.
        static func readOnlyUseSetPosition(_ name: String) -> String {
            "\"\(name)\" of the turtle is read-only — set the position instead."
        }

        /// Property SET on `filling`.
        static let filingReadOnly = "\"filling\" of the turtle is read-only — use beginFill and endFill."

        /// Unknown property name (GET or SET).
        static func noSuchProperty(_ name: String) -> String {
            "no such property \"\(name)\" for the turtle — the turtle has position, xcor, ycor, heading, penDown, penColor, penWidth, fillColor, and filling."
        }

        /// Tool-only size cap (not an E-number; composed by
        /// `TurtleProgramValidator`, P3).
        static let programTooLarge = "turtle: program is too large — the limit is 65536 bytes."

        /// Tool-only pre-parse nesting guard (not an E-number; composed
        /// by `TurtleProgramValidator`, P3 — Security A2 hardening). Runs
        /// BEFORE the recursive-descent parser ever sees the token
        /// stream, so a pathologically nested program is refused
        /// cleanly instead of reaching the parser's ~800-level SIGBUS
        /// threshold (measured on an 8 MB stack).
        static func nestingTooDeep(line: Int) -> String {
            "turtle: line \(line) is nested too deeply — draw_with_turtle allows at most 200 levels of nested parentheses or repeat loops."
        }

        private static func clip(_ raw: String) -> String {
            raw.count > maxEchoedInputLength ? String(raw.prefix(maxEchoedInputLength)) : raw
        }
    }

    // MARK: - Limits

    /// Session-globals key turtle scalar state is stored under. MUST
    /// stay lowercase (`Interpreter.messageBoxKey` precedent).
    public static let sessionGlobalKey = "__turtle"
    public static let maxPartsPerRun = 200
    public static let maxPathPointsPerRun = 50_000
    public static let positionLimit: Double = 1_000_000

    // MARK: - Instance state

    private var canvas: Canvas
    private var state: ScalarState
    private var strokeBuffer: [PathPoint] = []
    /// `nil` when not filling; holds the accumulated polygon vertices
    /// (seeded with the start position by `beginFill`) while filling.
    private var fillBuffer: [PathPoint]?
    private var emittedPartCount = 0
    private var emittedPointCount = 0

    public init(canvas: Canvas, restoring: ScalarState?) {
        self.canvas = canvas
        self.state = restoring ?? ScalarState.defaults(canvas: canvas)
    }

    public var scalarState: ScalarState { state }
    public var isFilling: Bool { fillBuffer != nil }
    public var hasOpenStroke: Bool { !strokeBuffer.isEmpty }

    // MARK: - perform

    /// Executes one command. Throws `TurtleError` for E1, E2, E4, E5,
    /// E8. A command either fully emits or throws with state
    /// unchanged — every case below validates and reserves capacity
    /// before mutating any stored property, so a thrown error never
    /// leaves partial state behind.
    public mutating func perform(_ command: Command) throws -> Outcome {
        switch command {
        case .forward(let n):
            let distance = TurtleEngine.sanitizedNumber(n)
            return try move(to: TurtleEngine.project(from: (state.x, state.y), distance: distance, heading: state.heading))

        case .back(let n):
            let distance = TurtleEngine.sanitizedNumber(n)
            return try move(to: TurtleEngine.project(from: (state.x, state.y), distance: -distance, heading: state.heading))

        case .right(let d):
            state.heading = TurtleEngine.normalizeHeading(state.heading + TurtleEngine.sanitizedNumber(d))
            return .empty

        case .left(let d):
            state.heading = TurtleEngine.normalizeHeading(state.heading - TurtleEngine.sanitizedNumber(d))
            return .empty

        case .setHeading(let h):
            state.heading = TurtleEngine.normalizeHeading(TurtleEngine.sanitizedNumber(h))
            return .empty

        case .setPos(let x, let y):
            return try move(to: (TurtleEngine.sanitizedNumber(x), TurtleEngine.sanitizedNumber(y)))

        case .home:
            let outcome = try move(to: (canvas.width / 2, canvas.height / 2))
            state.heading = 0
            return outcome

        case .penUp:
            let flushed = try flushOpenStroke()
            state.penDown = false
            return flushed.map { Outcome(emissions: [$0]) } ?? .empty

        case .penDown:
            state.penDown = true
            return .empty

        case .setPenColor(let raw):
            guard let normalized = HexColor.normalized(raw), !normalized.isEmpty else {
                throw TurtleError(ErrorCopy.notAColor(raw))
            }
            guard normalized != state.penColor else { return .empty }
            let flushed = try flushOpenStroke()
            state.penColor = normalized
            return flushed.map { Outcome(emissions: [$0]) } ?? .empty

        case .setPenWidth(let w):
            let clamped = min(100, max(0.5, TurtleEngine.sanitizedNumber(w)))
            guard clamped != state.penWidth else { return .empty }
            let flushed = try flushOpenStroke()
            state.penWidth = clamped
            return flushed.map { Outcome(emissions: [$0]) } ?? .empty

        case .setFillColor(let raw):
            // Deviations d7: "" (the app-wide auto sentinel) is not a
            // valid pen/fill color here — nil or empty both raise E1.
            guard let normalized = HexColor.normalized(raw), !normalized.isEmpty else {
                throw TurtleError(ErrorCopy.notAColor(raw))
            }
            // setFillColor never flushes the open stroke (only pen
            // color/width changes do, per §4.4's flush trigger list).
            state.fillColor = normalized
            return .empty

        case .beginFill:
            guard !isFilling else { throw TurtleError(ErrorCopy.alreadyFilling) }
            let candidate = candidateStrokeEmission()
            try reserveCapacity(points: 1, emissions: candidate != nil ? 1 : 0)
            strokeBuffer = []
            fillBuffer = [PathPoint(x: state.x, y: state.y)]
            return candidate.map { Outcome(emissions: [$0]) } ?? .empty

        case .endFill:
            guard let buffer = fillBuffer else { throw TurtleError(ErrorCopy.endFillWithoutBeginFill) }
            guard buffer.count >= 3 else {
                fillBuffer = nil
                return Outcome(resultNote: ErrorCopy.fillTooFewPoints)
            }
            try reserveCapacity(points: 0, emissions: 1)
            fillBuffer = nil
            let strokeWidth = state.penDown ? state.penWidth : 0
            let emission = Emission(
                kind: .fill,
                pathData: buffer,
                frame: TurtleEngine.frame(for: buffer, strokeWidth: strokeWidth),
                fillColor: state.fillColor,
                strokeColor: state.penColor,
                strokeWidth: strokeWidth
            )
            return Outcome(emissions: [emission])

        case .circle(let radius):
            let r = TurtleEngine.sanitizedNumber(radius)
            guard r > 0 else { throw TurtleError(ErrorCopy.needsPositiveRadius(shape: "circle", got: r)) }
            let points = TurtleEngine.circlePoints(center: (state.x, state.y), heading: state.heading, radius: r)
            return try emitCurve(points)

        case .arc(let degrees, let radius):
            let r = TurtleEngine.sanitizedNumber(radius)
            guard r > 0 else { throw TurtleError(ErrorCopy.needsPositiveRadius(shape: "arc", got: r)) }
            let clampedDegrees = min(360, max(-360, TurtleEngine.sanitizedNumber(degrees)))
            guard clampedDegrees != 0 else { return .empty }
            let points = TurtleEngine.arcPoints(center: (state.x, state.y), heading: state.heading, radius: r, degrees: clampedDegrees)
            return try emitCurve(points)

        case .dot(let diameter):
            let d: Double
            if let diameter {
                let sanitized = TurtleEngine.sanitizedNumber(diameter)
                guard sanitized > 0 else { throw TurtleError(ErrorCopy.needsPositiveDiameter(got: sanitized)) }
                d = sanitized
            } else {
                d = max(2 * state.penWidth, 4)
            }
            try reserveCapacity(points: 0, emissions: 1)
            let frame = FrameRect(left: state.x - d / 2, top: state.y - d / 2, width: d, height: d)
            let emission = Emission(kind: .dot, pathData: [], frame: frame, fillColor: state.penColor, strokeColor: state.penColor, strokeWidth: 0)
            return Outcome(emissions: [emission])

        case .clean:
            strokeBuffer = []
            fillBuffer = nil
            return Outcome(deletesTurtleParts: true)

        case .clearScreen:
            strokeBuffer = []
            fillBuffer = nil
            state.x = canvas.width / 2
            state.y = canvas.height / 2
            state.heading = 0
            return Outcome(deletesTurtleParts: true)

        case .resetTurtle:
            strokeBuffer = []
            fillBuffer = nil
            state = ScalarState.defaults(canvas: canvas)
            return .empty
        }
    }

    /// End-of-run / navigation flush (§4.5, §5.3): emits the open
    /// stroke when it has ≥ 2 vertices and non-zero length, discards
    /// an open fill and reports E7. Never throws — unlike `perform`,
    /// the final flush may emit even at the 200-part cap (bounded by
    /// at most one extra emission; E8 never applies here).
    public mutating func endRun() -> Outcome {
        var emissions: [Emission] = []
        if let candidate = candidateStrokeEmission() {
            emissions.append(candidate)
            emittedPartCount += 1
        }
        strokeBuffer = []

        var resultNote: String?
        if fillBuffer != nil {
            fillBuffer = nil
            resultNote = ErrorCopy.unclosedFill
        }
        return Outcome(emissions: emissions, resultNote: resultNote)
    }

    // MARK: - Property surface (§4.6)

    /// GET. Unknown name → `TurtleError`.
    public func propertyValue(_ name: String) throws -> String {
        switch TurtleEngine.normalizePropertyName(name) {
        case "position", "loc", "location":
            return "\(HypeTalkFormat.number(state.x)),\(HypeTalkFormat.number(state.y))"
        case "xcor":
            return HypeTalkFormat.number(state.x)
        case "ycor":
            return HypeTalkFormat.number(state.y)
        case "heading":
            return HypeTalkFormat.number(state.heading)
        case "pendown":
            return state.penDown ? "true" : "false"
        case "pencolor":
            return state.penColor
        case "penwidth":
            return HypeTalkFormat.number(state.penWidth)
        case "fillcolor":
            return state.fillColor
        case "filling":
            return isFilling ? "true" : "false"
        default:
            throw TurtleError(ErrorCopy.noSuchProperty(name))
        }
    }

    /// SET. Read-only / unknown / invalid value → `TurtleError`.
    /// Position and pen sets reuse the corresponding `Command` paths
    /// (so behavior is identical to the equivalent command — R12).
    public mutating func setProperty(_ name: String, to value: String) throws -> Outcome {
        switch TurtleEngine.normalizePropertyName(name) {
        case "position", "loc", "location":
            let parts = value.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            let x = parts.count > 0 ? HypeTalkFormat.number(from: parts[0]) : 0
            let y = parts.count > 1 ? HypeTalkFormat.number(from: parts[1]) : 0
            return try perform(.setPos(x: x, y: y))
        case "xcor":
            throw TurtleError(ErrorCopy.readOnlyUseSetPosition(name))
        case "ycor":
            throw TurtleError(ErrorCopy.readOnlyUseSetPosition(name))
        case "heading":
            return try perform(.setHeading(HypeTalkFormat.number(from: value)))
        case "pendown":
            return try perform(HypeTalkFormat.isTruthy(value) ? .penDown : .penUp)
        case "pencolor":
            return try perform(.setPenColor(value))
        case "penwidth":
            return try perform(.setPenWidth(HypeTalkFormat.number(from: value)))
        case "fillcolor":
            return try perform(.setFillColor(value))
        case "filling":
            throw TurtleError(ErrorCopy.filingReadOnly)
        default:
            throw TurtleError(ErrorCopy.noSuchProperty(name))
        }
    }

    private static func normalizePropertyName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - Movement

    /// Applies a move from the current position to `newPosition`
    /// (clamped to ±`positionLimit`), respecting pen/fill state per
    /// the buffering rules (§4.3): filling always records the
    /// destination (deduped against the polygon's last vertex,
    /// Deviations d6); pen-down-and-not-filling opens/extends the
    /// stroke buffer; pen-up-and-not-filling moves only. Reserves
    /// capacity (may throw E8) before appending any point, and before
    /// mutating `state.x`/`state.y`, so a throw leaves position and
    /// buffers untouched.
    private mutating func move(to newPosition: (x: Double, y: Double)) throws -> Outcome {
        let clamped = TurtleEngine.clampPosition(newPosition)
        let origin = PathPoint(x: state.x, y: state.y)
        let destination = PathPoint(x: clamped.x, y: clamped.y)

        if var fill = fillBuffer {
            if fill.last != destination {
                try reserveCapacity(points: 1, emissions: 0)
                fill.append(destination)
                fillBuffer = fill
            }
        } else if state.penDown {
            if strokeBuffer.isEmpty {
                let pointsNeeded = destination == origin ? 1 : 2
                try reserveCapacity(points: pointsNeeded, emissions: 0)
                strokeBuffer.append(origin)
                if destination != origin { strokeBuffer.append(destination) }
            } else if strokeBuffer.last != destination {
                try reserveCapacity(points: 1, emissions: 0)
                strokeBuffer.append(destination)
            }
        }

        state.x = clamped.x
        state.y = clamped.y
        return .empty
    }

    /// `circle`/`arc`: while filling, the curve's vertices feed the
    /// fill polygon (Deviations d4, parity with movement); otherwise
    /// the curve is its own standalone stroke emission. Either way the
    /// turtle does not move.
    private mutating func emitCurve(_ points: [PathPoint]) throws -> Outcome {
        if var fill = fillBuffer {
            try reserveCapacity(points: points.count, emissions: 0)
            fill.append(contentsOf: points)
            fillBuffer = fill
            return .empty
        }
        try reserveCapacity(points: points.count, emissions: 1)
        let emission = Emission(
            kind: .path,
            pathData: points,
            frame: TurtleEngine.frame(for: points, strokeWidth: state.penWidth),
            fillColor: "",
            strokeColor: state.penColor,
            strokeWidth: state.penWidth
        )
        return Outcome(emissions: [emission])
    }

    /// Flushes the open stroke buffer, if any: emits it (reserving one
    /// part slot — may throw E8, leaving the buffer intact) when it
    /// has ≥ 2 vertices and non-zero length, otherwise discards it
    /// silently. Vertex points were already reserved at append time,
    /// so only the emission slot is reserved here.
    @discardableResult
    private mutating func flushOpenStroke() throws -> Emission? {
        guard let candidate = candidateStrokeEmission() else {
            strokeBuffer = []
            return nil
        }
        try reserveCapacity(points: 0, emissions: 1)
        strokeBuffer = []
        return candidate
    }

    /// Pure: what the open stroke buffer would emit right now, or nil
    /// when it doesn't qualify (§4.5: ≥ 2 vertices, non-zero length).
    private func candidateStrokeEmission() -> Emission? {
        guard strokeBuffer.count >= 2, TurtleEngine.polylineLength(strokeBuffer) > 0 else { return nil }
        return Emission(
            kind: .path,
            pathData: strokeBuffer,
            frame: TurtleEngine.frame(for: strokeBuffer, strokeWidth: state.penWidth),
            fillColor: "",
            strokeColor: state.penColor,
            strokeWidth: state.penWidth
        )
    }

    // MARK: - Limits (§5.5)

    /// Checks and commits the shared per-run counters. Throws E8
    /// atomically — nothing is committed on a throw — when either
    /// counter would exceed its cap.
    private mutating func reserveCapacity(points: Int, emissions: Int) throws {
        guard emittedPointCount + points <= Self.maxPathPointsPerRun,
              emittedPartCount + emissions <= Self.maxPartsPerRun else {
            throw TurtleError(ErrorCopy.drawingLimitReached)
        }
        emittedPointCount += points
        emittedPartCount += emissions
    }

    // MARK: - Geometry helpers (static, pure)

    /// Non-finite numeric arguments coerce to 0 (§5's input-hygiene
    /// rule), applied before any command-specific rule (clamp, sign
    /// check, etc).
    private static func sanitizedNumber(_ n: Double) -> Double {
        n.isFinite ? n : 0
    }

    private static func clampPosition(_ p: (x: Double, y: Double)) -> (x: Double, y: Double) {
        (clampCoordinate(p.x), clampCoordinate(p.y))
    }

    private static func clampCoordinate(_ v: Double) -> Double {
        guard v.isFinite else { return 0 }
        return min(positionLimit, max(-positionLimit, v))
    }

    /// `normalize(h) = ((h mod 360) + 360) mod 360`.
    private static func normalizeHeading(_ h: Double) -> Double {
        let m = h.truncatingRemainder(dividingBy: 360)
        return (m + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Cardinal-snapped sine: exact `{0, 1, 0, -1}` at 0/90/180/270 so
    /// axis-aligned movement (and the closing vertex of a square) is
    /// exact, not epsilon-off. `degrees` must already be normalized to
    /// [0, 360).
    private static func sinDeg(_ degrees: Double) -> Double {
        switch degrees {
        case 0: return 0
        case 90: return 1
        case 180: return 0
        case 270: return -1
        default: return sin(degrees * .pi / 180)
        }
    }

    /// Cardinal-snapped cosine — see `sinDeg`.
    private static func cosDeg(_ degrees: Double) -> Double {
        switch degrees {
        case 0: return 1
        case 90: return 0
        case 180: return -1
        case 270: return 0
        default: return cos(degrees * .pi / 180)
        }
    }

    /// `dx = n·sinDeg(h)`, `dy = −n·cosDeg(h)` — heading 0 is up,
    /// clockwise positive, y-down card coordinates.
    private static func project(from origin: (x: Double, y: Double), distance: Double, heading: Double) -> (x: Double, y: Double) {
        let h = normalizeHeading(heading)
        return (origin.x + distance * sinDeg(h), origin.y - distance * cosDeg(h))
    }

    private static func vertexOnCircle(center: (x: Double, y: Double), heading: Double, radius: Double) -> PathPoint {
        let h = normalizeHeading(heading)
        return PathPoint(x: center.x + radius * sinDeg(h), y: center.y - radius * cosDeg(h))
    }

    /// 60 segments, 61 vertices, centered on the turtle; vertex 60 is
    /// copied from vertex 0 for exact closure (not re-derived by
    /// trig, which would leave a sub-epsilon gap).
    private static func circlePoints(center: (x: Double, y: Double), heading: Double, radius: Double) -> [PathPoint] {
        var points: [PathPoint] = []
        points.reserveCapacity(61)
        for i in 0..<60 {
            points.append(vertexOnCircle(center: center, heading: heading + Double(i) * 6, radius: radius))
        }
        points.append(points[0])
        return points
    }

    /// `n = max(8, ceil(|degrees|/6))` segments, `n + 1` vertices, at
    /// `heading + degrees·i/n` for `i` in `0...n`. `degrees` is
    /// already clamped to [-360, 360] and non-zero by the caller.
    private static func arcPoints(center: (x: Double, y: Double), heading: Double, radius: Double, degrees: Double) -> [PathPoint] {
        let n = max(8, Int(ceil(abs(degrees) / 6)))
        let step = degrees / Double(n)
        return (0...n).map { i in
            vertexOnCircle(center: center, heading: heading + Double(i) * step, radius: radius)
        }
    }

    private static func polylineLength(_ points: [PathPoint]) -> Double {
        guard points.count >= 2 else { return 0 }
        var total = 0.0
        for i in 1..<points.count {
            total += hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
        }
        return total
    }

    /// §5.1: tight bounding box of `points`, padded by `strokeWidth/2`
    /// per side, with a 1×1 point minimum so a degenerate shape still
    /// has a renderable frame.
    private static func frame(for points: [PathPoint], strokeWidth: Double) -> FrameRect {
        guard let first = points.first else {
            return FrameRect(left: 0, top: 0, width: 1, height: 1)
        }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }
        let pad = strokeWidth / 2
        return FrameRect(
            left: minX - pad,
            top: minY - pad,
            width: max(1, (maxX - minX) + 2 * pad),
            height: max(1, (maxY - minY) + 2 * pad)
        )
    }
}

// MARK: - TurtleVocabulary (D3)

/// Shared turtle-verb recognition — the parser gate (P2) and the AI
/// program validator (P3) both consult this so the vocabulary is
/// defined exactly once.
public enum TurtleVocabulary {
    /// Verbs that parse as a command with no trailing expression.
    public static let zeroArgumentVerbs: Set<String> = [
        "penup", "pendown", "pu", "pd", "home",
        "beginfill", "endfill", "clean", "clearscreen", "cs", "dot",
    ]

    private static let allVerbs: Set<String> = [
        "forward", "fd", "back", "bk", "right", "rt", "left", "lt",
        "setheading", "seth", "setpos", "setxy", "home",
        "penup", "pu", "pendown", "pd",
        "setpencolor", "setpenwidth", "setpensize", "setfillcolor",
        "beginfill", "endfill", "circle", "arc", "dot",
        "clean", "clearscreen", "cs",
    ]

    /// `lowercasedVerb` must already be lowercased.
    public static func isTurtleVerb(_ lowercasedVerb: String) -> Bool {
        allVerbs.contains(lowercasedVerb)
    }

    /// Builds the corresponding `TurtleEngine.Command`, coercing
    /// numeric arguments via `HypeTalkFormat.number(from:)`. Accepts
    /// `args.count` ≥ the verb's required count (extras ignored,
    /// HyperCard tolerance); missing numeric args coerce to 0. `verb`
    /// must already be lowercased. Returns `nil` for a non-turtle verb.
    public static func command(verb: String, args: [String]) -> TurtleEngine.Command? {
        func number(_ index: Int) -> Double {
            guard index < args.count else { return 0 }
            return HypeTalkFormat.number(from: args[index])
        }

        switch verb {
        case "forward", "fd": return .forward(number(0))
        case "back", "bk": return .back(number(0))
        case "right", "rt": return .right(number(0))
        case "left", "lt": return .left(number(0))
        case "setheading", "seth": return .setHeading(number(0))
        case "setpos", "setxy": return .setPos(x: number(0), y: number(1))
        case "home": return .home
        case "penup", "pu": return .penUp
        case "pendown", "pd": return .penDown
        case "setpencolor": return .setPenColor(args.first ?? "")
        case "setpenwidth", "setpensize": return .setPenWidth(number(0))
        case "setfillcolor": return .setFillColor(args.first ?? "")
        case "beginfill": return .beginFill
        case "endfill": return .endFill
        case "circle": return .circle(radius: number(0))
        case "arc": return .arc(degrees: number(0), radius: number(1))
        case "dot": return .dot(diameter: args.isEmpty ? nil : number(0))
        case "clean": return .clean
        case "clearscreen", "cs": return .clearScreen
        default: return nil
        }
    }
}
