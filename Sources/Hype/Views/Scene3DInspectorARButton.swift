import SwiftUI
import HypeCore

// MARK: - OpenInARButton

/// "Open in AR" button for any `model3D` asset.
///
/// Invokes `ARQuickLookPresenter.shared.present(asset:)` in a Task when
/// tapped. On macOS 12 and earlier, the button is hidden (GLB→USDZ
/// conversion requires macOS 13+). Errors are surfaced via an alert
/// with the localized description.
struct OpenInARButton: View {

    // MARK: - Inputs

    let asset: Asset

    // MARK: - State

    @State private var lastError: IdentifiableARError? = nil
    @State private var isPreparing: Bool = false

    // MARK: - Body

    var body: some View {
        // Require macOS 13 for GLB → USDZ conversion support.
        if #available(macOS 13, *) {
            Button {
                guard !isPreparing else { return }
                isPreparing = true
                Task { @MainActor in
                    defer { isPreparing = false }
                    do {
                        try await ARQuickLookPresenter.shared.present(asset: asset)
                    } catch let err as ARQuickLookError {
                        lastError = IdentifiableARError(error: err)
                    } catch {
                        lastError = IdentifiableARError(
                            error: .stagingFailed(reason: error.localizedDescription)
                        )
                    }
                }
            } label: {
                HStack {
                    if isPreparing {
                        ProgressView()
                            .scaleEffect(0.55)
                            .frame(width: 12, height: 12)
                    }
                    Image(systemName: "arkit")
                    Text("Open in AR")
                }
            }
            .buttonStyle(.plain)
            .help("Open this 3D model in macOS Quick Look. Devices with AR support can place it in their environment.")
            .alert(item: $lastError) { wrapped in
                Alert(
                    title: Text("AR Quick Look failed"),
                    message: Text(wrapped.error.errorDescription ?? "An unexpected error occurred."),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
}

// MARK: - IdentifiableARError

/// Wraps `ARQuickLookError` in an `Identifiable` type so it can drive
/// `.alert(item:)` bindings.
private struct IdentifiableARError: Identifiable {
    let id = UUID()
    let error: ARQuickLookError
}
