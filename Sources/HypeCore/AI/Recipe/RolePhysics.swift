import Foundation

// MARK: - RolePhysics

/// Single source of truth for mapping an EntityRole to physics categories and
/// a default `PhysicsBodySpec`. Used by `RecipeCompiler` to assign bodies to
/// compiled nodes without duplicating the bit-layout decision across behaviors.
///
/// Bit layout mirrors `SpriteGameTemplateBuilder`:
///   wall        = 1 << 0
///   player      = 1 << 1
///   enemy       = 1 << 2
///   collectible = 1 << 3
///   goal        = 1 << 5
///   hazard      = 1 << 7
///   projectile  = 1 << 8
public enum RolePhysics {

    // MARK: - Category Bitmasks

    private static let wallBit:        UInt32 = 1 << 0
    private static let playerBit:      UInt32 = 1 << 1
    private static let enemyBit:       UInt32 = 1 << 2
    private static let collectibleBit: UInt32 = 1 << 3
    private static let goalBit:        UInt32 = 1 << 5
    private static let hazardBit:      UInt32 = 1 << 7
    private static let projectileBit:  UInt32 = 1 << 8

    /// The physics category bitmask for the given role.
    ///
    /// Roles that are purely visual (decoration, background, hud) return 0
    /// so they have no physics category and are invisible to the physics engine.
    public static func category(for role: EntityRole) -> UInt32 {
        switch role {
        case .player:      return playerBit
        case .enemy:       return enemyBit
        case .collectible: return collectibleBit
        case .hazard:      return hazardBit
        case .goal:        return goalBit
        case .wall:        return wallBit
        case .projectile:  return projectileBit
        case .spawner:     return 0
        case .hud:         return 0
        case .decoration:  return 0
        case .background:  return 0
        }
    }

    // MARK: - Contact-test Masks

    /// What the player should contact-test against: enemies, hazards, collectibles, goals.
    private static let playerContactMask: UInt32 = enemyBit | hazardBit | collectibleBit | goalBit

    /// What an enemy should contact-test against: player and walls (so AI can detect walls).
    private static let enemyContactMask: UInt32 = playerBit | wallBit

    /// What a collectible should contact-test against: just the player.
    private static let collectibleContactMask: UInt32 = playerBit

    /// What a hazard should contact-test against: the player.
    private static let hazardContactMask: UInt32 = playerBit

    /// What a goal should contact-test against: the player.
    private static let goalContactMask: UInt32 = playerBit

    /// What a projectile should contact-test against: enemies and walls.
    private static let projectileContactMask: UInt32 = enemyBit | wallBit

    /// Returns the contact-test bitmask appropriate for the role.
    public static func contactMask(for role: EntityRole) -> UInt32 {
        switch role {
        case .player:      return playerContactMask
        case .enemy:       return enemyContactMask
        case .collectible: return collectibleContactMask
        case .hazard:      return hazardContactMask
        case .goal:        return goalContactMask
        case .projectile:  return projectileContactMask
        case .wall, .spawner, .hud, .decoration, .background:
            return 0
        }
    }

    // MARK: - Default Physics Body

    /// Returns a sensible default `PhysicsBodySpec` for the role, or `nil` when
    /// the role should carry no physics body (decoration, hud, background).
    ///
    /// - Parameters:
    ///   - role: The entity role driving the physics configuration.
    ///   - size: The entity's visual size, used to infer circle vs rect body type.
    public static func base(for role: EntityRole, size: SizeSpec) -> PhysicsBodySpec? {
        let cat = category(for: role)
        guard cat != 0 else { return nil }

        let contactMask = contactMask(for: role)

        switch role {
        case .player:
            return PhysicsBodySpec(
                bodyType: .circle,
                isDynamic: true,
                categoryBitmask: cat,
                contactTestBitmask: contactMask,
                collisionBitmask: wallBit,
                restitution: 0.0,
                friction: 0.2,
                affectedByGravity: true,
                allowsRotation: false,
                linearDamping: 0.0
            )

        case .enemy:
            return PhysicsBodySpec(
                bodyType: .rect,
                isDynamic: true,
                categoryBitmask: cat,
                contactTestBitmask: contactMask,
                collisionBitmask: wallBit,
                restitution: 0.1,
                friction: 0.2,
                affectedByGravity: false,
                allowsRotation: false,
                linearDamping: 0.0
            )

        case .collectible:
            // Static, contact-only (no collision response).
            return PhysicsBodySpec(
                bodyType: .circle,
                isDynamic: false,
                categoryBitmask: cat,
                contactTestBitmask: contactMask,
                collisionBitmask: 0,
                restitution: 0.0,
                friction: 0.0,
                affectedByGravity: false,
                allowsRotation: false
            )

        case .hazard:
            return PhysicsBodySpec(
                bodyType: .rect,
                isDynamic: true,
                categoryBitmask: cat,
                contactTestBitmask: contactMask,
                collisionBitmask: wallBit,
                restitution: 0.2,
                friction: 0.1,
                affectedByGravity: false,
                allowsRotation: false,
                linearDamping: 0.0
            )

        case .goal:
            // Static sensor: detect player arrival without blocking movement.
            return PhysicsBodySpec(
                bodyType: .rect,
                isDynamic: false,
                categoryBitmask: cat,
                contactTestBitmask: contactMask,
                collisionBitmask: 0,
                restitution: 0.0,
                friction: 0.0,
                affectedByGravity: false,
                allowsRotation: false
            )

        case .wall:
            // Edge/static body; no contact-test needed by default.
            return PhysicsBodySpec(
                bodyType: .rect,
                isDynamic: false,
                categoryBitmask: cat,
                contactTestBitmask: 0,
                collisionBitmask: playerBit | enemyBit | projectileBit,
                restitution: 0.0,
                friction: 0.5,
                affectedByGravity: false,
                allowsRotation: false
            )

        case .projectile:
            return PhysicsBodySpec(
                bodyType: .circle,
                isDynamic: true,
                categoryBitmask: cat,
                contactTestBitmask: contactMask,
                collisionBitmask: 0,
                restitution: 0.0,
                friction: 0.0,
                affectedByGravity: false,
                allowsRotation: false,
                linearDamping: 0.0
            )

        case .spawner, .hud, .decoration, .background:
            return nil
        }
    }
}
