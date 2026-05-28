import SwiftUI
import HypeCore
#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
#endif

// MARK: - Generate3DSheet

/// A SwiftUI sheet for generating a 3D model using Meshy.ai.
///
/// Phase 2 adds three tabs: Text / Image / Multi-image. All three tabs
/// feed the same progress/import pipeline via `Generate3DJob`.
///
/// Security invariants:
/// - The sheet DOES NOT auto-submit on first paint. Generate actions are only
///   invoked by explicit `Button("Generate")` presses (invariant 17).
/// - The monitor is cancelled on `.onDisappear`.
/// - Gate is re-checked at generate-call time as belt-and-suspenders.
struct Generate3DSheet: View {
    @Binding var document: HypeDocumentWrapper
    /// When set, the primary imported asset's ref is written into this part.
    var targetPartId: UUID?
    /// Called on success with the freshly-imported primary `AssetRef`.
    var onAssetImported: ((AssetRef) -> Void)?
    /// Called when the sheet should be dismissed.
    var onDismiss: () -> Void

    // MARK: - Input tab enum

    enum InputTab: String, CaseIterable, Identifiable, Hashable {
        case text, image, multiImage
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .text: return "Text"
            case .image: return "Image"
            case .multiImage: return "Multi-image"
            }
        }
    }

    // MARK: - Form state (Text tab)

    @State private var prompt: String = ""
    @State private var aiModel: MeshyAIModel = .meshy6
    @State private var artStyle: MeshyArtStyle = .realistic
    @State private var primaryFormat: MeshyOutputFormat = .glb
    @State private var assetName: String = ""
    @State private var alsoDownloadUSDZ: Bool = true
    @State private var alsoDownloadFBX: Bool = false
    @State private var polycount: Double = 30_000
    @State private var shouldRemesh: Bool = false
    @State private var textQuality: Generate3DJob.TextQuality = .preview
    @State private var topology: String = "triangle"
    @State private var enablePBR: Bool = false

    // MARK: - Tab state

    @State private var activeTab: InputTab = .text

    // MARK: - Image tab state

    @State private var imageResolved: MeshyImageInput.Resolved? = nil
    @State private var imagePreview: NSImage? = nil
    @State private var imageValidationError: String? = nil

    // MARK: - Multi-image tab state (4 slots)

    @State private var multiImageResolved: [MeshyImageInput.Resolved?] = [nil, nil, nil, nil]
    @State private var multiImagePreviews: [NSImage?] = [nil, nil, nil, nil]
    @State private var multiImageValidationError: String? = nil

    // MARK: - Runtime state

    @State private var phase: Phase = .form
    @State private var monitor: MeshyTaskMonitor?
    @State private var generateTask: Task<Void, Never>?
    @State private var balance: Int?
    @State private var balanceLoading: Bool = false
    @State private var meshyKeyIsSet: Bool = false
    @State private var earlyCancel: Bool = false  // OQ4 warning flag

    enum Phase: Equatable {
        case form
        case submitting
        case progress(percent: Int)
        case importing
        case error(MeshyError)
        case done
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Generate 3D Model")
                    .font(.headline)
                Spacer()
                if let balance {
                    Text("\(balance) credits")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                if balanceLoading {
                    ProgressView().scaleEffect(0.6)
                }
            }
            .padding()

            Divider()

            // Tab picker — only visible in .form phase
            if case .form = phase {
                Picker("", selection: $activeTab) {
                    ForEach(InputTab.allCases) { tab in
                        Text(tab.displayName).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            // Main content
            switch phase {
            case .form:
                switch activeTab {
                case .text:       textFormContent
                case .image:      imageFormContent
                case .multiImage: multiImageFormContent
                }
            case .submitting:
                progressContent(label: "Submitting…", percent: 0)
            case .progress(let percent):
                progressContent(label: "Generating… \(percent)%", percent: percent)
            case .importing:
                progressContent(label: "Importing model…", percent: 100)
            case .error(let err):
                errorContent(err)
            case .done:
                doneContent
            }
        }
        .frame(width: 540, height: 520)
        .onAppear {
            meshyKeyIsSet = KeychainStore.hasSecret(account: KeychainStore.meshyAPIKeyAccount)
            Task { await refreshBalance() }
        }
        .onDisappear {
            generateTask?.cancel()
            Task { await monitor?.cancel() }
        }
    }

    // MARK: - Text Form

    @ViewBuilder
    private var textFormContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Prompt
                VStack(alignment: .leading, spacing: 4) {
                    Text("Prompt (describe your 3D model)")
                        .font(.system(size: 11))
                    TextEditor(text: $prompt)
                        .frame(height: 80)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                        .onChange(of: prompt) { _, newValue in
                            // Cap at 600 chars (Meshy limit).
                            if newValue.count > 600 {
                                prompt = String(newValue.prefix(600))
                            }
                        }
                    Text("\(prompt.count)/600 characters")
                        .font(.system(size: 9))
                        .foregroundColor(prompt.count > 550 ? .orange : .secondary)
                }

                assetNameField

                // Model + Art Style row
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AI Model").font(.system(size: 11))
                        Picker("", selection: $aiModel) {
                            ForEach(MeshyAIModel.allCases) { model in
                                Text(model.displayName).tag(model)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .onChange(of: aiModel) { _, newModel in
                            shouldRemesh = newModel.defaultRemesh
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Art Style").font(.system(size: 11))
                        Picker("", selection: $artStyle) {
                            ForEach(MeshyArtStyle.allCases) { style in
                                Text(style.displayName).tag(style)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }

                // Quality + geometry controls
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Quality").font(.system(size: 11))
                        Picker("", selection: $textQuality) {
                            ForEach(Generate3DJob.TextQuality.allCases) { quality in
                                Text(quality.displayName).tag(quality)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Topology").font(.system(size: 11))
                        Picker("", selection: $topology) {
                            Text("Triangle").tag("triangle")
                            Text("Quad").tag("quad")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }

                HStack {
                    Text("Target polygons: \(Int(polycount))")
                        .font(.system(size: 11))
                    Slider(value: $polycount, in: 100...300_000, step: 100)
                }
                Toggle("Request PBR textures where supported", isOn: $enablePBR)
                    .font(.system(size: 11))

                // Additional formats
                VStack(alignment: .leading, spacing: 4) {
                    Text("Additional Formats").font(.system(size: 11))
                    Toggle("Also download USDZ (AR-ready)", isOn: $alsoDownloadUSDZ)
                        .font(.system(size: 11))
                    Toggle("Also download FBX (experimental — higher attack surface than GLB/USDZ)", isOn: $alsoDownloadFBX)
                        .font(.system(size: 11))
                }

                // Remesh toggle
                Toggle("Remesh geometry", isOn: $shouldRemesh)
                    .font(.system(size: 11))

                // Disclosure
                Text("Prompts are sent to api.meshy.ai using your Meshy.ai credits. The generated model is downloaded over HTTPS and embedded in this document.")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
        }

        Divider()

        HStack {
            Button("Cancel") { onDismiss() }
            Spacer()
            Button("Generate") {
                generateTask = Task { await generateText() }
            }
            .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !meshyKeyIsSet)
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Image Form

    @ViewBuilder
    private var imageFormContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Source Image")
                    .font(.system(size: 11))

                // Source row
                imageSourceRow(
                    resolved: $imageResolved,
                    preview: $imagePreview,
                    validationError: $imageValidationError
                )

                // Preview thumbnail
                if let preview = imagePreview {
                    HStack {
                        Image(nsImage: preview)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 120, height: 120)
                            .cornerRadius(6)
                        Spacer()
                    }
                }

                if let err = imageValidationError {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }

                assetNameField

                // Model + Remesh shared row
                sharedOptionsRow

                // Additional formats
                sharedFormatsSection

                // Disclosure
                Text("Source image is sent to api.meshy.ai over HTTPS along with your Meshy.ai credits.")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
        }

        Divider()

        HStack {
            Button("Cancel") { onDismiss() }
            Spacer()
            Button("Generate") {
                generateTask = Task { await generateImage() }
            }
            .disabled(imageResolved == nil || !meshyKeyIsSet)
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Multi-image Form

    @ViewBuilder
    private var multiImageFormContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Source Images (2–4 views of the same object)")
                    .font(.system(size: 11))

                // Four slots
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { idx in
                        multiImageSlot(index: idx)
                    }
                }

                if let err = multiImageValidationError {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }

                assetNameField

                // Model + Remesh shared row
                sharedOptionsRow

                // Additional formats
                sharedFormatsSection

                Text("All images should be the same object from different angles (front / side / back). Each image: max 10 MB, PNG/JPEG only.")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Source images are sent to api.meshy.ai over HTTPS along with your Meshy.ai credits.")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
        }

        Divider()

        HStack {
            Button("Cancel") { onDismiss() }
            Spacer()
            Button("Generate") {
                generateTask = Task { await generateMultiImage() }
            }
            .disabled(filledMultiImageCount < 2 || !meshyKeyIsSet)
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Shared form subviews

    @ViewBuilder
    private var sharedOptionsRow: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI Model").font(.system(size: 11))
                Picker("", selection: $aiModel) {
                    ForEach(MeshyAIModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .onChange(of: aiModel) { _, newModel in
                    shouldRemesh = newModel.defaultRemesh
                }
            }

            Toggle("Remesh geometry", isOn: $shouldRemesh)
                .font(.system(size: 11))

            Toggle("Request PBR textures where supported", isOn: $enablePBR)
                .font(.system(size: 11))
        }
    }

    @ViewBuilder
    private var assetNameField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Repository asset name")
                .font(.system(size: 11))
            TextField("Optional, e.g. wooden-barrel", text: $assetName)
                .textFieldStyle(.roundedBorder)
            Text("If provided, Hype uses this as the base name and adds .glb/.usdz/.fbx as needed.")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var sharedFormatsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Additional Formats").font(.system(size: 11))
            Toggle("Also download USDZ (AR-ready)", isOn: $alsoDownloadUSDZ)
                .font(.system(size: 11))
            Toggle("Also download FBX", isOn: $alsoDownloadFBX)
                .font(.system(size: 11))
        }
    }

    // MARK: - Image source row helper

    @ViewBuilder
    private func imageSourceRow(
        resolved: Binding<MeshyImageInput.Resolved?>,
        preview: Binding<NSImage?>,
        validationError: Binding<String?>
    ) -> some View {
        HStack(spacing: 8) {
            Menu("From Repository…") {
                if imageRepositoryAssets.isEmpty {
                    Text("(no image assets)").foregroundColor(.secondary)
                } else {
                    ForEach(imageRepositoryAssets, id: \.id) { asset in
                        Button(asset.name) {
                            resolveAndSet(
                                .assetName(asset.name),
                                resolved: resolved,
                                preview: preview,
                                error: validationError
                            )
                        }
                    }
                }
            }
            .controlSize(.small)

            Button("From Clipboard") {
                importFromClipboard(resolved: resolved, preview: preview, error: validationError)
            }
            .controlSize(.small)

            Button("Choose File…") {
                openImageFilePicker(resolved: resolved, preview: preview, error: validationError)
            }
            .controlSize(.small)

            if resolved.wrappedValue != nil {
                Button("Remove") {
                    resolved.wrappedValue = nil
                    preview.wrappedValue = nil
                    validationError.wrappedValue = nil
                }
                .controlSize(.small)
                .foregroundColor(.red)
            }
        }
    }

    // MARK: - Multi-image slot

    @ViewBuilder
    private func multiImageSlot(index: Int) -> some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.secondary.opacity(0.3))
                    .frame(width: 90, height: 90)

                if let preview = multiImagePreviews[index] {
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 84, height: 84)
                        .cornerRadius(4)
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 18))
                            .foregroundColor(.secondary)
                        Text("\(index + 1)")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .onTapGesture {
                openMultiImageFilePicker(index: index)
            }

            if multiImageResolved[index] != nil {
                Button("Remove") {
                    multiImageResolved[index] = nil
                    multiImagePreviews[index] = nil
                }
                .controlSize(.mini)
                .foregroundColor(.red)
            }
        }
    }

    // MARK: - Progress

    @ViewBuilder
    private func progressContent(label: String, percent: Int) -> some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView(value: Double(percent), total: 100)
                .frame(width: 300)
            Text(label)
                .font(.system(size: 13))

            if earlyCancel {
                Text("Task may have been created on Meshy. Check your dashboard.")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
            }

            Spacer()
            Button("Cancel") {
                generateTask?.cancel()
                Task { await monitor?.cancel() }
                if case .submitting = phase { earlyCancel = true }
                phase = .form
            }
        }
        .padding()
    }

    // MARK: - Error

    @ViewBuilder
    private func errorContent(_ error: MeshyError) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundColor(.red)
            Text(error.errorDescription ?? "An error occurred.")
                .multilineTextAlignment(.center)
                .font(.system(size: 13))
                .padding(.horizontal)
            Spacer()
            HStack {
                Button("Close") { onDismiss() }
                Button("Retry") { phase = .form }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    // MARK: - Done

    @ViewBuilder
    private var doneContent: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundColor(.green)
            Text("3D model generated and added to the repository.")
                .multilineTextAlignment(.center)
                .font(.system(size: 13))
            Text("The generated model is embedded in this stack and autosaved.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            Button("Done") { onDismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Actions

    private func generateText() async {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }
        await runJob(kind: .text(prompt: trimmedPrompt, artStyle: artStyle))
    }

    private func generateImage() async {
        guard let resolved = imageResolved else { return }
        await runJob(kind: .singleImage(image: resolved))
    }

    private func generateMultiImage() async {
        let resolvedImages = multiImageResolved.compactMap { $0 }
        guard (2...4).contains(resolvedImages.count) else {
            await MainActor.run {
                multiImageValidationError = "Add 2 to 4 images before generating."
            }
            return
        }
        await runJob(kind: .multiImage(images: resolvedImages))
    }

    /// Shared generation pipeline — replaces the old monolithic `generate()`.
    private func runJob(kind: Generate3DJob.Kind) async {
        // Belt-and-suspenders gate check.
        guard Meshy3DGate.status(for: document.document, keyIsSet: meshyKeyIsSet) == .ready else {
            await MainActor.run {
                phase = .error(.validationFailed(field: "stack", reason: "Meshy is not enabled for this stack. Enable it in Preferences → Meshy.ai."))
            }
            return
        }

        await MainActor.run { phase = .submitting }

        do {
            let apiKey = try KeychainStore.getSecret(account: KeychainStore.meshyAPIKeyAccount)
            let client = MeshyAIClient(apiKey: apiKey)
            let job = Generate3DJob(client: client)
            let options = Generate3DJob.Options(
                aiModel: aiModel,
                shouldRemesh: shouldRemesh,
                alsoUSDZ: alsoDownloadUSDZ,
                alsoFBX: alsoDownloadFBX,
                textQuality: textQuality,
                targetPolycount: Int(polycount),
                topology: topology,
                enablePbr: enablePBR,
                assetName: assetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : assetName,
                hardTimeout: 1800   // 30 min for sheet UI
            )
            let existing = Set(document.document.assetRepository.assets.map(\.name))
            let assets = try await job.run(
                kind: kind,
                options: options,
                existingAssetNames: existing,
                onProgress: { state in
                    await MainActor.run {
                        switch state {
                        case .pending:
                            phase = .progress(percent: 0)
                        case .inProgress(let pct):
                            phase = .progress(percent: pct)
                        case .succeeded:
                            phase = .importing
                        case .failed(let err):
                            phase = .error(err)
                        case .cancelled:
                            phase = .form
                        }
                    }
                }
            )
            await MainActor.run {
                for asset in assets {
                    document.document.assetRepository.addAsset(asset)
                }
                if let primary = assets.first {
                    let ref = document.document.assetRepository.assetRef(for: primary)
                    onAssetImported?(ref)
                }
                phase = .done
                HypeDocumentMutationCoordinator.shared.flushAllAutosaves()
            }
        } catch let error as MeshyError {
            await MainActor.run { phase = .error(error) }
        } catch KeychainStoreError.itemNotFound {
            await MainActor.run { phase = .error(.noAPIKey) }
        } catch {
            await MainActor.run { phase = .error(.networkError) }
        }
    }

    private func refreshBalance() async {
        guard meshyKeyIsSet else { return }
        await MainActor.run { balanceLoading = true }
        do {
            let apiKey = try KeychainStore.getSecret(account: KeychainStore.meshyAPIKeyAccount)
            let client = MeshyAIClient(apiKey: apiKey)
            let bal = try await client.fetchBalance()
            await MainActor.run {
                balance = bal
                balanceLoading = false
            }
        } catch {
            await MainActor.run { balanceLoading = false }
        }
    }

    // MARK: - Image input helpers

    /// Image-kinded assets available in the Asset Repository for the picker.
    private var imageRepositoryAssets: [Asset] {
        document.document.assetRepository.assets
            .filter { [AssetKind.imageTexture, .spriteSheet, .tileSet].contains($0.kind) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Count of filled multi-image slots.
    private var filledMultiImageCount: Int {
        multiImageResolved.compactMap { $0 }.count
    }

    /// Resolve a `MeshyImageInput` and write results into the provided bindings.
    private func resolveAndSet(
        _ input: MeshyImageInput,
        resolved: Binding<MeshyImageInput.Resolved?>,
        preview: Binding<NSImage?>,
        error: Binding<String?>
    ) {
        do {
            let result = try input.resolve(in: document.document.assetRepository)
            resolved.wrappedValue = result
            preview.wrappedValue = NSImage(data: result.data)
            error.wrappedValue = nil
        } catch let meshyError as MeshyError {
            error.wrappedValue = meshyError.errorDescription
            resolved.wrappedValue = nil
            preview.wrappedValue = nil
        } catch {
            self.imageValidationError = "Couldn't load image."
            resolved.wrappedValue = nil
            preview.wrappedValue = nil
        }
    }

    /// Import an image from the system clipboard.
    ///
    /// Priority: PNG > TIFF > PDF. NEVER reads `UTType.fileURL` from the
    /// pasteboard to avoid path-traversal via clipboard (OQ-B3).
    private func importFromClipboard(
        resolved: Binding<MeshyImageInput.Resolved?>,
        preview: Binding<NSImage?>,
        error: Binding<String?>
    ) {
        let pb = NSPasteboard.general

        // Try PNG first (preferred — no conversion needed).
        if let pngData = pb.data(forType: .png) {
            resolveAndSet(.base64(pngData.base64EncodedString()), resolved: resolved, preview: preview, error: error)
            return
        }

        // Try TIFF — convert to PNG via NSBitmapImageRep before resolving.
        if let tiffData = pb.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiffData),
           let pngData = rep.representation(using: .png, properties: [:]) {
            resolveAndSet(.base64(pngData.base64EncodedString()), resolved: resolved, preview: preview, error: error)
            return
        }

        // Try PDF — render first page to PNG.
        if let pdfData = pb.data(forType: .pdf),
           let pdfRep = NSPDFImageRep(data: pdfData) {
            let size = pdfRep.size
            guard size.width > 0 && size.height > 0 else {
                error.wrappedValue = "Could not read image from clipboard."
                return
            }
            let img = NSImage(size: size)
            img.lockFocus()
            pdfRep.draw()
            img.unlockFocus()

            // Prefer the non-deprecated TIFF round-trip for
            // `focusedViewRect`-free capture. The `tiffRepresentation` call
            // succeeds because the image was just drawn to during `lockFocus`.
            guard let tiffData = img.tiffRepresentation,
                  let rep2 = NSBitmapImageRep(data: tiffData),
                  let pngData = rep2.representation(using: .png, properties: [:]) else {
                error.wrappedValue = "Could not read image from clipboard."
                return
            }
            resolveAndSet(.base64(pngData.base64EncodedString()), resolved: resolved, preview: preview, error: error)
            return
        }

        error.wrappedValue = "No supported image found in clipboard. Copy a PNG or JPEG image first."
    }

    /// Open a file picker for a single image (Image tab).
    private func openImageFilePicker(
        resolved: Binding<MeshyImageInput.Resolved?>,
        preview: Binding<NSImage?>,
        error: Binding<String?>
    ) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.png, UTType.jpeg, UTType.webP].compactMap { $0 }
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            resolveAndSet(.filePath(url.path), resolved: resolved, preview: preview, error: error)
        }
    }

    /// Open a file picker for a multi-image slot.
    private func openMultiImageFilePicker(index: Int) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.png, UTType.jpeg, UTType.webP].compactMap { $0 }
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let resolved = try MeshyImageInput.filePath(url.path).resolve(in: document.document.assetRepository)
                multiImageResolved[index] = resolved
                multiImagePreviews[index] = NSImage(data: resolved.data)
                multiImageValidationError = nil
            } catch let err as MeshyError {
                multiImageValidationError = err.errorDescription
                multiImageResolved[index] = nil
                multiImagePreviews[index] = nil
            } catch {
                multiImageValidationError = "Could not load image."
                multiImageResolved[index] = nil
                multiImagePreviews[index] = nil
            }
        }
    }
}
