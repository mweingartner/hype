import Foundation
import Testing
@testable import HypeCore

@Suite("Target platform architecture")
struct TargetPlatformTests {
    @Test("new documents default to macOS and require target acknowledgement")
    func newDocumentDefaultsToMacOSButRequiresPrompt() {
        let document = HypeDocument.newDocument(name: "Targets")
        #expect(document.stack.deploymentTargets.selectedPlatforms == [.macOS])
        #expect(document.stack.deploymentTargets.primaryPlatform == .macOS)
        #expect(!document.stack.deploymentTargets.selectionPromptAcknowledged)
        #expect(document.stack.deploymentTargets.primaryProfile.id == "macos-default")
    }

    @Test("target platform parser accepts automation-friendly aliases")
    func targetPlatformParserAcceptsAutomationAliases() {
        #expect(HypeTargetPlatform.parse("macos") == .macOS)
        #expect(HypeTargetPlatform.parse("i-phone") == .iPhone)
        #expect(HypeTargetPlatform.parse("iPad") == .iPad)
        #expect(HypeTargetPlatform.parse("tv os") == .tvOS)
        #expect(HypeTargetPlatform.parseList("macOS,iPad,tvOS") == [.macOS, .iPad, .tvOS])
        #expect(HypeTargetPlatform.parseList("macOS,unknown") == nil)
    }

    @Test("decoded legacy stacks default to acknowledged macOS target")
    func decodedLegacyStackDefaultsToAcknowledgedMacOSTarget() throws {
        let encoded = try JSONEncoder().encode(Stack(name: "Legacy"))
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "deploymentTargets")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let stack = try JSONDecoder().decode(Stack.self, from: legacy)
        #expect(stack.deploymentTargets.selectedPlatforms == [.macOS])
        #expect(stack.deploymentTargets.selectionPromptAcknowledged)
    }

    @Test("part availability uses strict selected-target intersection")
    func partAvailabilityUsesStrictIntersection() {
        #expect(PartAvailabilityCatalog.supports(.button, across: [.macOS, .iPhone, .iPad, .tvOS]))
        #expect(!PartAvailabilityCatalog.supports(.spriteArea, across: [.macOS, .iPhone, .iPad, .tvOS]))
        #expect(!PartAvailabilityCatalog.supports(.spriteArea, across: [.iPhone]))
        #expect(!PartAvailabilityCatalog.supports(.field, across: [.macOS, .tvOS]))
        #expect(!PartAvailabilityCatalog.supports(.audioRecorder, across: [.iPhone, .tvOS]))
        #expect(PartAvailabilityCatalog.supports(.pdf, across: [.macOS, .iPhone, .iPad]))
        #expect(PartAvailabilityCatalog.unsupportedReasons(for: .spriteArea, across: [.iPhone]).first?.contains("SpriteKit runtime bridge") == true)
    }

    @Test("target availability does not overpromise standalone runtime adapters")
    func targetAvailabilityDoesNotOverpromiseRuntimeAdapters() {
        for partType in PartType.allCases {
            #expect(PartAvailabilityCatalog.support(for: partType, on: .iPhone).availability == TargetRuntimeAdapterCatalog.availability(for: partType, on: .iPhone))
            #expect(PartAvailabilityCatalog.support(for: partType, on: .iPad).availability == TargetRuntimeAdapterCatalog.availability(for: partType, on: .iPad))
            #expect(PartAvailabilityCatalog.support(for: partType, on: .tvOS).availability == TargetRuntimeAdapterCatalog.availability(for: partType, on: .tvOS))
        }
        #expect(TargetRuntimeAdapterCatalog.supportedPartTypes(on: .iPad).contains(.map))
        #expect(TargetRuntimeAdapterCatalog.supportedPartTypes(on: .iPad).contains(.pianoKeyboard))
        #expect(!TargetRuntimeAdapterCatalog.supportedPartTypes(on: .iPad).contains(.spriteArea))
        #expect(!TargetRuntimeAdapterCatalog.supportedPartTypes(on: .iPad).contains(.audioRecorder))
    }

    @Test("iPhone and iPad runtime style support covers advertised control variants")
    func iOSRuntimeStyleSupportCoversAdvertisedVariants() {
        #expect(TargetRuntimeCalendarStyle(rawOrAlias: "graphical") == .graphical)
        #expect(TargetRuntimeCalendarStyle(rawOrAlias: "textual").usesCompactPicker)
        #expect(TargetRuntimeCalendarStyle(rawOrAlias: "clockAndCalendar").persistsTime)
        #expect(TargetRuntimeCalendarStyle(rawOrAlias: "date_time").persistsTime)

        let buttonKinds = Set(ButtonStyle.pickerCases.map { TargetRuntimeButtonRenderKind(style: $0) })
        #expect(buttonKinds.contains(.filledRectangle))
        #expect(buttonKinds.contains(.prominentDefault))
        #expect(buttonKinds.contains(.shadow))
        #expect(buttonKinds.contains(.transparent))
        #expect(buttonKinds.contains(.oval))
        #expect(buttonKinds.contains(.toggle))
        #expect(buttonKinds.contains(.link))
        #expect(buttonKinds.contains(.checkBox))
        #expect(buttonKinds.contains(.popup))
        #expect(buttonKinds.contains(.radio))
    }

    @Test("target runtime adapter source has explicit style paths for iOS controls")
    func targetRuntimeAdapterSourceHasExplicitStylePaths() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/HypeCore/Export/TargetRuntimeControlViews.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("TargetRuntimeClockAndCalendarView(part: part"))
        #expect(source.contains("TargetRuntimeAnalogClockFace"))
        #expect(source.contains("monthGridDates(for: displayMonthDate)"))
        #expect(source.contains("TargetRuntimeButtonRenderKind(style: part.buttonStyle)"))
        #expect(source.contains("part.sliderControlOrientation == .vertical"))
        #expect(source.contains("!part.dontWrap && part.height > 64"))
        #expect(source.contains("targetRuntimePDFDisplayMode(part.pdfDisplayMode)"))
        #expect(source.contains("TargetRuntimeAnimatedImageView(data: data, isAnimating: part.animated)"))
        #expect(source.contains("GIFDecoder.decode(data)"))
        #expect(source.contains("animationImages = coordinator.animatedFrames"))
        #expect(source.contains("view.usePageViewController(false)"))
        #expect(source.contains("coordinator.currentPage != requestedPage"))
        #expect(source.contains("accessoryLinearCapacity"))
    }

    @Test("device profile catalog includes current shipping iPhone and iPad form factors")
    func deviceProfileCatalogIncludesCurrentShippingIOSFormFactors() {
        let ids = Set(HypeDeviceProfileCatalog.standardProfiles.map(\.id))
        let expectedIds: Set<String> = [
            "iphone-17-pro-portrait", "iphone-17-pro-landscape",
            "iphone-17-pro-max-portrait", "iphone-17-pro-max-landscape",
            "iphone-air-portrait", "iphone-air-landscape",
            "iphone-17-portrait", "iphone-17-landscape",
            "iphone-17e-portrait", "iphone-17e-landscape",
            "iphone-16-portrait", "iphone-16-landscape",
            "iphone-16-plus-portrait", "iphone-16-plus-landscape",
            "ipad-pro-13-m5-portrait", "ipad-pro-13-m5-landscape",
            "ipad-pro-11-m5-portrait", "ipad-pro-11-m5-landscape",
            "ipad-air-13-m4-portrait", "ipad-air-13-m4-landscape",
            "ipad-air-11-m4-portrait", "ipad-air-11-m4-landscape",
            "ipad-a16-portrait", "ipad-a16-landscape",
            "ipad-mini-a17-pro-portrait", "ipad-mini-a17-pro-landscape",
        ]

        #expect(expectedIds.isSubset(of: ids))
        let mobileProfiles = HypeDeviceProfileCatalog.standardProfiles.filter {
            $0.platform == .iPhone || $0.platform == .iPad
        }
        #expect(mobileProfiles.allSatisfy { $0.width > 0 && $0.height > 0 && $0.scale >= 2 })
        #expect(mobileProfiles.contains { $0.displayName == "iPhone 17 Pro Max Portrait" && $0.width == 440 && $0.height == 956 })
        #expect(mobileProfiles.contains { $0.displayName == "iPad Pro 13-inch (M5) Portrait" && $0.width == 1032 && $0.height == 1376 })
    }

    @Test("layout resolver projects constraints into target safe content area")
    func layoutResolverProjectsIntoSafeContentArea() throws {
        let cardId = UUID()
        let part = Part(partType: .button, cardId: cardId, left: 10, top: 20, width: 88, height: 24)
        let constraint = LayoutConstraint(
            sourcePartId: part.id,
            sourceEdge: .right,
            targetType: .canvas,
            targetEdge: .right,
            distance: -20
        )
        let profile = HypeDeviceProfileCatalog.defaultProfile(for: .tvOS)
        let resolution = LayoutResolver().resolve(parts: [part], constraints: [constraint], profile: profile)
        let geometry = try #require(resolution.geometries[part.id])

        #expect(resolution.safeContentLeft == 90)
        #expect(resolution.safeContentWidth == 1740)
        #expect(geometry.left == 90.0 + 1740.0 - 20.0 - 88.0)
    }

    @Test("layout resolver scales authored card into target safe area")
    func layoutResolverScalesAuthoredCardIntoTargetSafeArea() throws {
        let cardId = UUID()
        let part = Part(partType: .button, cardId: cardId, left: 400, top: 300, width: 100, height: 50)
        let profile = HypeDeviceProfileCatalog.defaultProfile(for: .iPhone)

        let resolution = LayoutResolver().resolve(
            parts: [part],
            constraints: [],
            profile: profile,
            sourceCanvasWidth: 800,
            sourceCanvasHeight: 600,
            policy: .scaleToFit
        )
        let geometry = try #require(resolution.geometries[part.id])

        #expect(resolution.layoutPolicy == .scaleToFit)
        #expect(abs(resolution.contentScaleX - 0.49125) < 0.001)
        #expect(abs(resolution.contentOffsetX) < 0.001)
        #expect(abs(resolution.contentOffsetY) < 0.001)
        #expect(abs(geometry.left - 196.5) < 0.1)
        #expect(abs(geometry.top - 206.375) < 0.1)
        #expect(abs(geometry.width - 49.125) < 0.1)
    }

    @Test("deployment targets decode missing layoutPolicy as fixed")
    func deploymentTargetsDecodeMissingLayoutPolicy() throws {
        let json = """
        {
          "selectedPlatforms": ["macOS", "iPhone"],
          "primaryPlatform": "macOS",
          "selectionPromptAcknowledged": true,
          "supportedOrientations": ["resizable", "portrait"]
        }
        """.data(using: .utf8)!

        let targets = try JSONDecoder().decode(StackDeploymentTargets.self, from: json)

        #expect(targets.layoutPolicy == .fixed)
        #expect(targets.selectedPlatforms == [.macOS, .iPhone])
    }

    @Test("deployment planner creates runtime-only platform plans")
    func deploymentPlannerCreatesRuntimeOnlyPlans() {
        var document = HypeDocument.newDocument(name: "Deployable")
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [.macOS, .iPhone, .iPad, .tvOS],
            primaryPlatform: .macOS,
            selectionPromptAcknowledged: true,
            layoutPolicy: .scaleToFit
        )
        document.stack.runtimeModeEnabled = false
        document.scriptGlobals["session"] = "temporary"

        let planner = StackDeploymentPlanner()
        let plans = planner.plans(for: document)
        #expect(plans.map(\.platform) == [.macOS, .iPhone, .iPad, .tvOS])
        #expect(plans.allSatisfy { $0.runtimeOnly })
        #expect(plans.allSatisfy { !$0.includesAuthoringUI })
        #expect(plans.first?.kind == .macOSStandalone)
        #expect(plans.first(where: { $0.platform == .iPad })?.runtimeAIProviderPolicy == .appleFoundationModels)
        #expect(plans.first(where: { $0.platform == .iPad })?.appIntents.map(\.kind).contains(.askStackAI) == true)
        #expect(plans.first(where: { $0.platform == .tvOS })?.runtimeAIProviderPolicy == .disabled)

        let runtimeDocument = planner.runtimeDocument(forDeployment: document)
        #expect(runtimeDocument.stack.runtimeModeEnabled)
        #expect(runtimeDocument.scriptGlobals.isEmpty)
        #expect(runtimeDocument.stack.deploymentTargets.layoutPolicy == .scaleToFit)
    }

    @Test("deployment validation reports unsupported existing parts per target")
    func deploymentValidationReportsUnsupportedExistingParts() throws {
        var document = HypeDocument.newDocument(name: "Validation")
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [.tvOS],
            primaryPlatform: .tvOS,
            selectionPromptAcknowledged: true
        )
        let field = Part(partType: .field, cardId: document.cards[0].id, name: "Search Term")
        document.addPart(field)

        let planner = StackDeploymentPlanner()
        let plan = try #require(planner.plans(for: document).first)
        let report = planner.validate(document: document, for: plan)

        #expect(!report.isDeployable)
        #expect(report.issues.count == 1)
        #expect(report.issues.first?.partId == field.id)
        #expect(report.issues.first?.partType == .field)
        #expect(report.issues.first?.platform == .tvOS)
        #expect(report.issues.first?.reason.contains("text-entry") == true)
    }

    @Test("runtime package builder rejects unsupported target parts")
    func runtimePackageBuilderRejectsUnsupportedTargetParts() throws {
        var document = HypeDocument.newDocument(name: "Unsupported Export")
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [.tvOS],
            primaryPlatform: .tvOS,
            selectionPromptAcknowledged: true
        )
        document.addPart(Part(partType: .field, cardId: document.cards[0].id, name: "Name Field"))

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("HypeUnsupportedRuntimePackageTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: output) }

        #expect(throws: TargetRuntimePackageBuilderError.self) {
            try TargetRuntimePackageBuilder().buildPackages(for: document, at: output)
        }
    }

    @Test("runtime package builder embeds self-contained stack and runtime-only shell metadata")
    func runtimePackageBuilderEmbedsSelfContainedStack() throws {
        var document = HypeDocument.newDocument(name: "Runtime Export")
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [.iPhone],
            primaryPlatform: .iPhone,
            selectionPromptAcknowledged: true,
            supportedOrientations: [.portrait, .landscape],
            layoutPolicy: .scaleToFit
        )
        document.stack.runtimeModeEnabled = false
        document.scriptGlobals["draft"] = "not persisted"
        let button = Part(partType: .button, cardId: document.cards[0].id, name: "Start")
        document.addPart(button)
        var map = Part(partType: .map, cardId: document.cards[0].id, name: "City Map", left: 20, top: 80, width: 320, height: 220)
        map.mapCenterLat = 37.7749
        map.mapCenterLon = -122.4194
        map.mapSpan = 0.05
        map.mapType = "standard"
        map.mapAnnotationsJSON = #"[{"lat":37.7749,"lon":-122.4194,"title":"San Francisco"}]"#
        document.addPart(map)
        var piano = Part(partType: .pianoKeyboard, cardId: document.cards[0].id, name: "Runtime Keys", left: 20, top: 320, width: 320, height: 150)
        piano.musicInstrumentName = "Electric Guitar Clean"
        piano.musicKeyCount = 49
        document.addPart(piano)

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("HypeRuntimePackageTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: output) }

        let result = try TargetRuntimePackageBuilder().buildPackages(for: document, at: output).first
        let package = try #require(result)
        let manifest = try TargetRuntimePackageBuilder().validatePackage(at: package.packageURL)
        let embeddedStackURL = package.packageURL
            .appendingPathComponent(TargetRuntimePackageBuilder.stackDirectoryName, isDirectory: true)
            .appendingPathComponent(TargetRuntimePackageBuilder.embeddedStackName, isDirectory: true)
        let runtimeDocument = try HypeSQLiteStackStore().load(fromPackageAt: embeddedStackURL)
        let shellSource = try String(
            contentsOf: package.packageURL
                .appendingPathComponent(TargetRuntimePackageBuilder.shellDirectoryName, isDirectory: true)
                .appendingPathComponent("Sources", isDirectory: true)
                .appendingPathComponent("HypeRuntimeApp.swift"),
            encoding: .utf8
        )
        let shellDir = package.packageURL
            .appendingPathComponent(TargetRuntimePackageBuilder.shellDirectoryName, isDirectory: true)
        let projectFile = try String(
            contentsOf: shellDir
                .appendingPathComponent("HypeRuntimeApp.xcodeproj", isDirectory: true)
                .appendingPathComponent("project.pbxproj"),
            encoding: .utf8
        )
        let runtimeCorePackage = try String(
            contentsOf: shellDir
                .appendingPathComponent("HypeSource", isDirectory: true)
                .appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let runtimeAdapterSource = try String(
            contentsOf: shellDir
                .appendingPathComponent("HypeSource", isDirectory: true)
                .appendingPathComponent("Sources", isDirectory: true)
                .appendingPathComponent("HypeCore", isDirectory: true)
                .appendingPathComponent("Export", isDirectory: true)
                .appendingPathComponent("TargetRuntimeControlViews.swift"),
            encoding: .utf8
        )
        let infoPlist = try String(
            contentsOf: shellDir.appendingPathComponent("Info.plist"),
            encoding: .utf8
        )
        let simulatorBuildScript = shellDir.appendingPathComponent("build-ios-simulator.sh")
        let deviceBuildScript = shellDir.appendingPathComponent("build-ios-device.sh")
        let deviceDeployScript = try String(
            contentsOf: shellDir.appendingPathComponent("deploy-ios-device.sh"),
            encoding: .utf8
        )

        #expect(manifest.platform == .iPhone)
        #expect(manifest.runtimeOnly)
        #expect(!manifest.includesAuthoringUI)
        #expect(manifest.layoutPolicy == .scaleToFit)
        #expect(manifest.runtimeAIProviderPolicy == .appleFoundationModels)
        #expect(manifest.appIntentKinds.contains(.askStackAI))
        #expect(manifest.embeddedStackPath == "Stack/Stack.hype")
        #expect(manifest.xcodeProjectPath == "RuntimeShell/HypeRuntimeApp.xcodeproj")
        #expect(manifest.simulatorBuildScriptPath == "RuntimeShell/build-ios-simulator.sh")
        #expect(manifest.deviceDeployScriptPath == "RuntimeShell/deploy-ios-device.sh")
        #expect(manifest.minimumOSVersion == "17.0")
        #expect(manifest.deviceFamilies == ["iPhone"])
        #expect(runtimeDocument.stack.runtimeModeEnabled)
        #expect(runtimeDocument.scriptGlobals.isEmpty)
        #expect(shellSource.contains("HypeSQLiteStackStore().load"))
        #expect(shellSource.contains("HypeRuntimeCardView"))
        #expect(shellSource.contains(".frame(maxWidth: .infinity, maxHeight: .infinity)"))
        #expect(shellSource.contains(".background(Color.white.ignoresSafeArea())"))
        #expect(shellSource.contains("GeometryReader { proxy in"))
        #expect(shellSource.contains("runtimeProfile(baseProfile: baseProfile, proxy: proxy)"))
        #expect(shellSource.contains("HypeSafeAreaInsets("))
        #expect(shellSource.contains("LayoutResolver().resolve"))
        #expect(shellSource.contains("profileId: \"iphone-portrait\""))
        #expect(shellSource.contains("StackRuntimeRegistry.shared.runtime"))
        #expect(shellSource.contains("StackRuntimeConfiguration(systemProvider: systemProvider)"))
        #expect(shellSource.contains("dispatchAndWait("))
        #expect(shellSource.contains("TargetRuntimePartView"))
        #expect(shellSource.contains("HypeRuntimeSystemProvider"))
        #expect(shellSource.contains("AVAudioPlayer"))
        #expect(!shellSource.contains(".frame(width: CGFloat(profile.width), height: CGFloat(profile.height))"))
        #expect(!shellSource.contains("struct HypeRuntimePartView"))
        #expect(runtimeAdapterSource.contains("TargetRuntimeMapView"))
        #expect(runtimeAdapterSource.contains("MKMapView"))
        #expect(runtimeAdapterSource.contains("TargetRuntimePianoKeyboardView"))
        #expect(runtimeAdapterSource.contains("MusicControlInteraction.keyboardLayout"))
        #expect(runtimeAdapterSource.contains("case .map:"))
        #expect(runtimeAdapterSource.contains("case .pianoKeyboard:"))
        #expect(runtimeAdapterSource.contains("TargetRuntimeAnimatedImageView(data: data, isAnimating: part.animated)"))
        #expect(runtimeAdapterSource.contains("view.usePageViewController(false)"))
        #expect(!shellSource.contains("PropertyInspector"))
        #expect(!shellSource.contains("ScriptEditor"))
        #expect(projectFile.contains("productType = \"com.apple.product-type.application\""))
        #expect(projectFile.contains("relativePath = HypeSource"))
        #expect(projectFile.contains("TARGETED_DEVICE_FAMILY = \"1\""))
        #expect(!projectFile.contains("/Users/"))
        #expect(runtimeCorePackage.contains("name: \"HypeRuntimeCore\""))
        #expect(runtimeCorePackage.contains(".library(name: \"HypeCore\""))
        #expect(FileManager.default.fileExists(atPath: shellDir.appendingPathComponent("HypeSource/Sources/HypeCore").path))
        #expect(infoPlist.contains("<key>UIDeviceFamily</key>"))
        #expect(infoPlist.contains("<integer>1</integer>"))
        #expect(infoPlist.contains("<key>UILaunchScreen</key>"))
        #expect(FileManager.default.isExecutableFile(atPath: simulatorBuildScript.path))
        #expect(FileManager.default.isExecutableFile(atPath: deviceBuildScript.path))
        #expect(deviceDeployScript.contains("devicectl device install app"))
    }

    @Test("runtime package builder emits iPad-specific app device family")
    func runtimePackageBuilderEmitsIPadDeviceFamily() throws {
        var document = HypeDocument.newDocument(name: "Tablet Runtime")
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [.iPad],
            primaryPlatform: .iPad,
            selectionPromptAcknowledged: true,
            layoutPolicy: .scaleToFit
        )
        document.addPart(Part(partType: .button, cardId: document.cards[0].id, name: "Start"))

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("HypeRuntimePackageiPadTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: output) }

        let package = try #require(TargetRuntimePackageBuilder().buildPackages(for: document, at: output).first)
        let shellDir = package.packageURL
            .appendingPathComponent(TargetRuntimePackageBuilder.shellDirectoryName, isDirectory: true)
        let projectFile = try String(
            contentsOf: shellDir
                .appendingPathComponent("HypeRuntimeApp.xcodeproj", isDirectory: true)
                .appendingPathComponent("project.pbxproj"),
            encoding: .utf8
        )
        let infoPlist = try String(
            contentsOf: shellDir.appendingPathComponent("Info.plist"),
            encoding: .utf8
        )

        #expect(package.manifest.platform == .iPad)
        #expect(package.manifest.profileId == "ipad-portrait")
        #expect(package.manifest.deviceFamilies == ["iPad"])
        #expect(projectFile.contains("TARGETED_DEVICE_FAMILY = \"2\""))
        #expect(infoPlist.contains("<integer>2</integer>"))
    }

    @Test("runtime package builder exports every advertised iPad runtime control")
    func runtimePackageBuilderExportsEveryAdvertisedIPadRuntimeControl() throws {
        let package = try buildAllAdvertisedRuntimeControlPackage(platform: .iPad, stackName: "All iPad Controls")

        #expect(package.manifest.platform == .iPad)
        #expect(package.manifest.unsupportedPartTypes.contains(PartType.spriteArea.rawValue))
        #expect(package.manifest.unsupportedPartTypes.contains(PartType.audioRecorder.rawValue))
        #expect(package.shellSource.contains("TargetRuntimePartView"))
        #expect(package.shellSource.contains("onPartChanged"))
        #expect(package.shellSource.contains("updatePart("))
        #expect(package.shellSource.contains("syncDocument(document)"))
    }

    @Test("runtime package builder exports every advertised iPhone runtime control")
    func runtimePackageBuilderExportsEveryAdvertisedIPhoneRuntimeControl() throws {
        let package = try buildAllAdvertisedRuntimeControlPackage(platform: .iPhone, stackName: "All iPhone Controls")

        #expect(package.manifest.platform == .iPhone)
        #expect(package.projectFile.contains("TARGETED_DEVICE_FAMILY = \"1\""))
        #expect(package.projectFile.contains("SDKROOT = iphoneos"))
        #expect(package.shellSource.contains("TargetRuntimePartView"))
    }

    @Test("runtime package builder exports every advertised tvOS runtime control")
    func runtimePackageBuilderExportsEveryAdvertisedTVOSRuntimeControl() throws {
        let package = try buildAllAdvertisedRuntimeControlPackage(platform: .tvOS, stackName: "All tvOS Controls")

        #expect(package.manifest.platform == .tvOS)
        #expect(package.manifest.deviceFamilies == ["Apple TV"])
        #expect(package.projectFile.contains("TARGETED_DEVICE_FAMILY = \"3\""))
        #expect(package.projectFile.contains("SDKROOT = appletvos"))
        #expect(package.projectFile.contains("SUPPORTED_PLATFORMS = \"appletvos appletvsimulator\""))
        #expect(package.simulatorBuildScript.contains("generic/platform=tvOS Simulator"))
        #expect(!package.manifest.supportedPartTypes.contains(PartType.field.rawValue))
        #expect(package.shellSource.contains("TargetRuntimePartView"))
    }

    private func buildAllAdvertisedRuntimeControlPackage(
        platform: HypeTargetPlatform,
        stackName: String
    ) throws -> (
        manifest: HypeRuntimePackageManifest,
        shellSource: String,
        projectFile: String,
        simulatorBuildScript: String
    ) {
        var document = HypeDocument.newDocument(name: stackName)
        document.stack.appleMusicAllowed = true
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [platform],
            primaryPlatform: platform,
            selectionPromptAcknowledged: true,
            layoutPolicy: .scaleToFit
        )
        let cardId = document.cards[0].id
        let supported = TargetRuntimeAdapterCatalog.supportedPartTypes(on: platform)
            .filter { $0 != .toggle && $0 != .link && $0 != .menu && $0 != .searchField }
            .sorted { $0.rawValue < $1.rawValue }

        for (index, type) in supported.enumerated() {
            var part = Part(
                partType: type,
                cardId: cardId,
                name: "\(type.rawValue) \(index)",
                left: Double(12 + (index % 3) * 180),
                top: Double(12 + (index / 3) * 80),
                width: 160,
                height: 56
            )
            part.url = "https://example.com"
            part.videoURL = ""
            part.pdfURL = ""
            part.chartData = ChartConfig(
                chartType: .bar,
                title: "Runtime Chart",
                series: [ChartSeries(name: "Series", data: [ChartDataPoint(name: "A", value: 1), ChartDataPoint(name: "B", value: 2)])]
            ).toJSON()
            part.musicPatternName = ""
            part.musicInstrumentName = "Acoustic Grand Piano"
            document.addPart(part)
        }

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("HypeAllControlsRuntimePackageTests-\(UUID().uuidString)", isDirectory: true)
        let keepPackage = ProcessInfo.processInfo.environment["HYPE_KEEP_RUNTIME_TEST_PACKAGES"] == "1"
        defer {
            if !keepPackage {
                try? FileManager.default.removeItem(at: output)
            }
        }

        let package = try #require(TargetRuntimePackageBuilder().buildPackages(for: document, at: output).first)
        let shellSource = try String(
            contentsOf: package.packageURL
                .appendingPathComponent(TargetRuntimePackageBuilder.shellDirectoryName, isDirectory: true)
                .appendingPathComponent("Sources", isDirectory: true)
                .appendingPathComponent("HypeRuntimeApp.swift"),
            encoding: .utf8
        )
        let shellDir = package.packageURL
            .appendingPathComponent(TargetRuntimePackageBuilder.shellDirectoryName, isDirectory: true)
        let projectFile = try String(
            contentsOf: shellDir
                .appendingPathComponent("HypeRuntimeApp.xcodeproj", isDirectory: true)
                .appendingPathComponent("project.pbxproj"),
            encoding: .utf8
        )
        let simulatorBuildScript = try String(
            contentsOf: shellDir.appendingPathComponent("build-ios-simulator.sh"),
            encoding: .utf8
        )

        #expect(Set(supported.map(\.rawValue)).isSubset(of: Set(package.manifest.supportedPartTypes)))
        #expect(package.manifest.unsupportedPartTypes.contains(PartType.spriteArea.rawValue))
        #expect(package.manifest.unsupportedPartTypes.contains(PartType.audioRecorder.rawValue))
        return (package.manifest, shellSource, projectFile, simulatorBuildScript)
    }

    @Test("AI tools expose target profile and availability queries")
    func aiToolsExposeTargetQueries() async {
        let toolNames = Set(HypeToolDefinitions.cardControlAuthoringTools.map(\.function.name))
        #expect(toolNames.contains("list_target_profiles"))
        #expect(toolNames.contains("get_part_target_availability"))
        #expect(toolNames.contains("get_hig_layout_guide"))
        #expect(toolNames.contains("validate_hig_layout"))
        #expect(toolNames.contains("apply_hig_layout"))
        #expect(toolNames.contains("pin_part_to_safe_area"))
        #expect(toolNames.contains("add_part_layout_constraint"))
        #expect(toolNames.contains("list_part_layout_constraints"))

        var document = HypeDocument.newDocument(name: "AI Targets")
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [.macOS, .tvOS],
            primaryPlatform: .macOS,
            selectionPromptAcknowledged: true
        )
        let cardId = document.cards[0].id
        let executor = HypeToolExecutor()

        let profiles = await executor.execute(
            toolName: "list_target_profiles",
            arguments: [:],
            document: &document,
            currentCardId: cardId
        )
        #expect(profiles.contains("Selected targets: macOS, tvOS"))
        #expect(profiles.contains("tvos-1080p"))

        let availability = await executor.execute(
            toolName: "get_part_target_availability",
            arguments: ["part_type": "field"],
            document: &document,
            currentCardId: cardId
        )
        #expect(availability.contains("field: not available"))
        #expect(availability.contains("tvOS: unsupported"))

        let layoutPreview = await executor.execute(
            toolName: "preview_layout_profile",
            arguments: ["profile_id": "tvos-1080p"],
            document: &document,
            currentCardId: cardId
        )
        #expect(layoutPreview.contains("Layout preview for tvOS 1080p"))
        #expect(layoutPreview.contains("policy=fixed"))

        let deploymentPlan = await executor.execute(
            toolName: "plan_stack_deployment",
            arguments: [:],
            document: &document,
            currentCardId: cardId
        )
        #expect(deploymentPlan.contains("macOS: kind=macOSStandalone"))
        #expect(deploymentPlan.contains("tvOS: kind=tvOSRuntimeShell"))
        #expect(deploymentPlan.contains("deployable=true"))

        document.addPart(Part(partType: .field, cardId: cardId, name: "TV Search"))
        let blockedDeploymentPlan = await executor.execute(
            toolName: "plan_stack_deployment",
            arguments: [:],
            document: &document,
            currentCardId: cardId
        )
        #expect(blockedDeploymentPlan.contains("deployable=false"))
        #expect(blockedDeploymentPlan.contains("unsupportedParts=[field \"TV Search\"]"))

        _ = await executor.execute(
            toolName: "set_stack_property",
            arguments: ["property": "targetPlatforms", "value": "macOS,iPhone,iPad"],
            document: &document,
            currentCardId: cardId
        )
        let targetPlatforms = await executor.execute(
            toolName: "get_stack_property",
            arguments: ["property": "targetPlatforms"],
            document: &document,
            currentCardId: cardId
        )
        #expect(targetPlatforms == "macOS,iPhone,iPad")

        _ = await executor.execute(
            toolName: "set_stack_property",
            arguments: ["property": "layoutPolicy", "value": "scaleToFit"],
            document: &document,
            currentCardId: cardId
        )
        let layoutPolicy = await executor.execute(
            toolName: "get_stack_property",
            arguments: ["property": "layoutPolicy"],
            document: &document,
            currentCardId: cardId
        )
        #expect(layoutPolicy == "scaleToFit")

        _ = await executor.execute(
            toolName: "set_stack_property",
            arguments: ["property": "runtimeAIProviderPolicy", "value": "appleFoundationModels"],
            document: &document,
            currentCardId: cardId
        )
        let runtimePolicy = await executor.execute(
            toolName: "get_stack_property",
            arguments: ["property": "runtimeAIProviderPolicy"],
            document: &document,
            currentCardId: cardId
        )
        #expect(runtimePolicy == "appleFoundationModels")
    }

    @Test("HIG layout metrics encode platform minimums and source attribution")
    func higLayoutMetricsEncodePlatformRules() {
        let phone = HIGLayoutCatalog.metrics(for: HypeDeviceProfileCatalog.defaultProfile(for: .iPhone))
        let tv = HIGLayoutCatalog.metrics(for: HypeDeviceProfileCatalog.defaultProfile(for: .tvOS))
        let guide = HIGLayoutCatalog.guide(profile: HypeDeviceProfileCatalog.defaultProfile(for: .iPhone))

        #expect(phone.minimumHitWidth == 44)
        #expect(phone.minimumHitHeight == 44)
        #expect(tv.minimumHitWidth == 66)
        #expect(tv.prefersFocusSafeSpacing)
        #expect(guide.contains("safeArea"))
        #expect(guide.contains("developer.apple.com/design/human-interface-guidelines/layout"))
    }

    @Test("HIG layout validation reports unsafe small controls")
    func higLayoutValidationReportsSmallUnsafeControls() async {
        var document = HypeDocument.newDocument(name: "Unsafe")
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [.iPhone],
            primaryPlatform: .iPhone,
            selectionPromptAcknowledged: true,
            layoutPolicy: .fixed
        )
        document.addPart(Part(partType: .button, cardId: document.cards[0].id, name: "Tiny", left: -10, top: 4, width: 20, height: 20))
        let executor = HypeToolExecutor()

        let report = await executor.execute(
            toolName: "validate_hig_layout",
            arguments: ["profile_ids": "iphone-portrait"],
            document: &document,
            currentCardId: document.cards[0].id
        )

        #expect(report.hasPrefix("FAIL:"))
        #expect(report.contains("outside safe content"))
        #expect(report.contains("interactive hit area"))
    }

    @Test("AI HIG layout tools arrange, constrain, and validate multi-target controls")
    func aiHIGLayoutToolsArrangeConstrainAndValidate() async throws {
        var document = HypeDocument.newDocument(name: "Responsive")
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [.macOS, .iPhone, .iPad],
            primaryPlatform: .macOS,
            selectionPromptAcknowledged: true,
            layoutPolicy: .fixed
        )
        let cardId = document.cards[0].id
        var name = Part(partType: .field, cardId: cardId, name: "Name", left: 5, top: 5, width: 80, height: 18)
        name.textSize = 12
        let submit = Part(partType: .button, cardId: cardId, name: "Submit", left: 100, top: 5, width: 80, height: 20)
        document.addPart(name)
        document.addPart(submit)
        let executor = HypeToolExecutor()

        let guide = await executor.execute(
            toolName: "get_hig_layout_guide",
            arguments: ["profile_id": "iphone-portrait"],
            document: &document,
            currentCardId: cardId
        )
        #expect(guide.contains("Minimum interactive hit target"))

        let applied = await executor.execute(
            toolName: "apply_hig_layout",
            arguments: [
                "layout_type": "vertical_stack",
                "part_names": "Name, Submit",
                "profile_id": "iphone-portrait",
                "fill_width": "true",
            ],
            document: &document,
            currentCardId: cardId
        )

        #expect(applied.contains("Applied HIG vertical_stack layout"))
        #expect(document.stack.deploymentTargets.layoutPolicy == .scaleToFit)
        let namePart = try #require(document.parts.first { $0.name == "Name" })
        let submitPart = try #require(document.parts.first { $0.name == "Submit" })
        #expect(namePart.height > 44)
        #expect(submitPart.height > 44)
        #expect(namePart.textSize >= 17)
        #expect(document.constraints.count >= 6)

        let constraints = await executor.execute(
            toolName: "list_part_layout_constraints",
            arguments: ["part_names": "Name, Submit"],
            document: &document,
            currentCardId: cardId
        )
        #expect(constraints.contains("Name.left"))
        #expect(constraints.contains("Submit.top"))

        let pin = await executor.execute(
            toolName: "pin_part_to_safe_area",
            arguments: ["part_name": "Submit", "edges": "bottom", "margin": "20"],
            document: &document,
            currentCardId: cardId
        )
        #expect(pin.contains("Pinned part \"Submit\""))

        let report = await executor.execute(
            toolName: "validate_hig_layout",
            arguments: [:],
            document: &document,
            currentCardId: cardId
        )
        #expect(report.hasPrefix("OK:") || report.hasPrefix("WARN:"))
        #expect(!report.contains("interactive hit area"))
        #expect(!report.contains("outside safe content"))
    }
}
