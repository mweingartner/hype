import AppKit
import PDFKit
import HypeCore

/// AppKit-hosted PDF viewer — wraps `PDFView` so PDF parts get a
/// scrollable, zoomable document inside the card. Loaded URLs can
/// be local file paths (resolved via `URL(fileURLWithPath:)`) or
/// http(s) URLs (fetched on a background thread; the view shows
/// the placeholder while downloading).
final class PDFHostNSView: NSView {

    let pdfView = PDFView()

    /// Path/URL we last loaded successfully. Lets `apply(_:)`
    /// avoid redundant network/disk reads when only sub-properties
    /// change (currentPage, displayMode).
    private var loadedURL: String = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        addSubview(pdfView)
        NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: topAnchor),
            pdfView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: trailingAnchor),
            pdfView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Apply the latest `Part` config to the live viewer.
    /// Re-loads only when `pdfURL` actually changed; cheap on
    /// follow-up update passes.
    func apply(_ part: Part, assetRepository: AssetRepository? = nil) {
        pdfView.autoScales = part.pdfAutoScales
        pdfView.displayMode = Self.displayMode(for: part.pdfDisplayMode)

        if let ref = part.pdfAssetRef,
           let asset = assetRepository?.asset(byId: ref.id) {
            let identity = "asset://\(asset.id.uuidString)/\(asset.data.count)"
            if identity != loadedURL {
                loadedURL = identity
                pdfView.document = PDFDocument(data: asset.data)
            }
        } else if part.pdfURL != loadedURL {
            loadedURL = part.pdfURL
            loadDocument(from: part.pdfURL)
        }

        // Page navigation — apply ONLY when a document is loaded
        // and the requested page is within range. Off-by-one
        // shouldn't crash; PDFKit clamps internally but we guard
        // explicitly to keep behavior predictable.
        if let doc = pdfView.document {
            let target = max(1, min(part.pdfCurrentPage, doc.pageCount))
            if let page = doc.page(at: target - 1), pdfView.currentPage != page {
                pdfView.go(to: page)
            }
        }
    }

    private func loadDocument(from raw: String) {
        guard !raw.isEmpty else {
            pdfView.document = nil
            return
        }
        // Heuristic: scheme present → treat as URL; otherwise
        // treat as a file path (relative paths resolve against
        // the current working dir, which is the document's
        // directory at runtime).
        let url: URL?
        if let parsed = URL(string: raw), parsed.scheme != nil {
            url = parsed
        } else {
            url = URL(fileURLWithPath: raw)
        }
        guard let url else {
            pdfView.document = nil
            return
        }
        // Synchronous load for local files — PDFKit's `init?(url:)`
        // is fast for local paths. Remote URLs are fetched on a
        // background dispatch to avoid blocking the main thread,
        // and the view stays empty until the data arrives.
        if url.isFileURL {
            pdfView.document = PDFDocument(url: url)
        } else {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let data = try? Data(contentsOf: url) else { return }
                let doc = PDFDocument(data: data)
                DispatchQueue.main.async {
                    self?.pdfView.document = doc
                }
            }
        }
    }

    private static func displayMode(for raw: String) -> PDFDisplayMode {
        switch raw.lowercased() {
        case "single", "singlepage": return .singlePage
        case "continuous", "singlepagecontinuous": return .singlePageContinuous
        case "twoup", "two_up", "twopage": return .twoUp
        case "twoupcontinuous", "twopagescontinuous": return .twoUpContinuous
        default: return .singlePageContinuous
        }
    }
}
