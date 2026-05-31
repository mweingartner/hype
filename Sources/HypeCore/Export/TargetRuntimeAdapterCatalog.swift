import Foundation

/// Runtime-control support matrix for standalone deployed stacks.
///
/// This catalog answers a narrower question than the macOS authoring canvas:
/// "Can the generated runtime shell render this part and provide its primary
/// interaction logic on the target platform?" Target availability should not
/// advertise a control for iPhone/iPad/tvOS until it has an adapter here.
public enum TargetRuntimeAdapterCatalog {
    /// Canonical controls with shipped iPhone/iPad runtime adapters.
    public static let iOSSupportedPartTypes: Set<PartType> = [
        .button,
        .field,
        .shape,
        .webpage,
        .image,
        .video,
        .chart,
        .calendar,
        .pdf,
        .map,
        .colorWell,
        .stepper,
        .slider,
        .segmented,
        .scene3D,
        .musicPlayer,
        .pianoKeyboard,
        .stepSequencer,
        .musicMixer,
        .appleMusicBrowser,
        .progressView,
        .gauge,
        .divider,
    ]

    /// Legacy part-type cases that decode into canonical button/field styles.
    public static let legacyEmulatedPartTypes: Set<PartType> = [
        .toggle,
        .link,
        .menu,
        .searchField,
    ]

    /// Controls that are intentionally not exported until a real standalone
    /// adapter exists. They may still work in the macOS authoring app.
    public static let unsupportedStandalonePartTypes: Set<PartType> = [
        .spriteArea,
        .audioRecorder,
        .musicQueue,
        .unknown,
    ]

    public static func availability(for partType: PartType, on platform: HypeTargetPlatform) -> PartTargetAvailability {
        switch platform {
        case .macOS:
            return partType == .unknown ? .unsupported : .native
        case .iPhone, .iPad:
            if iOSSupportedPartTypes.contains(partType) { return .native }
            if legacyEmulatedPartTypes.contains(partType) { return .emulated }
            return .unsupported
        case .tvOS:
            return tvOSSupportedPartTypes.contains(partType) ? .native : .unsupported
        }
    }

    public static func supportReason(for partType: PartType, on platform: HypeTargetPlatform) -> String {
        guard availability(for: partType, on: platform) == .unsupported else { return "" }
        switch (platform, partType) {
        case (_, .unknown):
            return "unknown future part types cannot be rendered safely by this runtime."
        case (.iPhone, .spriteArea), (.iPad, .spriteArea):
            return "Sprite areas require the cross-platform SpriteKit runtime bridge before they can be exported to iPhone or iPad."
        case (.tvOS, .spriteArea):
            return "Sprite areas require a focus-safe tvOS SpriteKit runtime bridge before they can be exported to tvOS."
        case (.iPhone, .audioRecorder), (.iPad, .audioRecorder):
            return "Audio recorder controls need an iOS recording adapter with microphone permission, file capture, and stack-embedded audio persistence."
        case (.tvOS, .audioRecorder):
            return "Audio recording is not supported in the tvOS runtime."
        case (_, .musicQueue):
            return "Music queue controls are legacy-only. Use AudioKit music controls or MusicKit Search in deployable stacks."
        case (.tvOS, .field), (.tvOS, .webpage), (.tvOS, .calendar), (.tvOS, .pdf), (.tvOS, .map), (.tvOS, .colorWell), (.tvOS, .stepper), (.tvOS, .slider), (.tvOS, .segmented), (.tvOS, .pianoKeyboard), (.tvOS, .stepSequencer), (.tvOS, .musicMixer), (.tvOS, .appleMusicBrowser), (.tvOS, .toggle), (.tvOS, .link), (.tvOS, .menu), (.tvOS, .searchField):
            return "this control requires pointer, touch, text-entry, browsing, or MusicKit behavior that is not yet implemented in the tvOS runtime shell."
        default:
            return "this control does not yet have a standalone \(platform.displayName) runtime adapter."
        }
    }

    public static func supportedPartTypes(on platform: HypeTargetPlatform) -> [PartType] {
        PartType.allCases.filter { availability(for: $0, on: platform).isUsable }
    }

    /// tvOS is intentionally narrower until each control has a focus-safe
    /// remote interaction adapter in the generated runtime shell.
    private static let tvOSSupportedPartTypes: Set<PartType> = [
        .button,
        .shape,
        .image,
        .video,
        .chart,
        .scene3D,
        .musicPlayer,
        .progressView,
        .gauge,
        .divider,
    ]
}
