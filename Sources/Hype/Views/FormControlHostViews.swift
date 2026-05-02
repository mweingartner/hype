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

    func apply(_ part: Part) {
        stepper.minValue = part.controlMin
        stepper.maxValue = part.controlMax
        stepper.increment = part.controlStep == 0 ? 1 : part.controlStep
        stepper.doubleValue = part.controlValue
        valueField.stringValue = formatNumber(part.controlValue)
    }

    @objc private func stepperDidChange() {
        valueField.stringValue = formatNumber(stepper.doubleValue)
        onValueChange?(stepper.doubleValue)
    }
}

// MARK: - Slider

final class SliderHostNSView: NSView {
    let slider = NSSlider()
    var onValueChange: ((Double) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.target = self
        slider.action = #selector(sliderDidChange)
        slider.isContinuous = true
        addSubview(slider)
        NSLayoutConstraint.activate([
            slider.topAnchor.constraint(equalTo: topAnchor),
            slider.bottomAnchor.constraint(equalTo: bottomAnchor),
            slider.leadingAnchor.constraint(equalTo: leadingAnchor),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(_ part: Part) {
        slider.minValue = part.controlMin
        slider.maxValue = part.controlMax
        slider.doubleValue = part.controlValue
    }

    @objc private func sliderDidChange() {
        onValueChange?(slider.doubleValue)
    }
}

// MARK: - Toggle (NSSwitch)

final class ToggleHostNSView: NSView {
    let toggle = NSSwitch()
    var onValueChange: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.target = self
        toggle.action = #selector(toggleDidChange)
        addSubview(toggle)
        NSLayoutConstraint.activate([
            toggle.centerXAnchor.constraint(equalTo: centerXAnchor),
            toggle.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(_ part: Part) {
        toggle.state = part.controlValue >= 0.5 ? .on : .off
    }

    @objc private func toggleDidChange() {
        onValueChange?(toggle.state == .on)
    }
}

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

    func apply(_ part: Part) {
        let labels = part.segmentItems.split(separator: "|").map(String.init)
        if segmented.segmentCount != labels.count {
            segmented.segmentCount = labels.count
        }
        for (i, label) in labels.enumerated() {
            segmented.setLabel(label, forSegment: i)
            segmented.setWidth(0, forSegment: i)
        }
        let idx = Int(part.controlValue)
        if idx >= 0 && idx < labels.count {
            segmented.selectedSegment = idx
        } else {
            segmented.selectedSegment = 0
        }
    }

    @objc private func segmentedDidChange() {
        onValueChange?(segmented.selectedSegment)
    }
}

// MARK: - Helpers

private func formatNumber(_ d: Double) -> String {
    if d.rounded() == d { return String(Int(d)) }
    return String(format: "%.2f", d)
}
