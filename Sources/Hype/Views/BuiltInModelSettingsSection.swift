import SwiftUI
import HypeCore
import HypeMLX

/// Install state of one Built-in model variant, as the author sees it.
enum BuiltInModelInstallState: Equatable {
    case unsupported(reason: String)
    case notInstalled
    case downloading(BuiltInDownloadProgress)
    case failed(message: String)
    case installed(BuiltInModelLocation)
}

/// Drives the Built-in model section of Settings → AI.
@MainActor
final class BuiltInModelManager: ObservableObject {
    @Published private(set) var states: [String: BuiltInModelInstallState] = [:]
    @Published private(set) var fits: [String: BuiltInMemoryFit] = [:]
    @Published private(set) var testStatus = ""
    @Published private(set) var isTesting = false

    let device: BuiltInDeviceProfile
    private let store = BuiltInModelStore()
    private var downloads: [String: Task<Void, Never>] = [:]

    init() {
        var device = BuiltInDeviceProfile.current
        device.recommendedWorkingSetBytes = HypeMLXRuntime.recommendedWorkingSetBytes()
        self.device = device
        refresh()
    }

    var recommendedVariant: BuiltInModelVariant? {
        BuiltInMemoryFitPolicy.automaticVariant(
            physicalMemoryBytes: device.physicalMemoryBytes,
            recommendedWorkingSetBytes: device.recommendedWorkingSetBytes)
    }

    func refresh() {
        for variant in BuiltInModelCatalog.variants {
            let fit = BuiltInMemoryFitPolicy.evaluate(
                variant: variant,
                physicalMemoryBytes: device.physicalMemoryBytes,
                recommendedWorkingSetBytes: device.recommendedWorkingSetBytes)
            fits[variant.id] = fit
            if case .downloading = states[variant.id] { continue }
            if let location = store.location(of: variant) {
                states[variant.id] = .installed(location)
            } else if fit.verdict == .insufficient {
                states[variant.id] = .unsupported(
                    reason: "Needs a Mac with \(variant.minimumPhysicalMemoryGB) GB of memory or more (this Mac has \(device.physicalMemoryGB) GB).")
            } else if case .failed = states[variant.id] {
                continue
            } else {
                states[variant.id] = .notInstalled
            }
        }
    }

    /// Only ever called from an explicit button press: Hype never starts a
    /// multi-gigabyte download on its own.
    func download(_ variant: BuiltInModelVariant) {
        guard downloads[variant.id] == nil else { return }
        states[variant.id] = .downloading(.init(phase: .downloading, completedBytes: 0, totalBytes: variant.totalBytes, currentFile: nil))
        let downloader = BuiltInModelDownloader(store: store)
        downloads[variant.id] = Task { [weak self] in
            let throttle = ProgressThrottle()
            do {
                try await downloader.install(variant) { progress in
                    guard throttle.shouldReport(progress) else { return }
                    Task { @MainActor in
                        guard let self, case .downloading = self.states[variant.id] else { return }
                        self.states[variant.id] = .downloading(progress)
                    }
                }
                self?.finishDownload(of: variant, failure: nil)
            } catch is CancellationError {
                self?.finishDownload(of: variant, failure: nil)
            } catch {
                self?.finishDownload(of: variant, failure: error.localizedDescription)
            }
        }
    }

    /// Stops the transfer. Verified and partial files stay on disk, so pressing
    /// Download again resumes where it stopped.
    func pause(_ variant: BuiltInModelVariant) {
        downloads[variant.id]?.cancel()
    }

    func remove(_ variant: BuiltInModelVariant) {
        do {
            try store.remove(variant)
            states[variant.id] = nil
        } catch {
            states[variant.id] = .failed(message: error.localizedDescription)
        }
        refresh()
    }

    func test() {
        guard !isTesting else { return }
        isTesting = true
        testStatus = "Loading the model…"
        Task {
            defer { isTesting = false }
            do {
                let client = try BuiltInModelClient.make(device: device)
                let start = Date()
                try await client.preloadModel()
                let loaded = Date().timeIntervalSince(start)
                testStatus = "Generating…"
                let reply = try await client.generate(
                    prompt: "Reply with the single word OK.", model: nil, system: nil)
                let total = Date().timeIntervalSince(start)
                testStatus = String(
                    format: "OK: %@ answered “%@” (load %.1f s, total %.1f s)",
                    client.variant.displayName, String(reply.prefix(40)), loaded, total)
            } catch {
                testStatus = "Failed: \(error.localizedDescription)"
            }
        }
    }

    private func finishDownload(of variant: BuiltInModelVariant, failure: String?) {
        downloads[variant.id] = nil
        states[variant.id] = failure.map { .failed(message: $0) }
        refresh()
    }
}

/// Lets a high-frequency progress callback through a few times per second.
private final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var lastReport = Date.distantPast
    private var lastPhase: BuiltInDownloadProgress.Phase?

    func shouldReport(_ progress: BuiltInDownloadProgress) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        guard progress.phase != lastPhase || now.timeIntervalSince(lastReport) > 0.25 else { return false }
        lastReport = now
        lastPhase = progress.phase
        return true
    }
}

/// Settings → AI → Built-in (on-device).
struct BuiltInModelSettingsSection: View {
    @StateObject private var manager = BuiltInModelManager()
    @AppStorage(BuiltInModelSettings.variantKey) private var selectedVariantID = BuiltInModelCatalog.automaticVariantID
    @AppStorage(BuiltInModelSettings.thinkingKey) private var thinkingEnabled = false
    @State private var variantPendingRemoval: BuiltInModelVariant?

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useMB]
        return formatter
    }()

    var body: some View {
        Section("Built-in Model") {
            Text("Runs entirely on this Mac with Apple's MLX — no server, no account, and nothing you write leaves your computer. It works offline once a model is installed.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Model", selection: $selectedVariantID) {
                Text(automaticLabel).tag(BuiltInModelCatalog.automaticVariantID)
                ForEach(BuiltInModelCatalog.variants) { variant in
                    Text(variant.displayName).tag(variant.id)
                }
            }
            .accessibilityHint("Automatic chooses the best installed model for this Mac's memory.")

            ForEach(BuiltInModelCatalog.variants) { variant in
                variantRow(variant)
            }

            Toggle("Think before answering (slower)", isOn: $thinkingEnabled)
                .accessibilityHint("Lets models that support it reason privately before replying. Tool loops take noticeably longer.")

            HStack {
                Button("Test Built-in Model") { manager.test() }
                    .disabled(manager.isTesting)
                if manager.isTesting { ProgressView().scaleEffect(0.7) }
                if !manager.testStatus.isEmpty {
                    Label(manager.testStatus, systemImage: statusSymbol(for: manager.testStatus))
                        .foregroundColor(statusColor(for: manager.testStatus))
                        .font(.system(size: 11))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(manager.testStatus)
                }
            }
        }
        .onAppear { manager.refresh() }
        .alert(item: $variantPendingRemoval) { variant in
            Alert(
                title: Text("Remove \(variant.displayName)?"),
                message: Text("This frees \(Self.byteFormatter.string(fromByteCount: variant.totalBytes)). You can download it again at any time."),
                primaryButton: .destructive(Text("Remove")) { manager.remove(variant) },
                secondaryButton: .cancel()
            )
        }
    }

    private var automaticLabel: String {
        if let recommended = manager.recommendedVariant {
            return "Automatic (\(recommended.tier.displayName))"
        }
        return "Automatic"
    }

    @ViewBuilder
    private func variantRow(_ variant: BuiltInModelVariant) -> some View {
        let state = manager.states[variant.id] ?? .notInstalled
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(variant.displayName).font(.system(size: 12, weight: .semibold))
                Text(variant.tier.displayName).font(.system(size: 10)).foregroundColor(.secondary)
                Spacer()
                fitBadge(for: variant)
            }
            Text(variant.summary)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(Self.byteFormatter.string(fromByteCount: variant.totalBytes)) · \(variant.license) · \(variant.huggingFaceRepo)")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            stateControls(for: variant, state: state)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(variant.displayName), \(variant.tier.displayName)")
    }

    @ViewBuilder
    private func stateControls(for variant: BuiltInModelVariant, state: BuiltInModelInstallState) -> some View {
        switch state {
        case .unsupported(let reason):
            Label(reason, systemImage: "nosign")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        case .notInstalled:
            HStack {
                Button("Download \(Self.byteFormatter.string(fromByteCount: variant.totalBytes))") {
                    manager.download(variant)
                }
                .accessibilityHint("Downloads the model from huggingface.co and verifies every file before use.")
                Text("From huggingface.co · verified with SHA-256")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 2) {
                ProgressView(value: progress.fraction)
                    .accessibilityLabel(progress.phase == .verifying ? "Verifying download" : "Downloading")
                    .accessibilityValue("\(Int(progress.fraction * 100)) percent")
                HStack {
                    Text(progressText(progress)).font(.system(size: 10)).foregroundColor(.secondary)
                    Spacer()
                    Button("Pause") { manager.pause(variant) }
                        .accessibilityHint("Stops the download. It resumes where it stopped.")
                }
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 2) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Resume Download") { manager.download(variant) }
            }
        case .installed(let location):
            HStack {
                Label(installedText(location), systemImage: "checkmark.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.green)
                Spacer()
                if location.isRemovable {
                    Button("Remove…") { variantPendingRemoval = variant }
                }
            }
        }
    }

    @ViewBuilder
    private func fitBadge(for variant: BuiltInModelVariant) -> some View {
        if let fit = manager.fits[variant.id] {
            switch fit.verdict {
            case .comfortable:
                Label("Fits this Mac", systemImage: "memorychip")
                    .font(.system(size: 10)).foregroundColor(.secondary)
                    .help("Up to \(fit.contextTokenLimit / 1000)K tokens of context on this Mac.")
            case .tight:
                Label("Tight fit", systemImage: "exclamationmark.circle")
                    .font(.system(size: 10)).foregroundColor(.orange)
                    .help("Fits with up to \(fit.contextTokenLimit / 1000)K tokens of context. Close other large apps for best results.")
            case .insufficient:
                Label("Too large", systemImage: "nosign")
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }
        }
    }

    private func progressText(_ progress: BuiltInDownloadProgress) -> String {
        let done = Self.byteFormatter.string(fromByteCount: progress.completedBytes)
        let total = Self.byteFormatter.string(fromByteCount: progress.totalBytes)
        switch progress.phase {
        case .downloading: return "Downloading \(done) of \(total)"
        case .verifying: return "Verifying \(progress.currentFile ?? "files")…"
        case .finished: return "Finished"
        }
    }

    private func installedText(_ location: BuiltInModelLocation) -> String {
        switch location {
        case .installed: return "Installed"
        case .huggingFaceCache: return "Installed (using your Hugging Face cache)"
        case .userDirectory: return "Installed (custom folder)"
        }
    }

    private func statusSymbol(for status: String) -> String {
        if status.hasPrefix("OK") { return "checkmark.circle" }
        if status.hasPrefix("Failed") { return "xmark.octagon" }
        return "hourglass"
    }

    private func statusColor(for status: String) -> Color {
        if status.hasPrefix("OK") { return .green }
        if status.hasPrefix("Failed") { return .red }
        return .secondary
    }
}
