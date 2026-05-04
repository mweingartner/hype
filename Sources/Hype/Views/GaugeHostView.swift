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

    var body: some View {
        let gauge = Gauge(value: value, in: bounds) {
            Text(label)
        } currentValueLabel: {
            Text(String(format: "%g", value))
        } minimumValueLabel: {
            Text(minLabel)
        } maximumValueLabel: {
            Text(maxLabel)
        }
        return AnyView(styledGauge(gauge))
            .padding(4)
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
final class GaugeHostNSView: NSView {

    private var hostingView: NSView?

    // Cached last-applied state to avoid redundant SwiftUI updates.
    private var lastValue: Double?
    private var lastMin: Double?
    private var lastMax: Double?
    private var lastStyle: String?
    private var lastTint: String?
    private var lastLabel: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(_ part: Part) {
        // Security condition 5: guard NaN/Inf and enforce max > min.
        let safeMin = part.gaugeMin.isFinite ? part.gaugeMin : 0
        let rawMax = part.gaugeMax.isFinite ? part.gaugeMax : 1
        let safeMax = rawMax > safeMin ? rawMax : safeMin + 1
        let safeValue = min(safeMax, max(safeMin, part.gaugeValue.isFinite ? part.gaugeValue : safeMin))

        let same = (safeValue == lastValue) && (safeMin == lastMin) && (safeMax == lastMax)
            && (part.gaugeStyle == lastStyle) && (part.gaugeTint == lastTint)
            && (part.gaugeLabel == lastLabel)
        guard !same else { return }

        lastValue = safeValue
        lastMin = safeMin
        lastMax = safeMax
        lastStyle = part.gaugeStyle
        lastTint = part.gaugeTint
        lastLabel = part.gaugeLabel

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
                maxLabel: String(part.gaugeMaxLabel.prefix(256))
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
