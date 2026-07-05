import Foundation

#if os(macOS)

/// A simulator device that Hype can target for an exported runtime shell.
public struct HypeSimulatorDevice: Codable, Sendable, Equatable, Identifiable {
    public var id: String { udid }
    public var name: String
    public var udid: String
    public var platform: HypeTargetPlatform
    public var runtimeIdentifier: String
    public var runtimeName: String
    public var deviceTypeIdentifier: String
    public var state: String

    public init(
        name: String,
        udid: String,
        platform: HypeTargetPlatform,
        runtimeIdentifier: String,
        runtimeName: String,
        deviceTypeIdentifier: String,
        state: String
    ) {
        self.name = name
        self.udid = udid
        self.platform = platform
        self.runtimeIdentifier = runtimeIdentifier
        self.runtimeName = runtimeName
        self.deviceTypeIdentifier = deviceTypeIdentifier
        self.state = state
    }

    public var displayName: String {
        "\(name) - \(runtimeName)"
    }

    public var isBooted: Bool {
        state.caseInsensitiveCompare("Booted") == .orderedSame
    }
}

public struct HypeSimulatorCommand: Sendable, Equatable {
    public var executableURL: URL
    public var arguments: [String]
    public var workingDirectory: URL?
    public var environment: [String: String]

    public init(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL? = nil,
        environment: [String: String] = [:]
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
    }
}

public struct HypeSimulatorCommandResult: Sendable, Equatable {
    public var command: HypeSimulatorCommand
    public var terminationStatus: Int32
    public var outputData: Data

    public init(command: HypeSimulatorCommand, terminationStatus: Int32, outputData: Data) {
        self.command = command
        self.terminationStatus = terminationStatus
        self.outputData = outputData
    }

    public var succeeded: Bool {
        terminationStatus == 0
    }

    public var output: String {
        String(data: outputData, encoding: .utf8) ?? ""
    }

    public func clippedOutput(limit: Int = 12_000) -> String {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > limit else { return text }
        let headCount = limit / 2
        let tailCount = limit - headCount
        let headEnd = text.index(text.startIndex, offsetBy: headCount)
        let tailStart = text.index(text.endIndex, offsetBy: -tailCount)
        return String(text[..<headEnd])
            + "\n... output truncated; showing final diagnostics ...\n"
            + String(text[tailStart...])
    }
}

public protocol HypeSimulatorCommandRunning: Sendable {
    func run(_ command: HypeSimulatorCommand) async throws -> HypeSimulatorCommandResult
}

public struct HypeSimulatorProcessRunner: HypeSimulatorCommandRunning, Sendable {
    public init() {}

    public func run(_ command: HypeSimulatorCommand) async throws -> HypeSimulatorCommandResult {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = command.executableURL
            process.arguments = command.arguments
            process.currentDirectoryURL = command.workingDirectory
            if !command.environment.isEmpty {
                var environment = ProcessInfo.processInfo.environment
                command.environment.forEach { environment[$0.key] = $0.value }
                process.environment = environment
            }

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            try process.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            return HypeSimulatorCommandResult(
                command: command,
                terminationStatus: process.terminationStatus,
                outputData: output
            )
        }.value
    }
}

public enum HypeSimulatorLauncherError: LocalizedError, Equatable, Sendable {
    case unsupportedPlatform(HypeTargetPlatform)
    case noDeploymentPlan(HypeTargetPlatform)
    case noDevices(HypeTargetPlatform)
    case invalidSimctlJSON(String)
    case missingAppTargetName
    case missingXcodeProject(URL)
    case missingBuildProduct(URL)
    case commandFailed(executable: String, arguments: [String], status: Int32, output: String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedPlatform(let platform):
            return "\(platform.displayName) does not run in Apple Simulator. Select iPhone, iPad, or tvOS."
        case .noDeploymentPlan(let platform):
            return "The stack does not include \(platform.displayName) as a selected deployment target."
        case .noDevices(let platform):
            return "No available \(platform.displayName) simulator devices were found. Install the platform runtime with Xcode's command-line tools or Xcode Settings."
        case .invalidSimctlJSON(let reason):
            return "Could not read simulator devices from simctl JSON: \(reason)"
        case .missingAppTargetName:
            return "The runtime package manifest did not include an app target name."
        case .missingXcodeProject(let url):
            return "The runtime package is missing its generated Xcode project at \(url.path)."
        case .missingBuildProduct(let url):
            return "The simulator build completed but the app bundle was not found at \(url.path)."
        case .commandFailed(let executable, let arguments, let status, let output):
            let command = ([executable] + arguments).joined(separator: " ")
            return "Command failed with status \(status): \(command)\n\(output)"
        }
    }
}

public struct HypeSimulatorLaunchResult: Sendable, Equatable {
    public var packageURL: URL
    public var appBundleURL: URL
    public var manifest: HypeRuntimePackageManifest
    public var device: HypeSimulatorDevice

    public init(
        packageURL: URL,
        appBundleURL: URL,
        manifest: HypeRuntimePackageManifest,
        device: HypeSimulatorDevice
    ) {
        self.packageURL = packageURL
        self.appBundleURL = appBundleURL
        self.manifest = manifest
        self.device = device
    }
}

/// Builds a target runtime package and launches it in a selected Apple Simulator.
///
/// This intentionally shells out only through explicit executable URLs plus
/// argument arrays. Hype never interpolates stack names, bundle IDs, paths, or
/// simulator UDIDs into `/bin/sh -c`.
public actor HypeSimulatorRuntimeLauncher {
    private let commandRunner: any HypeSimulatorCommandRunning
    private let packageBuilder: TargetRuntimePackageBuilder
    private let deploymentPlanner: StackDeploymentPlanner
    private let fileManager: FileManager

    public init(
        commandRunner: any HypeSimulatorCommandRunning = HypeSimulatorProcessRunner(),
        packageBuilder: TargetRuntimePackageBuilder = TargetRuntimePackageBuilder(),
        deploymentPlanner: StackDeploymentPlanner = StackDeploymentPlanner(),
        fileManager: FileManager = .default
    ) {
        self.commandRunner = commandRunner
        self.packageBuilder = packageBuilder
        self.deploymentPlanner = deploymentPlanner
        self.fileManager = fileManager
    }

    public func availableDevices() async throws -> [HypeSimulatorDevice] {
        let result = try await commandRunner.run(
            HypeSimulatorCommand(
                executableURL: Self.xcrunURL,
                arguments: ["simctl", "list", "devices", "available", "--json"]
            )
        )
        try ensureSuccess(result)
        return try Self.decodeAvailableDevices(from: result.outputData)
    }

    public func availableDevices(for platform: HypeTargetPlatform) async throws -> [HypeSimulatorDevice] {
        guard Self.supportsSimulator(platform) else {
            throw HypeSimulatorLauncherError.unsupportedPlatform(platform)
        }
        let allDevices = try await availableDevices()
        let devices = allDevices.filter { $0.platform == platform }
        guard !devices.isEmpty else {
            throw HypeSimulatorLauncherError.noDevices(platform)
        }
        return devices
    }

    public func launch(
        document: HypeDocument,
        platform: HypeTargetPlatform,
        device: HypeSimulatorDevice,
        outputDirectory: URL? = nil
    ) async throws -> HypeSimulatorLaunchResult {
        guard Self.supportsSimulator(platform) else {
            throw HypeSimulatorLauncherError.unsupportedPlatform(platform)
        }
        guard device.platform == platform else {
            throw HypeSimulatorLauncherError.noDevices(platform)
        }
        guard let plan = deploymentPlanner.plans(for: document).first(where: { $0.platform == platform }) else {
            throw HypeSimulatorLauncherError.noDeploymentPlan(platform)
        }

        let output = outputDirectory ?? defaultOutputDirectory(stackId: document.stack.id)
        let package = try packageBuilder.buildPackage(for: document, plan: plan, at: output)
        let manifest = package.manifest
        guard let targetName = manifest.appTargetName else {
            throw HypeSimulatorLauncherError.missingAppTargetName
        }

        let shellDirectory = package.packageURL.appendingPathComponent(
            TargetRuntimePackageBuilder.shellDirectoryName,
            isDirectory: true
        )
        let projectURL = shellDirectory.appendingPathComponent("HypeRuntimeApp.xcodeproj", isDirectory: true)
        guard fileManager.fileExists(atPath: projectURL.appendingPathComponent("project.pbxproj").path) else {
            throw HypeSimulatorLauncherError.missingXcodeProject(projectURL)
        }

        let derivedDataURL = shellDirectory
            .appendingPathComponent("Build", isDirectory: true)
            .appendingPathComponent("DerivedData", isDirectory: true)
        let sdk = Self.simulatorSDK(for: platform)

        try await runRequired(
            executableURL: Self.xcrunURL,
            arguments: [
                "xcodebuild",
                "-project", projectURL.path,
                "-scheme", targetName,
                "-configuration", "Debug",
                "-destination", "id=\(device.udid)",
                "-sdk", sdk,
                "-derivedDataPath", derivedDataURL.path,
                "CODE_SIGNING_ALLOWED=NO",
                "build",
            ],
            workingDirectory: shellDirectory
        )

        let appBundleURL = derivedDataURL
            .appendingPathComponent("Build", isDirectory: true)
            .appendingPathComponent("Products", isDirectory: true)
            .appendingPathComponent(Self.simulatorProductDirectory(for: platform), isDirectory: true)
            .appendingPathComponent("\(targetName).app", isDirectory: true)
        guard fileManager.fileExists(atPath: appBundleURL.path) else {
            throw HypeSimulatorLauncherError.missingBuildProduct(appBundleURL)
        }

        try await boot(device)
        await openSimulatorUI(for: device)
        try await runRequired(
            executableURL: Self.xcrunURL,
            arguments: ["simctl", "install", device.udid, appBundleURL.path]
        )
        try await runRequired(
            executableURL: Self.xcrunURL,
            arguments: ["simctl", "launch", device.udid, manifest.bundleIdentifier]
        )

        return HypeSimulatorLaunchResult(
            packageURL: package.packageURL,
            appBundleURL: appBundleURL,
            manifest: manifest,
            device: device
        )
    }

    private func openSimulatorUI(for device: HypeSimulatorDevice) async {
        _ = try? await commandRunner.run(
            HypeSimulatorCommand(
                executableURL: Self.openURL,
                arguments: ["-a", "Simulator", "--args", "-CurrentDeviceUDID", device.udid]
            )
        )
    }

    public static func decodeAvailableDevices(from data: Data) throws -> [HypeSimulatorDevice] {
        do {
            let payload = try JSONDecoder().decode(SimctlDeviceList.self, from: data)
            return payload.devices.flatMap { runtimeIdentifier, devices in
                devices.compactMap { raw -> HypeSimulatorDevice? in
                    guard raw.isAvailable,
                          let platform = platform(forRuntimeIdentifier: runtimeIdentifier, rawDevice: raw),
                          supportsSimulator(platform) else { return nil }
                    return HypeSimulatorDevice(
                        name: raw.name,
                        udid: raw.udid,
                        platform: platform,
                        runtimeIdentifier: runtimeIdentifier,
                        runtimeName: runtimeDisplayName(runtimeIdentifier),
                        deviceTypeIdentifier: raw.deviceTypeIdentifier,
                        state: raw.state
                    )
                }
            }
            .sorted(by: simulatorSort)
        } catch {
            throw HypeSimulatorLauncherError.invalidSimctlJSON(error.localizedDescription)
        }
    }

    public static func preferredDevice(
        from devices: [HypeSimulatorDevice],
        for platform: HypeTargetPlatform
    ) -> HypeSimulatorDevice? {
        devices
            .filter { $0.platform == platform }
            .sorted(by: simulatorSort)
            .first
    }

    public static func supportsSimulator(_ platform: HypeTargetPlatform) -> Bool {
        platform == .iPhone || platform == .iPad || platform == .tvOS
    }

    private func boot(_ device: HypeSimulatorDevice) async throws {
        let result = try await commandRunner.run(
            HypeSimulatorCommand(
                executableURL: Self.xcrunURL,
                arguments: ["simctl", "boot", device.udid]
            )
        )
        if result.succeeded || result.output.localizedCaseInsensitiveContains("current state: Booted") {
            return
        }
        throw commandError(result)
    }

    private func runRequired(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL? = nil
    ) async throws {
        let result = try await commandRunner.run(
            HypeSimulatorCommand(
                executableURL: executableURL,
                arguments: arguments,
                workingDirectory: workingDirectory
            )
        )
        try ensureSuccess(result)
    }

    private func ensureSuccess(_ result: HypeSimulatorCommandResult) throws {
        guard result.succeeded else {
            throw commandError(result)
        }
    }

    private func commandError(_ result: HypeSimulatorCommandResult) -> HypeSimulatorLauncherError {
        HypeSimulatorLauncherError.commandFailed(
            executable: result.command.executableURL.path,
            arguments: result.command.arguments,
            status: result.terminationStatus,
            output: result.clippedOutput()
        )
    }

    private func defaultOutputDirectory(stackId: UUID) -> URL {
        fileManager.temporaryDirectory
            .appendingPathComponent("HypeSimulatorLaunches", isDirectory: true)
            .appendingPathComponent(stackId.uuidString, isDirectory: true)
    }

    private static let xcrunURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    private static let openURL = URL(fileURLWithPath: "/usr/bin/open")

    private static func simulatorSDK(for platform: HypeTargetPlatform) -> String {
        platform == .tvOS ? "appletvsimulator" : "iphonesimulator"
    }

    private static func simulatorProductDirectory(for platform: HypeTargetPlatform) -> String {
        platform == .tvOS ? "Debug-appletvsimulator" : "Debug-iphonesimulator"
    }

    private static func platform(
        forRuntimeIdentifier runtimeIdentifier: String,
        rawDevice: SimctlDevice
    ) -> HypeTargetPlatform? {
        let runtime = runtimeIdentifier.lowercased()
        let type = rawDevice.deviceTypeIdentifier.lowercased()
        let name = rawDevice.name.lowercased()

        if runtime.contains("tvos") || type.contains("apple-tv") || name.contains("apple tv") {
            return .tvOS
        }
        if runtime.contains("ios") {
            if type.contains("ipad") || name.hasPrefix("ipad") {
                return .iPad
            }
            if type.contains("iphone") || name.hasPrefix("iphone") {
                return .iPhone
            }
        }
        return nil
    }

    private static func runtimeDisplayName(_ runtimeIdentifier: String) -> String {
        let raw = runtimeIdentifier
            .replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
        let components = raw.split(separator: "-").map(String.init)
        guard let family = components.first else { return runtimeIdentifier }
        let version = components.dropFirst().joined(separator: ".")
        return version.isEmpty ? family : "\(family) \(version)"
    }

    private static func simulatorSort(_ lhs: HypeSimulatorDevice, _ rhs: HypeSimulatorDevice) -> Bool {
        if lhs.platform != rhs.platform {
            return platformRank(lhs.platform) < platformRank(rhs.platform)
        }
        if lhs.isBooted != rhs.isBooted {
            return lhs.isBooted
        }
        let runtimeCompare = lhs.runtimeIdentifier.localizedStandardCompare(rhs.runtimeIdentifier)
        if runtimeCompare != .orderedSame {
            return runtimeCompare == .orderedDescending
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private static func platformRank(_ platform: HypeTargetPlatform) -> Int {
        switch platform {
        case .macOS: return 0
        case .iPhone: return 1
        case .iPad: return 2
        case .tvOS: return 3
        }
    }
}

private struct SimctlDeviceList: Decodable {
    var devices: [String: [SimctlDevice]]
}

private struct SimctlDevice: Decodable {
    var name: String
    var udid: String
    var isAvailable: Bool
    var deviceTypeIdentifier: String
    var state: String
}

#endif
