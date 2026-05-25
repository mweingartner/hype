import HypeCore
import SwiftUI

struct StackTargetSelectionSheet: View {
    @Binding var document: HypeDocumentWrapper
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPlatforms: Set<HypeTargetPlatform>
    @State private var primaryPlatform: HypeTargetPlatform

    init(document: Binding<HypeDocumentWrapper>) {
        self._document = document
        let targets = document.wrappedValue.document.stack.deploymentTargets
        let selected = Set(targets.selectedPlatforms.isEmpty ? [.macOS] : targets.selectedPlatforms)
        self._selectedPlatforms = State(initialValue: selected)
        self._primaryPlatform = State(initialValue: selected.contains(targets.primaryPlatform) ? targets.primaryPlatform : .macOS)
    }

    var body: some View {
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
        .padding(24)
        .frame(width: 520)
        .interactiveDismissDisabled(true)
        .onChange(of: selectedPlatforms) { _, newValue in
            if newValue.isEmpty {
                selectedPlatforms.insert(.macOS)
            }
            if !selectedPlatforms.contains(primaryPlatform) {
                primaryPlatform = selectedPlatforms.sortedByCatalogOrder.first ?? .macOS
            }
        }
    }

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
            supportedOrientations: orientations(for: ordered)
        )
        targets.normalize()

        document.document.stack.deploymentTargets = targets
        let profile = targets.primaryProfile
        document.document.stack.width = profile.width
        document.document.stack.height = profile.height
        document.document.stack.modifiedAt = Date()
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
            HypeTargetOrientation.allCases.firstIndex(of: lhs)! < HypeTargetOrientation.allCases.firstIndex(of: rhs)!
        }
    }
}

private extension Set where Element == HypeTargetPlatform {
    var sortedByCatalogOrder: [HypeTargetPlatform] {
        HypeTargetPlatform.allCases.filter { contains($0) }
    }
}
