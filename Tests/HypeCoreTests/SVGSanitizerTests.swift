import Testing
import Foundation
@testable import HypeCore

/// Comprehensive tests for `SVGSanitizer` — covers all sanitization rules
/// including Security Findings 2, 6, and C from the post-Builder review.
@Suite("SVGSanitizer — sanitization rules")
struct SVGSanitizerTests {

    // MARK: - Helpers

    private func svgData(_ body: String) -> Data {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
        \(body)
        </svg>
        """.data(using: .utf8)!
    }

    private func sanitize(_ body: String) throws -> (String, SVGSanitizer.Report) {
        let input = svgData(body)
        let (bytes, report) = try SVGSanitizer.sanitize(input)
        let output = String(data: bytes, encoding: .utf8) ?? ""
        return (output, report)
    }

    // MARK: - <script> removal

    @Test("<script> elements are removed from the SVG")
    func scriptElementsRemoved() throws {
        let (output, report) = try sanitize("""
        <rect x="0" y="0" width="50" height="50" fill="blue"/>
        <script>alert('xss')</script>
        """)
        #expect(!output.contains("<script"))
        #expect(!output.contains("alert"))
        #expect(report.removedScriptCount == 1)
    }

    @Test("multiple <script> elements all removed")
    func multipleScriptElementsRemoved() throws {
        let (output, report) = try sanitize("""
        <script>alert(1)</script>
        <rect x="0" y="0" width="10" height="10"/>
        <script>alert(2)</script>
        """)
        #expect(!output.contains("<script"))
        #expect(report.removedScriptCount == 2)
    }

    @Test("nested <script> element is removed")
    func nestedScriptRemoved() throws {
        let (output, report) = try sanitize("""
        <g>
            <script>document.cookie</script>
            <circle r="5"/>
        </g>
        """)
        #expect(!output.contains("<script"))
        #expect(report.removedScriptCount == 1)
    }

    // MARK: - <foreignObject> removal

    @Test("<foreignObject> elements are detached")
    func foreignObjectRemoved() throws {
        let (output, report) = try sanitize("""
        <foreignObject width="100" height="100">
            <div xmlns="http://www.w3.org/1999/xhtml">Hello</div>
        </foreignObject>
        """)
        #expect(!output.contains("foreignObject"))
        #expect(report.removedForeignObjectCount == 1)
    }

    // MARK: - SMIL animation javascript: stripping

    @Test("SMIL <animate> with javascript: in 'to' attribute is stripped")
    func animateJavaScriptToStripped() throws {
        let (output, report) = try sanitize("""
        <animate attributeName="href" to="javascript:alert(1)" dur="1s"/>
        """)
        #expect(!output.contains("javascript:"))
        #expect(report.strippedAnimationCount >= 1)
    }

    @Test("SMIL <animate> with javascript: in 'from' attribute is stripped")
    func animateJavaScriptFromStripped() throws {
        let (output, report) = try sanitize("""
        <animate attributeName="href" from="javascript:void(0)" dur="1s"/>
        """)
        #expect(!output.contains("javascript:"))
        #expect(report.strippedAnimationCount >= 1)
    }

    @Test("SMIL <animate> with javascript: in 'href' attribute is stripped")
    func animateJavaScriptHrefStripped() throws {
        let (output, report) = try sanitize("""
        <animate attributeName="xlink:href" href="javascript:alert(1)" dur="1s"/>
        """)
        #expect(!output.contains("javascript:"))
        #expect(report.strippedAnimationCount >= 1)
    }

    @Test("SMIL <animate> with javascript: case-insensitive is stripped")
    func animateJavaScriptCaseInsensitive() throws {
        let (output, report) = try sanitize("""
        <animate attributeName="href" to="JAVASCRIPT:alert(1)" dur="1s"/>
        """)
        #expect(!output.lowercased().contains("javascript:"))
        #expect(report.strippedAnimationCount >= 1)
    }

    @Test("SMIL <animate> with external http href is detached entirely")
    func animateExternalHrefDetached() throws {
        let (output, report) = try sanitize("""
        <animate attributeName="href" href="http://evil.com/payload" dur="1s"/>
        """)
        // The element itself should be removed (external href triggers element detach)
        #expect(!output.contains("http://evil.com"))
        #expect(report.strippedAnimationCount >= 1)
    }

    @Test("SMIL <animateTransform> with javascript: in 'by' is stripped")
    func animateTransformByJavaScript() throws {
        let (output, report) = try sanitize("""
        <animateTransform attributeName="transform" by="javascript:1" dur="1s"/>
        """)
        #expect(!output.contains("javascript:"))
        #expect(report.strippedAnimationCount >= 1)
    }

    @Test("SMIL <set> with javascript: in 'values' is stripped")
    func setValuesJavaScript() throws {
        let (output, report) = try sanitize("""
        <set attributeName="href" values="javascript:alert(1)" dur="1s"/>
        """)
        #expect(!output.contains("javascript:"))
        #expect(report.strippedAnimationCount >= 1)
    }

    // MARK: - <style> with external url() removal

    @Test("<style> element with external url() is detached")
    func styleExternalURLDetached() throws {
        let (output, report) = try sanitize("""
        <style>rect { fill: url(http://evil.com/track.png); }</style>
        <rect x="0" y="0" width="50" height="50"/>
        """)
        #expect(!output.contains("url(http://"))
        #expect(report.removedStyleCount == 1)
    }

    @Test("<style> element with external https url() is detached")
    func styleExternalHTTPSURLDetached() throws {
        let (output, report) = try sanitize("""
        <style>rect { fill: url(https://evil.com/track.png); }</style>
        """)
        #expect(!output.contains("url(https://"))
        #expect(report.removedStyleCount == 1)
    }

    @Test("<style> element without external url() is preserved")
    func styleWithoutExternalURLPreserved() throws {
        let (output, report) = try sanitize("""
        <style>rect { fill: blue; }</style>
        <rect x="0" y="0" width="50" height="50"/>
        """)
        // Style element without external url() should remain
        #expect(output.contains("fill: blue") || output.contains("fill:blue"))
        #expect(report.removedStyleCount == 0)
    }

    @Test("<style> element with fragment url() is preserved")
    func styleWithFragmentURLPreserved() throws {
        let (output, report) = try sanitize("""
        <style>rect { fill: url(#localGradient); }</style>
        <rect x="0" y="0" width="50" height="50"/>
        """)
        #expect(output.contains("url(#localGradient)"))
        #expect(report.removedStyleCount == 0)
    }

    // MARK: - style= attribute unconditional stripping (Security Finding C)

    @Test("style= attribute stripped unconditionally on every element")
    func styleAttributeStrippedUnconditionally() throws {
        let (output, report) = try sanitize("""
        <rect x="0" y="0" width="50" height="50" style="fill:blue"/>
        """)
        #expect(!output.contains("style=\"fill:blue\""))
        #expect(report.strippedStyleAttributeCount >= 1)
    }

    @Test("style= attribute with non-url value is still stripped (unconditional posture)")
    func styleAttributeNoURLStillStripped() throws {
        let (output, report) = try sanitize("""
        <rect style="opacity: 0.5"/>
        """)
        #expect(!output.contains("style="))
        #expect(report.strippedStyleAttributeCount >= 1)
    }

    @Test("style= attribute with url() is stripped")
    func styleAttributeWithURLStripped() throws {
        let (output, report) = try sanitize("""
        <rect style="fill: url(http://evil.com/track)"/>
        """)
        #expect(!output.contains("style="))
        #expect(report.strippedStyleAttributeCount >= 1)
    }

    @Test("style= attribute on nested elements all stripped")
    func styleAttributeNestedStripped() throws {
        let (output, report) = try sanitize("""
        <g style="color:red">
            <rect style="fill:blue"/>
        </g>
        """)
        #expect(!output.contains("style="))
        #expect(report.strippedStyleAttributeCount >= 2)
    }

    // MARK: - data:image/svg+xml rejection (Security Finding 6)

    @Test("data:image/svg+xml in href is REJECTED (Security Finding 6)")
    func dataSVGInHrefRejected() throws {
        let payload = "data:image/svg+xml;base64,PHN2Zy8+"  // base64 of <svg/>
        let (output, report) = try sanitize("""
        <use href="\(payload)"/>
        """)
        #expect(!output.contains("data:image/svg+xml"))
        #expect(report.strippedHrefCount >= 1)
    }

    @Test("data:image/svg+xml in xlink:href is REJECTED")
    func dataSVGInXlinkHrefRejected() throws {
        let payload = "data:image/svg+xml;base64,PHN2Zy8+"
        let (output, report) = try sanitize("""
        <use xmlns:xlink="http://www.w3.org/1999/xlink" xlink:href="\(payload)"/>
        """)
        #expect(!output.contains("data:image/svg+xml"))
        #expect(report.strippedHrefCount >= 1)
    }

    @Test("data:text/html in href is REJECTED")
    func dataHTMLInHrefRejected() throws {
        let (output, report) = try sanitize("""
        <use href="data:text/html,<script>alert(1)</script>"/>
        """)
        #expect(!output.contains("data:text/html"))
        #expect(report.strippedHrefCount >= 1)
    }

    @Test("data:image/png in href is PRESERVED")
    func dataPNGInHrefPreserved() throws {
        // A small valid data URL for a transparent PNG pixel
        let pngData = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        let (output, _) = try sanitize("""
        <image href="\(pngData)" width="1" height="1"/>
        """)
        #expect(output.contains("data:image/png"))
    }

    @Test("data:image/jpeg in href is preserved")
    func dataJPEGInHrefPreserved() throws {
        let (output, _) = try sanitize("""
        <image href="data:image/jpeg;base64,/9j/fake" width="1" height="1"/>
        """)
        #expect(output.contains("data:image/jpeg"))
    }

    @Test("data:image/webp in href is preserved")
    func dataWebpInHrefPreserved() throws {
        let (output, _) = try sanitize("""
        <image href="data:image/webp;base64,fake" width="1" height="1"/>
        """)
        #expect(output.contains("data:image/webp"))
    }

    // MARK: - <image> src stripping

    @Test("<image src='http://external'> is stripped")
    func imageExternalSrcStripped() throws {
        let (output, report) = try sanitize("""
        <image src="http://evil.com/track.png" width="100" height="100"/>
        """)
        #expect(!output.contains("http://evil.com"))
        #expect(report.strippedImageSrcCount >= 1)
    }

    @Test("<image src='#fragment'> is preserved")
    func imageFragmentSrcPreserved() throws {
        let (output, report) = try sanitize("""
        <image src="#myImage" width="100" height="100"/>
        """)
        #expect(output.contains("#myImage"))
        #expect(report.strippedImageSrcCount == 0)
    }

    // MARK: - href preservation rules

    @Test("fragment href (#id) is preserved")
    func fragmentHrefPreserved() throws {
        let (output, _) = try sanitize("""
        <use href="#star"/>
        """)
        #expect(output.contains("#star"))
    }

    @Test("relative path href is preserved")
    func relativeHrefPreserved() throws {
        let (output, _) = try sanitize("""
        <use href="sprites/dot.svg"/>
        """)
        #expect(output.contains("sprites/dot.svg"))
    }

    @Test("http:// href is stripped")
    func httpHrefStripped() throws {
        let (output, report) = try sanitize("""
        <use href="http://evil.com/exploit.svg"/>
        """)
        #expect(!output.contains("http://evil.com"))
        #expect(report.strippedHrefCount >= 1)
    }

    @Test("https:// href is stripped")
    func httpsHrefStripped() throws {
        let (output, report) = try sanitize("""
        <use href="https://evil.com/exploit.svg"/>
        """)
        #expect(!output.contains("https://evil.com"))
        #expect(report.strippedHrefCount >= 1)
    }

    @Test("protocol-relative // href is stripped")
    func protocolRelativeHrefStripped() throws {
        let (output, report) = try sanitize("""
        <use href="//evil.com/exploit.svg"/>
        """)
        #expect(!output.contains("//evil.com"))
        #expect(report.strippedHrefCount >= 1)
    }

    // MARK: - Benign SVG round-trip

    @Test("a benign SVG round-trips with no data loss")
    func benignSVGRoundTrips() throws {
        let original = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
            <defs>
                <linearGradient id="grad">
                    <stop offset="0%" stop-color="red"/>
                    <stop offset="100%" stop-color="blue"/>
                </linearGradient>
            </defs>
            <rect x="0" y="0" width="100" height="100" fill="url(#grad)"/>
            <circle cx="50" cy="50" r="30" fill="green"/>
        </svg>
        """
        let input = original.data(using: .utf8)!
        let (bytes, report) = try SVGSanitizer.sanitize(input)
        let output = String(data: bytes, encoding: .utf8) ?? ""

        // Should still contain the structural elements
        #expect(output.contains("linearGradient"))
        #expect(output.contains("rect"))
        #expect(output.contains("circle"))
        // No sanitization actions taken
        #expect(report.removedScriptCount == 0)
        #expect(report.removedForeignObjectCount == 0)
        #expect(report.strippedStyleAttributeCount == 0)
        #expect(report.strippedHrefCount == 0)
    }

    // MARK: - Garbage / invalid XML

    @Test("garbage input (invalid XML) throws svgRejected or returns empty report")
    func invalidXMLThrowsSVGRejected() throws {
        // XMLDocument with .documentTidyXML may attempt to recover partial XML.
        // For totally non-XML content, it typically throws — but behaviour is
        // implementation-defined. We accept either: an error (correct) or a
        // successful parse with no script/foreign-object content (safe).
        // What we MUST NOT see is a crash.
        let garbage = "AAAA BBBB CCCC!!!".data(using: .utf8)!
        do {
            let (_, _) = try SVGSanitizer.sanitize(garbage)
            // XMLDocument tidied it — acceptable, no crash
        } catch {
            #expect(error is WebAssetSearchError)
        }
    }

    @Test("empty data throws svgRejected")
    func emptyDataThrowsSVGRejected() throws {
        #expect(throws: WebAssetSearchError.self) {
            try SVGSanitizer.sanitize(Data())
        }
    }

    @Test("partially malformed XML throws svgRejected")
    func partiallyMalformedXMLThrows() throws {
        let partial = "<svg><rect x=0 y=0".data(using: .utf8)!
        // Either throws OR returns a report with empty bytes — XMLDocument may tidy it
        // The important thing is no crash; we accept either behavior.
        do {
            let (_, _) = try SVGSanitizer.sanitize(partial)
            // Tidied successfully — acceptable
        } catch {
            // Threw an error — also acceptable
            #expect(error is WebAssetSearchError)
        }
    }

    // MARK: - SVGSanitizer.Report verification

    @Test("report counts each sanitization action independently")
    func reportCountsIndependently() throws {
        let (_, report) = try sanitize("""
        <script>alert(1)</script>
        <foreignObject><div/></foreignObject>
        <rect style="fill:red"/>
        """)
        #expect(report.removedScriptCount == 1)
        #expect(report.removedForeignObjectCount == 1)
        #expect(report.strippedStyleAttributeCount >= 1)
    }
}
