const std = @import("std");
const skills = @import("skills.zig");

// ============================================================================
// COLOR PIE DESIGN - Magic: The Gathering style identity system
// ============================================================================
//
// Each School has primary/secondary/tertiary access to:
// - Skill Types (throw, trick, stance, call, gesture)
// - Chills (debuffs)
// - Cozies (buffs)
// - Damage ranges
// - Cooldown ranges
//
// Each Position specializes within these constraints.
//
// ============================================================================

pub const AccessLevel = enum {
    none,
    tertiary, // Conditional/rare access
    secondary, // Common but not core
    primary, // Core identity
};

// ============================================================================
// SCHOOL COLOR PIE (5 schools = 5 colors)
// ============================================================================

// PRIVATE SCHOOL (White: Order, Privilege, Resources)
// - Primary: Cozies (defensive), Healing, Long cooldowns
// - Secondary: Throw skills, Protective stances
// - Tertiary: Damage (conditional - when defending)
// - Damage Range: 8-15 (consistent, reliable)
// - Cooldowns: Long (15-30s) but powerful
// - Theme: "Money solves problems" - expensive but effective buffs

// PUBLIC SCHOOL (Red: Aggression, Grit, Combat)
// - Primary: Damage, Chills (DoT), Fast cooldowns
// - Secondary: Stances (combat-focused), Adjacent AoE
// - Tertiary: Cozies (fire_inside only, gained through combat)
// - Damage Range: 12-25 (high variance, risk/reward)
// - Cooldowns: Short (3-8s) but requires Grit stacks
// - Theme: "Scrappy fighter" - high damage, minimal defense

// MONTESSORI (Green: Adaptation, Variety, Growth)
// - Primary: Versatility (all skill types), sure_footed, variety bonuses
// - Secondary: Moderate everything (jack-of-all-trades)
// - Tertiary: Extreme effects (only with variety bonus active)
// - Damage Range: 10-18 (scales with variety)
// - Cooldowns: Medium (8-15s) rewards diversity
// - Theme: "Self-directed learning" - rewarded for trying different things

// HOMESCHOOL (Black: Sacrifice, Power, Isolation)
// - Primary: Chills (crippling), Life-to-resource conversion, High burst
// - Secondary: Self-debuffs for power
// - Tertiary: Team buffs (very rare, usually solo-focused)
// - Damage Range: 15-30 (pays health for damage)
// - Cooldowns: Very long (20-40s) but devastating
// - Theme: "Sacrifice for power" - hurt yourself to hurt them more

// WALDORF (Blue: Rhythm, Timing, Harmony)
// - Primary: Tricks, Timing-based cozies, Team support
// - Secondary: Calls (team support), Ground-targeted skills
// - Tertiary: Direct damage (only with perfect rhythm)
// - Damage Range: 5-20 (depends on timing)
// - Cooldowns: Rhythmic (must alternate skill types for bonuses)
// - Theme: "Flow state" - chaining skills in rhythm

// ============================================================================
// POSITION SPECIALIZATIONS (6 positions)
// ============================================================================

// PITCHER (Pure Damage Dealer)
// - Primary Schools: Public School, Homeschool
// - Skill Types: Throw (primary), Gesture (finishers)
// - Chills: windburn, soggy (DoT)
// - Range: 200-300 units (backline sniper)
// - Theme: The kid with the cannon arm

// FIELDER (Balanced Generalist)
// - Primary Schools: Montessori, Public School
// - Skill Types: Throw, Stance (equal mix)
// - Both: Moderate chills and cozies
// - Range: 150-220 units (medium)
// - Theme: Athletic all-rounder, adapts to the situation

// SLEDDER (Aggressive Skirmisher)
// - Primary Schools: Public School, Waldorf
// - Skill Types: Throw (close), Stance (mobility)
// - Cozies: sure_footed, fire_inside
// - Chills: slippery (control while closing)
// - Range: 80-150 units (dive in, burst)
// - Theme: Uses sled for mobility and ramming attacks

// SHOVELER (Tank/Defender)
// - Primary Schools: Private School, Homeschool
// - Skill Types: Stance (defensive), Gesture (fortifications)
// - Cozies: bundled_up, snowball_shield, frosty_fortitude
// - Range: 100-160 units
// - Theme: Digs in, builds walls, the immovable kid

// ANIMATOR (Summoner/Necromancer)
// - Primary Schools: Homeschool, Waldorf
// - Skill Types: Trick (summons), Call (commands)
// - Theme: Brings snowmen to life (Calvin and Hobbes grotesque snowmen)
// - The isolated homeschool kid who makes disturbing snow sculptures
// - Skills: "Deranged Snowman", "Snow Family", "Abomination", "Sentinel"

// THERMOS (Healer/Support)
// - Primary Schools: Waldorf (community/harmony), Private School (resources)
// - Skill Types: Call (team buffs), Gesture (healing)
// - Cozies: hot_cocoa (primary), insulated, bundled_up
// - Healing: Primary healer role
// - Range: 150-200 units (backline support)
// - Theme: Kid who brings thermoses of hot cocoa, hand warmers, extra scarves
// - Skills: "Share Cocoa", "Hand Warmers", "Extra Scarf", "Cocoa Break", "Mom's Cookies"

// ============================================================================
// CHILL/COZY DISTRIBUTION BY SCHOOL
// ============================================================================

pub const ChillAccess = struct {
    soggy: AccessLevel, // DoT - melting snow
    slippery: AccessLevel, // Movement speed reduction
    numb: AccessLevel, // Damage reduction (cold hands)
    frost_eyes: AccessLevel, // Miss chance (snow in face)
    windburn: AccessLevel, // DoT - cold wind
    brain_freeze: AccessLevel, // Energy degen
    packed_snow: AccessLevel, // Max health reduction
};

pub const CozyAccess = struct {
    bundled_up: AccessLevel, // Damage reduction
    hot_cocoa: AccessLevel, // Health regeneration
    fire_inside: AccessLevel, // Increased damage
    snow_goggles: AccessLevel, // Blind immunity
    insulated: AccessLevel, // Energy regen boost
    sure_footed: AccessLevel, // Movement speed
    frosty_fortitude: AccessLevel, // Max health increase
    snowball_shield: AccessLevel, // Blocks next attack
};

pub const SkillTypeAccess = struct {
    throw: AccessLevel,
    trick: AccessLevel,
    stance: AccessLevel,
    call: AccessLevel,
    gesture: AccessLevel,
};

// ============================================================================
// SCHOOL ACCESS TABLES
// ============================================================================

pub fn getChillAccess(school: @import("school.zig").School) ChillAccess {
    return switch (school) {
        .private_school => .{
            .soggy = .none,
            .slippery = .none,
            .numb = .tertiary, // Only defensively
            .frost_eyes = .none,
            .windburn = .none,
            .brain_freeze = .none,
            .packed_snow = .none,
        },
        .public_school => .{
            .soggy = .primary, // Aggressive DoT
            .slippery = .secondary,
            .numb = .none,
            .frost_eyes = .secondary,
            .windburn = .primary, // Aggressive DoT
            .brain_freeze = .none,
            .packed_snow = .none,
        },
        .montessori => .{
            .soggy = .secondary,
            .slippery = .secondary, // Versatile
            .numb = .secondary,
            .frost_eyes = .secondary,
            .windburn = .secondary,
            .brain_freeze = .secondary,
            .packed_snow = .secondary,
        },
        .homeschool => .{
            .soggy = .none,
            .slippery = .none,
            .numb = .none,
            .frost_eyes = .none,
            .windburn = .none,
            .brain_freeze = .primary, // Crippling
            .packed_snow = .primary, // Crippling
        },
        .waldorf => .{
            .soggy = .none,
            .slippery = .secondary,
            .numb = .none,
            .frost_eyes = .tertiary, // On perfect timing
            .windburn = .none,
            .brain_freeze = .none,
            .packed_snow = .none,
        },
    };
}

pub fn getCozyAccess(school: @import("school.zig").School) CozyAccess {
    return switch (school) {
        .private_school => .{
            .bundled_up = .primary, // Defensive
            .hot_cocoa = .secondary,
            .fire_inside = .none,
            .snow_goggles = .secondary,
            .insulated = .primary, // Resources
            .sure_footed = .none,
            .frosty_fortitude = .primary, // Defensive
            .snowball_shield = .secondary,
        },
        .public_school => .{
            .bundled_up = .none,
            .hot_cocoa = .none,
            .fire_inside = .tertiary, // Only via Grit stacks
            .snow_goggles = .none,
            .insulated = .none,
            .sure_footed = .secondary,
            .frosty_fortitude = .none,
            .snowball_shield = .none,
        },
        .montessori => .{
            .bundled_up = .secondary,
            .hot_cocoa = .secondary,
            .fire_inside = .secondary,
            .snow_goggles = .secondary,
            .insulated = .secondary,
            .sure_footed = .primary, // Variety bonus
            .frosty_fortitude = .secondary,
            .snowball_shield = .secondary,
        },
        .homeschool => .{
            .bundled_up = .none,
            .hot_cocoa = .none,
            .fire_inside = .secondary, // Sacrifice for power
            .snow_goggles = .none,
            .insulated = .none,
            .sure_footed = .none,
            .frosty_fortitude = .none,
            .snowball_shield = .none,
        },
        .waldorf => .{
            .bundled_up = .secondary,
            .hot_cocoa = .primary, // Team support
            .fire_inside = .none,
            .snow_goggles = .primary, // Team support
            .insulated = .secondary,
            .sure_footed = .secondary,
            .frosty_fortitude = .none,
            .snowball_shield = .tertiary, // Perfect timing
        },
    };
}

pub fn getSkillTypeAccess(school: @import("school.zig").School) SkillTypeAccess {
    return switch (school) {
        .private_school => .{
            .throw = .secondary,
            .trick = .none,
            .stance = .primary, // Defensive
            .call = .secondary,
            .gesture = .primary,
        },
        .public_school => .{
            .throw = .primary, // Aggressive
            .trick = .none,
            .stance = .secondary, // Combat stances
            .call = .none,
            .gesture = .secondary,
        },
        .montessori => .{
            .throw = .secondary,
            .trick = .secondary,
            .stance = .secondary,
            .call = .secondary,
            .gesture = .secondary,
        },
        .homeschool => .{
            .throw = .secondary,
            .trick = .primary, // Dark arts
            .stance = .none,
            .call = .none,
            .gesture = .secondary,
        },
        .waldorf => .{
            .throw = .tertiary, // On rhythm
            .trick = .primary, // Artistic
            .stance = .secondary,
            .call = .primary, // Team harmony
            .gesture = .secondary,
        },
    };
}

// ============================================================================
// DAMAGE AND COOLDOWN RANGES BY SCHOOL
// ============================================================================

pub const DamageRange = struct {
    min: f32,
    max: f32,
};

pub const CooldownRange = struct {
    min_ms: u32,
    max_ms: u32,
};

pub fn getDamageRange(school: @import("school.zig").School) DamageRange {
    return switch (school) {
        .private_school => .{ .min = 8.0, .max = 15.0 }, // Consistent, reliable
        .public_school => .{ .min = 12.0, .max = 25.0 }, // High variance
        .montessori => .{ .min = 10.0, .max = 18.0 }, // Scales with variety
        .homeschool => .{ .min = 15.0, .max = 30.0 }, // Pays health for damage
        .waldorf => .{ .min = 5.0, .max = 20.0 }, // Depends on timing
    };
}

pub fn getCooldownRange(school: @import("school.zig").School) CooldownRange {
    return switch (school) {
        .private_school => .{ .min_ms = 15000, .max_ms = 30000 }, // Long but powerful
        .public_school => .{ .min_ms = 3000, .max_ms = 8000 }, // Fast, requires Grit
        .montessori => .{ .min_ms = 8000, .max_ms = 15000 }, // Medium
        .homeschool => .{ .min_ms = 20000, .max_ms = 40000 }, // Very long, devastating
        .waldorf => .{ .min_ms = 5000, .max_ms = 15000 }, // Rhythmic
    };
}
