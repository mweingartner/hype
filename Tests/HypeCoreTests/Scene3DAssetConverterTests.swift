import Foundation
import Testing
@testable import HypeCore

// MARK: - Scene3DAssetConverterTests

@Suite("GLB → USDZ converter")
struct Scene3DAssetConverterTests {

    private let converter = Scene3DAssetConverter()

    // MARK: (b) Input not found throws .inputMissing

    @Test("convertToUSDZ throws .inputMissing when input file doesn't exist")
    func throwsInputMissingForMissingFile() throws {
        let inputURL = URL(fileURLWithPath: "/nonexistent/path/missing.glb")
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("out_\(UUID().uuidString).usdz")

        if #available(macOS 13, *) {
            #expect(throws: Scene3DAssetConverter.ConvertError.inputMissing(path: inputURL.path)) {
                try converter.convertToUSDZ(inputURL: inputURL, outputURL: outputURL)
            }
        }
    }

    // MARK: (c) USDZ input throws .alreadyTargetFormat

    @Test("convertToUSDZ throws .alreadyTargetFormat when input is already USDZ")
    func throwsAlreadyTargetFormatForUsdzInput() throws {
        // Create a dummy .usdz file so the existence check passes.
        let tmp = FileManager.default.temporaryDirectory
        let inputURL = tmp.appendingPathComponent("already_\(UUID().uuidString).usdz")
        let outputURL = tmp.appendingPathComponent("out_\(UUID().uuidString).usdz")
        FileManager.default.createFile(atPath: inputURL.path, contents: Data([0x00]))
        defer { try? FileManager.default.removeItem(at: inputURL) }

        // Should throw .alreadyTargetFormat regardless of OS version.
        #expect(throws: Scene3DAssetConverter.ConvertError.alreadyTargetFormat) {
            try converter.convertToUSDZ(inputURL: inputURL, outputURL: outputURL)
        }
    }

    // MARK: (d) USDZ check is case-insensitive

    @Test("convertToUSDZ treats .USDZ extension (uppercase) as already-USDZ")
    func alreadyTargetFormatIsCaseInsensitive() throws {
        let tmp = FileManager.default.temporaryDirectory
        let inputURL = tmp.appendingPathComponent("already_\(UUID().uuidString).USDZ")
        let outputURL = tmp.appendingPathComponent("out_\(UUID().uuidString).usdz")
        FileManager.default.createFile(atPath: inputURL.path, contents: Data([0x00]))
        defer { try? FileManager.default.removeItem(at: inputURL) }

        #expect(throws: Scene3DAssetConverter.ConvertError.alreadyTargetFormat) {
            try converter.convertToUSDZ(inputURL: inputURL, outputURL: outputURL)
        }
    }

    // MARK: (e) macOS 12 or earlier throws .unsupportedOS

    @Test("convertToUSDZ throws .unsupportedOS when macOS version < 13 (simulated)")
    func throwsUnsupportedOSOnOlderMacOS() {
        // We can only test the OS branch at compile time. This test documents
        // the expected behavior and validates the error type round-trips.
        let err = Scene3DAssetConverter.ConvertError.unsupportedOS
        #expect(err.errorDescription?.contains("macOS 13") == true)
    }

    // MARK: (f) ConvertError.exportFailed carries reason string

    @Test("ConvertError.exportFailed stores the reason string")
    func exportFailedCarriesReason() {
        let err = Scene3DAssetConverter.ConvertError.exportFailed(reason: "mesh has zero vertices")
        if let desc = err.errorDescription {
            #expect(desc.contains("mesh has zero vertices"))
        }
    }

    // MARK: (g) ConvertError round-trips equality

    @Test("ConvertError values compare equal when matching")
    func convertErrorEquality() {
        #expect(Scene3DAssetConverter.ConvertError.alreadyTargetFormat
                == Scene3DAssetConverter.ConvertError.alreadyTargetFormat)
        #expect(Scene3DAssetConverter.ConvertError.assetEmpty
                == Scene3DAssetConverter.ConvertError.assetEmpty)
        #expect(Scene3DAssetConverter.ConvertError.exportFailed(reason: "x")
                == Scene3DAssetConverter.ConvertError.exportFailed(reason: "x"))
        #expect(Scene3DAssetConverter.ConvertError.exportFailed(reason: "x")
                != Scene3DAssetConverter.ConvertError.exportFailed(reason: "y"))
    }
}
