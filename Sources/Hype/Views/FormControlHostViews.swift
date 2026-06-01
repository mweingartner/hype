import AppKit
import HypeCore

/// AppKit hosts for the four small form-control parts: stepper,
/// slider, toggle (NSSwitch), and segmented control. Each writes
/// back through a closure when the user interacts, mirroring the
/// patterns used by `CalendarHostNSView` and
/// `ColorWellHostNSView`.

// MARK: - Stepper

final class StepperHostNSView: NSView {
    let valueField = NSTextField(labelWithString: "0")
    let stepper = NSStepper()
    var onValueChange: ((Double) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        valueField.translatesAutoresizingMaskIntoConstraints = false
        valueField.alignment = .center
        valueField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        valueField.backgroundColor = .controlBackgroundColor
        valueField.drawsBackground = true
        valueField.isBordered = true
        addSubview(valueField)

        stepper.translatesAutoresizingMaskIntoConstraints = false
        stepper.target = self
        stepper.action = #selector(stepperDidChange)
        stepper.valueWraps = false
        addSubview(stepper)

        NSLayoutConstraint.activate([
            valueField.topAnchor.constraint(equalTo: topAnchor),
            valueField.bottomAnchor.constraint(equalTo: bottomAnchor),
            valueField.leadingAnchor.constraint(equalTo: leadingAnchor),
            stepper.topAnchor.constraint(equalTo: topAnchor),
            stepper.bottomAnchor.constraint(equalTo: bottomAnchor),
            stepper.leadingAnchor.constraint(equalTo: valueField.trailingAnchor, constant: 2),
            stepper.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var appliedValue: Double?
    private var appliedMin: Double?
    private var appliedMax: Double?
    private var appliedStep: Double?

    func apply(_ part: Part) {
        if part.controlMin != appliedMin {
            stepper.minValue = part.controlMin
            appliedMin = part.controlMin
        }
        if part.controlMax != appliedMax {
            stepper.maxValue = part.controlMax
            appliedMax = part.controlMax
        }
        let step = part.controlStep == 0 ? 1 : part.controlStep
        if step != appliedStep {
            stepper.increment = step
            appliedStep = step
        }
        if part.controlValue != appliedValue {
            stepper.doubleValue = part.controlValue
            valueField.stringValue = formatNumber(part.controlValue)
            appliedValue = part.controlValue
        }
    }

    @objc private func stepperDidChange() {
        valueField.stringValue = formatNumber(stepper.doubleValue)
        appliedValue = stepper.doubleValue
        onValueChange?(stepper.doubleValue)
    }
}

// MARK: - Slider

final class HypeSliderControl: NSSlider {
    var isMouseTracking = false
    var onMouseTrackingBegan: (() -> Void)?
    var onMouseTrackingEnded: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0, bounds.contains(point) else { return nil }
        // Modern AppKit sliders render the thumb through private child views.
        // Route every hit in the control bounds back through NSSlider so our
        // tracking begin/end hooks and AppKit's native drag handling both run.
        return self
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let initialPoint = convert(event.locationInWindow, from: nil)
        isMouseTracking = true
        onMouseTrackingBegan?()
        defer {
            if isMouseTracking {
                isMouseTracking = false
                notifyMouseTrackingEnded()
            }
        }
        if !knobHitRect().contains(initialPoint) {
            _ = setValue(fromLocalPoint: initialPoint)
        }
        super.mouseDown(with: event)
    }

    func notifyMouseTrackingEnded() {
        onMouseTrackingEnded?()
    }

    @discardableResult
    func setValue(fromLocalPoint point: NSPoint, fireAction: Bool = true) -> Bool {
        let nextValue = value(forLocalPoint: point)
        guard nextValue.isFinite else { return false }

        let changed = abs(doubleValue - nextValue) > Double.ulpOfOne
        if changed {
            doubleValue = nextValue
            needsDisplay = true
            if fireAction {
                _ = sendAction(action, to: target)
            }
        }
        return changed
    }

    func value(forLocalPoint point: NSPoint) -> Double {
        let range = maxValue - minValue
        guard range != 0 else { return minValue }

        let rect = effectiveTrackRect()
        let rawPercent: CGFloat
        if isVertical {
            let clampedY = min(max(point.y, rect.minY), rect.maxY)
            if rect.height <= 0 {
                rawPercent = 0
            } else if isFlipped {
                rawPercent = 1 - ((clampedY - rect.minY) / rect.height)
            } else {
                rawPercent = (clampedY - rect.minY) / rect.height
            }
        } else {
            let clampedX = min(max(point.x, rect.minX), rect.maxX)
            rawPercent = rect.width <= 0 ? 0 : (clampedX - rect.minX) / rect.width
        }

        let percent = Double(min(max(rawPercent, 0), 1))
        let value = minValue + range * percent
        return min(max(value, min(minValue, maxValue)), max(minValue, maxValue))
    }

    private func effectiveTrackRect() -> NSRect {
        let length = isVertical ? bounds.height : bounds.width
        let inset = min(CGFloat(6), max(0, length / 2))
        if isVertical {
            return bounds.insetBy(dx: 0, dy: inset)
        }
        return bounds.insetBy(dx: inset, dy: 0)
    }

    private func knobHitRect() -> NSRect {
        sliderCell().knobRect(flipped: isFlipped).insetBy(dx: -8, dy: -8)
    }

    private func sliderCell() -> NSSliderCell {
        if let cell = cell as? NSSliderCell {
            return cell
        }
        let fallback = NSSliderCell()
        fallback.minValue = minValue
        fallback.maxValue = maxValue
        fallback.doubleValue = doubleValue
        return fallback
    }
}

final class SliderHostNSView: NSView {
    let slider = HypeSliderControl()
    var onValueChange: ((Double) -> Void)?
    var onInteractionBegin: (() -> Void)?
    var onInteractionEnd: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.target = self
        slider.action = #selector(sliderDidChange)
        slider.isContinuous = true
        slider.onMouseTrackingBegan = { [weak self] in
            self?.onInteractionBegin?()
        }
        slider.onMouseTrackingEnded = { [weak self] in
            self?.onInteractionEnd?()
        }
        addSubview(slider)
        NSLayoutConstraint.activate([
            slider.topAnchor.constraint(equalTo: topAnchor),
            slider.bottomAnchor.constraint(equalTo: bottomAnchor),
            slider.leadingAnchor.constraint(equalTo: leadingAnchor),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var appliedValue: Double?
    private var appliedMin: Double?
    private var appliedMax: Double?

    func apply(_ part: Part) {
        let shouldBeVertical = part.sliderControlOrientation == .vertical
        if slider.isVertical != shouldBeVertical {
            slider.isVertical = shouldBeVertical
        }
        if part.controlMin != appliedMin {
            slider.minValue = part.controlMin
            appliedMin = part.controlMin
        }
        if part.controlMax != appliedMax {
            slider.maxValue = part.controlMax
            appliedMax = part.controlMax
        }
        if !slider.isMouseTracking && part.controlValue != appliedValue {
            slider.doubleValue = part.controlValue
            appliedValue = part.controlValue
        }
    }

    @objc private func sliderDidChange() {
        appliedValue = slider.doubleValue
        onValueChange?(slider.doubleValue)
    }
}

// ToggleHostNSView removed in dedup — toggle parts migrate to
// button + ButtonStyle.toggle on decode (see Part.init(from:)).
// The button's mouseUp dispatch flips `hilite`, the renderer
// draws the NSSwitch-style track + knob, no live AppKit overlay
// needed.

// MARK: - SegmentedControl

final class SegmentedHostNSView: NSView {
    let segmented = NSSegmentedControl()
    var onValueChange: ((Int) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        segmented.translatesAutoresizingMaskIntoConstraints = false
        segmented.target = self
        segmented.action = #selector(segmentedDidChange)
        segmented.segmentStyle = .rounded
        segmented.trackingMode = .selectOne
        addSubview(segmented)
        NSLayoutConstraint.activate([
            segmented.centerYAnchor.constraint(equalTo: centerYAnchor),
            segmented.leadingAnchor.constraint(equalTo: leadingAnchor),
            segmented.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var appliedSegmentItems: String?
    private var appliedSelected: Int?

    func apply(_ part: Part) {
        if part.segmentItems != appliedSegmentItems {
            let labels = part.segmentItems.split(separator: "|").map(String.init)
            if segmented.segmentCount != labels.count {
                segmented.segmentCount = labels.count
            }
            for (i, label) in labels.enumerated() {
                segmented.setLabel(label, forSegment: i)
                segmented.setWidth(0, forSegment: i)
            }
            appliedSegmentItems = part.segmentItems
        }
        let idx = Int(part.controlValue)
        if idx != appliedSelected {
            let labelCount = part.segmentItems.split(separator: "|").count
            if idx >= 0 && idx < labelCount {
                segmented.selectedSegment = idx
            } else {
                segmented.selectedSegment = 0
            }
            appliedSelected = idx
        }
    }

    @objc private func segmentedDidChange() {
        appliedSelected = segmented.selectedSegment
        onValueChange?(segmented.selectedSegment)
    }
}

// MARK: - Helpers

private func formatNumber(_ d: Double) -> String {
    if d.rounded() == d { return String(Int(d)) }
    return String(format: "%.2f", d)
}
