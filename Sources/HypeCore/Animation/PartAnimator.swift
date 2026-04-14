import Foundation

/// A single in-flight property animation on a standard part.
public struct PartAnimation: Sendable {
    public let id: UUID
    public let partId: UUID
    public let property: String
    public let fromValue: Double
    public let toValue: Double
    /// For point properties (loc), this holds the Y component.
    public let fromValueY: Double?
    public let toValueY: Double?
    public let startTime: CFTimeInterval
    public let duration: Double

    public init(id: UUID = UUID(), partId: UUID, property: String,
                fromValue: Double, toValue: Double,
                fromValueY: Double? = nil, toValueY: Double? = nil,
                startTime: CFTimeInterval, duration: Double) {
        self.id = id
        self.partId = partId
        self.property = property
        self.fromValue = fromValue
        self.toValue = toValue
        self.fromValueY = fromValueY
        self.toValueY = toValueY
        self.startTime = startTime
        self.duration = duration
    }
}

#if canImport(AppKit)
import AppKit

/// Timer-driven animation engine for standard HypeTalk parts.
/// Tweens numeric properties (left, top, width, height, rotation,
/// loc) at ~60fps. The interpreter's `animate` command registers
/// animations here; the tick callback writes property changes
/// back to the document via `onPropertyChange`.
///
/// This runs outside the interpreter (which is synchronous) and
/// uses the main thread's run loop timer -- the same pattern the
/// idle timer uses.
public final class PartAnimator {

    nonisolated(unsafe) public static let shared = PartAnimator()

    private var animations: [PartAnimation] = []
    private var timer: Timer?

    /// Callback invoked on every tick for each property change.
    /// The view layer sets this to write changes into the document
    /// binding and trigger redraws.
    /// Parameters: (partId, property, value as String)
    public var onPropertyChange: ((UUID, String, String) -> Void)?

    /// Callback invoked when an animation completes.
    /// Parameters: (partId, property)
    public var onAnimationComplete: ((UUID, String) -> Void)?

    /// Start a new animation. Replaces any existing animation on
    /// the same part+property.
    public func animate(
        partId: UUID,
        property: String,
        fromValue: Double,
        toValue: Double,
        fromValueY: Double? = nil,
        toValueY: Double? = nil,
        duration: Double
    ) {
        // Remove any existing animation on the same part+property
        animations.removeAll { $0.partId == partId && $0.property == property }

        let anim = PartAnimation(
            partId: partId,
            property: property,
            fromValue: fromValue,
            toValue: toValue,
            fromValueY: fromValueY,
            toValueY: toValueY,
            startTime: CACurrentMediaTime(),
            duration: max(0.001, duration)
        )
        animations.append(anim)
        startTimerIfNeeded()
    }

    /// Stop all animations on a specific part.
    public func stopAnimations(for partId: UUID) {
        animations.removeAll { $0.partId == partId }
        stopTimerIfIdle()
    }

    /// Stop all animations globally.
    public func stopAll() {
        animations.removeAll()
        stopTimerIfIdle()
    }

    /// Check if any animation is active on a specific part.
    public func isAnimating(partId: UUID) -> Bool {
        animations.contains { $0.partId == partId }
    }

    /// Check if a specific property on a part is animating.
    public func isAnimating(partId: UUID, property: String) -> Bool {
        animations.contains { $0.partId == partId && $0.property == property }
    }

    // MARK: - Timer

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        // ~60fps
        let t = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer = t
        // Ensure the timer fires during tracking (scrolling, dragging)
        RunLoop.main.add(t, forMode: .common)
    }

    private func stopTimerIfIdle() {
        guard animations.isEmpty else { return }
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let now = CACurrentMediaTime()
        var completed: [(UUID, String)] = []

        for anim in animations {
            let elapsed = now - anim.startTime
            let progress = min(1.0, elapsed / anim.duration)

            // Ease-in-out cubic for smoother animation
            let easedProgress = easeInOutCubic(progress)

            let currentValue = anim.fromValue + (anim.toValue - anim.fromValue) * easedProgress

            if let fromY = anim.fromValueY, let toY = anim.toValueY {
                // Point property (loc): interpolate both components
                let currentY = fromY + (toY - fromY) * easedProgress
                let formatted = "\(formatNum(currentValue)),\(formatNum(currentY))"
                onPropertyChange?(anim.partId, anim.property, formatted)
            } else {
                onPropertyChange?(anim.partId, anim.property, formatNum(currentValue))
            }

            if progress >= 1.0 {
                completed.append((anim.partId, anim.property))
            }
        }

        // Remove completed animations
        for (partId, property) in completed {
            animations.removeAll { $0.partId == partId && $0.property == property }
            onAnimationComplete?(partId, property)
        }

        stopTimerIfIdle()
    }

    /// Ease-in-out cubic for smooth acceleration/deceleration.
    private func easeInOutCubic(_ t: Double) -> Double {
        if t < 0.5 {
            return 4 * t * t * t
        } else {
            let f = 2 * t - 2
            return 0.5 * f * f * f + 1
        }
    }

    /// Format a Double cleanly: strip trailing zeros.
    private func formatNum(_ v: Double) -> String {
        if v == Double(Int(v)) {
            return String(Int(v))
        }
        return String(format: "%.2f", v)
    }
}
#endif
