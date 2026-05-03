import AppKit
import SceneKit
import HypeCore

/// AppKit-hosted 3D scene viewer for `scene3D` parts.
///
/// Wraps `SCNView`. Loads `.usdz` / `.scn` / `.dae` / `.obj` from a
/// local file path or http(s) URL. The `apply(_:)` method only re-
/// loads the scene when the URL actually changed — toggling
/// camera control or anti-aliasing without forcing a heavyweight
/// scene rebuild.
///
/// `onLoadFailed` is called (on the main thread) when `SCNScene(url:)`
/// returns nil — e.g. the file is missing, corrupt, or an unsupported
/// format. The caller wires this to a HypeTalk `modelLoadFailed` dispatch.
final class Scene3DHostNSView: NSView {

    let scnView = SCNView()
    private var loadedURL: String = ""

    /// Called on the main thread when a scene fails to load. The `reason`
    /// string is a safe structural description (no raw file bytes).
    var onLoadFailed: ((_ reason: String) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scnView.translatesAutoresizingMaskIntoConstraints = false
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.antialiasingMode = .multisampling4X
        scnView.backgroundColor = .clear
        addSubview(scnView)
        NSLayoutConstraint.activate([
            scnView.topAnchor.constraint(equalTo: topAnchor),
            scnView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scnView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scnView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(_ part: Part) {
        scnView.allowsCameraControl = part.scene3DAllowsCameraControl
        scnView.autoenablesDefaultLighting = part.scene3DAutoLighting
        scnView.antialiasingMode = Self.aaMode(for: part.scene3DAntialiasing)

        if part.scene3DBackground.isEmpty {
            scnView.backgroundColor = .clear
        } else if let bg = NSColor(hexString: part.scene3DBackground) {
            scnView.backgroundColor = bg
        }

        if part.scene3DURL != loadedURL {
            loadedURL = part.scene3DURL
            loadScene(from: part.scene3DURL)
        }
    }

    private func loadScene(from raw: String) {
        guard !raw.isEmpty else {
            scnView.scene = nil
            return
        }
        let url: URL?
        if let parsed = URL(string: raw), parsed.scheme != nil {
            url = parsed
        } else {
            url = URL(fileURLWithPath: raw)
        }
        guard let url else {
            scnView.scene = nil
            return
        }
        // Load on a background queue so a large model doesn't
        // freeze the main thread; swap the scene in once ready.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let scene: SCNScene? = (try? SCNScene(url: url, options: nil))
            DispatchQueue.main.async {
                self?.scnView.scene = scene
                if scene == nil {
                    self?.onLoadFailed?("SCNScene returned nil for \(url.path)")
                }
            }
        }
    }

    private static func aaMode(for raw: String) -> SCNAntialiasingMode {
        switch raw.lowercased() {
        case "none": return .none
        case "multisampling2x": return .multisampling2X
        case "multisampling4x": return .multisampling4X
        case "multisampling8x":
            // SCNAntialiasingMode .multisampling8X is iOS-only; fall
            // back to 4X on macOS so the model field round-trips
            // without crashing.
            return .multisampling4X
        default: return .multisampling4X
        }
    }
}
