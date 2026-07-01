import HypeCore
import SwiftUI

struct StackTargetSelectionSheet: View {
    @Binding var document: HypeDocumentWrapper
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPlatforms: Set<HypeTargetPlatform>
    @State private var primaryPlatform: HypeTargetPlatform
    @State private var layoutPolicy: TargetLayoutPolicy
    @State private var pendingResize: PendingResize?

    init(document: Binding<HypeDocumentWrapper>) {
        self._document = document
        let targets = document.wrappedValue.document.stack.deploymentTargets
        let selected = Set(targets.selectedPlatforms.isEmpty ? [.macOS] : targets.selectedPlatforms)
        self._selectedPlatforms = State(initialValue: selected)
        self._primaryPlatform = State(initialValue: selected.contains(targets.primaryPlatform) ? targets.primaryPlatform : .macOS)
        self._layoutPolicy = State(initialValue: targets.layoutPolicy)
    }

    var body: some View {
        Group {
            if let pending = pendingResize {
                resizeConfirmationView(pending: pending)
            } else {
                platformSelectionView
            }
        }
        .padding(24)
        .frame(width: 520)
        .interactiveDismissDisabled(true)
    }

    // MARK: - Platform selection view

    private var platformSelectionView: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Choose Target Platforms")
                    .font(.title2.weight(.semibold))
                Text("Hype will constrain available controls to the platforms selected here and use these targets for layout emulation and deployment.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(HypeTargetPlatform.allCases) { platform in
                    Toggle(isOn: binding(for: platform)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(platform.displayName)
                            Text(description(for: platform))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Picker("Primary design target", selection: $primaryPlatform) {
                ForEach(HypeTargetPlatform.allCases.filter { selectedPlatforms.contains($0) }) { platform in
                    Text(platform.displayName).tag(platform)
                }
            }
            .pickerStyle(.menu)

            Picker("Layout behavior", selection: $layoutPolicy) {
                Text("Fixed positions").tag(TargetLayoutPolicy.fixed)
                Text("Scale to fit").tag(TargetLayoutPolicy.scaleToFit)
                Text("Stretch to fill").tag(TargetLayoutPolicy.stretchToFill)
            }
            .pickerStyle(.menu)

            Text("Object palette filtering is strict: only controls that work across every selected target are shown.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Continue") {
                    applySelection()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedPlatforms.isEmpty)
            }
        }
        .onChange(of: selectedPlatforms) { _, newValue in
            if newValue.isEmpty {
                selectedPlatforms.insert(.macOS)
            }
            if !selectedPlatforms.contains(primaryPlatform) {
                primaryPlatform = selectedPlatforms.sortedByCatalogOrder.first ?? .macOS
            }
            // When the selection collapses to macOS-only, macOS does not support
            // scale or stretch policies (resizable window has no fixed safe area).
            // Reset the picker so it never shows a value the model would override.
            if newValue == [.macOS], layoutPolicy != .fixed {
                layoutPolicy = .fixed
            }
        }
    }

    // MARK: - Resize confirmation view

    @ViewBuilder
    private func resizeConfirmationView(pending: PendingResize) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Resize Design Canvas?")
                    .font(.title2.weight(.semibold))
                Text("Changing the primary target to \(pending.profileName) will resize the design canvas.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    Text("\(pending.oldWidth) × \(pending.oldHeight)")
                        .monospacedDigit()
                    Image(systemName: "arrow.right")
                    Text("\(pending.newWidth) × \(pending.newHeight)")
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
                .font(.callout.weight(.medium))
                .padding(.top, 2)

                if pending.hasParts {
                    Text("Parts placed at absolute coordinates may fall outside the new canvas bounds.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Button("Resize Only") {
                    commitResize(pending: pending, rescaleParts: false)
                }
                .keyboardShortcut(.defaultAction)
                .help("Resize the design canvas. Part coordinates are not changed.")

                if pending.hasParts {
                    Button("Resize and Rescale Parts") {
                        commitResize(pending: pending, rescaleParts: true)
                    }
                    .help("Resize the canvas and proportionally scale all part coordinates to the new size.")
                }

                Button("Cancel") {
                    pendingResize = nil
                }
                .keyboardShortcut(.escape)
            }
        }
    }

    // MARK: - Private helpers

    private func binding(for platform: HypeTargetPlatform) -> Binding<Bool> {
        Binding(
            get: { selectedPlatforms.contains(platform) },
            set: { isOn in
                if isOn {
                    selectedPlatforms.insert(platform)
                } else if selectedPlatforms.count > 1 {
                    selectedPlatforms.remove(platform)
                }
            }
        )
    }

    private func description(for platform: HypeTargetPlatform) -> String {
        switch platform {
        case .macOS:
            return "Desktop runtime with pointer, keyboard, menus, and resizable windows. Default for new stacks."
        case .iPhone:
            return "Touch-first phone layout with safe areas and smaller portrait/landscape profiles."
        case .iPad:
            return "Tablet layout with larger safe-area-aware profiles and optional pointer/keyboard use later."
        case .tvOS:
            return "Focus-remote runtime with 16:9 layout and a smaller supported-control set."
        }
    }

    private func applySelection() {
        let ordered = selectedPlatforms.sortedByCatalogOrder
        let primary = selectedPlatforms.contains(primaryPlatform) ? primaryPlatform : (ordered.first ?? .macOS)

        var targets = StackDeploymentTargets(
            selectedPlatforms: ordered,
            primaryPlatform: primary,
            selectionPromptAcknowledged: true,
            supportedOrientations: orientations(for: ordered),
            layoutPolicy: layoutPolicy
        )
        targets.normalize()
        // Clamp-only: explicit user choice; no auto-promotion to scaleToFit.
        targets.layoutPolicy = targets.clampedLayoutPolicy(layoutPolicy)

        let oldWidth = document.document.stack.width
        let oldHeight = document.document.stack.height
        let newProfile = HypeDeviceProfileCatalog.defaultProfile(for: primary)
        let newWidth = newProfile.width
        let newHeight = newProfile.height
        let hasParts = !document.document.parts.isEmpty

        // If the primary profile dimensions change AND the stack has parts,
        // confirm with the user before committing so coords are never silently moved.
        if (newWidth != oldWidth || newHeight != oldHeight), hasParts {
            pendingResize = PendingResize(
                targets: targets,
                oldWidth: oldWidth,
                oldHeight: oldHeight,
                newWidth: newWidth,
                newHeight: newHeight,
                profileName: newProfile.displayName,
                hasParts: hasParts
            )
            return
        }

        // No dimension change, or no parts: commit directly without confirmation.
        commitTargets(targets, newWidth: newWidth, newHeight: newHeight, rescaleParts: false, oldWidth: oldWidth, oldHeight: oldHeight)
    }

    /// Commit the resize action (from the confirmation step).
    private func commitResize(pending: PendingResize, rescaleParts: Bool) {
        commitTargets(
            pending.targets,
            newWidth: pending.newWidth,
            newHeight: pending.newHeight,
            rescaleParts: rescaleParts,
            oldWidth: pending.oldWidth,
            oldHeight: pending.oldHeight
        )
    }

    /// Apply the new deployment targets and canvas size, optionally rescaling parts.
    ///
    /// Part rescale mutates `left/top/width/height` proportionally. This is the
    /// ONLY place where authored part coordinates are moved; it requires an explicit
    /// "Resize and rescale" user choice. The mutation is made via the `document`
    /// binding, which records it as a single undoable group ("Resize Stack").
    ///
    /// Constraint `distance` values are NOT rescaled in v1 — they re-solve against
    /// live bounds at render time. (Known limitation; comment preserved for follow-up.)
    private func commitTargets(
        _ targets: StackDeploymentTargets,
        newWidth: Int,
        newHeight: Int,
        rescaleParts: Bool,
        oldWidth: Int,
        oldHeight: Int
    ) {
        document.document.stack.deploymentTargets = targets
        document.document.stack.width = newWidth
        document.document.stack.height = newHeight
        document.document.stack.modifiedAt = Date()

        if rescaleParts {
            // Guard against divide-by-zero on a degenerate old canvas.
            let sx = Double(newWidth) / Double(max(1, oldWidth))
            let sy = Double(newHeight) / Double(max(1, oldHeight))
            for i in document.document.parts.indices {
                document.document.parts[i].left   *= sx
                document.document.parts[i].top    *= sy
                document.document.parts[i].width  *= sx
                document.document.parts[i].height *= sy
            }
            // Note: LayoutConstraint.distance values are not rescaled here.
            // They re-solve against the new canvas bounds at render/export time.
        }

        pendingResize = nil
        dismiss()
    }

    private func orientations(for platforms: [HypeTargetPlatform]) -> [HypeTargetOrientation] {
        if platforms == [.macOS] {
            return [.resizable]
        }
        var result: [HypeTargetOrientation] = []
        if platforms.contains(.macOS) { result.append(.resizable) }
        if platforms.contains(.iPhone) || platforms.contains(.iPad) { result.append(contentsOf: [.portrait, .landscape]) }
        if platforms.contains(.tvOS) { result.append(.landscape) }
        return Array(Set(result)).sorted { lhs, rhs in
            let lhsIndex = HypeTargetOrientation.allCases.firstIndex(of: lhs) ?? 0
            let rhsIndex = HypeTargetOrientation.allCases.firstIndex(of: rhs) ?? 0
            return lhsIndex < rhsIndex
        }
    }
}

// MARK: - Supporting types

/// Captures the pending resize parameters so the confirmation step can display
/// dimension info and the commit step can apply changes without re-deriving them.
private struct PendingResize {
    let targets: StackDeploymentTargets
    let oldWidth: Int
    let oldHeight: Int
    let newWidth: Int
    let newHeight: Int
    let profileName: String
    let hasParts: Bool
}

private extension Set where Element == HypeTargetPlatform {
    var sortedByCatalogOrder: [HypeTargetPlatform] {
        HypeTargetPlatform.allCases.filter { contains($0) }
    }
}
