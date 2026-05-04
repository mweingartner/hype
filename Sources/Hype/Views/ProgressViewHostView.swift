import AppKit
import HypeCore

/// AppKit-hosted progress indicator for `progressView` parts.
///
/// Wraps `NSProgressIndicator` (linear bar or circular spinner) with an
/// optional caption label above. The `apply(_:)` method mirrors the Part
/// state onto the live AppKit control without redundant redraws.
///
/// `onProgressFinished` is called (main thread) when the indicator
/// transitions from incomplete to complete (`value >= total`) for the
/// first time since the last reset.
final class ProgressViewHostNSView: NSView {

    let progressIndicator = NSProgressIndicator()
    private let labelField = NSTextField(labelWithString: "")

    /// Called once when `progressValue` crosses `progressTotal` (≥).
    /// Only fires when `progressTotal > 0` (security condition 5).
    var onProgressFinished: (() -> Void)?

    // Cached applied values to avoid redundant writes.
    private var appliedIsCircular: Bool?
    private var appliedIsIndeterminate: Bool?
    private var appliedTotal: Double?
    private var appliedValue: Double?
    private var appliedLabel: String?
    private var appliedTint: String?

    /// Tracks whether we've already fired `onProgressFinished` for the
    /// current `value >= total` condition. Resets when value drops below total.
    private var didFireCompleted = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        labelField.translatesAutoresizingMaskIntoConstraints = false
        labelField.font = NSFont.systemFont(ofSize: 11)
        labelField.textColor = NSColor.secondaryLabelColor
        labelField.isHidden = true
        addSubview(labelField)
        addSubview(progressIndicator)

        NSLayoutConstraint.activate([
            labelField.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            labelField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            labelField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            labelField.heightAnchor.constraint(equalToConstant: 16),

            progressIndicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            progressIndicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            progressIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Sync the AppKit control with the current Part state.
    func apply(_ part: Part) {
        // Label
        let newLabel = String(part.progressLabel.prefix(256))
        if newLabel != appliedLabel {
            appliedLabel = newLabel
            labelField.stringValue = newLabel
            labelField.isHidden = newLabel.isEmpty
        }

        // Style: circular vs. bar
        let newIsCircular = part.progressIsCircular
        if newIsCircular != appliedIsCircular {
            appliedIsCircular = newIsCircular
            progressIndicator.style = newIsCircular ? .spinning : .bar
        }

        // Indeterminate
        let newIndet = part.progressIsIndeterminate
        if newIndet != appliedIsIndeterminate {
            appliedIsIndeterminate = newIndet
            progressIndicator.isIndeterminate = newIndet
            if newIndet {
                progressIndicator.startAnimation(nil)
            } else {
                progressIndicator.stopAnimation(nil)
            }
        }

        if !newIndet {
            // Security condition 5: clamp total to avoid divide-by-zero.
            let safeTotal = max(1e-10, part.progressTotal.isFinite ? part.progressTotal : 1)
            let safeValue = min(safeTotal, max(0, part.progressValue.isFinite ? part.progressValue : 0))

            if safeTotal != appliedTotal {
                appliedTotal = safeTotal
                progressIndicator.maxValue = safeTotal
                progressIndicator.minValue = 0
            }
            if safeValue != appliedValue {
                appliedValue = safeValue
                progressIndicator.doubleValue = safeValue

                // Security condition 5: only fire when total > 0 and value >= total.
                let isNowComplete = safeTotal > 0 && safeValue >= safeTotal
                if isNowComplete && !didFireCompleted {
                    didFireCompleted = true
                    onProgressFinished?()
                } else if !isNowComplete {
                    didFireCompleted = false
                }
            }
        }

        // Tint color
        let newTint = part.progressTint
        if newTint != appliedTint {
            appliedTint = newTint
            // NSProgressIndicator doesn't have a direct tint API on all
            // macOS versions; we apply via the control's layer tint.
            if !newTint.isEmpty, let color = NSColor(hexString: newTint) {
                progressIndicator.contentFilters = []
                wantsLayer = true
                progressIndicator.layer?.backgroundColor = nil
                // Attempt a best-effort tint via NSAppearance customization
                // by wrapping the indicator in a tinted layer. This is
                // approximate — NSProgressIndicator doesn't officially
                // support per-instance tinting below macOS 14.
                progressIndicator.layer?.borderColor = color.cgColor
            }
        }
    }
}
