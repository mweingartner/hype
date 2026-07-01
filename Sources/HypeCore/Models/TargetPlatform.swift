import Foundation

/// Deployment platforms a stack can target.
///
/// `iPhone` and `iPad` are intentionally separate even though both are iOS
/// family runtimes: their default form factors, safe areas, and layout
/// expectations are different enough that Hype treats them as distinct design
/// targets.
public enum HypeTargetPlatform: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case macOS
    case iPhone
    case iPad
    case tvOS

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .macOS: return "macOS"
        case .iPhone: return "iPhone"
        case .iPad: return "iPad"
        case .tvOS: return "tvOS"
        }
    }

    public var defaultProfileId: String {
        switch self {
        case .macOS: return "macos-default"
        case .iPhone: return "iphone-portrait"
        case .iPad: return "ipad-portrait"
        case .tvOS: return "tvos-1080p"
        }
    }

    public static func parse(_ raw: String) -> HypeTargetPlatform? {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
        switch normalized {
        case "macos", "mac":
            return .macOS
        case "iphone", "iosphone":
            return .iPhone
        case "ipad", "iospad":
            return .iPad
        case "tvos", "tv":
            return .tvOS
        default:
            return nil
        }
    }

    public static func parseList(_ raw: String) -> [HypeTargetPlatform]? {
        let platforms = raw
            .split { $0 == "," || $0 == ";" || $0 == " " || $0 == "\n" || $0 == "\t" }
            .map(String.init)
        guard !platforms.isEmpty else { return nil }
        let parsed = platforms.compactMap(parse)
        guard parsed.count == platforms.count else { return nil }
        return parsed
    }
}

public enum HypeTargetOrientation: String, Codable, CaseIterable, Sendable, Hashable {
    case portrait
    case landscape
    case resizable
}

public enum HypeInputModel: String, Codable, CaseIterable, Sendable, Hashable {
    case pointerKeyboard
    case touch
    case focusRemote
}

public enum TargetLayoutPolicy: String, Codable, CaseIterable, Sendable, Hashable {
    /// Preserve persisted absolute coordinates, only offsetting into target safe areas.
    case fixed
    /// Uniformly scale the authored card into the target safe area and center it.
    case scaleToFit
    /// Scale X and Y independently so the authored card fills the target safe area.
    case stretchToFill

    public static func parse(_ raw: String) -> TargetLayoutPolicy? {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
        switch normalized {
        case "fixed", "absolute":
            return .fixed
        case "scaletofit", "fit", "uniform":
            return .scaleToFit
        case "stretchtofill", "stretch", "fill":
            return .stretchToFill
        default:
            return nil
        }
    }
}

public struct HypeSafeAreaInsets: Codable, Sendable, Equatable {
    public var top: Double
    public var left: Double
    public var bottom: Double
    public var right: Double

    public init(top: Double = 0, left: Double = 0, bottom: Double = 0, right: Double = 0) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }
}

public struct HypeDeviceProfile: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var platform: HypeTargetPlatform
    public var displayName: String
    public var width: Int
    public var height: Int
    public var orientation: HypeTargetOrientation
    public var inputModel: HypeInputModel
    public var safeArea: HypeSafeAreaInsets
    public var scale: Double

    public init(
        id: String,
        platform: HypeTargetPlatform,
        displayName: String,
        width: Int,
        height: Int,
        orientation: HypeTargetOrientation,
        inputModel: HypeInputModel,
        safeArea: HypeSafeAreaInsets = HypeSafeAreaInsets(),
        scale: Double = 1
    ) {
        self.id = id
        self.platform = platform
        self.displayName = displayName
        self.width = width
        self.height = height
        self.orientation = orientation
        self.inputModel = inputModel
        self.safeArea = safeArea
        self.scale = scale
    }
}

public enum HypeDeviceProfileCatalog {
    public static let standardProfiles: [HypeDeviceProfile] = [
        HypeDeviceProfile(
            id: "macos-default",
            platform: .macOS,
            displayName: "macOS Default Card",
            width: 800,
            height: 600,
            orientation: .resizable,
            inputModel: .pointerKeyboard
        ),
        HypeDeviceProfile(
            id: "iphone-portrait",
            platform: .iPhone,
            displayName: "iPhone Portrait",
            width: 393,
            height: 852,
            orientation: .portrait,
            inputModel: .touch,
            safeArea: HypeSafeAreaInsets(top: 59, left: 0, bottom: 34, right: 0),
            scale: 3
        ),
        HypeDeviceProfile(
            id: "iphone-landscape",
            platform: .iPhone,
            displayName: "iPhone Landscape",
            width: 852,
            height: 393,
            orientation: .landscape,
            inputModel: .touch,
            safeArea: HypeSafeAreaInsets(top: 0, left: 59, bottom: 21, right: 59),
            scale: 3
        ),
        HypeDeviceProfile(
            id: "ipad-portrait",
            platform: .iPad,
            displayName: "iPad Portrait",
            width: 820,
            height: 1180,
            orientation: .portrait,
            inputModel: .touch,
            safeArea: HypeSafeAreaInsets(top: 24, left: 0, bottom: 20, right: 0),
            scale: 2
        ),
        HypeDeviceProfile(
            id: "ipad-landscape",
            platform: .iPad,
            displayName: "iPad Landscape",
            width: 1180,
            height: 820,
            orientation: .landscape,
            inputModel: .touch,
            safeArea: HypeSafeAreaInsets(top: 24, left: 0, bottom: 20, right: 0),
            scale: 2
        ),
        HypeDeviceProfile(
            id: "iphone-17-pro-portrait",
            platform: .iPhone,
            displayName: "iPhone 17 Pro Portrait",
            width: 402,
            height: 874,
            orientation: .portrait,
            inputModel: .touch,
            safeArea: HypeSafeAreaInsets(top: 59, left: 0, bottom: 34, right: 0),
            scale: 3
        ),
        HypeDeviceProfile(
            id: "iphone-17-pro-landscape",
            platform: .iPhone,
            displayName: "iPhone 17 Pro Landscape",
            width: 874,
            height: 402,
            orientation: .landscape,
            inputModel: .touch,
            safeArea: HypeSafeAreaInsets(top: 0, left: 59, bottom: 21, right: 59),
            scale: 3
        ),
        HypeDeviceProfile(
            id: "iphone-17-pro-max-portrait",
            platform: .iPhone,
            displayName: "iPhone 17 Pro Max Portrait",
            width: 440,
            height: 956,
            orientation: .portrait,
            inputModel: .touch,
            safeArea: HypeSafeAreaInsets(top: 59, left: 0, bottom: 34, right: 0),
            scale: 3
        ),
        HypeDeviceProfile(
            id: "iphone-17-pro-max-landscape",
            platform: .iPhone,
            displayName: "iPhone 17 Pro Max Landscape",
            width: 956,
            height: 440,
            orientation: .landscape,
            inputModel: .touch,
            safeArea: HypeSafeAreaInsets(top: 0, left: 59, bottom: 21, right: 59),
            scale: 3
        ),
        HypeDeviceProfile(
            id: "iphone-air-portrait",
            platform: .iPhone,
            displayName: "iPhone Air Portrait",
            width: 420,
            height: 912,
            orientation: .portrait,
            inputModel: .touch,
            safeArea: HypeSafeAreaInsets(top: 59, left: 0, bottom: 34, right: 0),
            scale: 3
        ),
        HypeDeviceProfile(
            id: "iphone-air-landscape",
            platform: .iPhone,
            displayName: "iPhone Air Landscape",
            width: 912,
            height: 420,
            orientation: .landscape,
            inputModel: .touch,
            safeArea: HypeSafeAreaInsets(top: 0, left: 59, bottom: 21, right: 59),
            scale: 3
        ),
        HypeDeviceProfile(
            id: "iphone-17-portrait",
            platform: .iPhone,
            displayName: "iPhone 17 Portrait",
            width: 402,
            height: 874,
            orientation: .portrait,
            inputModel: .touch,
            safeArea: HypeSafeAreaInsets(top: 59, left: 0, bottom: 34, right: 0),
            scale: 3
        ),
        HypeDeviceProfile(
            id: "iphone-17-landscape",
            platform: .iPhone,
            displayName: "iPhone 17 Landscape",
            width: 874,
            height: 402,
            orientation: .landscape,
            inputModel: .touch,
            safeArea: HypeSafeAreaInsets(top: 0, left: 59, bottom: 21, right: 59),
            scale: 3
        ),
        HypeDeviceProfile(
            id: "iphone-17e-portrait",
            platform: .iPhone,
            displayName: "iPhone 17e Portrait",
            width: 390,
            height: 844,
            orientation: .portrait,
            inputModel: .touch,
            safeArea: HypeSafeAreaInsets(top: 47, left: 0, bottom: 34, right: 0),
            scale: 3
        ),
        HypeDeviceProfile(
            id: "iphone-17e-landscape",
            platform: .iPhone,
            displayName: "iPhone 17e Landscape",
            width: 844,
            height: 390,
            orientation: .landscape,
            inputModel: .touch,
            safeArea: HypeSafeAreaInsets(top: 0, left: 47, bottom: 21, right: 47),
            scale: 3
        ),
        HypeDeviceProfile(
            id: "iphone-16-portrait",
            platform: .iPhone,
            displayName: "iPhone 16 Portrait",
            width: 393,
            height: 852,
            orientation: .portrait,
            inputModel: .touch,
            safeArea: HypeSafeAreaInsets(top: 59, left: 0, bottom: 34, right: 0),
            scale: 3
        ),
        HypeDeviceProfile(
            id: "iphone-16-landscape",
            platform: .iPhone,
            displayName: "iPhone 16 Landscape",
            width: 852,
            height: 393,
            orientation: .landscape,
            inputModel: .touch,
            safeArea: HypeSafeAreaInsets(top: 0, left: 59, bottom: 21, right: 59),
            scale: 3
        ),
        HypeDeviceProfile(
            id: "iphone-16-plus-portrait",
            platform: .iPhone,
            displayName: "iPhone 16 Plus Portrait",
            width: 430,
            height: 932,
            orientation: .portrait,
            inputModel: .touch,
            safeArea: HypeSafeAreaInsets(top: 59, left: 0, bottom: 34, right: 0),
            scale: 3
        ),
        HypeDeviceProfile(
            id: "iphone-16-plus-landscape",
            platform: .iPhone,
            displayName: "iPhone 16 Plus Landscape",
            width: 932,
            height: 430,
            orientation: .landscape,
            inputModel: .touch,
            safeArea: HypeSafeAreaInsets(top: 0, left: 59, bottom: 21, right: 59),
            scale: 3
        ),
        HypeDeviceProfile(
            id: "ipad-pro-13-m5-portrait",
            platform: .iPad,
            displayName: "iPad Pro 13-inch (M5) Portrait",
            width: 1032,
            height: 1376,
            orientation: .portrait,
            inputModel: .touch,
            safeArea: HypeSafeAreaInsets(top: 24, left: 0, bottom: 20, right: 0),
            scale: 2
        ),
        HypeDeviceProfile(
            id: "ipad-pro-13-m5-landscape",
            platform: .iPad,
            displayName: "iPad Pro 13-inch (M5) Landscape",
            width: 1376,
            height: 1032,
            orientation: .landscape,
            inputModel: .touch,
            safeArea: HypeSafeAreaInsets(top: 24, left: 0, bottom: 20, right: 0),
            scale: 2
        ),
        HypeDeviceProfile(
            id: "ipad-pro-11-m5-portrait",
            platform: .iPad,
            displayName: "iPad Pro 11-inch (M5) Portrait",
            width: 834,
            height: 1210,
            orientation: .portrait,
            inputModel: .touch,
            safeArea: HypeSafeAreaInsets(top: 24, left: 0, bottom: 20, right: 0),
            scale: 2
        ),
        HypeDeviceProfile(
            id: "ipad-pro-11-m5-landscape",
            platform: .iPad,
            displayName: "iPad Pro 11-inch (M5) Landscape",
            width: 1210,
            height: 834,
            orientation: .landscape,
            inputModel: .touch,
            safeArea: HypeSafeAreaInsets(top: 24, left: 0, bottom: 20, right: 0),
            scale: 2
        ),
        HypeDeviceProfile(
            id: "ipad-air-13-m4-portrait",
            platform: .iPad,
            displayName: "iPad Air 13-inch (M4) Portrait",
            width: 1024,
            height: 1366,
            orientation: .portrait,
            inputModel: .touch,
            safeArea: HypeSafeAreaInsets(top: 24, left: 0, bottom: 20, right: 0),
            scale: 2
        ),
        HypeDeviceProfile(
            id: "ipad-air-13-m4-landscape",
            platform: .iPad,
            displayName: "iPad Air 13-inch (M4) Landscape",
            width: 1366,
            height: 1024,
            orientation: .landscape,
            inputModel: .touch,
            safeArea: HypeSafeAreaInsets(top: 24, left: 0, bottom: 20, right: 0),
            scale: 2
        ),
        HypeDeviceProfile(
            id: "ipad-air-11-m4-portrait",
            platform: .iPad,
            displayName: "iPad Air 11-inch (M4) Portrait",
            width: 820,
            height: 1180,
            orientation: .portrait,
            inputModel: .touch,
            safeArea: HypeSafeAreaInsets(top: 24, left: 0, bottom: 20, right: 0),
            scale: 2
        ),
        HypeDeviceProfile(
            id: "ipad-air-11-m4-landscape",
            platform: .iPad,
            displayName: "iPad Air 11-inch (M4) Landscape",
            width: 1180,
            height: 820,
            orientation: .landscape,
            inputModel: .touch,
            safeArea: HypeSafeAreaInsets(top: 24, left: 0, bottom: 20, right: 0),
            scale: 2
        ),
        HypeDeviceProfile(
            id: "ipad-a16-portrait",
            platform: .iPad,
            displayName: "iPad (A16) Portrait",
            width: 820,
            height: 1180,
            orientation: .portrait,
            inputModel: .touch,
            safeArea: HypeSafeAreaInsets(top: 24, left: 0, bottom: 20, right: 0),
            scale: 2
        ),
        HypeDeviceProfile(
            id: "ipad-a16-landscape",
            platform: .iPad,
            displayName: "iPad (A16) Landscape",
            width: 1180,
            height: 820,
            orientation: .landscape,
            inputModel: .touch,
            safeArea: HypeSafeAreaInsets(top: 24, left: 0, bottom: 20, right: 0),
            scale: 2
        ),
        HypeDeviceProfile(
            id: "ipad-mini-a17-pro-portrait",
            platform: .iPad,
            displayName: "iPad mini (A17 Pro) Portrait",
            width: 744,
            height: 1133,
            orientation: .portrait,
            inputModel: .touch,
            safeArea: HypeSafeAreaInsets(top: 24, left: 0, bottom: 20, right: 0),
            scale: 2
        ),
        HypeDeviceProfile(
            id: "ipad-mini-a17-pro-landscape",
            platform: .iPad,
            displayName: "iPad mini (A17 Pro) Landscape",
            width: 1133,
            height: 744,
            orientation: .landscape,
            inputModel: .touch,
            safeArea: HypeSafeAreaInsets(top: 24, left: 0, bottom: 20, right: 0),
            scale: 2
        ),
        HypeDeviceProfile(
            id: "tvos-1080p",
            platform: .tvOS,
            displayName: "tvOS 1080p",
            width: 1920,
            height: 1080,
            orientation: .landscape,
            inputModel: .focusRemote,
            safeArea: HypeSafeAreaInsets(top: 60, left: 90, bottom: 60, right: 90)
        ),
    ]

    public static func profile(id: String) -> HypeDeviceProfile? {
        standardProfiles.first { $0.id == id }
    }

    public static func defaultProfile(for platform: HypeTargetPlatform) -> HypeDeviceProfile {
        profile(id: platform.defaultProfileId) ?? standardProfiles[0]
    }

    public static func profiles(for platforms: [HypeTargetPlatform]) -> [HypeDeviceProfile] {
        let selected = Set(platforms)
        return standardProfiles.filter { selected.contains($0.platform) }
    }
}

public struct StackDeploymentTargets: Codable, Sendable, Equatable {
    public var selectedPlatforms: [HypeTargetPlatform]
    public var primaryPlatform: HypeTargetPlatform
    public var selectionPromptAcknowledged: Bool
    public var supportedOrientations: [HypeTargetOrientation]
    /// The active layout policy for this deployment target set.
    ///
    /// This property stores the value verbatim at decode time — the caller is
    /// responsible for clamping or defaulting via `clampedLayoutPolicy(_:)` or
    /// `defaultedLayoutPolicy(_:)` at mutation sites. Do not apply policy
    /// normalization inside `init`, `decode`, or `normalize()`.
    public var layoutPolicy: TargetLayoutPolicy

    public init(
        selectedPlatforms: [HypeTargetPlatform] = [.macOS],
        primaryPlatform: HypeTargetPlatform = .macOS,
        selectionPromptAcknowledged: Bool = false,
        supportedOrientations: [HypeTargetOrientation] = [.resizable],
        layoutPolicy: TargetLayoutPolicy = .fixed
    ) {
        self.selectedPlatforms = Self.normalized(selectedPlatforms)
        self.primaryPlatform = self.selectedPlatforms.contains(primaryPlatform) ? primaryPlatform : self.selectedPlatforms[0]
        self.selectionPromptAcknowledged = selectionPromptAcknowledged
        self.supportedOrientations = supportedOrientations.isEmpty ? [.resizable] : supportedOrientations
        self.layoutPolicy = layoutPolicy
    }

    enum CodingKeys: String, CodingKey {
        case selectedPlatforms
        case primaryPlatform
        case selectionPromptAcknowledged
        case supportedOrientations
        case layoutPolicy
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        selectedPlatforms = try c.decodeIfPresent([HypeTargetPlatform].self, forKey: .selectedPlatforms) ?? [.macOS]
        primaryPlatform = try c.decodeIfPresent(HypeTargetPlatform.self, forKey: .primaryPlatform) ?? .macOS
        selectionPromptAcknowledged = try c.decodeIfPresent(Bool.self, forKey: .selectionPromptAcknowledged) ?? false
        supportedOrientations = try c.decodeIfPresent([HypeTargetOrientation].self, forKey: .supportedOrientations) ?? [.resizable]
        layoutPolicy = try c.decodeIfPresent(TargetLayoutPolicy.self, forKey: .layoutPolicy) ?? .fixed
        normalize()
    }

    public static func macOSDefault(selectionPromptAcknowledged: Bool) -> StackDeploymentTargets {
        StackDeploymentTargets(selectionPromptAcknowledged: selectionPromptAcknowledged)
    }

    public static func automationDefault(
        selectedPlatforms: [HypeTargetPlatform] = [.macOS],
        primaryPlatform: HypeTargetPlatform? = nil
    ) -> StackDeploymentTargets {
        let normalized = normalized(selectedPlatforms)
        return StackDeploymentTargets(
            selectedPlatforms: normalized,
            primaryPlatform: primaryPlatform.flatMap { normalized.contains($0) ? $0 : nil } ?? normalized[0],
            selectionPromptAcknowledged: true
        )
    }

    public var primaryProfile: HypeDeviceProfile {
        HypeDeviceProfileCatalog.defaultProfile(for: primaryPlatform)
    }

    public var selectedProfiles: [HypeDeviceProfile] {
        HypeDeviceProfileCatalog.profiles(for: selectedPlatforms)
    }

    public mutating func normalize() {
        selectedPlatforms = Self.normalized(selectedPlatforms)
        if !selectedPlatforms.contains(primaryPlatform) {
            primaryPlatform = selectedPlatforms[0]
        }
        if supportedOrientations.isEmpty {
            supportedOrientations = [.resizable]
        }
    }

    private static func normalized(_ platforms: [HypeTargetPlatform]) -> [HypeTargetPlatform] {
        let unique = Array(Set(platforms.isEmpty ? [.macOS] : platforms))
        return HypeTargetPlatform.allCases.filter { unique.contains($0) }
    }

    // MARK: - Layout policy helpers

    /// Returns the layout policy clamped to what this target selection permits.
    ///
    /// When the selected platforms are exclusively macOS (resizable window with
    /// no fixed safe area to scale into), `.scaleToFit` and `.stretchToFill`
    /// are not meaningful, so the policy is clamped to `.fixed`. Any other
    /// platform combination respects the requested policy unchanged.
    ///
    /// **Caller contract**: invoke this at mutation sites only — do NOT call
    /// from `init`, `decode`, or `normalize()`. Loaded documents must decode
    /// their stored policy verbatim.
    public func clampedLayoutPolicy(_ requested: TargetLayoutPolicy) -> TargetLayoutPolicy {
        if selectedPlatforms == [.macOS] {
            return .fixed
        }
        return requested
    }

    /// Returns the layout policy defaulted for multi-target authoring.
    ///
    /// Applies the same macOS-only clamp as `clampedLayoutPolicy`, then
    /// additionally promotes `.fixed` to `.scaleToFit` when more than one
    /// platform is selected — a convenient default that prevents authored
    /// parts from overflowing smaller target safe areas.
    ///
    /// Use this only in layout-authoring tools (e.g. HIG layout apply) where
    /// the multi-target → scaleToFit contract is a known convenience. For
    /// explicit user-driven policy changes, use `clampedLayoutPolicy` instead.
    ///
    /// **Caller contract**: same as `clampedLayoutPolicy` — mutation sites only.
    public func defaultedLayoutPolicy(_ requested: TargetLayoutPolicy) -> TargetLayoutPolicy {
        let clamped = clampedLayoutPolicy(requested)
        if selectedPlatforms.count > 1, clamped == .fixed {
            return .scaleToFit
        }
        return clamped
    }
}

public enum PartTargetAvailability: String, Codable, Sendable, Equatable {
    case native
    case emulated
    case unsupported

    public var isUsable: Bool {
        self == .native || self == .emulated
    }
}

public struct PartTargetSupport: Codable, Sendable, Equatable {
    public var partType: PartType
    public var platform: HypeTargetPlatform
    public var availability: PartTargetAvailability
    public var reason: String

    public init(
        partType: PartType,
        platform: HypeTargetPlatform,
        availability: PartTargetAvailability,
        reason: String = ""
    ) {
        self.partType = partType
        self.platform = platform
        self.availability = availability
        self.reason = reason
    }
}

/// Conservative target compatibility catalog used by both UI and AI tools.
///
/// The default rule is strict: a part appears in the object palette only when
/// it is usable on every selected deployment target. tvOS is intentionally
/// narrower because its focus-remote interaction model does not support
/// arbitrary pointer, drag, or text-entry controls the same way macOS/iOS do.
public enum PartAvailabilityCatalog {
    public static func support(for partType: PartType, on platform: HypeTargetPlatform) -> PartTargetSupport {
        switch platform {
        case .macOS:
            return PartTargetSupport(partType: partType, platform: platform, availability: macOSAvailability(partType))
        case .iPhone, .iPad:
            return PartTargetSupport(
                partType: partType,
                platform: platform,
                availability: iOSFamilyAvailability(partType),
                reason: TargetRuntimeAdapterCatalog.supportReason(for: partType, on: platform)
            )
        case .tvOS:
            return tvOSSupport(partType)
        }
    }

    public static func supports(_ partType: PartType, across platforms: [HypeTargetPlatform]) -> Bool {
        let targets = platforms.isEmpty ? [.macOS] : platforms
        return targets.allSatisfy { support(for: partType, on: $0).availability.isUsable }
    }

    public static func unsupportedReasons(for partType: PartType, across platforms: [HypeTargetPlatform]) -> [String] {
        let targets = platforms.isEmpty ? [.macOS] : platforms
        return targets
            .map { support(for: partType, on: $0) }
            .filter { !$0.availability.isUsable }
            .map { "\($0.platform.displayName): \($0.reason)" }
    }

    private static func macOSAvailability(_ partType: PartType) -> PartTargetAvailability {
        TargetRuntimeAdapterCatalog.availability(for: partType, on: .macOS)
    }

    private static func iOSFamilyAvailability(_ partType: PartType) -> PartTargetAvailability {
        TargetRuntimeAdapterCatalog.availability(for: partType, on: .iPhone)
    }

    private static func tvOSSupport(_ partType: PartType) -> PartTargetSupport {
        PartTargetSupport(
            partType: partType,
            platform: .tvOS,
            availability: TargetRuntimeAdapterCatalog.availability(for: partType, on: .tvOS),
            reason: TargetRuntimeAdapterCatalog.supportReason(for: partType, on: .tvOS)
        )
    }
}
