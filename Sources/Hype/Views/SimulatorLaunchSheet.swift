import HypeCore
import SwiftUI

struct SimulatorLaunchSheet: View {
    @Binding var document: HypeDocumentWrapper
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: SimulatorLaunchViewModel

    init(document: Binding<HypeDocumentWrapper>) {
        self._document = document
        let targets = document.wrappedValue.document.stack.deploymentTargets.selectedPlatforms
        self._model = StateObject(wrappedValue: SimulatorLaunchViewModel(selectedTargets: targets))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if model.availablePlatforms.isEmpty {
                noTargetMessage
            } else {
                selectors
                statusPanel
            }

            HStack {
                Button("Refresh Devices") {
                    model.refreshDevices()
                }
                .disabled(model.isRefreshing || model.isLaunching || model.availablePlatforms.isEmpty)

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .disabled(model.isLaunching)

                Button("Launch") {
                    model.launch(document: document.document)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canLaunch)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear {
            model.refreshDevices()
        }
        .onChange(of: document.document.stack.deploymentTargets.selectedPlatforms) { _, targets in
            model.setAvailablePlatforms(targets)
        }
        .onChange(of: model.selectedPlatform) { _, _ in
            model.normalizeSelectedDevice()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Test Stack in Simulator")
                .font(.title2.weight(.semibold))
            Text("Build a runtime-only target app, boot the selected Apple Simulator, install the generated app, and launch this stack without opening Xcode.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var noTargetMessage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("No simulator target selected", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text("Open Target Platforms and add iPhone, iPad, or tvOS before testing in Simulator. macOS stacks run directly in Hype and do not use Apple Simulator.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Choose Target Platforms...") {
                dismiss()
                NotificationCenter.default.post(name: .showTargetPlatforms, object: nil)
            }
        }
        .padding(14)
        .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var selectors: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Target", selection: $model.selectedPlatform) {
                ForEach(model.availablePlatforms) { platform in
                    Text(platform.displayName).tag(Optional(platform))
                }
            }
            .pickerStyle(.menu)

            Picker("Simulator", selection: $model.selectedDeviceID) {
                ForEach(model.filteredDevices) { device in
                    Text(device.displayName).tag(device.udid)
                }
            }
            .pickerStyle(.menu)
            .disabled(model.filteredDevices.isEmpty || model.isRefreshing || model.isLaunching)

            if model.filteredDevices.isEmpty, !model.isRefreshing {
                Text("No matching devices are available for \(model.selectedPlatform?.displayName ?? "the selected target"). Install the simulator runtime through Xcode command-line tools or Xcode Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if model.isRefreshing || model.isLaunching {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(model.statusMessage)
                    .font(.callout)
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let result = model.lastResult {
                Text("Launched \(result.manifest.stackName) on \(result.device.displayName).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

@MainActor
private final class SimulatorLaunchViewModel: ObservableObject {
    @Published var availablePlatforms: [HypeTargetPlatform]
    @Published var selectedPlatform: HypeTargetPlatform?
    @Published var selectedDeviceID: String = ""
    @Published var devices: [HypeSimulatorDevice] = []
    @Published var isRefreshing = false
    @Published var isLaunching = false
    @Published var statusMessage = "Choose a target and simulator."
    @Published var errorMessage: String?
    @Published var lastResult: HypeSimulatorLaunchResult?

    private var refreshTask: Task<Void, Never>?
    private var launchTask: Task<Void, Never>?

    init(selectedTargets: [HypeTargetPlatform]) {
        let platforms = Self.simulatorPlatforms(from: selectedTargets)
        self.availablePlatforms = platforms
        self.selectedPlatform = platforms.first
    }

    deinit {
        refreshTask?.cancel()
        launchTask?.cancel()
    }

    var filteredDevices: [HypeSimulatorDevice] {
        guard let selectedPlatform else { return [] }
        return devices.filter { $0.platform == selectedPlatform }
    }

    var canLaunch: Bool {
        !isRefreshing && !isLaunching && selectedPlatform != nil && selectedDevice != nil
    }

    private var selectedDevice: HypeSimulatorDevice? {
        filteredDevices.first { $0.udid == selectedDeviceID }
    }

    func setAvailablePlatforms(_ targets: [HypeTargetPlatform]) {
        availablePlatforms = Self.simulatorPlatforms(from: targets)
        if let selectedPlatform, availablePlatforms.contains(selectedPlatform) {
            normalizeSelectedDevice()
        } else {
            selectedPlatform = availablePlatforms.first
            normalizeSelectedDevice()
        }
    }

    func refreshDevices() {
        refreshTask?.cancel()
        guard !availablePlatforms.isEmpty else {
            statusMessage = "Add iPhone, iPad, or tvOS as a target first."
            return
        }
        isRefreshing = true
        errorMessage = nil
        statusMessage = "Looking for available Apple Simulator devices..."

        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let launcher = HypeSimulatorRuntimeLauncher()
                let found = try await launcher.availableDevices()
                guard !Task.isCancelled else { return }
                self.devices = found
                self.normalizeSelectedDevice()
                self.statusMessage = found.isEmpty
                    ? "No Apple Simulator devices were reported by simctl."
                    : "Found \(found.count) available simulator device(s)."
            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = error.localizedDescription
                self.statusMessage = "Could not list simulator devices."
                HypeLogger.shared.error(
                    "Simulator device discovery failed: \(error.localizedDescription)",
                    source: "SimulatorRuntimeLauncher"
                )
            }
            self.isRefreshing = false
        }
    }

    func launch(document: HypeDocument) {
        guard let selectedPlatform, let selectedDevice else { return }
        launchTask?.cancel()
        isLaunching = true
        errorMessage = nil
        lastResult = nil
        statusMessage = "Building runtime package and launching \(selectedDevice.displayName)..."
        HypeLogger.shared.info(
            "Testing stack '\(document.stack.name)' in \(selectedDevice.displayName).",
            source: "SimulatorRuntimeLauncher"
        )

        launchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let launcher = HypeSimulatorRuntimeLauncher()
                let result = try await launcher.launch(
                    document: document,
                    platform: selectedPlatform,
                    device: selectedDevice
                )
                guard !Task.isCancelled else { return }
                self.lastResult = result
                self.statusMessage = "Simulator launch complete."
                HypeLogger.shared.info(
                    "Launched simulator runtime \(result.manifest.bundleIdentifier) at \(result.appBundleURL.path).",
                    source: "SimulatorRuntimeLauncher"
                )
            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = error.localizedDescription
                self.statusMessage = "Simulator launch failed."
                HypeLogger.shared.error(
                    "Simulator launch failed: \(error.localizedDescription)",
                    source: "SimulatorRuntimeLauncher"
                )
            }
            self.isLaunching = false
        }
    }

    func normalizeSelectedDevice() {
        let candidates = filteredDevices
        if candidates.contains(where: { $0.udid == selectedDeviceID }) {
            return
        }
        if let selectedPlatform {
            selectedDeviceID = HypeSimulatorRuntimeLauncher
                .preferredDevice(from: devices, for: selectedPlatform)?
                .udid ?? ""
        } else {
            selectedDeviceID = ""
        }
    }

    private static func simulatorPlatforms(from targets: [HypeTargetPlatform]) -> [HypeTargetPlatform] {
        HypeTargetPlatform.allCases.filter { platform in
            targets.contains(platform) && HypeSimulatorRuntimeLauncher.supportsSimulator(platform)
        }
    }
}
