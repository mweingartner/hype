import AppKit
import SwiftUI
import HypeCore

/// SwiftUI `Gauge` wrapper used inside `GaugeHostNSView`.
///
/// Requires macOS 13+. On earlier OS the host falls back to a simple
/// linear progress bar via `NSProgressIndicator`.
@available(macOS 13.0, *)
struct GaugeHostSwiftView: View {
    let value: Double
    let bounds: ClosedRange<Double>
    let style: String
    let tintHex: String
    let label: String
    let minLabel: String
    let maxLabel: String
    /// Number of fractional digits in the displayed value (and in
    /// the user-scrub writeback — see `GaugeHostNSView.commitValue`).
    /// `0` shows integers only, matching the documented default.
    let decimals: Int

    var body: some View {
        let gauge = Gauge(value: value, in: bounds) {
            Text(label)
        } currentValueLabel: {
            Text(formatValue(value))
        } minimumValueLabel: {
            Text(minLabel)
        } maximumValueLabel: {
            Text(maxLabel)
        }
        return AnyView(styledGauge(gauge))
            .padding(4)
    }

    private func formatValue(_ v: Double) -> String {
        let d = max(0, decimals)
        return String(format: "%.\(d)f", v)
    }

    @ViewBuilder
    private func styledGauge<V: View>(_ view: V) -> some View {
        let tinted = applyTint(to: view)
        switch style {
        case "accessoryCircular":         tinted.gaugeStyle(.accessoryCircular)
        case "accessoryCircularCapacity": tinted.gaugeStyle(.accessoryCircularCapacity)
        case "accessoryLinear":           tinted.gaugeStyle(.accessoryLinear)
        case "accessoryLinearCapacity":   tinted.gaugeStyle(.accessoryLinearCapacity)
        default:                          tinted.gaugeStyle(.linearCapacity)
        }
    }

    @ViewBuilder
    private func applyTint<V: View>(to view: V) -> some View {
        if !tintHex.isEmpty, let nsColor = NSColor(hexString: tintHex) {
            view.tint(Color(nsColor))
        } else {
            view
        }
    }
}

/// AppKit-hosted gauge for `gauge` parts.
///
/// Uses an `NSHostingView<GaugeHostSwiftView>` on macOS 13+ and falls
/// back to an `NSProgressIndicator` on older systems.
///
/// When `part.enabled == true`, the gauge is interactive: click or
/// drag horizontally on the gauge to scrub the value. The closure
/// `onValueChange` fires each tick so the chat / coordinator can
/// write back into the document. Disabled gauges are display-only.
final class GaugeHostNSView: NSView {

    private var hostingView: NSView?
    private var panGesture: NSPanGestureRecognizer?
    private var clickGesture: NSClickGestureRecognizer?

    /// Live state captured at apply() time so the pan/click handlers
    /// can map mouse position → value without re-reading the part.
    private var liveMin: Double = 0
    private var liveMax: Double = 1
    private var liveEnabled: Bool = false
    /// Decimal places to round to when the user scrubs interactively.
    /// 0 = integral steps (the documented default).
    private var liveDecimals: Int = 0

    /// Closure fires whenever the user adjusts the gauge value via
    /// click or drag. Wired in `CardCanvasView.updateGaugeViews` to
    /// the coordinator's writeback.
    var onValueChange: ((Double) -> Void)?

    // Cached last-applied state to avoid redundant SwiftUI updates.
    private var lastValue: Double?
    private var lastMin: Double?
    private var lastMax: Double?
    private var lastStyle: String?
    private var lastTint: String?
    private var lastLabel: String?
    private var lastEnabled: Bool?
    private var lastDecimals: Int?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installGestures()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func installGestures() {
        let pan = NSPanGestureRecognizer(target: self, action: #selector(didPan(_:)))
        addGestureRecognizer(pan)
        panGesture = pan
        let click = NSClickGestureRecognizer(target: self, action: #selector(didClick(_:)))
        addGestureRecognizer(click)
        clickGesture = click
    }

    @objc private func didClick(_ g: NSClickGestureRecognizer) {
        guard liveEnabled else { return }
        commitValue(from: g.location(in: self))
    }

    @objc private func didPan(_ g: NSPanGestureRecognizer) {
        guard liveEnabled else { return }
        commitValue(from: g.location(in: self))
    }

    private func commitValue(from point: NSPoint) {
        let w = max(1, bounds.width)
        let frac = max(0, min(1, point.x / w))
        let raw = liveMin + frac * (liveMax - liveMin)
        // Quantize to the part's `gaugeDecimals` precision so a
        // gauge configured for integer-only steps doesn't write
        // 17.93624… on every drag tick. `decimals = 0` rounds to
        // the nearest integer (the default).
        let d = max(0, liveDecimals)
        let scale = pow(10.0, Double(d))
        let quantized = (raw * scale).rounded() / scale
        onValueChange?(quantized)
    }

    func apply(_ part: Part) {
        // Security condition 5: guard NaN/Inf and enforce max > min.
        let safeMin = part.gaugeMin.isFinite ? part.gaugeMin : 0
        let rawMax = part.gaugeMax.isFinite ? part.gaugeMax : 1
        let safeMax = rawMax > safeMin ? rawMax : safeMin + 1
        let safeValue = min(safeMax, max(safeMin, part.gaugeValue.isFinite ? part.gaugeValue : safeMin))

        // Track live state so gesture handlers can compute values
        // without re-reading the part.
        liveMin = safeMin
        liveMax = safeMax
        liveEnabled = part.enabled
        liveDecimals = max(0, part.gaugeDecimals)

        let same = (safeValue == lastValue) && (safeMin == lastMin) && (safeMax == lastMax)
            && (part.gaugeStyle == lastStyle) && (part.gaugeTint == lastTint)
            && (part.gaugeLabel == lastLabel) && (part.enabled == lastEnabled)
            && (part.gaugeDecimals == lastDecimals)
        guard !same else { return }

        lastValue = safeValue
        lastMin = safeMin
        lastMax = safeMax
        lastStyle = part.gaugeStyle
        lastTint = part.gaugeTint
        lastLabel = part.gaugeLabel
        lastEnabled = part.enabled
        lastDecimals = part.gaugeDecimals

        // Remove stale view.
        hostingView?.removeFromSuperview()

        if #available(macOS 13.0, *) {
            let swiftView = GaugeHostSwiftView(
                value: safeValue,
                bounds: safeMin...safeMax,
                style: part.gaugeStyle,
                tintHex: part.gaugeTint,
                label: String(part.gaugeLabel.prefix(256)),
                minLabel: String(part.gaugeMinLabel.prefix(256)),
                maxLabel: String(part.gaugeMaxLabel.prefix(256)),
                decimals: max(0, part.gaugeDecimals)
            )
            let hv = NSHostingView(rootView: swiftView)
            hv.translatesAutoresizingMaskIntoConstraints = false
            addSubview(hv)
            NSLayoutConstraint.activate([
                hv.topAnchor.constraint(equalTo: topAnchor),
                hv.leadingAnchor.constraint(equalTo: leadingAnchor),
                hv.trailingAnchor.constraint(equalTo: trailingAnchor),
                hv.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            hostingView = hv
        } else {
            // Fallback: NSProgressIndicator for pre-macOS 13.
            let pi = NSProgressIndicator()
            pi.style = .bar
            pi.isIndeterminate = false
            pi.minValue = safeMin
            pi.maxValue = safeMax
            pi.doubleValue = safeValue
            pi.translatesAutoresizingMaskIntoConstraints = false
            addSubview(pi)
            NSLayoutConstraint.activate([
                pi.centerXAnchor.constraint(equalTo: centerXAnchor),
                pi.centerYAnchor.constraint(equalTo: centerYAnchor),
                pi.widthAnchor.constraint(equalTo: widthAnchor, constant: -8),
            ])
            hostingView = pi
        }
    }
}
