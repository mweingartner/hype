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
        self.generatedAt = generatedAt
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

    public var errorDescription: String? {
        switch self {
        case .invalidPackageName:
            return "The stack name cannot be converted to a safe runtime package name."
        case .packageValidationFailed(let message):
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
        let packageName = try runtimePackageName(stackName: document.stack.name, platform: plan.platform)
        let finalURL = outputDirectory.appendingPathComponent(packageName, isDirectory: true)
        let tempURL = outputDirectory.appendingPathComponent(".\(packageName)-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: tempURL, withIntermediateDirectories: true)

        do {
            let manifest = makeManifest(for: document, plan: plan)
            var generatedFiles: [String] = []

            let stackDir = tempURL.appendingPathComponent(Self.stackDirectoryName, isDirectory: true)
            try fm.createDirectory(at: stackDir, withIntermediateDirectories: true)
            let embeddedStackURL = stackDir.appendingPathComponent(Self.embeddedStackName, isDirectory: true)
            try stackStore.save(planner.runtimeDocument(forDeployment: document), toPackageAt: embeddedStackURL)
            generatedFiles.append("\(Self.stackDirectoryName)/\(Self.embeddedStackName)/\(HypeSQLiteStackStore.manifestFileName)")
            generatedFiles.append("\(Self.stackDirectoryName)/\(Self.embeddedStackName)/\(HypeSQLiteStackStore.sqliteFileName)")

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(to: tempURL.appendingPathComponent(Self.manifestFileName), options: [.atomic])
            generatedFiles.append(Self.manifestFileName)

            let shellDir = tempURL.appendingPathComponent(Self.shellDirectoryName, isDirectory: true)
            try fm.createDirectory(at: shellDir, withIntermediateDirectories: true)
            try writeShellFiles(for: document, plan: plan, manifest: manifest, shellDir: shellDir, generatedFiles: &generatedFiles)

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
            bundleIdentifier: bundleIdentifier(stackName: document.stack.name, platform: plan.platform)
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

        let entitlements = entitlementsPlist(for: manifest.requiredEntitlements)
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

    private func bundleIdentifier(stackName: String, platform: HypeTargetPlatform) -> String {
        let component = sanitizeIdentifier(stackName, lowercase: true).lowercased()
        let safeComponent = component.isEmpty ? "stack" : component
        return "com.hype.runtime.\(safeComponent).\(platform.rawValue.lowercased())"
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
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>\(manifest.bundleIdentifier)</string>
            <key>CFBundleName</key>
            <string>\(escapePlist(manifest.stackName))</string>
            <key>HypeRuntimeOnly</key>
            <true/>
            <key>HypeRuntimeManifest</key>
            <string>\(Self.manifestFileName)</string>
            <key>HypeEmbeddedStackPath</key>
            <string>\(manifest.embeddedStackPath)</string>
            <key>HypeTargetPlatform</key>
            <string>\(manifest.platform.rawValue)</string>
        </dict>
        </plist>
        """
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

    private func runtimeShellSource(for document: HypeDocument, manifest: HypeRuntimePackageManifest) -> String {
        let appName = sanitizeIdentifier(document.stack.name, lowercase: false).replacingOccurrences(of: "-", with: "")
        let safeAppName = appName.isEmpty ? "HypeStack" : appName
        return """
        import Foundation
        import SwiftUI
        import HypeCore
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
                        embeddedStackPath: "\(manifest.embeddedStackPath)"
                    )
                }
            }
        }

        struct HypeRuntimeRootView: View {
            let stackName: String
            let targetPlatform: String
            let embeddedStackPath: String

            var body: some View {
                HypeStackRuntimeShellView(
                    stackName: stackName,
                    targetPlatform: targetPlatform,
                    embeddedStackPath: embeddedStackPath
                )
            }
        }

        struct HypeStackRuntimeShellView: View {
            let stackName: String
            let targetPlatform: String
            let embeddedStackPath: String
            @StateObject private var model = HypeRuntimeDocumentModel()

            var body: some View {
                Group {
                    if let document = model.document {
                        HypeRuntimeCardView(document: document)
                    } else if let loadError = model.loadError {
                        Text(loadError)
                            .foregroundStyle(.red)
                    } else {
                        ProgressView("Loading \\(stackName)")
                    }
                }
                .accessibilityLabel("Hype runtime stack \\(stackName) for \\(targetPlatform)")
                .task {
                    model.load(embeddedStackPath: embeddedStackPath)
                }
            }
        }

        @MainActor
        final class HypeRuntimeDocumentModel: ObservableObject {
            @Published var document: HypeDocument?
            @Published var loadError: String?

            func load(embeddedStackPath: String) {
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
                    document = loaded
                } catch {
                    loadError = "Could not load embedded Hype stack: \\(error.localizedDescription)"
                }
            }
        }

        struct HypeRuntimeCardView: View {
            let document: HypeDocument

            var body: some View {
                let card = document.sortedCards.first
                ZStack(alignment: .topLeading) {
                    Color.white
                    if let card {
                        ForEach(document.effectivePartsForCard(card.id)) { part in
                            HypeRuntimePartView(part: part)
                        }
                    }
                }
                .frame(width: CGFloat(document.stack.width), height: CGFloat(document.stack.height))
            }
        }

        struct HypeRuntimePartView: View {
            let part: Part

            var body: some View {
                Group {
                    switch part.partType {
                    case .button:
                        Button(part.showName ? part.name : part.textContent) {}
                    case .field:
                        Text(part.textContent)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    case .shape:
                        RoundedRectangle(cornerRadius: part.cornerRadius)
                            .fill(Color(hex: part.fillColor))
                    case .image:
                        if let data = part.imageData, let image = PlatformImage(data: data) {
                            PlatformImageView(image: image)
                        } else {
                            Rectangle().fill(Color.gray.opacity(0.2))
                        }
                    default:
                        Text(part.name)
                    }
                }
                .frame(width: CGFloat(part.width), height: CGFloat(part.height))
                .position(x: CGFloat(part.left + part.width / 2), y: CGFloat(part.top + part.height / 2))
                .opacity(part.visible ? 1 : 0)
                .accessibilityLabel(part.name)
            }
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

    private func runtimeReadme(for manifest: HypeRuntimePackageManifest) -> String {
        """
        # \(manifest.stackName) Runtime Package

        Target: \(manifest.platform.displayName)
        Profile: \(manifest.profileName) (\(manifest.profileWidth)x\(manifest.profileHeight))
        Runtime only: \(manifest.runtimeOnly)
        Embedded stack: \(manifest.embeddedStackPath)

        This package intentionally contains runtime shell files and an embedded, self-contained `.hype` stack package. It must not include Hype authoring surfaces, API keys, local model endpoints, or user preferences.
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
