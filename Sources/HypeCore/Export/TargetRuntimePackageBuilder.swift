import Foundation

public struct HypeRuntimePackageManifest: Codable, Sendable, Equatable {
    public var format: String
    public var formatVersion: Int
    public var stackId: UUID
    public var stackName: String
    public var platform: HypeTargetPlatform
    public var deploymentKind: HypeDeploymentKind
    public var profileId: String
    public var profileName: String
    public var profileWidth: Int
    public var profileHeight: Int
    public var inputModel: HypeInputModel
    public var layoutPolicy: TargetLayoutPolicy
    public var runtimeOnly: Bool
    public var includesAuthoringUI: Bool
    public var embeddedStackPath: String
    public var runtimeAIProviderPolicy: RuntimeAIProviderPolicy
    public var appIntentKinds: [DeploymentAppIntentKind]
    public var supportedPartTypes: [String]
    public var unsupportedPartTypes: [String]
    public var requiredEntitlements: [String]
    public var bundleIdentifier: String
    public var appTargetName: String?
    public var xcodeProjectPath: String?
    public var simulatorBuildScriptPath: String?
    public var deviceBuildScriptPath: String?
    public var deviceDeployScriptPath: String?
    public var deploymentPreflightScriptPath: String?
    public var archiveScriptPath: String?
    public var exportArchiveScriptPath: String?
    public var testFlightUploadScriptPath: String?
    public var deploymentDiagnosticsPath: String?
    public var privacyManifestPath: String?
    public var minimumOSVersion: String?
    public var deviceFamilies: [String]?
    public var generatedAt: Date

    public init(
        format: String = "hype-runtime-package",
        formatVersion: Int = 1,
        stackId: UUID,
        stackName: String,
        platform: HypeTargetPlatform,
        deploymentKind: HypeDeploymentKind,
        profileId: String,
        profileName: String,
        profileWidth: Int,
        profileHeight: Int,
        inputModel: HypeInputModel,
        layoutPolicy: TargetLayoutPolicy,
        runtimeOnly: Bool,
        includesAuthoringUI: Bool,
        embeddedStackPath: String,
        runtimeAIProviderPolicy: RuntimeAIProviderPolicy,
        appIntentKinds: [DeploymentAppIntentKind],
        supportedPartTypes: [String],
        unsupportedPartTypes: [String],
        requiredEntitlements: [String],
        bundleIdentifier: String,
        appTargetName: String? = nil,
        xcodeProjectPath: String? = nil,
        simulatorBuildScriptPath: String? = nil,
        deviceBuildScriptPath: String? = nil,
        deviceDeployScriptPath: String? = nil,
        deploymentPreflightScriptPath: String? = nil,
        archiveScriptPath: String? = nil,
        exportArchiveScriptPath: String? = nil,
        testFlightUploadScriptPath: String? = nil,
        deploymentDiagnosticsPath: String? = nil,
        privacyManifestPath: String? = nil,
        minimumOSVersion: String? = nil,
        deviceFamilies: [String]? = nil,
        generatedAt: Date = Date()
    ) {
        self.format = format
        self.formatVersion = formatVersion
        self.stackId = stackId
        self.stackName = stackName
        self.platform = platform
        self.deploymentKind = deploymentKind
        self.profileId = profileId
        self.profileName = profileName
        self.profileWidth = profileWidth
        self.profileHeight = profileHeight
        self.inputModel = inputModel
        self.layoutPolicy = layoutPolicy
        self.runtimeOnly = runtimeOnly
        self.includesAuthoringUI = includesAuthoringUI
        self.embeddedStackPath = embeddedStackPath
        self.runtimeAIProviderPolicy = runtimeAIProviderPolicy
        self.appIntentKinds = appIntentKinds
        self.supportedPartTypes = supportedPartTypes
        self.unsupportedPartTypes = unsupportedPartTypes
        self.requiredEntitlements = requiredEntitlements
        self.bundleIdentifier = bundleIdentifier
        self.appTargetName = appTargetName
        self.xcodeProjectPath = xcodeProjectPath
        self.simulatorBuildScriptPath = simulatorBuildScriptPath
        self.deviceBuildScriptPath = deviceBuildScriptPath
        self.deviceDeployScriptPath = deviceDeployScriptPath
        self.deploymentPreflightScriptPath = deploymentPreflightScriptPath
        self.archiveScriptPath = archiveScriptPath
        self.exportArchiveScriptPath = exportArchiveScriptPath
        self.testFlightUploadScriptPath = testFlightUploadScriptPath
        self.deploymentDiagnosticsPath = deploymentDiagnosticsPath
        self.privacyManifestPath = privacyManifestPath
        self.minimumOSVersion = minimumOSVersion
        self.deviceFamilies = deviceFamilies
        self.generatedAt = generatedAt
    }
}

public struct HypeRuntimeDeploymentDiagnostics: Codable, Sendable, Equatable {
    public var format: String
    public var formatVersion: Int
    public var generatedAt: Date
    public var stackId: UUID
    public var stackName: String
    public var platform: HypeTargetPlatform
    public var profileId: String
    public var profileName: String
    public var bundleIdentifier: String
    public var runtimeOnly: Bool
    public var includesAuthoringUI: Bool
    public var totalPartCount: Int
    public var partCountsByType: [String: Int]
    public var assetCount: Int
    public var assetByteCount: Int
    public var requiredEntitlements: [String]
    public var supportedPartTypes: [String]
    public var unsupportedPartTypes: [String]
    public var distributionScripts: [String]

    public init(
        format: String = "hype-runtime-deployment-diagnostics",
        formatVersion: Int = 1,
        generatedAt: Date = Date(),
        stackId: UUID,
        stackName: String,
        platform: HypeTargetPlatform,
        profileId: String,
        profileName: String,
        bundleIdentifier: String,
        runtimeOnly: Bool,
        includesAuthoringUI: Bool,
        totalPartCount: Int,
        partCountsByType: [String: Int],
        assetCount: Int,
        assetByteCount: Int,
        requiredEntitlements: [String],
        supportedPartTypes: [String],
        unsupportedPartTypes: [String],
        distributionScripts: [String]
    ) {
        self.format = format
        self.formatVersion = formatVersion
        self.generatedAt = generatedAt
        self.stackId = stackId
        self.stackName = stackName
        self.platform = platform
        self.profileId = profileId
        self.profileName = profileName
        self.bundleIdentifier = bundleIdentifier
        self.runtimeOnly = runtimeOnly
        self.includesAuthoringUI = includesAuthoringUI
        self.totalPartCount = totalPartCount
        self.partCountsByType = partCountsByType
        self.assetCount = assetCount
        self.assetByteCount = assetByteCount
        self.requiredEntitlements = requiredEntitlements
        self.supportedPartTypes = supportedPartTypes
        self.unsupportedPartTypes = unsupportedPartTypes
        self.distributionScripts = distributionScripts
    }
}

public struct HypeRuntimePackageResult: Sendable, Equatable {
    public var packageURL: URL
    public var manifest: HypeRuntimePackageManifest
    public var generatedFiles: [String]

    public init(packageURL: URL, manifest: HypeRuntimePackageManifest, generatedFiles: [String]) {
        self.packageURL = packageURL
        self.manifest = manifest
        self.generatedFiles = generatedFiles
    }
}

public enum TargetRuntimePackageBuilderError: Error, LocalizedError, Equatable {
    case invalidPackageName
    case packageValidationFailed(String)
    case runtimeSourceUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPackageName:
            return "The stack name cannot be converted to a safe runtime package name."
        case .packageValidationFailed(let message):
            return message
        case .runtimeSourceUnavailable(let message):
            return message
        }
    }
}

public struct TargetRuntimePackageBuilder {
    public static let manifestFileName = "RuntimeManifest.json"
    public static let stackDirectoryName = "Stack"
    public static let embeddedStackName = "Stack.hype"
    public static let shellDirectoryName = "RuntimeShell"

    private let planner: StackDeploymentPlanner
    private let stackStore: HypeSQLiteStackStore

    public init(planner: StackDeploymentPlanner = StackDeploymentPlanner(), stackStore: HypeSQLiteStackStore = HypeSQLiteStackStore()) {
        self.planner = planner
        self.stackStore = stackStore
    }

    public func buildPackages(for document: HypeDocument, at outputDirectory: URL) throws -> [HypeRuntimePackageResult] {
        try planner.plans(for: document).map { plan in
            try buildPackage(for: document, plan: plan, at: outputDirectory)
        }
    }

    public func buildPackage(
        for document: HypeDocument,
        plan: HypeDeploymentPlan,
        at outputDirectory: URL
    ) throws -> HypeRuntimePackageResult {
        var runtimeDocument = planner.runtimeDocument(forDeployment: document)
        _ = try StackAssetEmbedder.embedReferencedAssets(in: &runtimeDocument)
        let selfContainmentIssues = StackAssetEmbedder.selfContainmentIssues(in: runtimeDocument)
        guard selfContainmentIssues.isEmpty else {
            throw TargetRuntimePackageBuilderError.packageValidationFailed(
                selfContainedValidationMessage(selfContainmentIssues)
            )
        }

        let validation = planner.validate(document: runtimeDocument, for: plan)
        guard validation.isDeployable else {
            throw TargetRuntimePackageBuilderError.packageValidationFailed(
                deploymentValidationMessage(validation)
            )
        }

        let packageName = try runtimePackageName(stackName: runtimeDocument.stack.name, platform: plan.platform)
        let finalURL = outputDirectory.appendingPathComponent(packageName, isDirectory: true)
        let tempURL = outputDirectory.appendingPathComponent(".\(packageName)-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: tempURL, withIntermediateDirectories: true)

        do {
            let manifest = makeManifest(for: runtimeDocument, plan: plan)
            var generatedFiles: [String] = []

            let stackDir = tempURL.appendingPathComponent(Self.stackDirectoryName, isDirectory: true)
            try fm.createDirectory(at: stackDir, withIntermediateDirectories: true)
            let embeddedStackURL = stackDir.appendingPathComponent(Self.embeddedStackName, isDirectory: true)
            try stackStore.save(runtimeDocument, toPackageAt: embeddedStackURL)
            generatedFiles.append("\(Self.stackDirectoryName)/\(Self.embeddedStackName)/\(HypeSQLiteStackStore.manifestFileName)")
            generatedFiles.append("\(Self.stackDirectoryName)/\(Self.embeddedStackName)/\(HypeSQLiteStackStore.sqliteFileName)")

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(to: tempURL.appendingPathComponent(Self.manifestFileName), options: [.atomic])
            generatedFiles.append(Self.manifestFileName)

            let shellDir = tempURL.appendingPathComponent(Self.shellDirectoryName, isDirectory: true)
            try fm.createDirectory(at: shellDir, withIntermediateDirectories: true)
            try writeShellFiles(for: runtimeDocument, plan: plan, manifest: manifest, shellDir: shellDir, generatedFiles: &generatedFiles)

            try validatePackage(at: tempURL, manifest: manifest)
            try replaceItem(at: finalURL, with: tempURL)
            return HypeRuntimePackageResult(packageURL: finalURL, manifest: manifest, generatedFiles: generatedFiles.sorted())
        } catch {
            try? fm.removeItem(at: tempURL)
            throw error
        }
    }

    public func validatePackage(at packageURL: URL) throws -> HypeRuntimePackageManifest {
        let manifestURL = packageURL.appendingPathComponent(Self.manifestFileName)
        let stackURL = packageURL
            .appendingPathComponent(Self.stackDirectoryName, isDirectory: true)
            .appendingPathComponent(Self.embeddedStackName, isDirectory: true)
        let manifest = try JSONDecoder().decode(HypeRuntimePackageManifest.self, from: Data(contentsOf: manifestURL))
        try validatePackage(at: packageURL, manifest: manifest)
        _ = try stackStore.validate(packageURL: stackURL)
        return manifest
    }

    private func makeManifest(for document: HypeDocument, plan: HypeDeploymentPlan) -> HypeRuntimePackageManifest {
        let supported = PartType.allCases
            .filter { PartAvailabilityCatalog.support(for: $0, on: plan.platform).availability.isUsable }
            .map(\.rawValue)
            .sorted()
        let unsupported = PartType.allCases
            .filter { !PartAvailabilityCatalog.support(for: $0, on: plan.platform).availability.isUsable }
            .map(\.rawValue)
            .sorted()
        return HypeRuntimePackageManifest(
            stackId: document.stack.id,
            stackName: document.stack.name,
            platform: plan.platform,
            deploymentKind: plan.kind,
            profileId: plan.profile.id,
            profileName: plan.profile.displayName,
            profileWidth: plan.profile.width,
            profileHeight: plan.profile.height,
            inputModel: plan.profile.inputModel,
            layoutPolicy: document.stack.deploymentTargets.layoutPolicy,
            runtimeOnly: plan.runtimeOnly,
            includesAuthoringUI: plan.includesAuthoringUI,
            embeddedStackPath: "\(Self.stackDirectoryName)/\(Self.embeddedStackName)",
            runtimeAIProviderPolicy: plan.runtimeAIProviderPolicy,
            appIntentKinds: plan.appIntents.map(\.kind),
            supportedPartTypes: supported,
            unsupportedPartTypes: unsupported,
            requiredEntitlements: requiredEntitlements(for: document, plan: plan),
            bundleIdentifier: bundleIdentifier(stackName: document.stack.name, platform: plan.platform),
            appTargetName: appTargetName(stackName: document.stack.name, platform: plan.platform),
            xcodeProjectPath: isGeneratedAppleRuntimePlatform(plan.platform) ? "\(Self.shellDirectoryName)/HypeRuntimeApp.xcodeproj" : nil,
            simulatorBuildScriptPath: isGeneratedAppleRuntimePlatform(plan.platform) ? "\(Self.shellDirectoryName)/build-ios-simulator.sh" : nil,
            deviceBuildScriptPath: isGeneratedAppleRuntimePlatform(plan.platform) ? "\(Self.shellDirectoryName)/build-ios-device.sh" : nil,
            deviceDeployScriptPath: isGeneratedAppleRuntimePlatform(plan.platform) ? "\(Self.shellDirectoryName)/deploy-ios-device.sh" : nil,
            deploymentPreflightScriptPath: isGeneratedAppleRuntimePlatform(plan.platform) ? "\(Self.shellDirectoryName)/preflight-ios-deployment.sh" : nil,
            archiveScriptPath: isIOSRuntimePlatform(plan.platform) ? "\(Self.shellDirectoryName)/archive-ios.sh" : nil,
            exportArchiveScriptPath: isIOSRuntimePlatform(plan.platform) ? "\(Self.shellDirectoryName)/export-ios-archive.sh" : nil,
            testFlightUploadScriptPath: isIOSRuntimePlatform(plan.platform) ? "\(Self.shellDirectoryName)/upload-testflight.sh" : nil,
            deploymentDiagnosticsPath: "\(Self.shellDirectoryName)/DeploymentDiagnostics.json",
            privacyManifestPath: isGeneratedAppleRuntimePlatform(plan.platform) ? "\(Self.shellDirectoryName)/PrivacyInfo.xcprivacy" : nil,
            minimumOSVersion: isGeneratedAppleRuntimePlatform(plan.platform) ? "17.0" : nil,
            deviceFamilies: deviceFamilies(for: plan.platform)
        )
    }

    private func writeShellFiles(
        for document: HypeDocument,
        plan: HypeDeploymentPlan,
        manifest: HypeRuntimePackageManifest,
        shellDir: URL,
        generatedFiles: inout [String]
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let infoPlist = infoPlist(for: manifest)
        try infoPlist.write(to: shellDir.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        generatedFiles.append("\(Self.shellDirectoryName)/Info.plist")

        let entitlements = entitlementsPlist(for: codeSigningEntitlementKeys(for: manifest))
        try entitlements.write(to: shellDir.appendingPathComponent("Entitlements.plist"), atomically: true, encoding: .utf8)
        generatedFiles.append("\(Self.shellDirectoryName)/Entitlements.plist")

        try encoder.encode(plan.appIntents).write(to: shellDir.appendingPathComponent("AppIntents.json"), options: [.atomic])
        generatedFiles.append("\(Self.shellDirectoryName)/AppIntents.json")

        let source = runtimeShellSource(for: document, manifest: manifest)
        let sourcesDir = shellDir.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        try source.write(to: sourcesDir.appendingPathComponent("HypeRuntimeApp.swift"), atomically: true, encoding: .utf8)
        generatedFiles.append("\(Self.shellDirectoryName)/Sources/HypeRuntimeApp.swift")

        let readme = runtimeReadme(for: manifest)
        try readme.write(to: shellDir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        generatedFiles.append("\(Self.shellDirectoryName)/README.md")

        let diagnostics = deploymentDiagnostics(for: document, manifest: manifest)
        try encoder.encode(diagnostics).write(to: shellDir.appendingPathComponent("DeploymentDiagnostics.json"), options: [.atomic])
        generatedFiles.append("\(Self.shellDirectoryName)/DeploymentDiagnostics.json")

        if isGeneratedAppleRuntimePlatform(plan.platform) {
            try writeIOSAppProject(for: document, manifest: manifest, shellDir: shellDir, generatedFiles: &generatedFiles)
        }
    }

    private func validatePackage(at packageURL: URL, manifest: HypeRuntimePackageManifest) throws {
        guard manifest.runtimeOnly, !manifest.includesAuthoringUI else {
            throw TargetRuntimePackageBuilderError.packageValidationFailed("Runtime packages must be runtime-only and exclude authoring UI.")
        }
        let stackURL = packageURL
            .appendingPathComponent(Self.stackDirectoryName, isDirectory: true)
            .appendingPathComponent(Self.embeddedStackName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: stackURL.appendingPathComponent(HypeSQLiteStackStore.sqliteFileName).path) else {
            throw TargetRuntimePackageBuilderError.packageValidationFailed("Runtime package is missing its embedded SQLite stack.")
        }
        let forbiddenShellTerms = ["PropertyInspector", "ScriptEditor", "ObjectToolCatalog", "AIChatPanel", "PreferencesView"]
        let shellSourceURL = packageURL
            .appendingPathComponent(Self.shellDirectoryName, isDirectory: true)
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("HypeRuntimeApp.swift")
        let shellSource = (try? String(contentsOf: shellSourceURL, encoding: .utf8)) ?? ""
        for term in forbiddenShellTerms where shellSource.contains(term) {
            throw TargetRuntimePackageBuilderError.packageValidationFailed("Runtime shell source contains authoring-only symbol \(term).")
        }
        if isGeneratedAppleRuntimePlatform(manifest.platform) {
            let shellDir = packageURL.appendingPathComponent(Self.shellDirectoryName, isDirectory: true)
            let projectURL = shellDir.appendingPathComponent("HypeRuntimeApp.xcodeproj", isDirectory: true)
            let sourcePackageURL = shellDir.appendingPathComponent("HypeSource", isDirectory: true)
            guard FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("project.pbxproj").path) else {
                throw TargetRuntimePackageBuilderError.packageValidationFailed("\(manifest.platform.displayName) runtime package is missing its generated Xcode project.")
            }
            guard FileManager.default.fileExists(atPath: sourcePackageURL.appendingPathComponent("Package.swift").path),
                  FileManager.default.fileExists(atPath: sourcePackageURL.appendingPathComponent("Sources/HypeCore").path) else {
                throw TargetRuntimePackageBuilderError.packageValidationFailed("\(manifest.platform.displayName) runtime package is missing its embedded HypeCore runtime source package.")
            }
            var requiredScripts = ["build-ios-simulator.sh", "build-ios-device.sh", "deploy-ios-device.sh", "preflight-ios-deployment.sh"]
            if isIOSRuntimePlatform(manifest.platform) {
                requiredScripts += ["archive-ios.sh", "export-ios-archive.sh", "upload-testflight.sh"]
            }
            for script in requiredScripts {
                guard FileManager.default.fileExists(atPath: shellDir.appendingPathComponent(script).path) else {
                    throw TargetRuntimePackageBuilderError.packageValidationFailed("\(manifest.platform.displayName) runtime package is missing \(script).")
                }
            }
            guard FileManager.default.fileExists(atPath: shellDir.appendingPathComponent("PrivacyInfo.xcprivacy").path) else {
                throw TargetRuntimePackageBuilderError.packageValidationFailed("\(manifest.platform.displayName) runtime package is missing PrivacyInfo.xcprivacy.")
            }
        }
        guard FileManager.default.fileExists(atPath: packageURL.appendingPathComponent(Self.shellDirectoryName, isDirectory: true).appendingPathComponent("DeploymentDiagnostics.json").path) else {
            throw TargetRuntimePackageBuilderError.packageValidationFailed("Runtime package is missing DeploymentDiagnostics.json.")
        }
    }

    private func requiredEntitlements(for document: HypeDocument, plan: HypeDeploymentPlan) -> [String] {
        var entitlements: Set<String> = []
        if document.parts.contains(where: { $0.partType == .webpage }) {
            entitlements.insert("com.apple.security.network.client")
        }
        if document.parts.contains(where: { $0.partType == .audioRecorder }) {
            entitlements.insert("microphone")
        }
        if document.parts.contains(where: { $0.partType == .map }) {
            entitlements.insert("location-when-in-use")
        }
        if document.parts.contains(where: { $0.partType == .appleMusicBrowser }) || !document.musicLibrary.appleMusicItems.isEmpty {
            entitlements.insert("music-user-token")
        }
        if plan.runtimeAIProviderPolicy == .appleFoundationModels {
            entitlements.insert("foundation-models")
        }
        return entitlements.sorted()
    }

    private func runtimePackageName(stackName: String, platform: HypeTargetPlatform) throws -> String {
        let base = sanitizeIdentifier(stackName, lowercase: false)
        guard !base.isEmpty else { throw TargetRuntimePackageBuilderError.invalidPackageName }
        return "\(base)-\(platform.rawValue).hyperuntime"
    }

    private func deploymentValidationMessage(_ report: HypeDeploymentValidationReport) -> String {
        let details = report.issues.prefix(5).map { issue in
            let name = issue.partName.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = name.isEmpty ? issue.partType.rawValue : "\(issue.partType.rawValue) \"\(name)\""
            return "\(label): \(issue.reason)"
        }.joined(separator: "; ")
        let suffix = report.issues.count > 5 ? "; plus \(report.issues.count - 5) more" : ""
        return "\(report.platform.displayName) runtime package cannot be exported because \(report.issues.count) part(s) are unsupported: \(details)\(suffix)"
    }

    private func selfContainedValidationMessage(_ issues: [StackAssetSelfContainmentIssue]) -> String {
        let details = issues.prefix(5).map { issue in
            let name = issue.partName.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = name.isEmpty ? issue.partType.rawValue : "\(issue.partType.rawValue) \"\(name)\""
            return "\(label).\(issue.property): \(issue.reason)"
        }.joined(separator: "; ")
        let suffix = issues.count > 5 ? "; plus \(issues.count - 5) more" : ""
        return "Runtime package cannot be exported because \(issues.count) referenced media item(s) are not embedded in the stack: \(details)\(suffix)"
    }

    private func bundleIdentifier(stackName: String, platform: HypeTargetPlatform) -> String {
        let component = sanitizeIdentifier(stackName, lowercase: true).lowercased()
        let safeComponent = component.isEmpty ? "stack" : component
        return "com.hype.runtime.\(safeComponent).\(platform.rawValue.lowercased())"
    }

    private func appTargetName(stackName: String, platform: HypeTargetPlatform) -> String {
        let base = sanitizeIdentifier(stackName, lowercase: false)
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
        let safeBase = base.isEmpty ? "HypeStack" : base
        return "\(safeBase)\(platform.rawValue)Runtime"
    }

    private func isIOSRuntimePlatform(_ platform: HypeTargetPlatform) -> Bool {
        platform == .iPhone || platform == .iPad
    }

    private func isGeneratedAppleRuntimePlatform(_ platform: HypeTargetPlatform) -> Bool {
        platform == .iPhone || platform == .iPad || platform == .tvOS
    }

    private func deviceFamilies(for platform: HypeTargetPlatform) -> [String]? {
        switch platform {
        case .iPhone: return ["iPhone"]
        case .iPad: return ["iPad"]
        case .tvOS: return ["Apple TV"]
        default: return nil
        }
    }

    private func targetDeviceFamilyValue(for platform: HypeTargetPlatform) -> String {
        switch platform {
        case .iPhone: return "1"
        case .iPad: return "2"
        case .tvOS: return "3"
        case .macOS: return ""
        }
    }

    private func sanitizeIdentifier(_ value: String, lowercase: Bool) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { scalar -> String in
            allowed.contains(scalar) ? String(scalar) : "-"
        }
        let collapsed = scalars.joined()
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return lowercase ? collapsed.lowercased() : collapsed
    }

    private func infoPlist(for manifest: HypeRuntimePackageManifest) -> String {
        let platformEntries = platformInfoPlistEntries(for: manifest)
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleDevelopmentRegion</key>
            <string>$(DEVELOPMENT_LANGUAGE)</string>
            <key>CFBundleExecutable</key>
            <string>$(EXECUTABLE_NAME)</string>
            <key>CFBundleIdentifier</key>
            <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
            <key>CFBundleInfoDictionaryVersion</key>
            <string>6.0</string>
            <key>CFBundleName</key>
            <string>\(escapePlist(manifest.stackName))</string>
            <key>CFBundlePackageType</key>
            <string>APPL</string>
            <key>CFBundleShortVersionString</key>
            <string>1.0</string>
            <key>CFBundleVersion</key>
            <string>1</string>
            <key>HypeRuntimeOnly</key>
            <true/>
            <key>HypeRuntimeManifest</key>
            <string>\(Self.manifestFileName)</string>
            <key>HypeEmbeddedStackPath</key>
            <string>\(manifest.embeddedStackPath)</string>
            <key>HypeTargetPlatform</key>
            <string>\(manifest.platform.rawValue)</string>
        \(platformEntries)
        </dict>
        </plist>
        """
    }

    private func platformInfoPlistEntries(for manifest: HypeRuntimePackageManifest) -> String {
        let deviceFamilyEntries = uidDeviceFamilyEntries(for: manifest.platform)
        let privacyEntries = privacyUsageDescriptionEntries(for: manifest.requiredEntitlements)
        switch manifest.platform {
        case .iPhone, .iPad:
            return """
                <key>LSRequiresIPhoneOS</key>
                <true/>
            \(deviceFamilyEntries)
                <key>UIApplicationSupportsIndirectInputEvents</key>
                <true/>
                <key>UILaunchScreen</key>
                <dict/>
                <key>UISupportedInterfaceOrientations</key>
                <array>
                    <string>UIInterfaceOrientationPortrait</string>
                    <string>UIInterfaceOrientationLandscapeLeft</string>
                    <string>UIInterfaceOrientationLandscapeRight</string>
                </array>
            \(privacyEntries)
            """
        case .tvOS:
            return """
            \(deviceFamilyEntries)
            \(privacyEntries)
            """
        case .macOS:
            return ""
        }
    }

    private func uidDeviceFamilyEntries(for platform: HypeTargetPlatform) -> String {
        switch platform {
        case .iPhone:
            return """
                <key>UIDeviceFamily</key>
                <array>
                    <integer>1</integer>
                </array>
            """
        case .iPad:
            return """
                <key>UIDeviceFamily</key>
                <array>
                    <integer>2</integer>
                </array>
            """
        case .tvOS:
            return """
                <key>UIDeviceFamily</key>
                <array>
                    <integer>3</integer>
                </array>
            """
        default:
            return ""
        }
    }

    private func privacyUsageDescriptionEntries(for requiredEntitlements: [String]) -> String {
        var entries: [String] = []
        if requiredEntitlements.contains("microphone") {
            entries.append("""
                <key>NSMicrophoneUsageDescription</key>
                <string>This Hype stack uses microphone input for its runtime audio features.</string>
            """)
        }
        if requiredEntitlements.contains("location-when-in-use") {
            entries.append("""
                <key>NSLocationWhenInUseUsageDescription</key>
                <string>This Hype stack uses location only while the stack is running.</string>
            """)
        }
        if requiredEntitlements.contains("music-user-token") {
            entries.append("""
                <key>NSAppleMusicUsageDescription</key>
                <string>This Hype stack can browse and play music selected from your Apple Music library.</string>
            """)
        }
        return entries.joined(separator: "\n")
    }

    private func codeSigningEntitlementKeys(for manifest: HypeRuntimePackageManifest) -> [String] {
        var keys: [String] = []
        if manifest.platform == .macOS, manifest.requiredEntitlements.contains("com.apple.security.network.client") {
            keys.append("com.apple.security.network.client")
        }
        if isGeneratedAppleRuntimePlatform(manifest.platform), manifest.requiredEntitlements.contains("music-user-token") {
            keys.append("com.apple.developer.music-user-token")
        }
        return keys
    }

    private func entitlementsPlist(for entitlements: [String]) -> String {
        let entries = entitlements.map { entitlement in
            "    <key>\(escapePlist(entitlement))</key>\n    <true/>"
        }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \(entries)
        </dict>
        </plist>
        """
    }

    private func deploymentDiagnostics(
        for document: HypeDocument,
        manifest: HypeRuntimePackageManifest
    ) -> HypeRuntimeDeploymentDiagnostics {
        let counts = Dictionary(grouping: document.parts, by: { $0.partType.rawValue })
            .mapValues(\.count)
        let assetByteCount = document.assetRepository.assets.reduce(0) { partial, asset in
            partial + asset.data.count
        }
        let scripts = [
            manifest.simulatorBuildScriptPath,
            manifest.deviceBuildScriptPath,
            manifest.deviceDeployScriptPath,
            manifest.deploymentPreflightScriptPath,
            manifest.archiveScriptPath,
            manifest.exportArchiveScriptPath,
            manifest.testFlightUploadScriptPath
        ].compactMap { $0 }.sorted()
        return HypeRuntimeDeploymentDiagnostics(
            stackId: manifest.stackId,
            stackName: manifest.stackName,
            platform: manifest.platform,
            profileId: manifest.profileId,
            profileName: manifest.profileName,
            bundleIdentifier: manifest.bundleIdentifier,
            runtimeOnly: manifest.runtimeOnly,
            includesAuthoringUI: manifest.includesAuthoringUI,
            totalPartCount: document.parts.count,
            partCountsByType: counts,
            assetCount: document.assetRepository.assets.count,
            assetByteCount: assetByteCount,
            requiredEntitlements: manifest.requiredEntitlements,
            supportedPartTypes: manifest.supportedPartTypes,
            unsupportedPartTypes: manifest.unsupportedPartTypes,
            distributionScripts: scripts
        )
    }

    private func privacyManifest() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>NSPrivacyTracking</key>
            <false/>
            <key>NSPrivacyTrackingDomains</key>
            <array/>
            <key>NSPrivacyCollectedDataTypes</key>
            <array/>
            <key>NSPrivacyAccessedAPITypes</key>
            <array/>
        </dict>
        </plist>
        """
    }

    private func runtimeShellSource(for document: HypeDocument, manifest: HypeRuntimePackageManifest) -> String {
        let safeAppName = manifest.appTargetName ?? appTargetName(stackName: document.stack.name, platform: manifest.platform)
        return """
        import Foundation
        import SwiftUI
        import HypeCore
        #if canImport(MapKit)
        import MapKit
        #endif
        #if canImport(AVFoundation)
        import AVFoundation
        #endif
        #if os(macOS)
        import AppKit
        #else
        import UIKit
        #endif

        @main
        struct \(safeAppName)RuntimeApp: App {
            var body: some Scene {
                WindowGroup {
                    HypeRuntimeRootView(
                        stackName: "\(escapedSwiftString(manifest.stackName))",
                        targetPlatform: "\(manifest.platform.rawValue)",
                        profileId: "\(manifest.profileId)",
                        embeddedStackPath: "\(manifest.embeddedStackPath)"
                    )
                }
            }
        }

        struct HypeRuntimeRootView: View {
            let stackName: String
            let targetPlatform: String
            let profileId: String
            let embeddedStackPath: String

            var body: some View {
                HypeStackRuntimeShellView(
                    stackName: stackName,
                    targetPlatform: targetPlatform,
                    profileId: profileId,
                    embeddedStackPath: embeddedStackPath
                )
            }
        }

        struct HypeStackRuntimeShellView: View {
            let stackName: String
            let targetPlatform: String
            let profileId: String
            let embeddedStackPath: String
            @StateObject private var model = HypeRuntimeDocumentModel()

            var body: some View {
                Group {
                    if let document = model.document {
                        HypeRuntimeCardView(
                            document: document,
                            currentCardId: model.currentCardId,
                            profileId: profileId,
                            systemProvider: model.systemProvider,
                            onPartChanged: { part, message in
                                await model.updatePart(part, dispatchMessage: message)
                            },
                            onMouseUp: { part in
                                await model.dispatchMouseUp(to: part)
                            }
                        )
                    } else if let loadError = model.loadError {
                        Text(loadError)
                            .foregroundStyle(.red)
                    } else {
                        ProgressView("Loading \\(stackName)")
                    }
                }
                .accessibilityLabel("Hype runtime stack \\(stackName) for \\(targetPlatform)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.ignoresSafeArea())
                .task {
                    await model.load(embeddedStackPath: embeddedStackPath)
                }
            }
        }

        @MainActor
        final class HypeRuntimeDocumentModel: ObservableObject {
            @Published var document: HypeDocument?
            @Published var currentCardId: UUID?
            @Published var loadError: String?
            let systemProvider = HypeRuntimeSystemProvider()
            private var runtime: StackRuntime?

            func load(embeddedStackPath: String) async {
                guard document == nil else { return }
                guard let resourceURL = Bundle.main.resourceURL else {
                    loadError = "Runtime resources are unavailable."
                    return
                }
                do {
                    let packageURL = resourceURL.appendingPathComponent(embeddedStackPath, isDirectory: true)
                    var loaded = try HypeSQLiteStackStore().load(fromPackageAt: packageURL)
                    loaded.stack.runtimeModeEnabled = true
                    loaded.scriptGlobals = [:]
                    let initialCardId = loaded.sortedCards.first?.id
                    let runtime = await StackRuntimeRegistry.shared.runtime(
                        for: loaded,
                        configuration: StackRuntimeConfiguration(systemProvider: systemProvider)
                    )
                    self.runtime = runtime
                    self.currentCardId = initialCardId
                    document = loaded
                } catch {
                    loadError = "Could not load embedded Hype stack: \\(error.localizedDescription)"
                }
            }

            func dispatchMouseUp(to part: Part) async {
                guard let document, let cardId = currentCardId ?? document.sortedCards.first?.id else { return }
                let runtime = await runtimeFor(document)
                let result = await runtime.dispatchAndWait(
                    "mouseUp",
                    params: [],
                    targetId: part.id,
                    currentCardId: cardId
                )
                let updated = await runtime.currentDocument()
                self.document = updated
                if let navigationTarget = result.navigationTarget {
                    self.currentCardId = navigationTarget
                }
            }

            func updatePart(_ updatedPart: Part, dispatchMessage message: String?) async {
                guard var document else { return }
                guard let index = document.parts.firstIndex(where: { $0.id == updatedPart.id }) else { return }
                document.parts[index] = updatedPart
                self.document = document
                let runtime = await runtimeFor(document)
                await runtime.syncDocument(document)
                guard let message, let cardId = currentCardId ?? document.sortedCards.first?.id else { return }
                let result = await runtime.dispatchAndWait(
                    message,
                    params: [],
                    targetId: updatedPart.id,
                    currentCardId: cardId
                )
                let current = await runtime.currentDocument()
                self.document = current
                if let navigationTarget = result.navigationTarget {
                    self.currentCardId = navigationTarget
                }
            }

            private func runtimeFor(_ document: HypeDocument) async -> StackRuntime {
                if let existing = self.runtime {
                    return existing
                }
                let runtime = await StackRuntimeRegistry.shared.runtime(
                    for: document,
                    configuration: StackRuntimeConfiguration(systemProvider: systemProvider)
                )
                self.runtime = runtime
                return runtime
            }
        }

        struct HypeRuntimeCardView: View {
            let document: HypeDocument
            let currentCardId: UUID?
            let profileId: String
            let systemProvider: HypeRuntimeSystemProvider
            let onPartChanged: @Sendable (Part, String?) async -> Void
            let onMouseUp: @Sendable (Part) async -> Void

            var body: some View {
                GeometryReader { proxy in
                    let card = currentCardId.flatMap { id in document.cards.first { $0.id == id } } ?? document.sortedCards.first
                    let baseProfile = HypeDeviceProfileCatalog.profile(id: profileId) ?? document.stack.deploymentTargets.primaryProfile
                    let liveProfile = runtimeProfile(baseProfile: baseProfile, proxy: proxy)
                    let resolution = card.map { LayoutResolver().resolve(document: document, profile: liveProfile, cardId: $0.id) }
                    ZStack(alignment: .topLeading) {
                        Color.white
                        if let card {
                            ForEach(document.effectivePartsForCard(card.id)) { part in
                                TargetRuntimePartView(
                                    part: part,
                                    geometry: resolution?.geometries[part.id],
                                    document: document,
                                    systemProvider: systemProvider,
                                    onPartChanged: onPartChanged,
                                    onMouseUp: onMouseUp
                                )
                            }
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                }
                .background(Color.white.ignoresSafeArea())
            }

            private func runtimeProfile(baseProfile: HypeDeviceProfile, proxy: GeometryProxy) -> HypeDeviceProfile {
                let width = max(1, Int((proxy.size.width > 0 ? proxy.size.width : CGFloat(baseProfile.width)).rounded()))
                let height = max(1, Int((proxy.size.height > 0 ? proxy.size.height : CGFloat(baseProfile.height)).rounded()))
                return HypeDeviceProfile(
                    id: baseProfile.id,
                    platform: baseProfile.platform,
                    displayName: baseProfile.displayName,
                    width: width,
                    height: height,
                    orientation: baseProfile.orientation,
                    inputModel: baseProfile.inputModel,
                    safeArea: HypeSafeAreaInsets(
                        top: Double(proxy.safeAreaInsets.top),
                        left: Double(proxy.safeAreaInsets.leading),
                        bottom: Double(proxy.safeAreaInsets.bottom),
                        right: Double(proxy.safeAreaInsets.trailing)
                    ),
                    scale: baseProfile.scale
                )
            }
        }

        actor HypeRuntimeSystemProvider: SystemProvider {
            private let appleMusicProvider = AppleMusicProviderFactory.makeDefault()

        #if canImport(AVFoundation)
            private var activePlayers: [UUID: AVAudioPlayer] = [:]
            private var sustainedPlayersByPart: [UUID: Set<UUID>] = [:]
            private var latestSoundName = "done"
            private var musicState = "stopped"
        #endif

            func beep(count: Int) async {
                let noteCount = max(1, count)
                let notes = Array(repeating: "c5s", count: noteCount).joined(separator: " ")
                let pattern = MusicPatternSpec.singleTrack(
                    name: "Runtime Beep",
                    instrument: "Square Lead",
                    tempo: 180,
                    notes: notes
                )
                await playMusicPattern(pattern, loop: false, document: HypeDocument.newDocument(name: "Runtime"))
            }

            func playSound(name: String, document: HypeDocument) async {
                await playNotes(instrument: name, noteString: "c4q", tempo: MusicTempo.defaultBPM, document: document)
            }

            func playNotes(instrument: String, noteString: String, tempo: Int, document: HypeDocument) async {
                let pattern = MusicPatternSpec.singleTrack(
                    name: "Runtime Notes",
                    instrument: instrument,
                    tempo: MusicTempo.clamp(tempo),
                    notes: noteString
                )
                await playMusicPattern(pattern, loop: false, document: document)
            }

            func stopSound() async {
                await stopMusic()
            }

            func currentSoundName() async -> String {
        #if canImport(AVFoundation)
                return activePlayers.values.contains { $0.isPlaying } ? latestSoundName : "done"
        #else
                return "done"
        #endif
            }

            func playMusicPattern(_ pattern: MusicPatternSpec, loop: Bool, document: HypeDocument) async {
        #if canImport(AVFoundation)
                configureAudioSessionIfNeeded()
                let data = MusicPatternRenderer.wavData(for: pattern)
                do {
                    let player = try AVAudioPlayer(data: data)
                    player.numberOfLoops = loop ? -1 : 0
                    player.prepareToPlay()
                    player.play()
                    activePlayers = activePlayers.filter { $0.value.isPlaying }
                    activePlayers[pattern.id] = player
                    latestSoundName = pattern.name
                    musicState = "playing"
                } catch {
                    latestSoundName = "done"
                    musicState = "stopped"
                }
        #endif
            }

            func playSustainedMusicNote(_ note: MusicSustainedNoteSpec, document: HypeDocument) async {
        #if canImport(AVFoundation)
                configureAudioSessionIfNeeded()
                let noteString = note.note + "h"
                let pattern = MusicPatternSpec(
                    id: note.id,
                    name: "Runtime Note " + note.note,
                    tempo: 120,
                    loop: true,
                    tracks: [
                        MusicTrackSpec(
                            name: "key",
                            instrument: note.instrument,
                            noteString: noteString,
                            volume: note.volume
                        ),
                    ],
                    notes: noteString
                )
                let data = MusicPatternRenderer.wavData(for: pattern)
                do {
                    let player = try AVAudioPlayer(data: data)
                    player.numberOfLoops = -1
                    player.prepareToPlay()
                    player.play()
                    activePlayers[note.id] = player
                    sustainedPlayersByPart[note.partId, default: []].insert(note.id)
                    latestSoundName = pattern.name
                    musicState = "playing"
                } catch {
                    latestSoundName = "done"
                }
        #endif
            }

            func stopSustainedMusicNote(id: UUID) async {
        #if canImport(AVFoundation)
                activePlayers[id]?.stop()
                activePlayers.removeValue(forKey: id)
                for partId in sustainedPlayersByPart.keys {
                    sustainedPlayersByPart[partId]?.remove(id)
                }
        #endif
            }

            func stopSustainedMusicNotes(forPart partId: UUID?) async {
        #if canImport(AVFoundation)
                guard let partId else {
                    for ids in sustainedPlayersByPart.values {
                        for id in ids {
                            activePlayers[id]?.stop()
                            activePlayers.removeValue(forKey: id)
                        }
                    }
                    sustainedPlayersByPart.removeAll()
                    return
                }
                let ids = sustainedPlayersByPart[partId] ?? []
                for id in ids {
                    activePlayers[id]?.stop()
                    activePlayers.removeValue(forKey: id)
                }
                sustainedPlayersByPart.removeValue(forKey: partId)
        #endif
            }

            func stopMusic() async {
        #if canImport(AVFoundation)
                for player in activePlayers.values {
                    player.stop()
                }
                activePlayers.removeAll()
                sustainedPlayersByPart.removeAll()
                latestSoundName = "done"
                musicState = "stopped"
        #endif
            }

            func pauseMusic() async {
        #if canImport(AVFoundation)
                for player in activePlayers.values {
                    player.pause()
                }
                musicState = "paused"
        #endif
            }

            func resumeMusic() async {
        #if canImport(AVFoundation)
                for player in activePlayers.values {
                    player.play()
                }
                if !activePlayers.isEmpty {
                    musicState = "playing"
                }
        #endif
            }

            func currentMusicState() async -> String {
        #if canImport(AVFoundation)
                if activePlayers.values.contains(where: { $0.isPlaying }) {
                    return musicState == "paused" ? "paused" : "playing"
                }
                return "stopped"
        #else
                return "stopped"
        #endif
            }

            func appleMusicAuthorizationStatus() async -> AppleMusicAuthorizationState {
                await appleMusicProvider.authorizationStatus()
            }

            func authorizeAppleMusic() async -> AppleMusicAuthorizationState {
                await appleMusicProvider.requestAuthorization()
            }

            func appleMusicCapabilities() async -> AppleMusicCapabilities {
                await appleMusicProvider.capabilities()
            }

            func searchAppleMusic(_ request: AppleMusicSearchRequest) async throws -> [AppleMusicItemRef] {
                try await appleMusicProvider.search(request)
            }

            func playAppleMusic(_ item: AppleMusicItemRef, engine: AppleMusicPlaybackEngine) async throws {
                try await appleMusicProvider.play(item, engine: engine)
            }

            func pauseAppleMusic(engine: AppleMusicPlaybackEngine) async {
                await appleMusicProvider.pause(engine: engine)
            }

            func resumeAppleMusic(engine: AppleMusicPlaybackEngine) async throws {
                try await appleMusicProvider.resume(engine: engine)
            }

            func stopAppleMusic(engine: AppleMusicPlaybackEngine) async {
                await appleMusicProvider.stop(engine: engine)
            }

            func currentAppleMusicState(engine: AppleMusicPlaybackEngine) async -> String {
                await appleMusicProvider.currentPlaybackState(engine: engine)
            }

            func seekAppleMusic(to position: Double, engine: AppleMusicPlaybackEngine) async throws {
                try await appleMusicProvider.seek(to: position, engine: engine)
            }

            func currentAppleMusicPosition(engine: AppleMusicPlaybackEngine) async -> Double {
                await appleMusicProvider.currentPlaybackPosition(engine: engine)
            }

        #if canImport(AVFoundation)
            private func configureAudioSessionIfNeeded() {
        #if os(iOS) || os(tvOS)
                try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
                try? AVAudioSession.sharedInstance().setActive(true)
        #endif
            }
        #endif
        }

        #if os(macOS)
        typealias PlatformImage = NSImage
        struct PlatformImageView: View {
            let image: NSImage
            var body: some View { Image(nsImage: image).resizable().scaledToFit() }
        }
        #else
        typealias PlatformImage = UIImage
        struct PlatformImageView: View {
            let image: UIImage
            var body: some View { Image(uiImage: image).resizable().scaledToFit() }
        }
        #endif

        extension Color {
            init(hex: String) {
                let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                let scanner = Scanner(string: trimmed)
                var value: UInt64 = 0
                scanner.scanHexInt64(&value)
                let red = Double((value >> 16) & 0xff) / 255.0
                let green = Double((value >> 8) & 0xff) / 255.0
                let blue = Double(value & 0xff) / 255.0
                self.init(red: red, green: green, blue: blue)
            }
        }
        """
    }

    private func writeIOSAppProject(
        for document: HypeDocument,
        manifest: HypeRuntimePackageManifest,
        shellDir: URL,
        generatedFiles: inout [String]
    ) throws {
        let projectDir = shellDir.appendingPathComponent("HypeRuntimeApp.xcodeproj", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let pbxproj = xcodeProjectFile(for: document, manifest: manifest)
        try pbxproj.write(to: projectDir.appendingPathComponent("project.pbxproj"), atomically: true, encoding: .utf8)
        generatedFiles.append("\(Self.shellDirectoryName)/HypeRuntimeApp.xcodeproj/project.pbxproj")

        try privacyManifest().write(to: shellDir.appendingPathComponent("PrivacyInfo.xcprivacy"), atomically: true, encoding: .utf8)
        generatedFiles.append("\(Self.shellDirectoryName)/PrivacyInfo.xcprivacy")

        try writeRuntimeCoreSourcePackage(to: shellDir.appendingPathComponent("HypeSource", isDirectory: true), generatedFiles: &generatedFiles)

        let preflight = iosDeploymentPreflightScript(for: manifest)
        let preflightURL = shellDir.appendingPathComponent("preflight-ios-deployment.sh")
        try preflight.write(to: preflightURL, atomically: true, encoding: .utf8)
        try makeExecutable(preflightURL)
        generatedFiles.append("\(Self.shellDirectoryName)/preflight-ios-deployment.sh")

        let simulatorBuild = iosSimulatorBuildScript(for: manifest)
        let simulatorBuildURL = shellDir.appendingPathComponent("build-ios-simulator.sh")
        try simulatorBuild.write(to: simulatorBuildURL, atomically: true, encoding: .utf8)
        try makeExecutable(simulatorBuildURL)
        generatedFiles.append("\(Self.shellDirectoryName)/build-ios-simulator.sh")

        let deviceBuild = iosDeviceBuildScript(for: manifest)
        let deviceBuildURL = shellDir.appendingPathComponent("build-ios-device.sh")
        try deviceBuild.write(to: deviceBuildURL, atomically: true, encoding: .utf8)
        try makeExecutable(deviceBuildURL)
        generatedFiles.append("\(Self.shellDirectoryName)/build-ios-device.sh")

        let deviceDeploy = iosDeviceDeployScript(for: manifest)
        let deviceDeployURL = shellDir.appendingPathComponent("deploy-ios-device.sh")
        try deviceDeploy.write(to: deviceDeployURL, atomically: true, encoding: .utf8)
        try makeExecutable(deviceDeployURL)
        generatedFiles.append("\(Self.shellDirectoryName)/deploy-ios-device.sh")

        if isIOSRuntimePlatform(manifest.platform) {
            let archive = iosArchiveScript(for: manifest)
            let archiveURL = shellDir.appendingPathComponent("archive-ios.sh")
            try archive.write(to: archiveURL, atomically: true, encoding: .utf8)
            try makeExecutable(archiveURL)
            generatedFiles.append("\(Self.shellDirectoryName)/archive-ios.sh")

            let export = iosExportArchiveScript(for: manifest)
            let exportURL = shellDir.appendingPathComponent("export-ios-archive.sh")
            try export.write(to: exportURL, atomically: true, encoding: .utf8)
            try makeExecutable(exportURL)
            generatedFiles.append("\(Self.shellDirectoryName)/export-ios-archive.sh")

            let upload = iosTestFlightUploadScript(for: manifest)
            let uploadURL = shellDir.appendingPathComponent("upload-testflight.sh")
            try upload.write(to: uploadURL, atomically: true, encoding: .utf8)
            try makeExecutable(uploadURL)
            generatedFiles.append("\(Self.shellDirectoryName)/upload-testflight.sh")
        }
    }

    private func writeRuntimeCoreSourcePackage(to sourcePackageDir: URL, generatedFiles: inout [String]) throws {
        guard let sourceRoot = inferredSourceRoot() else {
            throw TargetRuntimePackageBuilderError.runtimeSourceUnavailable(
                "Could not locate HypeCore source files to embed in the Apple runtime package."
            )
        }
        let fm = FileManager.default
        try fm.createDirectory(at: sourcePackageDir.appendingPathComponent("Sources", isDirectory: true), withIntermediateDirectories: true)
        try fm.createDirectory(at: sourcePackageDir.appendingPathComponent("Vendor", isDirectory: true), withIntermediateDirectories: true)
        try copyDirectory(
            from: sourceRoot.appendingPathComponent("Sources/HypeCore", isDirectory: true),
            to: sourcePackageDir.appendingPathComponent("Sources/HypeCore", isDirectory: true)
        )
        try removeRuntimeExcludedSourceDirectories(from: sourcePackageDir)
        try copyDirectory(
            from: sourceRoot.appendingPathComponent("Sources/CStackImport", isDirectory: true),
            to: sourcePackageDir.appendingPathComponent("Sources/CStackImport", isDirectory: true)
        )
        try copyDirectory(
            from: sourceRoot.appendingPathComponent("Vendor/AudioKit", isDirectory: true),
            to: sourcePackageDir.appendingPathComponent("Vendor/AudioKit", isDirectory: true)
        )
        try runtimeCorePackageSwift().write(to: sourcePackageDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        generatedFiles.append("\(Self.shellDirectoryName)/HypeSource/Package.swift")
        generatedFiles.append("\(Self.shellDirectoryName)/HypeSource/Sources/HypeCore")
        generatedFiles.append("\(Self.shellDirectoryName)/HypeSource/Sources/CStackImport")
        generatedFiles.append("\(Self.shellDirectoryName)/HypeSource/Vendor/AudioKit")
    }

    private func inferredSourceRoot() -> URL? {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<8 {
            url.deleteLastPathComponent()
            let package = url.appendingPathComponent("Package.swift")
            let core = url.appendingPathComponent("Sources/HypeCore", isDirectory: true)
            if FileManager.default.fileExists(atPath: package.path),
               FileManager.default.fileExists(atPath: core.path) {
                return url
            }
        }
        return nil
    }

    private func removeRuntimeExcludedSourceDirectories(from sourcePackageDir: URL) throws {
        let fm = FileManager.default
        let excludedDirectories = ["MCP"]
        for relativePath in excludedDirectories {
            let url = sourcePackageDir
                .appendingPathComponent("Sources/HypeCore", isDirectory: true)
                .appendingPathComponent(relativePath, isDirectory: true)
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
        }
    }

    private func copyDirectory(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else {
            throw TargetRuntimePackageBuilderError.runtimeSourceUnavailable(
                "Missing runtime source directory \(source.path)."
            )
        }
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: source, to: destination)
    }

    private func makeExecutable(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func runtimeCorePackageSwift() -> String {
        """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "HypeRuntimeCore",
            platforms: [.macOS(.v15), .iOS(.v17), .tvOS(.v17)],
            products: [
                .library(name: "HypeCore", targets: ["HypeCore"]),
            ],
            dependencies: [
                .package(path: "Vendor/AudioKit"),
            ],
            targets: [
                .target(
                    name: "HypeCore",
                    dependencies: [
                        "CStackImport",
                        .product(name: "AudioKit", package: "AudioKit"),
                    ],
                    path: "Sources/HypeCore",
                    exclude: ["MCP"],
                    resources: [
                        .process("Resources/MeshyAnimationCatalog.json"),
                    ],
                    linkerSettings: [
                        .linkedLibrary("sqlite3"),
                        .linkedLibrary("c++"),
                    ]
                ),
                .systemLibrary(
                    name: "CStackImport",
                    path: "Sources/CStackImport"
                ),
            ]
        )
        """
    }

    private func iosDeploymentPreflightScript(for manifest: HypeRuntimePackageManifest) -> String {
        let target = manifest.appTargetName ?? appTargetName(stackName: manifest.stackName, platform: manifest.platform)
        let sdk = sdkRoot(for: manifest.platform)
        let defaultBundleID = manifest.bundleIdentifier
        return """
        #!/bin/bash
        set -euo pipefail

        SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
        TARGET="\(target)"
        BUNDLE_IDENTIFIER="${HYPE_BUNDLE_IDENTIFIER:-\(defaultBundleID)}"

        echo "Hype runtime preflight"
        echo "Target: $TARGET"
        echo "Bundle identifier: $BUNDLE_IDENTIFIER"
        echo "Platform: \(manifest.platform.displayName)"
        echo "Profile: \(manifest.profileName)"

        /usr/bin/xcrun -f xcodebuild >/dev/null
        /usr/bin/xcrun xcodebuild -version
        /usr/bin/xcrun xcodebuild -showsdks | /usr/bin/grep -q "\(sdk)" || {
          echo "Missing \(sdk) SDK in the active Xcode installation." >&2
          exit 1
        }

        test -d "$SCRIPT_DIR/HypeRuntimeApp.xcodeproj" || { echo "Missing generated Xcode project." >&2; exit 1; }
        test -f "$SCRIPT_DIR/../RuntimeManifest.json" || { echo "Missing RuntimeManifest.json." >&2; exit 1; }
        test -d "$SCRIPT_DIR/../Stack/Stack.hype" || { echo "Missing embedded Stack/Stack.hype package." >&2; exit 1; }
        test -f "$SCRIPT_DIR/DeploymentDiagnostics.json" || { echo "Missing DeploymentDiagnostics.json." >&2; exit 1; }
        test -f "$SCRIPT_DIR/PrivacyInfo.xcprivacy" || { echo "Missing PrivacyInfo.xcprivacy." >&2; exit 1; }

        if [ -z "${HYPE_DEVELOPMENT_TEAM:-}" ]; then
          echo "HYPE_DEVELOPMENT_TEAM is not set. Simulator builds can run, but device/archive/export flows need a Team ID." >&2
        fi

        echo "Preflight passed."
        """
    }

    private func iosSimulatorBuildScript(for manifest: HypeRuntimePackageManifest) -> String {
        let target = manifest.appTargetName ?? appTargetName(stackName: manifest.stackName, platform: manifest.platform)
        let destination = simulatorDestination(for: manifest.platform)
        let defaultBundleID = manifest.bundleIdentifier
        return """
        #!/bin/bash
        set -euo pipefail
        SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
        DERIVED_DATA="${DERIVED_DATA:-"$SCRIPT_DIR/Build/DerivedData"}"
        CONFIGURATION="${HYPE_CONFIGURATION:-Debug}"
        BUNDLE_IDENTIFIER="${HYPE_BUNDLE_IDENTIFIER:-\(defaultBundleID)}"
        "$SCRIPT_DIR/preflight-ios-deployment.sh"
        /usr/bin/xcrun xcodebuild \\
          -project "$SCRIPT_DIR/HypeRuntimeApp.xcodeproj" \\
          -scheme "\(target)" \\
          -configuration "$CONFIGURATION" \\
          -destination '\(destination)' \\
          -derivedDataPath "$DERIVED_DATA" \\
          PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" \\
          CODE_SIGNING_ALLOWED=NO \\
          build
        """
    }

    private func iosDeviceBuildScript(for manifest: HypeRuntimePackageManifest) -> String {
        let target = manifest.appTargetName ?? appTargetName(stackName: manifest.stackName, platform: manifest.platform)
        let destination = deviceDestination(for: manifest.platform)
        let defaultBundleID = manifest.bundleIdentifier
        return """
        #!/bin/bash
        set -euo pipefail
        : "${HYPE_DEVELOPMENT_TEAM:?Set HYPE_DEVELOPMENT_TEAM to your Apple Developer Team ID before building for device.}"
        SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
        DERIVED_DATA="${DERIVED_DATA:-"$SCRIPT_DIR/Build/DerivedData"}"
        CONFIGURATION="${HYPE_CONFIGURATION:-Debug}"
        BUNDLE_IDENTIFIER="${HYPE_BUNDLE_IDENTIFIER:-\(defaultBundleID)}"
        "$SCRIPT_DIR/preflight-ios-deployment.sh"
        /usr/bin/xcrun xcodebuild \\
          -project "$SCRIPT_DIR/HypeRuntimeApp.xcodeproj" \\
          -scheme "\(target)" \\
          -configuration "$CONFIGURATION" \\
          -destination '\(destination)' \\
          -derivedDataPath "$DERIVED_DATA" \\
          -allowProvisioningUpdates \\
          DEVELOPMENT_TEAM="$HYPE_DEVELOPMENT_TEAM" \\
          PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" \\
          build
        """
    }

    private func iosDeviceDeployScript(for manifest: HypeRuntimePackageManifest) -> String {
        let target = manifest.appTargetName ?? appTargetName(stackName: manifest.stackName, platform: manifest.platform)
        let productSuffix = deviceProductSuffix(for: manifest.platform)
        return """
        #!/bin/bash
        set -euo pipefail
        : "${HYPE_DEVICE_ID:?Set HYPE_DEVICE_ID to the target device UDID, serial number, or device name.}"
        SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
        DERIVED_DATA="${DERIVED_DATA:-"$SCRIPT_DIR/Build/DerivedData"}"
        CONFIGURATION="${HYPE_CONFIGURATION:-Debug}"
        "$SCRIPT_DIR/build-ios-device.sh"
        APP_PATH="$DERIVED_DATA/Build/Products/${CONFIGURATION}-\(productSuffix)/\(target).app"
        if [ ! -d "$APP_PATH" ]; then
          echo "Built app not found at $APP_PATH" >&2
          exit 1
        fi
        /usr/bin/xcrun devicectl device install app --device "$HYPE_DEVICE_ID" "$APP_PATH"
        """
    }

    private func iosArchiveScript(for manifest: HypeRuntimePackageManifest) -> String {
        let target = manifest.appTargetName ?? appTargetName(stackName: manifest.stackName, platform: manifest.platform)
        let destination = deviceDestination(for: manifest.platform)
        let defaultBundleID = manifest.bundleIdentifier
        return """
        #!/bin/bash
        set -euo pipefail
        : "${HYPE_DEVELOPMENT_TEAM:?Set HYPE_DEVELOPMENT_TEAM to your Apple Developer Team ID before archiving.}"

        SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
        DERIVED_DATA="${DERIVED_DATA:-"$SCRIPT_DIR/Build/DerivedData"}"
        ARCHIVE_PATH="${HYPE_ARCHIVE_PATH:-"$SCRIPT_DIR/Build/Archives/\(target).xcarchive"}"
        BUNDLE_IDENTIFIER="${HYPE_BUNDLE_IDENTIFIER:-\(defaultBundleID)}"

        AUTH_ARGS=()
        if [ -n "${HYPE_ASC_KEY_PATH:-}" ] || [ -n "${HYPE_ASC_KEY_ID:-}" ] || [ -n "${HYPE_ASC_ISSUER_ID:-}" ]; then
          : "${HYPE_ASC_KEY_PATH:?Set HYPE_ASC_KEY_PATH, HYPE_ASC_KEY_ID, and HYPE_ASC_ISSUER_ID together.}"
          : "${HYPE_ASC_KEY_ID:?Set HYPE_ASC_KEY_PATH, HYPE_ASC_KEY_ID, and HYPE_ASC_ISSUER_ID together.}"
          : "${HYPE_ASC_ISSUER_ID:?Set HYPE_ASC_KEY_PATH, HYPE_ASC_KEY_ID, and HYPE_ASC_ISSUER_ID together.}"
          AUTH_ARGS=(-authenticationKeyPath "$HYPE_ASC_KEY_PATH" -authenticationKeyID "$HYPE_ASC_KEY_ID" -authenticationKeyIssuerID "$HYPE_ASC_ISSUER_ID")
        fi

        "$SCRIPT_DIR/preflight-ios-deployment.sh"
        /bin/mkdir -p "$(dirname "$ARCHIVE_PATH")"
        /usr/bin/xcrun xcodebuild \\
          -project "$SCRIPT_DIR/HypeRuntimeApp.xcodeproj" \\
          -scheme "\(target)" \\
          -configuration Release \\
          -destination '\(destination)' \\
          -derivedDataPath "$DERIVED_DATA" \\
          -archivePath "$ARCHIVE_PATH" \\
          -allowProvisioningUpdates \\
          "${AUTH_ARGS[@]}" \\
          DEVELOPMENT_TEAM="$HYPE_DEVELOPMENT_TEAM" \\
          PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" \\
          archive
        echo "Archive written to $ARCHIVE_PATH"
        """
    }

    private func iosExportArchiveScript(for manifest: HypeRuntimePackageManifest) -> String {
        let target = manifest.appTargetName ?? appTargetName(stackName: manifest.stackName, platform: manifest.platform)
        let defaultBundleID = manifest.bundleIdentifier
        return """
        #!/bin/bash
        set -euo pipefail
        : "${HYPE_DEVELOPMENT_TEAM:?Set HYPE_DEVELOPMENT_TEAM to your Apple Developer Team ID before exporting.}"

        SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
        ARCHIVE_PATH="${HYPE_ARCHIVE_PATH:-"$SCRIPT_DIR/Build/Archives/\(target).xcarchive"}"
        EXPORT_PATH="${HYPE_EXPORT_PATH:-"$SCRIPT_DIR/Build/Export"}"
        EXPORT_OPTIONS="${HYPE_EXPORT_OPTIONS_PLIST:-"$SCRIPT_DIR/Build/ExportOptions.plist"}"
        EXPORT_METHOD="${HYPE_EXPORT_METHOD:-debugging}"
        EXPORT_DESTINATION="${HYPE_EXPORT_DESTINATION:-export}"
        BUNDLE_IDENTIFIER="${HYPE_BUNDLE_IDENTIFIER:-\(defaultBundleID)}"
        TESTFLIGHT_INTERNAL_ONLY="${HYPE_TESTFLIGHT_INTERNAL_ONLY:-true}"

        if [ "$EXPORT_DESTINATION" = "upload" ] && [ "$EXPORT_METHOD" != "app-store-connect" ]; then
          echo "HYPE_EXPORT_DESTINATION=upload requires HYPE_EXPORT_METHOD=app-store-connect." >&2
          exit 1
        fi
        test -d "$ARCHIVE_PATH" || { echo "Archive not found at $ARCHIVE_PATH. Run archive-ios.sh first." >&2; exit 1; }

        AUTH_ARGS=()
        if [ -n "${HYPE_ASC_KEY_PATH:-}" ] || [ -n "${HYPE_ASC_KEY_ID:-}" ] || [ -n "${HYPE_ASC_ISSUER_ID:-}" ]; then
          : "${HYPE_ASC_KEY_PATH:?Set HYPE_ASC_KEY_PATH, HYPE_ASC_KEY_ID, and HYPE_ASC_ISSUER_ID together.}"
          : "${HYPE_ASC_KEY_ID:?Set HYPE_ASC_KEY_PATH, HYPE_ASC_KEY_ID, and HYPE_ASC_ISSUER_ID together.}"
          : "${HYPE_ASC_ISSUER_ID:?Set HYPE_ASC_KEY_PATH, HYPE_ASC_KEY_ID, and HYPE_ASC_ISSUER_ID together.}"
          AUTH_ARGS=(-authenticationKeyPath "$HYPE_ASC_KEY_PATH" -authenticationKeyID "$HYPE_ASC_KEY_ID" -authenticationKeyIssuerID "$HYPE_ASC_ISSUER_ID")
        fi

        /bin/mkdir -p "$(dirname "$EXPORT_OPTIONS")" "$EXPORT_PATH"
        {
          echo '<?xml version="1.0" encoding="UTF-8"?>'
          echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">'
          echo '<plist version="1.0">'
          echo '<dict>'
          echo '  <key>method</key>'
          echo "  <string>$EXPORT_METHOD</string>"
          echo '  <key>destination</key>'
          echo "  <string>$EXPORT_DESTINATION</string>"
          echo '  <key>teamID</key>'
          echo "  <string>$HYPE_DEVELOPMENT_TEAM</string>"
          echo '  <key>signingStyle</key>'
          echo '  <string>automatic</string>'
          echo '  <key>stripSwiftSymbols</key>'
          echo '  <true/>'
          echo '  <key>thinning</key>'
          echo '  <string>&lt;none&gt;</string>'
          if [ "$EXPORT_METHOD" = "app-store-connect" ]; then
            echo '  <key>distributionBundleIdentifier</key>'
            echo "  <string>$BUNDLE_IDENTIFIER</string>"
            echo '  <key>uploadSymbols</key>'
            echo '  <true/>'
            echo '  <key>manageAppVersionAndBuildNumber</key>'
            echo '  <true/>'
            echo '  <key>testFlightInternalTestingOnly</key>'
            if [ "$TESTFLIGHT_INTERNAL_ONLY" = "true" ] || [ "$TESTFLIGHT_INTERNAL_ONLY" = "1" ]; then
              echo '  <true/>'
            else
              echo '  <false/>'
            fi
          fi
          echo '</dict>'
          echo '</plist>'
        } > "$EXPORT_OPTIONS"

        /usr/bin/xcrun xcodebuild \\
          -exportArchive \\
          -archivePath "$ARCHIVE_PATH" \\
          -exportPath "$EXPORT_PATH" \\
          -exportOptionsPlist "$EXPORT_OPTIONS" \\
          -allowProvisioningUpdates \\
          "${AUTH_ARGS[@]}"
        echo "Export completed at $EXPORT_PATH"
        """
    }

    private func iosTestFlightUploadScript(for manifest: HypeRuntimePackageManifest) -> String {
        """
        #!/bin/bash
        set -euo pipefail
        SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
        "$SCRIPT_DIR/archive-ios.sh"
        HYPE_EXPORT_METHOD=app-store-connect \\
        HYPE_EXPORT_DESTINATION=upload \\
        HYPE_TESTFLIGHT_INTERNAL_ONLY="${HYPE_TESTFLIGHT_INTERNAL_ONLY:-true}" \\
        "$SCRIPT_DIR/export-ios-archive.sh"
        """
    }

    private func simulatorDestination(for platform: HypeTargetPlatform) -> String {
        switch platform {
        case .tvOS: return "generic/platform=tvOS Simulator"
        default: return "generic/platform=iOS Simulator"
        }
    }

    private func deviceDestination(for platform: HypeTargetPlatform) -> String {
        switch platform {
        case .tvOS: return "generic/platform=tvOS"
        default: return "generic/platform=iOS"
        }
    }

    private func deviceProductSuffix(for platform: HypeTargetPlatform) -> String {
        switch platform {
        case .tvOS: return "appletvos"
        default: return "iphoneos"
        }
    }

    private func xcodeProjectFile(for document: HypeDocument, manifest: HypeRuntimePackageManifest) -> String {
        let target = manifest.appTargetName ?? appTargetName(stackName: document.stack.name, platform: manifest.platform)
        let bundleID = manifest.bundleIdentifier
        let family = targetDeviceFamilyValue(for: manifest.platform)
        let deploymentTargetSetting = deploymentTargetSetting(for: manifest.platform)
        let sdkRoot = sdkRoot(for: manifest.platform)
        let supportedPlatforms = supportedPlatforms(for: manifest.platform)
        let entitlementsSetting = codeSigningEntitlementKeys(for: manifest).isEmpty
            ? ""
            : "CODE_SIGN_ENTITLEMENTS = Entitlements.plist;"
        return """
        // !$*UTF8*$!
        {
            archiveVersion = 1;
            classes = {
            };
            objectVersion = 77;
            objects = {

        /* Begin PBXBuildFile section */
                A00000000000000000000001 /* HypeRuntimeApp.swift in Sources */ = {isa = PBXBuildFile; fileRef = A00000000000000000000101 /* HypeRuntimeApp.swift */; };
                A00000000000000000000002 /* RuntimeManifest.json in Resources */ = {isa = PBXBuildFile; fileRef = A00000000000000000000102 /* RuntimeManifest.json */; };
                A00000000000000000000003 /* Stack in Resources */ = {isa = PBXBuildFile; fileRef = A00000000000000000000103 /* Stack */; };
                A00000000000000000000004 /* AppIntents.json in Resources */ = {isa = PBXBuildFile; fileRef = A00000000000000000000104 /* AppIntents.json */; };
                A00000000000000000000005 /* HypeCore in Frameworks */ = {isa = PBXBuildFile; productRef = A00000000000000000000301 /* HypeCore */; };
                A00000000000000000000006 /* DeploymentDiagnostics.json in Resources */ = {isa = PBXBuildFile; fileRef = A00000000000000000000108 /* DeploymentDiagnostics.json */; };
                A00000000000000000000007 /* PrivacyInfo.xcprivacy in Resources */ = {isa = PBXBuildFile; fileRef = A00000000000000000000109 /* PrivacyInfo.xcprivacy */; };
        /* End PBXBuildFile section */

        /* Begin PBXFileReference section */
                A00000000000000000000101 /* HypeRuntimeApp.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Sources/HypeRuntimeApp.swift; sourceTree = "<group>"; };
                A00000000000000000000102 /* RuntimeManifest.json */ = {isa = PBXFileReference; lastKnownFileType = text.json; name = RuntimeManifest.json; path = ../RuntimeManifest.json; sourceTree = "<group>"; };
                A00000000000000000000103 /* Stack */ = {isa = PBXFileReference; lastKnownFileType = folder; name = Stack; path = ../Stack; sourceTree = "<group>"; };
                A00000000000000000000104 /* AppIntents.json */ = {isa = PBXFileReference; lastKnownFileType = text.json; path = AppIntents.json; sourceTree = "<group>"; };
                A00000000000000000000105 /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
                A00000000000000000000106 /* Entitlements.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = Entitlements.plist; sourceTree = "<group>"; };
                A00000000000000000000107 /* \(target).app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "\(target).app"; sourceTree = BUILT_PRODUCTS_DIR; };
                A00000000000000000000108 /* DeploymentDiagnostics.json */ = {isa = PBXFileReference; lastKnownFileType = text.json; path = DeploymentDiagnostics.json; sourceTree = "<group>"; };
                A00000000000000000000109 /* PrivacyInfo.xcprivacy */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = PrivacyInfo.xcprivacy; sourceTree = "<group>"; };
        /* End PBXFileReference section */

        /* Begin PBXFrameworksBuildPhase section */
                A00000000000000000000201 /* Frameworks */ = {
                    isa = PBXFrameworksBuildPhase;
                    buildActionMask = 2147483647;
                    files = (
                        A00000000000000000000005 /* HypeCore in Frameworks */,
                    );
                    runOnlyForDeploymentPostprocessing = 0;
                };
        /* End PBXFrameworksBuildPhase section */

        /* Begin PBXGroup section */
                A00000000000000000000401 = {
                    isa = PBXGroup;
                    children = (
                        A00000000000000000000101 /* HypeRuntimeApp.swift */,
                        A00000000000000000000102 /* RuntimeManifest.json */,
                        A00000000000000000000103 /* Stack */,
                        A00000000000000000000104 /* AppIntents.json */,
                        A00000000000000000000105 /* Info.plist */,
                        A00000000000000000000106 /* Entitlements.plist */,
                        A00000000000000000000108 /* DeploymentDiagnostics.json */,
                        A00000000000000000000109 /* PrivacyInfo.xcprivacy */,
                        A00000000000000000000402 /* Products */,
                    );
                    sourceTree = "<group>";
                };
                A00000000000000000000402 /* Products */ = {
                    isa = PBXGroup;
                    children = (
                        A00000000000000000000107 /* \(target).app */,
                    );
                    name = Products;
                    sourceTree = "<group>";
                };
        /* End PBXGroup section */

        /* Begin PBXNativeTarget section */
                A00000000000000000000501 /* \(target) */ = {
                    isa = PBXNativeTarget;
                    buildConfigurationList = A00000000000000000000801 /* Build configuration list for PBXNativeTarget "\(target)" */;
                    buildPhases = (
                        A00000000000000000000203 /* Sources */,
                        A00000000000000000000201 /* Frameworks */,
                        A00000000000000000000202 /* Resources */,
                    );
                    buildRules = (
                    );
                    dependencies = (
                    );
                    name = "\(target)";
                    packageProductDependencies = (
                        A00000000000000000000301 /* HypeCore */,
                    );
                    productName = "\(target)";
                    productReference = A00000000000000000000107 /* \(target).app */;
                    productType = "com.apple.product-type.application";
                };
        /* End PBXNativeTarget section */

        /* Begin PBXProject section */
                A00000000000000000000601 /* Project object */ = {
                    isa = PBXProject;
                    attributes = {
                        LastSwiftUpdateCheck = 1700;
                        LastUpgradeCheck = 1700;
                        TargetAttributes = {
                            A00000000000000000000501 = {
                                CreatedOnToolsVersion = 17.0;
                            };
                        };
                    };
                    buildConfigurationList = A00000000000000000000802 /* Build configuration list for PBXProject "HypeRuntimeApp" */;
                    compatibilityVersion = "Xcode 16.0";
                    developmentRegion = en;
                    hasScannedForEncodings = 0;
                    knownRegions = (
                        en,
                        Base,
                    );
                    mainGroup = A00000000000000000000401;
                    minimizedProjectReferenceProxies = 1;
                    packageReferences = (
                        A00000000000000000000302 /* XCLocalSwiftPackageReference "HypeSource" */,
                    );
                    preferredProjectObjectVersion = 77;
                    productRefGroup = A00000000000000000000402 /* Products */;
                    projectDirPath = "";
                    projectRoot = "";
                    targets = (
                        A00000000000000000000501 /* \(target) */,
                    );
                };
        /* End PBXProject section */

        /* Begin PBXResourcesBuildPhase section */
                A00000000000000000000202 /* Resources */ = {
                    isa = PBXResourcesBuildPhase;
                    buildActionMask = 2147483647;
                    files = (
                        A00000000000000000000002 /* RuntimeManifest.json in Resources */,
                        A00000000000000000000003 /* Stack in Resources */,
                        A00000000000000000000004 /* AppIntents.json in Resources */,
                        A00000000000000000000006 /* DeploymentDiagnostics.json in Resources */,
                        A00000000000000000000007 /* PrivacyInfo.xcprivacy in Resources */,
                    );
                    runOnlyForDeploymentPostprocessing = 0;
                };
        /* End PBXResourcesBuildPhase section */

        /* Begin PBXSourcesBuildPhase section */
                A00000000000000000000203 /* Sources */ = {
                    isa = PBXSourcesBuildPhase;
                    buildActionMask = 2147483647;
                    files = (
                        A00000000000000000000001 /* HypeRuntimeApp.swift in Sources */,
                    );
                    runOnlyForDeploymentPostprocessing = 0;
                };
        /* End PBXSourcesBuildPhase section */

        /* Begin XCBuildConfiguration section */
                A00000000000000000000701 /* Debug */ = {
                    isa = XCBuildConfiguration;
                    buildSettings = {
                        ALWAYS_SEARCH_USER_PATHS = NO;
                        CLANG_ANALYZER_NONNULL = YES;
                        CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
                        CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
                        CLANG_ENABLE_MODULES = YES;
                        CLANG_ENABLE_OBJC_ARC = YES;
                        CLANG_ENABLE_OBJC_WEAK = YES;
                        CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
                        CLANG_WARN_BOOL_CONVERSION = YES;
                        CLANG_WARN_COMMA = YES;
                        CLANG_WARN_CONSTANT_CONVERSION = YES;
                        CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
                        CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
                        CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
                        CLANG_WARN_EMPTY_BODY = YES;
                        CLANG_WARN_ENUM_CONVERSION = YES;
                        CLANG_WARN_INFINITE_RECURSION = YES;
                        CLANG_WARN_INT_CONVERSION = YES;
                        CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
                        CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
                        CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
                        CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
                        CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
                        CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
                        CLANG_WARN_STRICT_PROTOTYPES = YES;
                        CLANG_WARN_SUSPICIOUS_MOVE = YES;
                        CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
                        CLANG_WARN_UNREACHABLE_CODE = YES;
                        CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
                        COPY_PHASE_STRIP = NO;
                        DEBUG_INFORMATION_FORMAT = dwarf;
                        ENABLE_STRICT_OBJC_MSGSEND = YES;
                        ENABLE_TESTABILITY = YES;
                        GCC_C_LANGUAGE_STANDARD = gnu17;
                        GCC_DYNAMIC_NO_PIC = NO;
                        GCC_NO_COMMON_BLOCKS = YES;
                        GCC_OPTIMIZATION_LEVEL = 0;
                        GCC_PREPROCESSOR_DEFINITIONS = (
                            "DEBUG=1",
                            "$(inherited)",
                        );
                        GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
                        GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
                        GCC_WARN_UNDECLARED_SELECTOR = YES;
                        GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
                        GCC_WARN_UNUSED_FUNCTION = YES;
                        GCC_WARN_UNUSED_VARIABLE = YES;
                        \(deploymentTargetSetting) = 17.0;
                        SDKROOT = \(sdkRoot);
                        SUPPORTED_PLATFORMS = "\(supportedPlatforms)";
                        SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
                        SWIFT_OPTIMIZATION_LEVEL = "-Onone";
                    };
                    name = Debug;
                };
                A00000000000000000000702 /* Release */ = {
                    isa = XCBuildConfiguration;
                    buildSettings = {
                        ALWAYS_SEARCH_USER_PATHS = NO;
                        CLANG_ANALYZER_NONNULL = YES;
                        CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
                        CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
                        CLANG_ENABLE_MODULES = YES;
                        CLANG_ENABLE_OBJC_ARC = YES;
                        CLANG_ENABLE_OBJC_WEAK = YES;
                        COPY_PHASE_STRIP = NO;
                        DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
                        ENABLE_NS_ASSERTIONS = NO;
                        ENABLE_STRICT_OBJC_MSGSEND = YES;
                        GCC_C_LANGUAGE_STANDARD = gnu17;
                        GCC_NO_COMMON_BLOCKS = YES;
                        GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
                        GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
                        GCC_WARN_UNDECLARED_SELECTOR = YES;
                        GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
                        GCC_WARN_UNUSED_FUNCTION = YES;
                        GCC_WARN_UNUSED_VARIABLE = YES;
                        \(deploymentTargetSetting) = 17.0;
                        SDKROOT = \(sdkRoot);
                        SUPPORTED_PLATFORMS = "\(supportedPlatforms)";
                        SWIFT_COMPILATION_MODE = wholemodule;
                        VALIDATE_PRODUCT = YES;
                    };
                    name = Release;
                };
                A00000000000000000000703 /* Debug */ = {
                    isa = XCBuildConfiguration;
                    buildSettings = {
                        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
                        CODE_SIGN_STYLE = Automatic;
                        CURRENT_PROJECT_VERSION = 1;
                        \(entitlementsSetting)
                        GENERATE_INFOPLIST_FILE = NO;
                        INFOPLIST_FILE = Info.plist;
                        MARKETING_VERSION = 1.0;
                        PRODUCT_BUNDLE_IDENTIFIER = \(bundleID);
                        PRODUCT_NAME = "$(TARGET_NAME)";
                        SWIFT_EMIT_LOC_STRINGS = YES;
                        SWIFT_VERSION = 6.0;
                        TARGETED_DEVICE_FAMILY = "\(family)";
                    };
                    name = Debug;
                };
                A00000000000000000000704 /* Release */ = {
                    isa = XCBuildConfiguration;
                    buildSettings = {
                        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
                        CODE_SIGN_STYLE = Automatic;
                        CURRENT_PROJECT_VERSION = 1;
                        \(entitlementsSetting)
                        GENERATE_INFOPLIST_FILE = NO;
                        INFOPLIST_FILE = Info.plist;
                        MARKETING_VERSION = 1.0;
                        PRODUCT_BUNDLE_IDENTIFIER = \(bundleID);
                        PRODUCT_NAME = "$(TARGET_NAME)";
                        SWIFT_EMIT_LOC_STRINGS = YES;
                        SWIFT_VERSION = 6.0;
                        TARGETED_DEVICE_FAMILY = "\(family)";
                    };
                    name = Release;
                };
        /* End XCBuildConfiguration section */

        /* Begin XCConfigurationList section */
                A00000000000000000000801 /* Build configuration list for PBXNativeTarget "\(target)" */ = {
                    isa = XCConfigurationList;
                    buildConfigurations = (
                        A00000000000000000000703 /* Debug */,
                        A00000000000000000000704 /* Release */,
                    );
                    defaultConfigurationIsVisible = 0;
                    defaultConfigurationName = Release;
                };
                A00000000000000000000802 /* Build configuration list for PBXProject "HypeRuntimeApp" */ = {
                    isa = XCConfigurationList;
                    buildConfigurations = (
                        A00000000000000000000701 /* Debug */,
                        A00000000000000000000702 /* Release */,
                    );
                    defaultConfigurationIsVisible = 0;
                    defaultConfigurationName = Release;
                };
        /* End XCConfigurationList section */

        /* Begin XCLocalSwiftPackageReference section */
                A00000000000000000000302 /* XCLocalSwiftPackageReference "HypeSource" */ = {
                    isa = XCLocalSwiftPackageReference;
                    relativePath = HypeSource;
                };
        /* End XCLocalSwiftPackageReference section */

        /* Begin XCSwiftPackageProductDependency section */
                A00000000000000000000301 /* HypeCore */ = {
                    isa = XCSwiftPackageProductDependency;
                    package = A00000000000000000000302 /* XCLocalSwiftPackageReference "HypeSource" */;
                    productName = HypeCore;
                };
        /* End XCSwiftPackageProductDependency section */
            };
            rootObject = A00000000000000000000601 /* Project object */;
        }
        """
    }

    private func deploymentTargetSetting(for platform: HypeTargetPlatform) -> String {
        switch platform {
        case .tvOS: return "TVOS_DEPLOYMENT_TARGET"
        default: return "IPHONEOS_DEPLOYMENT_TARGET"
        }
    }

    private func sdkRoot(for platform: HypeTargetPlatform) -> String {
        switch platform {
        case .tvOS: return "appletvos"
        default: return "iphoneos"
        }
    }

    private func supportedPlatforms(for platform: HypeTargetPlatform) -> String {
        switch platform {
        case .tvOS: return "appletvos appletvsimulator"
        default: return "iphoneos iphonesimulator"
        }
    }

    private func runtimeReadme(for manifest: HypeRuntimePackageManifest) -> String {
        let iosInstructions: String
        if isIOSRuntimePlatform(manifest.platform) {
            iosInstructions = """

            ## Build and Deploy

            This package includes a generated Xcode project at `RuntimeShell/HypeRuntimeApp.xcodeproj` and a local `RuntimeShell/HypeSource` package containing the HypeCore runtime source needed to compile the app.

            - Build for Simulator: `RuntimeShell/build-ios-simulator.sh`
            - Build for device: `HYPE_DEVELOPMENT_TEAM=YOURTEAMID RuntimeShell/build-ios-device.sh`
            - Install to device: `HYPE_DEVELOPMENT_TEAM=YOURTEAMID HYPE_DEVICE_ID=DEVICE_UDID RuntimeShell/deploy-ios-device.sh`

            Device signing uses Apple's standard Xcode provisioning flow. The deployed app is runtime-only; edit mode and authoring panels are not present.
            """
        } else {
            iosInstructions = ""
        }
        return """
        # \(manifest.stackName) Runtime Package

        Target: \(manifest.platform.displayName)
        Profile: \(manifest.profileName) (\(manifest.profileWidth)x\(manifest.profileHeight))
        Runtime only: \(manifest.runtimeOnly)
        Embedded stack: \(manifest.embeddedStackPath)

        This package intentionally contains runtime shell files and an embedded, self-contained `.hype` stack package. It must not include Hype authoring surfaces, API keys, local model endpoints, or user preferences.
        \(iosInstructions)
        """
    }

    private func replaceItem(at finalURL: URL, with tempURL: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: finalURL.path) {
            try fm.removeItem(at: finalURL)
        }
        try fm.moveItem(at: tempURL, to: finalURL)
    }

    private func escapePlist(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func escapedSwiftString(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
