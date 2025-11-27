const std = @import("std");
const effects = @import("../effects.zig");

pub const SkillTarget = enum {
    enemy,
    ally,
    self,
    ground,
};

// Projectile trajectory type (for cover mechanics)
pub const ProjectileType = enum {
    direct, // Straight line (fastball) - affected by cover
    arcing, // Arcing trajectory (lob) - ignores cover, arcs over walls
    instant, // No projectile (instant hit) - affected by cover
};

// Skill mechanics - determines casting behavior (snowball fight timing!)
// These describe HOW the skill executes (timing), not WHAT it is (that's SkillType)
pub const SkillMechanic = enum {
    windup, // Wind up and release - projectile flies mid-animation (most throw skills)
    concentrate, // Focus required - effect at end + recovery (complex tricks)
    shout, // Quick yell - instant, no recovery needed (call skills)
    shift, // Reposition body - instant, no recovery (stance skills)
    ready, // Quick preparation - brief setup + recovery (gesture/signet skills)
    reflex, // Split-second reaction - instant, can't use while busy (future: dodges)

    pub fn hasAftercast(self: SkillMechanic) bool {
        return switch (self) {
            .windup, .concentrate, .ready => true,
            .shout, .shift, .reflex => false,
        };
    }

    pub fn canUseWhileCasting(self: SkillMechanic) bool {
        return switch (self) {
            .reflex => false, // Can't react while mid-action
            else => false, // Default: can't use while casting
        };
    }

    pub fn executesAtHalfActivation(self: SkillMechanic) bool {
        return self == .windup; // Snowball leaves hand mid-windup!
    }
};

// Thematic skill type (flavor/animation) - kept for visual variety
pub const SkillType = enum {
    throw, // Attack skills - throwing snowballs
    trick, // Magic-like abilities - special snow powers
    stance, // Movement/defensive buffs - footwork
    call, // Shouts - team buffs
    gesture, // Signets - quick utility, no energy cost
};

pub const AoeType = enum {
    single, // Single target
    adjacent, // Hits adjacent foes (like cleave)
    area, // Ground-targeted AoE
};

// Negative effects - "Chills" (debuffs)
pub const Chill = enum {
    soggy, // DoT - melting snow
    slippery, // Movement speed reduction
    numb, // Damage reduction (cold hands)
    frost_eyes, // Miss chance (snow in face)
    windburn, // DoT - cold wind
    brain_freeze, // Energy degen (ate snow)
    packed_snow, // Max health reduction
    dazed, // Attacks interrupt casts
};

// Positive effects - "Cozy" (buffs)
pub const Cozy = enum {
    bundled_up, // Damage reduction (extra layers)
    hot_cocoa, // Health regeneration over time
    fire_inside, // Increased damage output
    snow_goggles, // Cannot be blinded
    insulated, // Energy regeneration boost
    sure_footed, // Movement speed increase
    frosty_fortitude, // Max health increase
    snowball_shield, // Blocks next attack
};

pub const ChillEffect = struct {
    chill: Chill,
    duration_ms: u32, // milliseconds
    stack_intensity: u8 = 1, // some chills stack
};

pub const CozyEffect = struct {
    cozy: Cozy,
    duration_ms: u32, // milliseconds
    stack_intensity: u8 = 1, // some cozy effects stack
};

// Terrain modification - COMPOSITIONAL SYSTEM
// Separates WHAT terrain, HOW to apply it, and WHERE

pub const TerrainShape = enum {
    none, // No terrain modification
    circle, // Circular area (radius)
    cone, // Cone from caster toward target
    line, // Line from caster to target
    ring, // Ring/donut shape (inner + outer radius)
    trail, // Left behind as you move (requires duration)
    square, // Square/rectangle
    cross, // Plus sign shape
};

pub const TerrainModifier = enum {
    replace, // Replace terrain completely (default)
    add_traffic, // Add traffic to pack down snow faster
    remove_snow, // Reduce snow depth
    add_snow, // Increase snow depth
    freeze, // Convert toward icy
    melt, // Convert toward slushy
};

pub const TerrainEffect = struct {
    terrain_type: ?@import("../terrain.zig").TerrainType = null, // What terrain to create (null = no change)
    shape: TerrainShape = .none, // How to apply it
    modifier: TerrainModifier = .replace, // How it modifies existing terrain

    // Shape parameters (filled from skill's aoe_radius or other fields)
    // radius: set from skill.aoe_radius
    // inner_radius: for rings (stored separately if needed)
    // width: for lines/trails

    // Special properties
    heals_allies: bool = false, // Does standing in this terrain heal allies?
    damages_enemies: bool = false, // Does standing in this terrain damage enemies?
    blocks_movement: bool = false, // Does this terrain block movement? (future: walls)

    // Helper constructors for common patterns
    pub fn none() TerrainEffect {
        return .{};
    }

    pub fn ice(shape: TerrainShape) TerrainEffect {
        const TerrainType = @import("../terrain.zig").TerrainType;
        return .{ .terrain_type = TerrainType.icy_ground, .shape = shape };
    }

    pub fn deepSnow(shape: TerrainShape) TerrainEffect {
        const TerrainType = @import("../terrain.zig").TerrainType;
        return .{ .terrain_type = TerrainType.deep_powder, .shape = shape };
    }

    pub fn packedSnow(shape: TerrainShape) TerrainEffect {
        const TerrainType = @import("../terrain.zig").TerrainType;
        return .{ .terrain_type = TerrainType.packed_snow, .shape = shape };
    }

    pub fn cleared(shape: TerrainShape) TerrainEffect {
        const TerrainType = @import("../terrain.zig").TerrainType;
        return .{ .terrain_type = TerrainType.cleared_ground, .shape = shape };
    }

    pub fn slush(shape: TerrainShape) TerrainEffect {
        const TerrainType = @import("../terrain.zig").TerrainType;
        return .{ .terrain_type = TerrainType.slushy, .shape = shape };
    }

    pub fn healingSlush(shape: TerrainShape) TerrainEffect {
        const TerrainType = @import("../terrain.zig").TerrainType;
        return .{
            .terrain_type = TerrainType.slushy,
            .shape = shape,
            .heals_allies = true,
        };
    }
};

// ============================================================================
// SKILL BEHAVIORS - Complex mechanics that aren't stat modifiers
// ============================================================================
// These are whole mechanics that require special handling in the combat system.
// They are NOT composable modifiers - they're complete behaviors that need
// dedicated implementation. A skill can have at most ONE behavior.
//
// Philosophy: Effects modify stats. Behaviors change game flow.

pub const SummonType = enum {
    snowman, // Basic snowman minion
    abomination, // Large tanky creature
    suicide_snowman, // Explodes on death
    snow_fort, // Stationary turret-like summon
};

pub const SummonParams = struct {
    summon_type: SummonType,
    count: u8 = 1, // How many to summon
    level: u8 = 1, // Power/health scaling
    duration_ms: u32 = 30000, // How long summon lasts
    damage_per_attack: f32 = 5.0, // Base damage
    explode_damage: f32 = 0.0, // If > 0, explodes on death for this damage
    explode_radius: f32 = 0.0, // Explosion radius
};

pub const LinkParams = struct {
    max_targets: u8 = 5, // Max allies in the link
    damage_share_percent: f32 = 1.0, // How much damage is shared (1.0 = 100%)
    healing_share_percent: f32 = 0.0, // How much healing is shared
    duration_ms: u32 = 15000,
};

pub const RedirectParams = struct {
    redirect_percent: f32 = 1.0, // How much damage to redirect (1.0 = 100%)
    to_caster: bool = true, // Redirect TO caster (Guardian Angel) vs FROM caster
    duration_ms: u32 = 15000,
};

pub const ProjectileReturnParams = struct {
    return_damage: f32 = 20.0, // Damage when projectile is returned
    block_count: u8 = 1, // How many projectiles to catch
    duration_ms: u32 = 5000,
};

pub const PreventDeathParams = struct {
    heal_to_percent: f32 = 0.5, // Heal to this % when triggered
    invulnerable_ms: u32 = 3000, // Invulnerability duration after trigger
    trigger_below_percent: f32 = 0.2, // Trigger when dropping below this %
};

/// Complex skill behaviors that need dedicated combat system handling
pub const SkillBehavior = union(enum) {
    none: void, // No special behavior (default)

    // Summoning creatures
    summon: SummonParams,

    // Damage/healing sharing between linked targets
    spirit_link: LinkParams,

    // Redirect damage between characters
    damage_redirect: RedirectParams,

    // Catch and return projectiles
    projectile_return: ProjectileReturnParams,

    // Prevent death and heal (Golden Parachute style)
    prevent_death: PreventDeathParams,

    // Taunt - force target to attack caster
    taunt: struct {
        duration_ms: u32 = 5000,
    },
};

// An active chill (debuff) on a character
pub const ActiveChill = struct {
    chill: Chill,
    time_remaining_ms: u32,
    stack_intensity: u8,
    source_character_id: ?u32 = null, // who applied it (for tracking)
};

// An active cozy (buff) on a character
pub const ActiveCozy = struct {
    cozy: Cozy,
    time_remaining_ms: u32,
    stack_intensity: u8,
    source_character_id: ?u32 = null, // who applied it (for tracking)
};

pub const Skill = struct {
    name: [:0]const u8,
    description: [:0]const u8 = "", // GW1-style oracle text describing what the skill does
    skill_type: SkillType, // Thematic type (visual/animation)
    mechanic: SkillMechanic, // Mechanical type (timing behavior)
    energy_cost: u8 = 5,

    // Timing (GW1-accurate)
    activation_time_ms: u32 = 0, // 0 = instant
    aftercast_ms: u32 = 750, // Standard 3/4 second aftercast (0 for instant skills)
    recharge_time_ms: u32 = 2000, // cooldown
    duration_ms: u32 = 0, // for buffs/debuffs (0 = not applicable)

    // Damage/healing
    damage: f32 = 0.0,
    healing: f32 = 0.0,

    // Targeting
    cast_range: f32 = 200.0,
    target_type: SkillTarget = .enemy,
    aoe_type: AoeType = .single,
    aoe_radius: f32 = 0.0, // for area skills

    // Effects
    chills: []const ChillEffect = &[_]ChillEffect{}, // debuffs to apply
    cozies: []const CozyEffect = &[_]CozyEffect{}, // buffs to apply

    // New composable effects system (future: replace chills/cozies with this)
    // These are applied when the skill hits a target
    effects: []const effects.Effect = &[_]effects.Effect{}, // composable effects (damage multipliers, etc.)

    // Complex skill behavior (summons, links, redirects, etc.)
    // A skill can have at most ONE behavior. These need dedicated combat system handling.
    behavior: SkillBehavior = .none,

    // Special properties
    unblockable: bool = false,
    soak: f32 = 0.0, // percentage (0.0 to 1.0) - soaks through padding/layers
    interrupts: bool = false, // Does this skill interrupt target's casting?

    // Projectile type (for cover mechanics)
    projectile_type: ProjectileType = .direct, // Direct (fastball) or arcing (lob)

    // Terrain modification (for ground-targeted skills) - COMPOSITIONAL
    terrain_effect: TerrainEffect = .{},

    // Wall building (perpendicular to caster facing)
    creates_wall: bool = false,
    wall_length: f32 = 0.0, // Length of wall segment
    wall_height: f32 = 0.0, // Height of wall
    wall_thickness: f32 = 20.0, // Thickness of wall (default 20 units)
    wall_distance_from_caster: f32 = 40.0, // How far in front to place wall (legacy, prefer ground targeting)
    wall_arc_factor: f32 = 0.1, // Arc curvature toward caster (0.1 = 10% of length curves back)

    // Wall destruction
    destroys_walls: bool = false,
    wall_damage_multiplier: f32 = 1.0, // Damage multiplier against walls

    // School-specific resource costs
    grit_cost: u8 = 0, // Public School - adrenaline-like resource
    requires_grit_stacks: u8 = 0, // Public School - minimum grit stacks to cast
    consumes_all_grit: bool = false, // Public School - consume all grit (for skills like Final Push)
    damage_per_grit_consumed: f32 = 0.0, // Public School - bonus damage per grit stack consumed
    warmth_cost_percent: f32 = 0.0, // Homeschool - % of max warmth sacrificed
    min_warmth_percent: f32 = 0.0, // Homeschool - can't cast below this warmth %
    credit_cost: u8 = 0, // Private School - reduces max energy temporarily (spending on credit)
    requires_rhythm_stacks: u8 = 0, // Waldorf - minimum rhythm stacks to cast
    rhythm_cost: u8 = 0, // Waldorf - rhythm stacks consumed on cast
    consumes_all_rhythm: bool = false, // Waldorf - consume all rhythm (for skills like Crescendo)
    damage_per_rhythm_consumed: f32 = 0.0, // Waldorf - bonus damage per rhythm stack consumed

    // Private School - Credit bonus effects
    bonus_if_in_debt: bool = false, // Does this skill get bonus effects when in debt (credit > 0)?

    // Resource gains (on successful cast/hit)
    grants_grit_on_hit: u8 = 0, // Public School - gain Grit when skill hits
    grants_grit_on_cast: u8 = 0, // Public School - gain Grit on cast (regardless of hit)
    grants_grit_to_allies_on_cast: u8 = 0, // Public School - all nearby allies gain Grit on cast
    grants_energy_on_hit: u8 = 0, // Gain energy when skill hits
    grants_rhythm_on_cast: u8 = 0, // Waldorf - gain rhythm stacks on cast

    // Warmth-conditional effects (GW1-style health conditionals)
    bonus_damage_if_self_above_50_warmth: f32 = 0.0,
    bonus_damage_if_self_below_50_warmth: f32 = 0.0,
    bonus_damage_if_foe_above_50_warmth: f32 = 0.0,
    bonus_damage_if_foe_below_50_warmth: f32 = 0.0,

    // ========================================================================
    // ADVANCED PLACEMENT (AP) SKILLS
    // ========================================================================
    // AP skills are powerful build-defining abilities. Like GW1 elites:
    // - Only ONE AP skill can be equipped per character
    // - AP skills have stronger effects but often longer cooldowns
    // - Builds are often named after their AP skill ("Avalanche Pitcher")
    // - Visually distinguished with a gold star / honor roll treatment
    is_ap: bool = false,
};
