import Foundation
import CoreGraphics
import ImageIO
import Testing
@testable import HypeCore

@Suite("Simulator runtime launcher")
struct SimulatorRuntimeLauncherTests {
    @Test("simctl JSON parser filters Apple runtime devices by Hype target")
    func parserFiltersAppleRuntimeDevicesByTarget() throws {
        let json = """
        {
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
              {
                "udid": "PHONE-1",
                "isAvailable": true,
                "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
                "state": "Shutdown",
                "name": "iPhone 17"
              },
              {
                "udid": "PAD-1",
                "isAvailable": true,
                "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB",
                "state": "Booted",
                "name": "iPad Pro 13-inch (M5)"
              },
              {
                "udid": "UNAVAILABLE-1",
                "isAvailable": false,
                "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro",
                "state": "Shutdown",
                "name": "iPhone 17 Pro"
              }
            ],
            "com.apple.CoreSimulator.SimRuntime.tvOS-26-5": [
              {
                "udid": "TV-1",
                "isAvailable": true,
                "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.Apple-TV-4K-3rd-generation-4K",
                "state": "Shutdown",
                "name": "Apple TV 4K"
              }
            ],
            "com.apple.CoreSimulator.SimRuntime.watchOS-26-5": [
              {
                "udid": "WATCH-1",
                "isAvailable": true,
                "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-11-46mm",
                "state": "Shutdown",
                "name": "Apple Watch"
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let devices = try HypeSimulatorRuntimeLauncher.decodeAvailableDevices(from: json)

        #expect(devices.map(\.udid) == ["PHONE-1", "PAD-1", "TV-1"])
        #expect(devices.first { $0.udid == "PHONE-1" }?.platform == .iPhone)
        #expect(devices.first { $0.udid == "PAD-1" }?.platform == .iPad)
        #expect(devices.first { $0.udid == "TV-1" }?.platform == .tvOS)
        #expect(devices.first { $0.udid == "PAD-1" }?.runtimeName == "iOS 26.5")
    }

    @Test("launcher builds package and runs simulator commands without shell interpolation")
    func launcherRunsSimulatorCommandsWithoutShellInterpolation() async throws {
        var document = HypeDocument.newDocument(name: "Launch Test")
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [.iPhone],
            primaryPlatform: .iPhone,
            selectionPromptAcknowledged: true,
            layoutPolicy: .scaleToFit
        )
        document.addPart(Part(partType: .button, cardId: document.cards[0].id, name: "Tap Me"))

        let device = HypeSimulatorDevice(
            name: "iPhone 17",
            udid: "PHONE-1",
            platform: .iPhone,
            runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
            runtimeName: "iOS 26.5",
            deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
            state: "Shutdown"
        )
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("HypeSimulatorLauncherTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: output) }

        let runner = RecordingSimulatorCommandRunner()
        let launcher = HypeSimulatorRuntimeLauncher(commandRunner: runner)
        let result = try await launcher.launch(
            document: document,
            platform: .iPhone,
            device: device,
            outputDirectory: output
        )
        let commands = await runner.recordedCommands()

        #expect(result.manifest.platform == .iPhone)
        #expect(result.manifest.runtimeOnly)
        #expect(result.manifest.bundleIdentifier == "com.hype.runtime.launch-test.iphone")
        #expect(FileManager.default.fileExists(atPath: result.appBundleURL.path))
        #expect(commands.allSatisfy { $0.executableURL.path != "/bin/sh" })
        #expect(commands.contains { $0.executableURL.path == "/usr/bin/xcrun" && $0.arguments.prefix(2) == ["xcodebuild", "-project"] })
        #expect(commands.contains { $0.arguments.prefix(3) == ["simctl", "boot", "PHONE-1"] })
        #expect(commands.contains { $0.executableURL.path == "/usr/bin/open" && $0.arguments == ["-a", "Simulator", "--args", "-CurrentDeviceUDID", "PHONE-1"] })
        #expect(commands.contains { $0.arguments.prefix(3) == ["simctl", "install", "PHONE-1"] })
        #expect(commands.contains { $0.arguments == ["simctl", "launch", "PHONE-1", "com.hype.runtime.launch-test.iphone"] })
    }

    @Test("launcher treats Simulator UI open as best effort")
    func launcherDoesNotFailWhenSimulatorAppOpenFails() async throws {
        var document = HypeDocument.newDocument(name: "Launch Test")
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [.iPhone],
            primaryPlatform: .iPhone,
            selectionPromptAcknowledged: true,
            layoutPolicy: .scaleToFit
        )
        document.addPart(Part(partType: .button, cardId: document.cards[0].id, name: "Tap Me"))

        let device = HypeSimulatorDevice(
            name: "iPhone 17",
            udid: "PHONE-1",
            platform: .iPhone,
            runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
            runtimeName: "iOS 26.5",
            deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
            state: "Shutdown"
        )
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("HypeSimulatorLauncherOpenFailureTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: output) }

        let runner = RecordingSimulatorCommandRunner(failOpen: true)
        let launcher = HypeSimulatorRuntimeLauncher(commandRunner: runner)
        let result = try await launcher.launch(
            document: document,
            platform: .iPhone,
            device: device,
            outputDirectory: output
        )
        let commands = await runner.recordedCommands()

        #expect(result.manifest.platform == .iPhone)
        #expect(commands.contains { $0.executableURL.path == "/usr/bin/open" })
        #expect(commands.contains { $0.arguments.prefix(3) == ["simctl", "install", "PHONE-1"] })
        #expect(commands.contains { $0.arguments == ["simctl", "launch", "PHONE-1", "com.hype.runtime.launch-test.iphone"] })
    }

    @Test(
        "live simulator smoke builds, installs, and launches a generated runtime app",
        .enabled(if: ProcessInfo.processInfo.environment["HYPE_LIVE_SIMULATOR_SMOKE"] == "1")
    )
    func liveSimulatorSmoke() async throws {
        let launcher = HypeSimulatorRuntimeLauncher()
        let devices = try await launcher.availableDevices()
        let device = HypeSimulatorRuntimeLauncher.preferredDevice(from: devices, for: .iPhone)
            ?? HypeSimulatorRuntimeLauncher.preferredDevice(from: devices, for: .iPad)
            ?? HypeSimulatorRuntimeLauncher.preferredDevice(from: devices, for: .tvOS)
        let selectedDevice = try #require(device)

        var document = HypeDocument.newDocument(name: "Live Simulator Smoke")
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [selectedDevice.platform],
            primaryPlatform: selectedDevice.platform,
            selectionPromptAcknowledged: true,
            layoutPolicy: .scaleToFit
        )
        document.addPart(Part(partType: .button, cardId: document.cards[0].id, name: "Smoke Button"))

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("HypeLiveSimulatorSmoke-\(UUID().uuidString)", isDirectory: true)
        let keepPackage = ProcessInfo.processInfo.environment["HYPE_KEEP_RUNTIME_TEST_PACKAGES"] == "1"
        defer {
            if !keepPackage {
                try? FileManager.default.removeItem(at: output)
            }
        }

        let result = try await launcher.launch(
            document: document,
            platform: selectedDevice.platform,
            device: selectedDevice,
            outputDirectory: output
        )

        #expect(result.manifest.runtimeOnly)
        #expect(FileManager.default.fileExists(atPath: result.appBundleURL.path))
    }

    @Test(
        "live iPad clockAndCalendar smoke builds installs and launches a runtime app",
        .enabled(if: ProcessInfo.processInfo.environment["HYPE_LIVE_CALENDAR_SIMULATOR_SMOKE"] == "1")
    )
    func liveIPadClockAndCalendarSmoke() async throws {
        let launcher = HypeSimulatorRuntimeLauncher()
        let devices = try await launcher.availableDevices()
        let selectedDevice = try #require(HypeSimulatorRuntimeLauncher.preferredDevice(from: devices, for: .iPad))

        var document = HypeDocument.newDocument(name: "Clock Calendar Smoke")
        document.stack.width = 640
        document.stack.height = 420
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [.iPad],
            primaryPlatform: .iPad,
            selectionPromptAcknowledged: true,
            layoutPolicy: .fixed
        )

        var calendar = Part(
            partType: .calendar,
            cardId: document.cards[0].id,
            name: "Clock Calendar",
            left: 40,
            top: 40,
            width: 460,
            height: 260
        )
        calendar.calendarStyle = "clockAndCalendar"
        calendar.selectedDate = "2026-06-01"
        calendar.selectedTime = "14:45:00"
        calendar.displayMonth = "2026-06-01"
        document.addPart(calendar)

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("HypeCalendarRuntimeSmoke-\(UUID().uuidString)", isDirectory: true)
        let keepPackage = ProcessInfo.processInfo.environment["HYPE_KEEP_RUNTIME_TEST_PACKAGES"] == "1"
        defer {
            if !keepPackage {
                try? FileManager.default.removeItem(at: output)
            }
        }

        let result = try await launcher.launch(
            document: document,
            platform: .iPad,
            device: selectedDevice,
            outputDirectory: output
        )

        #expect(result.manifest.platform == .iPad)
        #expect(result.manifest.runtimeOnly)
        #expect(FileManager.default.fileExists(atPath: result.appBundleURL.path))
    }

    @Test(
        "live iOS runtime control smoke builds installs and launches GIF PDF layout controls",
        .enabled(if: ProcessInfo.processInfo.environment["HYPE_LIVE_IOS_CONTROL_SIMULATOR_SMOKE"] == "1")
    )
    func liveIOSRuntimeControlSmoke() async throws {
        let launcher = HypeSimulatorRuntimeLauncher()
        let devices = try await launcher.availableDevices()
        let selectedDevice = HypeSimulatorRuntimeLauncher.preferredDevice(from: devices, for: .iPhone)
            ?? HypeSimulatorRuntimeLauncher.preferredDevice(from: devices, for: .iPad)
        let device = try #require(selectedDevice)

        var document = HypeDocument.newDocument(name: "Runtime Control Smoke")
        document.stack.width = 800
        document.stack.height = 600
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [device.platform],
            primaryPlatform: device.platform,
            selectionPromptAcknowledged: true,
            supportedOrientations: [.portrait, .landscape],
            layoutPolicy: .scaleToFit
        )
        let cardId = try #require(document.cards.first?.id)

        var title = Part(partType: .field, cardId: cardId, name: "Title", left: 24, top: 18, width: 742, height: 44)
        title.textContent = "iOS runtime controls should scale, remain legible, animate GIFs, and scroll PDFs."
        document.addPart(title)

        var gif = Part(partType: .image, cardId: cardId, name: "Animated GIF", left: 24, top: 80, width: 180, height: 160)
        guard let smokeGIF = Self.makeSmokeGIF(frameCount: 3, width: 48, height: 48) else {
            Issue.record("Could not synthesize the simulator smoke animated GIF.")
            return
        }
        gif.imageData = smokeGIF
        gif.animated = true
        document.addPart(gif)

        var map = Part(partType: .map, cardId: cardId, name: "Map", left: 224, top: 80, width: 300, height: 220)
        map.mapCenterLat = 37.7749
        map.mapCenterLon = -122.4194
        map.mapSpan = 0.05
        map.mapType = "standard"
        map.mapAnnotationsJSON = #"[{"lat":37.7749,"lon":-122.4194,"title":"San Francisco"}]"#
        document.addPart(map)

        var pdf = Part(partType: .pdf, cardId: cardId, name: "Embedded PDF", left: 544, top: 80, width: 232, height: 360)
        let pdfAsset = Asset(
            name: "runtime-smoke.pdf",
            kind: .document,
            mimeType: "application/pdf",
            data: Self.makeSmokePDF(),
            width: 240,
            height: 360
        )
        document.assetRepository.assets.append(pdfAsset)
        pdf.pdfAssetRef = AssetRef(id: pdfAsset.id, name: pdfAsset.name, mimeType: pdfAsset.mimeType)
        pdf.pdfURL = StackAssetEmbedder.assetURLString(for: pdfAsset)
        pdf.pdfDisplayMode = "continuous"
        pdf.pdfAutoScales = true
        document.addPart(pdf)

        var piano = Part(partType: .pianoKeyboard, cardId: cardId, name: "Piano", left: 24, top: 330, width: 500, height: 140)
        piano.musicInstrumentName = "Electric Guitar Clean"
        piano.musicKeyCount = 49
        document.addPart(piano)

        var slider = Part(partType: .slider, cardId: cardId, name: "Value Slider", left: 24, top: 500, width: 500, height: 40)
        slider.controlValue = 0.5
        document.addPart(slider)

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("HypeRuntimeControlSmoke-\(UUID().uuidString)", isDirectory: true)
        let keepPackage = ProcessInfo.processInfo.environment["HYPE_KEEP_RUNTIME_TEST_PACKAGES"] == "1"
        defer {
            if !keepPackage {
                try? FileManager.default.removeItem(at: output)
            }
        }

        let result = try await launcher.launch(
            document: document,
            platform: device.platform,
            device: device,
            outputDirectory: output
        )

        #expect(result.manifest.platform == device.platform)
        #expect(result.manifest.runtimeOnly)
        #expect(FileManager.default.fileExists(atPath: result.appBundleURL.path))
    }

    @Test("iPad all runtime controls package with representative deployed styles")
    func iPadAllRuntimeControlsPackage() throws {
        let document = try Self.makeAllIOSRuntimeControlsDocument(name: "All iPad Runtime Controls")
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("HypeAllIOSRuntimeControlsPackage-\(UUID().uuidString)", isDirectory: true)
        let keepPackage = ProcessInfo.processInfo.environment["HYPE_KEEP_RUNTIME_TEST_PACKAGES"] == "1"
        defer {
            if !keepPackage {
                try? FileManager.default.removeItem(at: output)
            }
        }

        let result = try #require(TargetRuntimePackageBuilder().buildPackages(for: document, at: output).first)

        #expect(result.manifest.platform == .iPad)
        #expect(result.manifest.runtimeOnly)
        #expect(result.manifest.includesAuthoringUI == false)
        #expect(FileManager.default.fileExists(atPath: result.packageURL.path))
        #expect(result.manifest.supportedPartTypes.contains(PartType.appleMusicBrowser.rawValue))
        #expect(result.manifest.supportedPartTypes.contains(PartType.pianoKeyboard.rawValue))
        #expect(result.manifest.supportedPartTypes.contains(PartType.chart.rawValue))
        #expect(result.manifest.unsupportedPartTypes.contains(PartType.spriteArea.rawValue))
    }

    @Test(
        "live iPad all runtime controls smoke builds installs and launches representative deployed controls",
        .enabled(if: ProcessInfo.processInfo.environment["HYPE_LIVE_IOS_ALL_CONTROLS_SMOKE"] == "1")
    )
    func liveIPadAllRuntimeControlsSmoke() async throws {
        let launcher = HypeSimulatorRuntimeLauncher()
        let devices = try await launcher.availableDevices()
        let selectedDevice = try #require(HypeSimulatorRuntimeLauncher.preferredDevice(from: devices, for: .iPad))

        let document = try Self.makeAllIOSRuntimeControlsDocument(name: "All iPad Runtime Controls")
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("HypeAllIOSRuntimeControlsSmoke-\(UUID().uuidString)", isDirectory: true)
        let keepPackage = ProcessInfo.processInfo.environment["HYPE_KEEP_RUNTIME_TEST_PACKAGES"] == "1"
        defer {
            if !keepPackage {
                try? FileManager.default.removeItem(at: output)
            }
        }

        let result = try await launcher.launch(
            document: document,
            platform: .iPad,
            device: selectedDevice,
            outputDirectory: output
        )

        #expect(result.manifest.platform == .iPad)
        #expect(result.manifest.runtimeOnly)
        #expect(FileManager.default.fileExists(atPath: result.appBundleURL.path))
    }

    @Test(
        "live installed iPhone and iPad simulator matrix builds installs and launches generated runtime apps",
        .enabled(if: ProcessInfo.processInfo.environment["HYPE_LIVE_IOS_SIMULATOR_MATRIX"] == "1")
    )
    func liveInstalledIOSSimulatorMatrix() async throws {
        let launcher = HypeSimulatorRuntimeLauncher()
        let devices = try await launcher.availableDevices()
        let selectedDevices = devices
            .filter { $0.platform == .iPhone || $0.platform == .iPad }
            .filter { Self.currentShippingSimulatorNames.contains($0.name) }
        #expect(!selectedDevices.isEmpty)

        for device in selectedDevices {
            var document = HypeDocument.newDocument(name: "Simulator Matrix \(device.name)")
            document.stack.deploymentTargets = StackDeploymentTargets(
                selectedPlatforms: [device.platform],
                primaryPlatform: device.platform,
                selectionPromptAcknowledged: true,
                layoutPolicy: .scaleToFit
            )
            document.addPart(Part(partType: .button, cardId: document.cards[0].id, name: "Launch \(device.name)"))

            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent("HypeSimulatorMatrix-\(device.udid)-\(UUID().uuidString)", isDirectory: true)
            let keepPackage = ProcessInfo.processInfo.environment["HYPE_KEEP_RUNTIME_TEST_PACKAGES"] == "1"
            defer {
                if !keepPackage {
                    try? FileManager.default.removeItem(at: output)
                }
            }

            let result = try await launcher.launch(
                document: document,
                platform: device.platform,
                device: device,
                outputDirectory: output
            )
            #expect(result.manifest.platform == device.platform)
            #expect(result.manifest.runtimeOnly)
            #expect(FileManager.default.fileExists(atPath: result.appBundleURL.path))
        }
    }

    private static let currentShippingSimulatorNames: Set<String> = [
        "iPhone 17 Pro",
        "iPhone 17 Pro Max",
        "iPhone Air",
        "iPhone 17",
        "iPhone 17e",
        "iPhone 16",
        "iPhone 16 Plus",
        "iPad Pro 13-inch (M5)",
        "iPad Pro 11-inch (M5)",
        "iPad Air 13-inch (M4)",
        "iPad Air 11-inch (M4)",
        "iPad (A16)",
        "iPad mini (A17 Pro)",
    ]

    private static func makeSmokeGIF(frameCount: Int, width: Int, height: Int) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            "com.compuserve.gif" as CFString,
            frameCount,
            nil
        ) else { return nil }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        for index in 0..<frameCount {
            guard let image = makeSmokeImage(index: index, width: width, height: height) else { return nil }
            CGImageDestinationAddImage(destination, image, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.18],
            ] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private static func makeSmokeImage(index: Int, width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let colors: [CGColor] = [
            CGColor(red: 0.95, green: 0.25, blue: 0.18, alpha: 1),
            CGColor(red: 0.12, green: 0.55, blue: 0.95, alpha: 1),
            CGColor(red: 0.26, green: 0.78, blue: 0.34, alpha: 1),
        ]
        let imageWidth = CGFloat(width)
        let imageHeight = CGFloat(height)
        context.setFillColor(colors[index % colors.count])
        context.fill(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
        context.fillEllipse(in: CGRect(x: imageWidth / 4, y: imageHeight / 4, width: imageWidth / 2, height: imageHeight / 2))
        return context.makeImage()
    }

    private static func makeSmokePDF() -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else {
            return "%PDF-1.4\n".data(using: .utf8) ?? Data()
        }
        var mediaBox = CGRect(x: 0, y: 0, width: 240, height: 360)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return "%PDF-1.4\n".data(using: .utf8) ?? Data()
        }
        let pageColors: [CGColor] = [
            CGColor(red: 0.96, green: 0.98, blue: 1.0, alpha: 1),
            CGColor(red: 0.96, green: 1.0, blue: 0.95, alpha: 1),
            CGColor(red: 1.0, green: 0.96, blue: 0.94, alpha: 1),
        ]
        for (index, color) in pageColors.enumerated() {
            context.beginPDFPage(nil)
            context.setFillColor(color)
            context.fill(mediaBox)
            context.setFillColor(CGColor(red: 0.12, green: 0.16, blue: 0.22, alpha: 1))
            for row in 0..<8 {
                let y = 300 - CGFloat(row) * 28
                let width = CGFloat(60 + ((index + row) % 5) * 24)
                context.fill(CGRect(x: 28, y: y, width: width, height: 8))
            }
            context.setStrokeColor(CGColor(red: 0.2, green: 0.32, blue: 0.48, alpha: 1))
            context.setLineWidth(3)
            context.stroke(CGRect(x: 18, y: 18, width: 204, height: 324))
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    private static func makeAllIOSRuntimeControlsDocument(name: String) throws -> HypeDocument {
        var document = HypeDocument.newDocument(name: name)
        document.stack.width = 760
        document.stack.height = 1340
        document.stack.appleMusicAllowed = false
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [.iPad],
            primaryPlatform: .iPad,
            selectionPromptAcknowledged: true,
            supportedOrientations: [.portrait, .landscape],
            layoutPolicy: .scaleToFit
        )
        let cardId = try #require(document.cards.first?.id)
        let smokeGIF = try #require(Self.makeSmokeGIF(frameCount: 3, width: 64, height: 64))
        let pdfAsset = Asset(
            name: "all-controls-smoke.pdf",
            kind: .document,
            mimeType: "application/pdf",
            data: Self.makeSmokePDF(),
            width: 240,
            height: 360
        )
        document.assetRepository.assets.append(pdfAsset)

        let cellWidth = 238.0
        let cellHeight = 110.0
        func frame(_ index: Int, width: Double? = nil, height: Double? = nil) -> (left: Double, top: Double, width: Double, height: Double) {
            let column = index % 3
            let row = index / 3
            return (
                left: 18 + Double(column) * cellWidth,
                top: 18 + Double(row) * cellHeight,
                width: width ?? 216,
                height: height ?? 82
            )
        }
        func add(_ part: Part) {
            document.addPart(part)
        }

        var index = 0

        func nextPart(_ type: PartType, name: String, width: Double? = nil, height: Double? = nil) -> Part {
            let rect = frame(index, width: width, height: height)
            index += 1
            return Part(partType: type, cardId: cardId, name: name, left: rect.left, top: rect.top, width: rect.width, height: rect.height)
        }

        var button = nextPart(.button, name: "Push Button", height: 54)
        button.textContent = "Tap me"
        button.buttonStyle = .default
        add(button)

        var toggle = nextPart(.toggle, name: "Toggle", height: 54)
        toggle.buttonStyle = .toggle
        toggle.controlValue = 1
        add(toggle)

        var checkBox = nextPart(.button, name: "Check Box", height: 54)
        checkBox.buttonStyle = .checkBox
        checkBox.hilite = true
        add(checkBox)

        var radio = nextPart(.button, name: "Radio", height: 54)
        radio.buttonStyle = .radio
        add(radio)

        var popup = nextPart(.menu, name: "Popup", height: 54)
        popup.buttonStyle = .popup
        popup.popupItems = "Alpha\nBeta\nGamma"
        popup.textContent = "Alpha"
        add(popup)

        var link = nextPart(.link, name: "Link", height: 54)
        link.buttonStyle = .link
        link.url = "https://example.com"
        add(link)

        var field = nextPart(.field, name: "Text Field", height: 54)
        field.textContent = "Editable text"
        field.textSize = 15
        add(field)

        var search = nextPart(.searchField, name: "Search Field", height: 54)
        search.fieldStyle = .search
        search.searchPrompt = "Search"
        search.textContent = "query"
        add(search)

        var shape = nextPart(.shape, name: "Shape", height: 72)
        shape.shapeType = .roundRect
        shape.fillColor = "#E8F5FF"
        shape.strokeColor = "#1D4ED8"
        shape.strokeWidth = 2
        add(shape)

        var webpage = nextPart(.webpage, name: "Web Page", height: 72)
        webpage.url = ""
        add(webpage)

        var image = nextPart(.image, name: "Animated Image", height: 72)
        image.imageData = smokeGIF
        image.animated = true
        add(image)

        var video = nextPart(.video, name: "Video", height: 72)
        video.videoURL = ""
        add(video)

        var chart = nextPart(.chart, name: "Spider Chart", width: 454, height: 180)
        chart.chartData = ChartConfig(
            chartType: .spider,
            title: "Runtime Spider",
            series: [
                ChartSeries(name: "A", color: "#B6FF76", data: [
                    ChartDataPoint(name: "Speed", value: 72, minimumValue: 0, maximumValue: 100),
                    ChartDataPoint(name: "Power", value: 64, minimumValue: 0, maximumValue: 100),
                    ChartDataPoint(name: "Skill", value: 83, minimumValue: 0, maximumValue: 100),
                    ChartDataPoint(name: "Luck", value: 40, minimumValue: 0, maximumValue: 100),
                    ChartDataPoint(name: "Focus", value: 55, minimumValue: 0, maximumValue: 100),
                ]),
                ChartSeries(name: "B", color: "#FF6B85", data: [
                    ChartDataPoint(name: "Speed", value: 46, minimumValue: 0, maximumValue: 100),
                    ChartDataPoint(name: "Power", value: 70, minimumValue: 0, maximumValue: 100),
                    ChartDataPoint(name: "Skill", value: 52, minimumValue: 0, maximumValue: 100),
                    ChartDataPoint(name: "Luck", value: 88, minimumValue: 0, maximumValue: 100),
                    ChartDataPoint(name: "Focus", value: 66, minimumValue: 0, maximumValue: 100),
                ]),
            ],
            interactable: true,
            spiderRingCount: 5,
            spiderFillOpacity: 0.24,
            spiderShowValueLabels: true
        ).toJSON()
        add(chart)
        index = 14

        var calendar = nextPart(.calendar, name: "Clock Calendar", height: 180)
        calendar.calendarStyle = "clockAndCalendar"
        calendar.selectedDate = "2026-06-01"
        calendar.displayMonth = "2026-06-01"
        calendar.selectedTime = "14:45:00"
        add(calendar)
        index = 18

        var pdf = nextPart(.pdf, name: "PDF", height: 118)
        pdf.pdfAssetRef = AssetRef(id: pdfAsset.id, name: pdfAsset.name, mimeType: pdfAsset.mimeType)
        pdf.pdfURL = StackAssetEmbedder.assetURLString(for: pdfAsset)
        pdf.pdfDisplayMode = "continuous"
        pdf.pdfAutoScales = true
        add(pdf)

        var map = nextPart(.map, name: "Map", height: 118)
        map.mapCenterLat = 37.7749
        map.mapCenterLon = -122.4194
        map.mapSpan = 0.05
        map.mapAnnotationsJSON = #"[{"lat":37.7749,"lon":-122.4194,"title":"SF"}]"#
        add(map)

        var colorWell = nextPart(.colorWell, name: "Color", height: 62)
        colorWell.colorWellHex = "#2EC4B6"
        colorWell.colorWellInteractive = false
        add(colorWell)

        var stepper = nextPart(.stepper, name: "Stepper", height: 62)
        stepper.controlMin = 0
        stepper.controlMax = 10
        stepper.controlValue = 4
        stepper.controlStep = 1
        add(stepper)

        var slider = nextPart(.slider, name: "Slider", height: 62)
        slider.controlMin = 0
        slider.controlMax = 100
        slider.controlValue = 35
        slider.controlStep = 1
        add(slider)

        var verticalSlider = nextPart(.slider, name: "Vertical Slider", width: 96, height: 98)
        verticalSlider.controlMin = 0
        verticalSlider.controlMax = 100
        verticalSlider.controlValue = 65
        verticalSlider.controlStep = 1
        add(verticalSlider)

        var segmented = nextPart(.segmented, name: "Segmented", height: 62)
        segmented.segmentItems = "One|Two|Three"
        segmented.controlValue = 1
        add(segmented)

        var scene3D = nextPart(.scene3D, name: "3D Scene", height: 82)
        scene3D.scene3DURL = ""
        scene3D.scene3DBackground = "#111827"
        add(scene3D)

        var musicPlayer = nextPart(.musicPlayer, name: "Music Player", height: 82)
        musicPlayer.musicInstrumentName = "Electric Piano"
        musicPlayer.musicTempo = 120
        add(musicPlayer)

        var piano = nextPart(.pianoKeyboard, name: "Piano", height: 92)
        piano.musicInstrumentName = "Electric Guitar Clean"
        piano.musicKeyCount = 49
        add(piano)

        var sequencer = nextPart(.stepSequencer, name: "Step Sequencer", height: 92)
        sequencer.musicInstrumentName = "Analog Synth"
        sequencer.musicTempo = 120
        add(sequencer)

        var mixer = nextPart(.musicMixer, name: "Music Mixer", height: 92)
        mixer.musicInstrumentName = "Acoustic Grand Piano"
        add(mixer)

        var appleMusic = nextPart(.appleMusicBrowser, name: "MusicKit Search", height: 142)
        appleMusic.musicSearchTerm = "test"
        appleMusic.musicSourceType = AppleMusicItemKind.song.rawValue
        appleMusic.musicSearchScope = AppleMusicSearchScope.catalog.rawValue
        add(appleMusic)

        var progress = nextPart(.progressView, name: "Progress", height: 62)
        progress.progressLabel = "Progress"
        progress.progressValue = 42
        progress.progressTotal = 100
        progress.progressTint = "#2563EB"
        add(progress)

        var gauge = nextPart(.gauge, name: "Gauge", height: 82)
        gauge.gaugeLabel = "Gauge"
        gauge.gaugeMin = 0
        gauge.gaugeMax = 100
        gauge.gaugeValue = 68
        gauge.gaugeTint = "#F59E0B"
        add(gauge)

        var divider = nextPart(.divider, name: "Divider", height: 16)
        divider.dividerColor = "#6B7280"
        divider.dividerThickness = 2
        add(divider)

        return document
    }
}

private actor RecordingSimulatorCommandRunner: HypeSimulatorCommandRunning {
    private var commands: [HypeSimulatorCommand] = []
    private let failOpen: Bool

    init(failOpen: Bool = false) {
        self.failOpen = failOpen
    }

    func run(_ command: HypeSimulatorCommand) async throws -> HypeSimulatorCommandResult {
        commands.append(command)
        if command.executableURL.path == "/usr/bin/xcrun",
           command.arguments.first == "xcodebuild" {
            try createFakeBuildProduct(for: command)
        }
        if failOpen, command.executableURL.path == "/usr/bin/open" {
            return HypeSimulatorCommandResult(
                command: command,
                terminationStatus: 1,
                outputData: Data("Unable to find application named 'Simulator'".utf8)
            )
        }
        return HypeSimulatorCommandResult(
            command: command,
            terminationStatus: 0,
            outputData: Data()
        )
    }

    func recordedCommands() -> [HypeSimulatorCommand] {
        commands
    }

    private func createFakeBuildProduct(for command: HypeSimulatorCommand) throws {
        let arguments = command.arguments
        guard let scheme = value(after: "-scheme", in: arguments),
              let derivedDataPath = value(after: "-derivedDataPath", in: arguments),
              let sdk = value(after: "-sdk", in: arguments) else { return }
        let productDirectory = sdk == "appletvsimulator" ? "Debug-appletvsimulator" : "Debug-iphonesimulator"
        let appURL = URL(fileURLWithPath: derivedDataPath)
            .appendingPathComponent("Build", isDirectory: true)
            .appendingPathComponent("Products", isDirectory: true)
            .appendingPathComponent(productDirectory, isDirectory: true)
            .appendingPathComponent("\(scheme).app", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
    }

    private func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else { return nil }
        return arguments[valueIndex]
    }
}
