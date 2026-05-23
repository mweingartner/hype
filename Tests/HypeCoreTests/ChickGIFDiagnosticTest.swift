import Foundation
import Testing
@testable import HypeCore

/// Synthetic 2-frame GIF decode sanity check.
///
/// Note: the original user-visible bug ("chick GIF in teststack.hype
/// displays as a static image") was NOT in the animator itself but in
/// the host NSView's `layerContentsRedrawPolicy`. See
/// `Tests/HypeTests/CardCanvasRedrawPolicyTests.swift` for the actual
/// regression pin. The end-to-end animator lifecycle is already covered
/// by `Tests/HypeCoreTests/GIFAnimatorTests.swift`.
///
/// This test exists to confirm the multi-frame branch of `GIFDecoder`
/// works against a minimal, hand-crafted GIF89a payload, without any
/// binary fixtures on disk.
@Suite("Diagnostic: GIFDecoder synthetic 2-frame GIF")
struct ChickGIFDiagnosticTest {

    /// Smallest possible valid GIF89a with 2 frames of solid color.
    /// Frame 1: 1x1 red pixel, Frame 2: 1x1 blue pixel, each 0.16s delay,
    /// infinite loop. Hand-crafted to exercise the multi-frame branch
    /// in GIFDecoder without needing a binary fixture on disk.
    private static let twoFrameGIF: Data = {
        var bytes: [UInt8] = [
            0x47, 0x49, 0x46, 0x38, 0x39, 0x61,            // GIF89a
            0x01, 0x00, 0x01, 0x00,                        // 1x1 logical screen
            0x91, 0x00, 0x00,                              // packed: global color table, 2 colors
            0xFF, 0x00, 0x00,                              // color 0: red
            0x00, 0x00, 0xFF,                              // color 1: blue
            0x00, 0x00, 0x00,                              // color 2: unused
            0x00, 0x00, 0x00,                              // color 3: unused
            // NETSCAPE2.0 looping extension
            0x21, 0xFF, 0x0B,
            0x4E, 0x45, 0x54, 0x53, 0x43, 0x41, 0x50, 0x45, 0x32, 0x2E, 0x30,
            0x03, 0x01, 0x00, 0x00, 0x00,
        ]
        bytes += [
            0x21, 0xF9, 0x04, 0x00, 0x10, 0x00, 0x00, 0x00,
            0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
            0x02, 0x02, 0x44, 0x01, 0x00,
        ]
        bytes += [
            0x21, 0xF9, 0x04, 0x00, 0x10, 0x00, 0x00, 0x00,
            0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
            0x02, 0x02, 0x4C, 0x01, 0x00,
        ]
        bytes += [0x3B]
        return Data(bytes)
    }()

    @Test("synthetic 2-frame GIF decodes via GIFDecoder")
    func syntheticGIFDecodes() throws {
        let decoded = try #require(GIFDecoder.decode(Self.twoFrameGIF),
                                   "synthetic 2-frame GIF must decode")
        #expect(decoded.frames.count == 2)
        #expect(decoded.frameDelays.count == 2)
        // The GIF's GCE byte 0x10 is delay = 0x0010 = 16 hundredths = 0.16s.
        // GIFDecoder clamps anything ≤ 0.020 to 0.100; 0.16 is above that.
        #expect(decoded.frameDelays[0] >= 0.15)
        // loopCount == 0 is "infinite loop" per the GIF/NETSCAPE spec.
        #expect(decoded.loopCount == 0)
    }
}
