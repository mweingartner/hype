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
/// Threading contract: `animate`, `stopAll`, `stopAnimations(for:)`,
/// and `isAnimating` may be called from any thread. All access to the
/// `animations` array is serialized by `lock`. The timer is always
/// scheduled on the main run loop (via `DispatchQueue.main.async` when
/// the caller is off-main) so the tick fires reliably regardless of
/// which thread registers an animation — matching the fix applied to
/// GIFAnimator. Callbacks (`onPropertyChange`, `onAnimationComplete`)
/// are always invoked on the main thread by the timer tick.
public final class PartAnimator: @unchecked Sendable {

    public static let shared = PartAnimator()

    /// Guards all reads and writes of `animations` and `timer`.
    private let lock = NSLock()
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
    /// the same part+property. Safe to call from any thread.
    public func animate(
        partId: UUID,
        property: String,
        fromValue: Double,
        toValue: Double,
        fromValueY: Double? = nil,
        toValueY: Double? = nil,
        duration: Double
    ) {
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
        lock.lock()
        // Remove any existing animation on the same part+property
        animations.removeAll { $0.partId == partId && $0.property == property }
        animations.append(anim)
        let needsTimer = timer == nil
        lock.unlock()

        if needsTimer {
            startTimerOnMain()
        }
    }

    /// Stop all animations on a specific part. Safe to call from any thread.
    public func stopAnimations(for partId: UUID) {
        lock.lock()
        animations.removeAll { $0.partId == partId }
        let idle = animations.isEmpty
        lock.unlock()

        if idle {
            stopTimerOnMain()
        }
    }

    /// Stop all animations globally. Safe to call from any thread.
    public func stopAll() {
        lock.lock()
        animations.removeAll()
        lock.unlock()

        stopTimerOnMain()
    }

    /// Check if any animation is active on a specific part. Safe to call from any thread.
    public func isAnimating(partId: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return animations.contains { $0.partId == partId }
    }

    /// Check if a specific property on a part is animating. Safe to call from any thread.
    public func isAnimating(partId: UUID, property: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return animations.contains { $0.partId == partId && $0.property == property }
    }

    // MARK: - Timer (main-thread only)

    private func startTimerOnMain() {
        if Thread.isMainThread {
            startTimerIfNeeded()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.startTimerIfNeeded()
            }
        }
    }

    private func stopTimerOnMain() {
        if Thread.isMainThread {
            stopTimerIfIdle()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.stopTimerIfIdle()
            }
        }
    }

    /// Must be called on the main thread.
    private func startTimerIfNeeded() {
        lock.lock()
        guard timer == nil else {
            lock.unlock()
            return
        }
        // ~60fps
        let t = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer = t
        lock.unlock()
        // Ensure the timer fires during tracking (scrolling, dragging)
        RunLoop.main.add(t, forMode: .common)
    }

    /// Must be called on the main thread.
    private func stopTimerIfIdle() {
        lock.lock()
        guard animations.isEmpty else {
            lock.unlock()
            return
        }
        let t = timer
        timer = nil
        lock.unlock()
        t?.invalidate()
    }

    /// Invoked by the timer on the main thread.
    private func tick() {
        let now = CACurrentMediaTime()
        var completed: [(UUID, String)] = []

        lock.lock()
        let snapshot = animations
        lock.unlock()

        for anim in snapshot {
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

        // Remove completed animations and fire completion callbacks
        if !completed.isEmpty {
            lock.lock()
            for (partId, property) in completed {
                animations.removeAll { $0.partId == partId && $0.property == property }
            }
            lock.unlock()

            for (partId, property) in completed {
                onAnimationComplete?(partId, property)
            }
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
