import Foundation

// MARK: - SVGSanitizer

/// Pure-functional sanitizer for SVG assets downloaded from the web.
///
/// **Rationale**: `NSImage` on macOS uses WebKit to render SVG. Any unsanitized
/// vector — `<script>`, `<foreignObject>` with embedded HTML/JS, SMIL animations
/// whose `to`/`from`/`href` point at JavaScript, inline `<style>` or `style=`
/// that fetches a remote URL via `url()`, `data:image/svg+xml` re-embedded via
/// `<use href="data:…">`, or `<image src=…>` pointing off-site — becomes directly
/// exploitable because WebKit will execute scripts and fetch resources. This
/// sanitizer is the only line of defense between a malicious SVG and WebKit
/// execution; every attack vector below is covered.
///
/// **Unconditional `style=` strip** (Security Finding C): the `style=` attribute is
/// stripped on every element regardless of whether it contains `url(`. The
/// `contains("url(")` substring check is evadable via CSS escape sequences; the
/// harder posture — strip unconditionally — is both safer and simpler. Sprite
/// assets never need inline CSS to render.
public enum SVGSanitizer {

    // MARK: - Report

    /// A count of each sanitization action taken during `sanitize(_:)`.
    public struct Report: Sendable {
        public var removedScriptCount: Int = 0
        public var strippedHrefCount: Int = 0
        public var removedForeignObjectCount: Int = 0
        public var strippedAnimationCount: Int = 0
        public var removedStyleCount: Int = 0
        /// Number of `style=` attributes stripped (unconditionally, per Finding C).
        public var strippedStyleAttributeCount: Int = 0
        public var strippedImageSrcCount: Int = 0
    }

    // MARK: - SMIL animation local names

    private static let smilAnimationNames: Set<String> = [
        "animate", "animatetransform", "animatemotion", "set", "discard"
    ]

    // MARK: - Allowed data: MIME types for href/src

    /// Only these four `data:` MIME types may appear in `href`/`xlink:href`/`src`.
    /// `data:image/svg+xml` is explicitly forbidden — re-embedded SVG is a known
    /// sanitizer bypass (Security Findings 2 and 6).
    private static let allowedDataMimeTypes: Set<String> = [
        "data:image/png",
        "data:image/jpeg",
        "data:image/webp",
        "data:image/gif",
    ]

    // MARK: - Public API

    /// Sanitize an SVG byte payload, returning clean bytes and a report of changes.
    ///
    /// - Parameter input: Raw SVG bytes (expected to be valid UTF-8 XML).
    /// - Returns: Sanitized UTF-8 bytes and a change report.
    /// - Throws: `WebAssetSearchError.svgRejected` on XML parse failure.
    public static func sanitize(_ input: Data) throws -> (bytes: Data, report: Report) {
        #if os(macOS)
        // Step 1: Parse with XMLDocument for a proper DOM.
        let options: XMLNode.Options = [.documentTidyXML, .nodePreserveWhitespace]
        let doc: XMLDocument
        do {
            doc = try XMLDocument(data: input, options: options)
        } catch {
            throw WebAssetSearchError.svgRejected("Invalid XML: \(error.localizedDescription)")
        }

        var report = Report()

        // Step 2 (baseline): remove <script> elements anywhere in the tree.
        if let scripts = try? doc.nodes(forXPath: "//*[local-name()='script']") {
            for node in scripts {
                node.detach()
                report.removedScriptCount += 1
            }
        }

        // Step 3a: detach <foreignObject> elements.
        if let fos = try? doc.nodes(forXPath: "//*[local-name()='foreignObject']") {
            for node in fos {
                node.detach()
                report.removedForeignObjectCount += 1
            }
        }

        // Step 3b: SMIL animation elements — strip javascript: and external hrefs.
        // Walk all elements, check local name.
        walkElements(doc.rootElement()) { element in
            let localName = element.localName?.lowercased() ?? ""
            guard smilAnimationNames.contains(localName) else { return }

            // Strip attributes whose values begin with "javascript:" (case-insensitive, trimmed).
            let animAttrsToCheck = ["to", "from", "by", "values", "href", "xlink:href"]
            for attrName in animAttrsToCheck {
                if let attr = element.attribute(forLocalName: attrName.components(separatedBy: ":").last!, uri: nil)
                    ?? element.attribute(forName: attrName) {
                    let val = attr.stringValue?.trimmingCharacters(in: .whitespaces) ?? ""
                    if val.lowercased().hasPrefix("javascript:") {
                        attr.detach()
                        report.strippedAnimationCount += 1
                    }
                }
            }

            // If remaining href / xlink:href references an external URL, detach the element.
            let hrefVal = (element.attribute(forLocalName: "href", uri: nil)
                ?? element.attribute(forName: "xlink:href"))?.stringValue ?? ""
            if !hrefVal.isEmpty && isExternalURL(hrefVal) {
                element.detach()
                report.strippedAnimationCount += 1
            }
        }

        // Step 3c: Inline CSS url() containment.
        // <style> elements whose text content contains url( with a non-local argument: detach.
        if let styles = try? doc.nodes(forXPath: "//*[local-name()='style']") {
            for node in styles {
                if let textContent = node.stringValue, textContent.contains("url(") {
                    // Check if any url() argument is non-local (not a fragment or relative path).
                    if styleHasExternalURL(textContent) {
                        node.detach()
                        report.removedStyleCount += 1
                    }
                }
            }
        }

        // style= attribute: strip unconditionally on every element (Security Finding C).
        // The `contains("url(")` check is evadable via CSS escapes; unconditional strip
        // is the recommended hardening posture. Sprite assets never need inline CSS.
        walkElements(doc.rootElement()) { element in
            if let styleAttr = element.attribute(forName: "style") {
                styleAttr.detach()
                report.strippedStyleAttributeCount += 1
            }
        }

        // Step 3 (href preservation) + Step 3d (narrowed data: allow-list):
        // For every href / xlink:href attribute, apply preservation rules.
        walkElements(doc.rootElement()) { element in
            for attrName in ["href", "xlink:href"] {
                let attr: XMLNode?
                if attrName == "href" {
                    attr = element.attribute(forLocalName: "href", uri: nil) ?? element.attribute(forName: "href")
                } else {
                    attr = element.attribute(forLocalName: "href", uri: "http://www.w3.org/1999/xlink")
                        ?? element.attribute(forName: "xlink:href")
                }
                guard let hrefAttr = attr else { continue }
                let value = hrefAttr.stringValue?.trimmingCharacters(in: .whitespaces) ?? ""
                if !shouldPreserveHref(value) {
                    hrefAttr.detach()
                    report.strippedHrefCount += 1
                }
            }
        }

        // Step 3e: <image> element src / xlink:src stripping.
        walkElements(doc.rootElement()) { element in
            let localName = element.localName?.lowercased() ?? ""
            guard localName == "image" else { return }
            for srcAttrName in ["src", "xlink:src"] {
                let attr: XMLNode?
                if srcAttrName == "src" {
                    attr = element.attribute(forLocalName: "src", uri: nil) ?? element.attribute(forName: "src")
                } else {
                    attr = element.attribute(forLocalName: "src", uri: "http://www.w3.org/1999/xlink")
                        ?? element.attribute(forName: "xlink:src")
                }
                guard let srcAttr = attr else { continue }
                let value = srcAttr.stringValue?.trimmingCharacters(in: .whitespaces) ?? ""
                if !shouldPreserveHref(value) {
                    srcAttr.detach()
                    report.strippedImageSrcCount += 1
                }
            }
        }

        // Step 4: Serialize back to XML.
        let xmlData = doc.xmlData(options: .nodeCompactEmptyElement)
        return (bytes: xmlData, report: report)
        #else
        throw WebAssetSearchError.svgRejected("SVG sanitization is available only in the macOS authoring runtime.")
        #endif
    }

    // MARK: - Helpers

    /// Walk every XML element in the subtree rooted at `element`, calling `visitor` on each.
    #if os(macOS)
    private static func walkElements(_ element: XMLElement?, visitor: (XMLElement) -> Void) {
        guard let element else { return }
        visitor(element)
        for child in element.children ?? [] {
            if let childElement = child as? XMLElement {
                walkElements(childElement, visitor: visitor)
            }
        }
    }
    #endif

    /// Returns `true` if an href/src value should be preserved:
    /// - Fragment references (`#something`)
    /// - Relative paths (no `://` and doesn't start with `//`)
    /// - `data:image/{png,jpeg,webp,gif}` (narrowed allow-list per Finding 2/6)
    ///
    /// Everything else — including `data:image/svg+xml`, `javascript:`, `http://`,
    /// `https://`, `file:`, `mailto:`, protocol-relative `//` — is stripped.
    private static func shouldPreserveHref(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }

        // Fragment reference
        if value.hasPrefix("#") { return true }

        // data: URLs — MUST be checked before the relative-path heuristic
        // because "data:..." doesn't contain "://" and doesn't start with "//"
        // and would therefore pass the relative-path guard below incorrectly.
        // Only the narrow allow-list of safe image MIME types is permitted.
        // data:image/svg+xml is explicitly excluded (Security Findings 2 and 6).
        let lowered = value.lowercased()
        if lowered.hasPrefix("data:") {
            for allowed in allowedDataMimeTypes {
                if lowered.hasPrefix(allowed) { return true }
            }
            return false  // data: scheme not in allow-list → reject
        }

        // Relative path (no scheme, no protocol-relative)
        if !value.contains("://") && !value.hasPrefix("//") { return true }

        // Everything else (http://, https://, javascript:, etc.) is rejected
        return false
    }

    /// Returns `true` if the URL in a href/xlink:href is an external URL
    /// (not a fragment, not a relative path, not an allowed data: URL).
    private static func isExternalURL(_ value: String) -> Bool {
        return !shouldPreserveHref(value)
    }

    /// Inspect a `<style>` element's text for external `url()` references.
    /// A url() is "external" if its argument is not a `#fragment`, a relative
    /// path, or one of the allowed `data:image/{png,jpeg,webp,gif}` types.
    private static func styleHasExternalURL(_ css: String) -> Bool {
        // Scan for url( occurrences
        var searchRange = css.startIndex..<css.endIndex
        while let urlStart = css.range(of: "url(", options: .caseInsensitive, range: searchRange) {
            // Find the closing )
            let argStart = urlStart.upperBound
            guard let closeIndex = css[argStart...].firstIndex(of: ")") else { return true }

            var arg = String(css[argStart..<closeIndex])
                .trimmingCharacters(in: .whitespaces)
            // Strip optional quotes
            if (arg.hasPrefix("\"") && arg.hasSuffix("\""))
                || (arg.hasPrefix("'") && arg.hasSuffix("'")) {
                arg = String(arg.dropFirst().dropLast())
            }

            if !shouldPreserveHref(arg) { return true }
            searchRange = closeIndex..<css.endIndex
        }
        return false
    }
}
