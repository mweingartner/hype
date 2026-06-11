import Foundation

// MARK: - BehaviorKind

/// The catalog of behaviors a GameEntity can carry.
///
/// Each behavior kind defines a deterministic effect on the compiled SceneSpec/HypeTalk.
/// The compiler (built in a later phase) reads the `params` dictionary using the keys
/// documented below. All param values are strings; the compiler interprets them as the
/// appropriate type (Bool, Double, etc.).
///
/// Param key contracts (name = defaultValue):
///
/// | Kind                  | Params                                                                  |
/// |-----------------------|-------------------------------------------------------------------------|
/// | platformerMovement    | speed=200, jumpForce=620                                                |
/// | topDownMovement       | speed=200                                                               |
/// | eightDirection        | speed=200                                                               |
/// | followPointer         | speed=220, axis=both                                                    |
/// | chaseTarget           | targetRole=player, speed=120                                            |
/// | patrol                | axis=x, speed=120, range=120                                            |
/// | physicsBody           | dynamic=true, gravity=roleDefault, restitution=0.2, friction=0.2, bodyShape=rect |
/// | bounce                | (none)                                                                  |
/// | wrapAround            | (none)                                                                  |
/// | constrainToBounds     | (none)                                                                  |
/// | destroyOutsideBounds  | margin=80                                                               |
/// | spawner               | spawnRole=enemy, interval=1.5, fromEdge=top, velocity=0,-160, max=8    |
/// | collectible           | (none)                                                                  |
/// | damageOnContact       | amount=1, targetRole=player                                             |
/// | health                | max=3                                                                   |
/// | scoreOnCollect        | points=10                                                               |
/// | winOnReach            | (none)                                                                  |
/// | winOnScore            | threshold=100                                                           |
/// | loseOnContact         | withRole=hazard                                                         |
/// | loseOnZeroHealth      | (none)                                                                  |
/// | draggable             | (none)                                                                  |
/// | rotator               | degreesPerSecond=90                                                     |
/// | oscillate             | axis=y, amplitude=40, period=2                                          |
public enum BehaviorKind: String, Codable, Sendable, Equatable, CaseIterable {
    case platformerMovement
    case topDownMovement
    case eightDirection
    case followPointer
    case chaseTarget
    case patrol
    case physicsBody
    case bounce
    case wrapAround
    case constrainToBounds
    case destroyOutsideBounds
    case spawner
    case collectible
    case damageOnContact
    case health
    case scoreOnCollect
    case winOnReach
    case winOnScore
    case loseOnContact
    case loseOnZeroHealth
    case draggable
    case rotator
    case oscillate

    /// Tolerant decode: unknown raw strings return nil so the enclosing
    /// `Behavior.init(from:)` can throw and the entity's behaviors array
    /// decoder can drop it via `try?`.
    public static func decodeTolerant(_ raw: String) -> BehaviorKind? {
        return BehaviorKind(rawValue: raw)
    }
}

// MARK: - Behavior

/// A single behavior attached to a `GameEntity`.
///
/// `kind` identifies the behavior; `params` carries override values for
/// the behavior's documented defaults. The compiler interprets both.
/// Unknown `kind` values throw during decode so the entity's tolerant
/// array decoder can silently drop them (see `GameEntity.init(from:)`).
public struct Behavior: Codable, Sendable, Equatable {
    public var kind: BehaviorKind
    /// Compiler-contract key/value overrides for this behavior's defaults.
    public var params: [String: String]

    public init(kind: BehaviorKind, params: [String: String] = [:]) {
        self.kind = kind
        self.params = params
    }

    /// Tolerant decoder: if `kind` is an unknown string, throws so the
    /// entity's `compactMap(try?)` loop drops this behavior entry.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawKind = (try? container.decode(String.self, forKey: .kind)) ?? ""
        guard let resolvedKind = BehaviorKind.decodeTolerant(rawKind) else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown BehaviorKind: '\(rawKind)'"
            )
        }
        self.kind = resolvedKind
        self.params = (try? container.decode([String: String].self, forKey: .params)) ?? [:]
    }

    private enum CodingKeys: String, CodingKey {
        case kind, params
    }
}
