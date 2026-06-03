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

/// Runtime slider host owned entirely by Hype.
///
/// We intentionally do not use `NSSlider` here. AppKit's private slider
/// tracking behavior has repeatedly proven fragile inside Hype's canvas
/// overlay stack, especially for "click the value line" interactions.
/// This view draws the slider and owns click/drag tracking directly while
/// still writing through the same coordinator closures as every form control.
final class SliderHostNSView: NSView {
    var onValueChange: ((Double) -> Void)?
    var onInteractionBegin: (() -> Void)?
    var onInteractionEnd: (() -> Void)?

    private(set) var isMouseTracking = false
    private(set) var controlMin: Double = 0
    private(set) var controlMax: Double = 100
    private(set) var controlValue: Double = 0
    private(set) var orientation: SliderControlOrientation = .horizontal

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) { super.init(frame: frameRect) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var appliedValue: Double?
    private var appliedMin: Double?
    private var appliedMax: Double?
    private var appliedOrientation: SliderControlOrientation?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0, bounds.contains(point) else { return nil }
        // Own the full part rect so the control remains interactive even when
        // AppKit's private NSSlider subviews do not expose a stable hit target.
        return self
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        trackMouseSequence(startingWith: event)
    }

    override func mouseDragged(with event: NSEvent) {
        continueMouseTracking(atLocalPoint: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        endMouseTracking(atLocalPoint: convert(event.locationInWindow, from: nil))
    }

    private func trackMouseSequence(startingWith event: NSEvent) {
        beginMouseTracking(atLocalPoint: convert(event.locationInWindow, from: nil))
        defer {
            if isMouseTracking {
                cancelMouseTracking()
            }
        }
        guard let window else { return }

        while isMouseTracking {
            guard let nextEvent = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else {
                break
            }

            let point = convert(nextEvent.locationInWindow, from: nil)
            switch nextEvent.type {
            case .leftMouseDragged:
                continueMouseTracking(atLocalPoint: point)
            case .leftMouseUp:
                endMouseTracking(atLocalPoint: point)
            default:
                break
            }
        }
    }

    func apply(_ part: Part) {
        let shouldBeVertical = part.sliderControlOrientation == .vertical
        let nextOrientation: SliderControlOrientation = shouldBeVertical ? .vertical : .horizontal
        if nextOrientation != appliedOrientation {
            orientation = nextOrientation
            appliedOrientation = nextOrientation
            needsDisplay = true
        }
        if part.controlMin != appliedMin {
            controlMin = part.controlMin
            appliedMin = part.controlMin
            needsDisplay = true
        }
        if part.controlMax != appliedMax {
            controlMax = part.controlMax
            appliedMax = part.controlMax
            needsDisplay = true
        }
        if !isMouseTracking && part.controlValue != appliedValue {
            controlValue = clampedValue(part.controlValue)
            appliedValue = part.controlValue
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let track = trackRect()
        let trackPath = NSBezierPath(roundedRect: track, xRadius: track.height / 2, yRadius: track.height / 2)
        NSColor.tertiaryLabelColor.withAlphaComponent(0.8).setFill()
        trackPath.fill()

        let activeTrack = activeTrackRect(in: track)
        if !activeTrack.isEmpty {
            let activePath = NSBezierPath(roundedRect: activeTrack, xRadius: activeTrack.height / 2, yRadius: activeTrack.height / 2)
            NSColor.controlAccentColor.withAlphaComponent(0.55).setFill()
            activePath.fill()
        }

        let knob = knobRect(in: track)
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(ovalIn: knob.insetBy(dx: -1, dy: -1)).fill()
        (isMouseTracking ? NSColor.controlAccentColor : NSColor.labelColor).withAlphaComponent(isMouseTracking ? 0.95 : 0.75).setStroke()
        let knobPath = NSBezierPath(ovalIn: knob)
        knobPath.lineWidth = isMouseTracking ? 2 : 1
        knobPath.stroke()
        NSColor.controlAccentColor.setFill()
        knobPath.fill()
    }

    func beginMouseTracking(atLocalPoint point: NSPoint) {
        if !isMouseTracking {
            isMouseTracking = true
            onInteractionBegin?()
        }
        _ = setValue(fromLocalPoint: point)
    }

    func continueMouseTracking(atLocalPoint point: NSPoint) {
        guard isMouseTracking else { return }
        _ = setValue(fromLocalPoint: point)
    }

    func endMouseTracking(atLocalPoint point: NSPoint) {
        guard isMouseTracking else { return }
        _ = setValue(fromLocalPoint: point)
        finishMouseTracking()
    }

    private func cancelMouseTracking() {
        finishMouseTracking()
    }

    private func finishMouseTracking() {
        guard isMouseTracking else { return }
        isMouseTracking = false
        needsDisplay = true
        onInteractionEnd?()
    }

    func setDisplayedValue(_ value: Double) {
        controlValue = clampedValue(value)
        appliedValue = controlValue
        needsDisplay = true
    }

    @discardableResult
    func setValue(fromLocalPoint point: NSPoint) -> Bool {
        let nextValue = value(forLocalPoint: point)
        guard nextValue.isFinite else { return false }
        let changed = abs(controlValue - nextValue) > Double.ulpOfOne
        if changed {
            controlValue = nextValue
            appliedValue = nextValue
            needsDisplay = true
            onValueChange?(nextValue)
        }
        return changed
    }

    func value(forLocalPoint point: NSPoint) -> Double {
        let range = controlMax - controlMin
        guard range != 0 else { return controlMin }

        let rect = trackRect()
        let rawPercent: CGFloat
        switch orientation {
        case .vertical:
            let clampedY = min(max(point.y, rect.minY), rect.maxY)
            rawPercent = rect.height <= 0 ? 0 : 1 - ((clampedY - rect.minY) / rect.height)
        case .horizontal:
            let clampedX = min(max(point.x, rect.minX), rect.maxX)
            rawPercent = rect.width <= 0 ? 0 : (clampedX - rect.minX) / rect.width
        }

        let percent = Double(min(max(rawPercent, 0), 1))
        return clampedValue(controlMin + range * percent)
    }

    private func clampedValue(_ value: Double) -> Double {
        min(max(value, min(controlMin, controlMax)), max(controlMin, controlMax))
    }

    private func trackRect() -> NSRect {
        let length = orientation == .vertical ? bounds.height : bounds.width
        let inset = min(CGFloat(6), max(0, length / 2))
        let thickness: CGFloat = 4
        switch orientation {
        case .vertical:
            return NSRect(
                x: bounds.midX - thickness / 2,
                y: bounds.minY + inset,
                width: thickness,
                height: max(0, bounds.height - inset * 2)
            )
        case .horizontal:
            return NSRect(
                x: bounds.minX + inset,
                y: bounds.midY - thickness / 2,
                width: max(0, bounds.width - inset * 2),
                height: thickness
            )
        }
    }

    private func activeTrackRect(in track: NSRect) -> NSRect {
        let percent = knobPercent()
        switch orientation {
        case .vertical:
            let knobY = track.maxY - track.height * CGFloat(percent)
            return NSRect(x: track.minX, y: knobY, width: track.width, height: track.maxY - knobY)
        case .horizontal:
            return NSRect(x: track.minX, y: track.minY, width: track.width * CGFloat(percent), height: track.height)
        }
    }

    private func knobRect(in track: NSRect) -> NSRect {
        let percent = CGFloat(knobPercent())
        let size: CGFloat = 16
        switch orientation {
        case .vertical:
            let y = track.maxY - track.height * percent
            return NSRect(x: bounds.midX - size / 2, y: y - size / 2, width: size, height: size)
        case .horizontal:
            let x = track.minX + track.width * percent
            return NSRect(x: x - size / 2, y: bounds.midY - size / 2, width: size, height: size)
        }
    }

    private func knobPercent() -> Double {
        let range = controlMax - controlMin
        guard range != 0 else { return 0 }
        return min(max((controlValue - controlMin) / range, 0), 1)
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
