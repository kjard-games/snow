const std = @import("std");
const effects = @import("effects.zig");

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
    terrain_type: ?@import("terrain.zig").TerrainType = null, // What terrain to create (null = no change)
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
        const TerrainType = @import("terrain.zig").TerrainType;
        return .{ .terrain_type = TerrainType.icy_ground, .shape = shape };
    }

    pub fn deepSnow(shape: TerrainShape) TerrainEffect {
        const TerrainType = @import("terrain.zig").TerrainType;
        return .{ .terrain_type = TerrainType.deep_powder, .shape = shape };
    }

    pub fn packedSnow(shape: TerrainShape) TerrainEffect {
        const TerrainType = @import("terrain.zig").TerrainType;
        return .{ .terrain_type = TerrainType.packed_snow, .shape = shape };
    }

    pub fn cleared(shape: TerrainShape) TerrainEffect {
        const TerrainType = @import("terrain.zig").TerrainType;
        return .{ .terrain_type = TerrainType.cleared_ground, .shape = shape };
    }

    pub fn slush(shape: TerrainShape) TerrainEffect {
        const TerrainType = @import("terrain.zig").TerrainType;
        return .{ .terrain_type = TerrainType.slushy, .shape = shape };
    }

    pub fn healingSlush(shape: TerrainShape) TerrainEffect {
        const TerrainType = @import("terrain.zig").TerrainType;
        return .{
            .terrain_type = TerrainType.slushy,
            .shape = shape,
            .heals_allies = true,
        };
    }
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

// Example snowball-themed skills
pub const QUICK_TOSS = Skill{
    .name = "Quick Toss",
    .skill_type = .throw,
    .mechanic = .windup,
    .energy_cost = 3,
    .activation_time_ms = 0, // instant
    .aftercast_ms = 750, // Standard aftercast
    .recharge_time_ms = 1000, // 1 second
    .damage = 8.0,
    .cast_range = 180.0,
};

pub const POWER_THROW = Skill{
    .name = "Power Throw",
    .skill_type = .throw,
    .mechanic = .windup, // Attack skills execute at half activation
    .energy_cost = 8,
    .activation_time_ms = 1500, // 1.5 second wind-up, projectile fires at 750ms
    .aftercast_ms = 750, // Standard aftercast
    .recharge_time_ms = 5000, // 5 seconds
    .damage = 30.0,
    .cast_range = 250.0,
    .unblockable = true,
};

const soggy_chill = [_]ChillEffect{.{
    .chill = .soggy,
    .duration_ms = 5000, // 5 seconds of DoT
    .stack_intensity = 1,
}};

pub const SLUSH_BALL = Skill{
    .name = "Slush Ball",
    .skill_type = .throw,
    .mechanic = .windup, // Attack skill
    .energy_cost = 6,
    .activation_time_ms = 750, // Projectile fires at 375ms
    .aftercast_ms = 750,
    .recharge_time_ms = 8000, // 8 seconds
    .damage = 12.0,
    .cast_range = 200.0,
    .chills = &soggy_chill,
};

const frost_eyes_chill = [_]ChillEffect{.{
    .chill = .frost_eyes,
    .duration_ms = 3000, // 3 seconds of miss chance
    .stack_intensity = 1,
}};

pub const SNOW_IN_FACE = Skill{
    .name = "Snow in Face",
    .skill_type = .trick,
    .mechanic = .concentrate, // Spell - executes at end of cast
    .energy_cost = 5,
    .activation_time_ms = 500, // Cast for 500ms
    .aftercast_ms = 750, // Then 750ms aftercast
    .recharge_time_ms = 12000, // 12 seconds
    .damage = 5.0,
    .cast_range = 150.0,
    .chills = &frost_eyes_chill,
};

const slippery_chill = [_]ChillEffect{.{
    .chill = .slippery,
    .duration_ms = 4000, // 4 seconds of slow
    .stack_intensity = 1,
}};

pub const ICE_PATCH = Skill{
    .name = "Ice Patch",
    .skill_type = .trick,
    .mechanic = .concentrate,
    .energy_cost = 7,
    .activation_time_ms = 1000, // 1 second cast
    .aftercast_ms = 750,
    .recharge_time_ms = 15000, // 15 seconds
    .damage = 3.0,
    .cast_range = 300.0,
    .target_type = .ground,
    .aoe_type = .area,
    .aoe_radius = 100.0,
    .chills = &slippery_chill,
};

const snowball_shield_cozy = [_]CozyEffect{.{
    .cozy = .snowball_shield,
    .duration_ms = 5000, // 5 seconds - blocks one attack
    .stack_intensity = 1,
}};

pub const DODGE_ROLL = Skill{
    .name = "Dodge Roll",
    .skill_type = .stance,
    .mechanic = .shift, // Instant, no aftercast
    .energy_cost = 4,
    .activation_time_ms = 0, // instant
    .aftercast_ms = 0, // No aftercast for stances
    .recharge_time_ms = 8000, // 8 seconds
    .target_type = .self,
    .duration_ms = 2000, // 2 seconds of evade
    .cozies = &snowball_shield_cozy,
};

const hot_cocoa_cozy = [_]CozyEffect{.{
    .cozy = .hot_cocoa,
    .duration_ms = 10000, // 10 seconds of regen
    .stack_intensity = 1,
}};

pub const WARM_UP = Skill{
    .name = "Warm Up",
    .skill_type = .gesture,
    .mechanic = .ready, // Signets have cast time + aftercast
    .energy_cost = 0, // gestures are free
    .activation_time_ms = 0, // But this one is instant
    .aftercast_ms = 750, // Standard aftercast
    .recharge_time_ms = 20000, // 20 seconds
    .healing = 25.0,
    .target_type = .self,
    .cozies = &hot_cocoa_cozy,
};

pub const RALLY_CRY = Skill{
    .name = "Rally Cry",
    .skill_type = .call,
    .mechanic = .shout, // Shouts are instant, no aftercast
    .energy_cost = 10,
    .activation_time_ms = 0,
    .aftercast_ms = 0, // No aftercast for shouts
    .recharge_time_ms = 30000, // 30 seconds
    .healing = 15.0,
    .target_type = .ally,
    .aoe_type = .area,
    .aoe_radius = 200.0, // affects all allies in range
};

pub const PRECISION_STRIKE = Skill{
    .name = "Precision Strike",
    .skill_type = .throw,
    .mechanic = .windup, // Attack skill - executes at half activation
    .energy_cost = 7,
    .activation_time_ms = 1000, // Projectile fires at 500ms
    .aftercast_ms = 750,
    .recharge_time_ms = 10000, // 10 seconds
    .damage = 20.0,
    .cast_range = 220.0,
    .soak = 0.5, // 50% soak - soaks through padding
};

const bundled_up_cozy = [_]CozyEffect{.{
    .cozy = .bundled_up,
    .duration_ms = 8000, // 8 seconds damage reduction
    .stack_intensity = 1,
}};

pub const BUNDLE_UP = Skill{
    .name = "Bundle Up",
    .skill_type = .stance,
    .mechanic = .shift, // Instant, no aftercast
    .energy_cost = 5,
    .activation_time_ms = 0,
    .aftercast_ms = 0,
    .recharge_time_ms = 15000, // 15 seconds
    .target_type = .self,
    .cozies = &bundled_up_cozy,
};

const fire_inside_cozy = [_]CozyEffect{.{
    .cozy = .fire_inside,
    .duration_ms = 12000, // 12 seconds increased damage
    .stack_intensity = 1,
}};

pub const BURNING_RAGE = Skill{
    .name = "Burning Rage",
    .skill_type = .stance,
    .mechanic = .shift,
    .energy_cost = 6,
    .activation_time_ms = 0,
    .aftercast_ms = 0,
    .recharge_time_ms = 20000, // 20 seconds
    .target_type = .self,
    .cozies = &fire_inside_cozy,
};

const snow_goggles_cozy = [_]CozyEffect{.{
    .cozy = .snow_goggles,
    .duration_ms = 15000, // 15 seconds blind immunity
    .stack_intensity = 1,
}};

pub const GOGGLES_ON = Skill{
    .name = "Goggles On",
    .skill_type = .gesture,
    .mechanic = .ready,
    .energy_cost = 0,
    .activation_time_ms = 0,
    .aftercast_ms = 750,
    .recharge_time_ms = 25000, // 25 seconds
    .target_type = .self,
    .cozies = &snow_goggles_cozy,
};

const sure_footed_cozy = [_]CozyEffect{.{
    .cozy = .sure_footed,
    .duration_ms = 6000, // 6 seconds speed boost
    .stack_intensity = 1,
}};

pub const SPRINT = Skill{
    .name = "Sprint",
    .skill_type = .stance,
    .mechanic = .shift,
    .energy_cost = 4,
    .activation_time_ms = 0,
    .aftercast_ms = 0,
    .recharge_time_ms = 12000, // 12 seconds
    .target_type = .self,
    .cozies = &sure_footed_cozy,
};

// Interrupt skills - these call target.interrupt() on hit
pub const INTERRUPT_SHOT = Skill{
    .name = "Interrupt Shot",
    .skill_type = .throw,
    .mechanic = .windup, // Attack - fires at 250ms (half of 500ms)
    .energy_cost = 10,
    .activation_time_ms = 500, // Half second cast
    .aftercast_ms = 750,
    .recharge_time_ms = 10000, // 10 seconds
    .damage = 15.0,
    .cast_range = 200.0,
    .interrupts = true,
};

const dazed_chill = [_]ChillEffect{.{
    .chill = .dazed,
    .duration_ms = 5000, // 5 seconds - attacks interrupt during this time
    .stack_intensity = 1,
}};

pub const DAZING_BLOW = Skill{
    .name = "Dazing Blow",
    .skill_type = .throw,
    .mechanic = .windup,
    .energy_cost = 5,
    .activation_time_ms = 0, // Instant
    .aftercast_ms = 750,
    .recharge_time_ms = 8000, // 8 seconds
    .damage = 10.0,
    .cast_range = 180.0,
    .chills = &dazed_chill, // Applies dazed - future attacks will interrupt
};

pub const DISRUPTING_THROW = Skill{
    .name = "Disrupting Throw",
    .skill_type = .trick,
    .mechanic = .concentrate, // Spell mechanic but instant for quick interrupt
    .energy_cost = 15,
    .activation_time_ms = 0, // Instant - must be fast to interrupt
    .aftercast_ms = 750,
    .recharge_time_ms = 20000, // 20 seconds - powerful interrupt
    .damage = 5.0,
    .cast_range = 250.0,
    .interrupts = true,
    .chills = &dazed_chill,
};

// ============================================================================
// Example skills using the new composable effects system
// These demonstrate conditional effects and complex skill mechanics
// ============================================================================

const weakness_effect_array = [_]effects.Effect{effects.SOAKED_THROUGH_EFFECT};

pub const WEAKNESS_SHOT = Skill{
    .name = "Soaked Shot",
    .description = "Throw a wet snowball. Deals 18 damage and leaves target Soaked Through (takes 2x damage) for 5 seconds",
    .skill_type = .throw,
    .mechanic = .windup,
    .energy_cost = 8,
    .activation_time_ms = 500,
    .aftercast_ms = 750,
    .recharge_time_ms = 10000,
    .damage = 18.0,
    .cast_range = 220.0,
    .effects = &weakness_effect_array,
};

const haste_effect_array = [_]effects.Effect{effects.MOMENTUM_EFFECT};

pub const SWIFT_BLESSING = Skill{
    .name = "Get Going",
    .description = "Shout encouragement. Allies gain Momentum (50% faster movement, 20% quicker skill recharge) for 6 seconds",
    .skill_type = .call,
    .mechanic = .shout,
    .energy_cost = 12,
    .activation_time_ms = 0,
    .aftercast_ms = 0,
    .recharge_time_ms = 25000,
    .target_type = .ally,
    .aoe_type = .area,
    .aoe_radius = 200.0,
    .effects = &haste_effect_array,
};

const fragile_effect_array = [_]effects.Effect{effects.COLD_STIFF_EFFECT};

pub const EXPLOIT_WEAKNESS = Skill{
    .name = "Cold Snap",
    .description = "Strike at frozen muscles. Deals 22 damage. If target is badly hurt (below 50% warmth), inflicts Cold Stiff (padding 50% less effective) for 8 seconds",
    .skill_type = .throw,
    .mechanic = .windup,
    .energy_cost = 10,
    .activation_time_ms = 750,
    .aftercast_ms = 750,
    .recharge_time_ms = 12000,
    .damage = 22.0,
    .cast_range = 250.0,
    .effects = &fragile_effect_array,
};

const quickened_effect_array = [_]effects.Effect{effects.IN_THE_ZONE_EFFECT};

pub const QUICKSTEP = Skill{
    .name = "Rhythm Running",
    .description = "Get In The Zone (attack and cast 30% faster) for 12 seconds",
    .skill_type = .stance,
    .mechanic = .shift,
    .energy_cost = 6,
    .activation_time_ms = 0,
    .aftercast_ms = 0,
    .recharge_time_ms = 18000,
    .target_type = .self,
    .effects = &quickened_effect_array,
};

// ============================================================================
// NEW SKILLS - Demonstrating the full composable effect system
// ============================================================================

// ----------------------------------------------------------------------------
// CONDITIONAL DAMAGE SKILLS
// ----------------------------------------------------------------------------

const chase_effect_array = [_]effects.Effect{effects.CHASE_DOWN_EFFECT};

pub const PURSUIT_THROW = Skill{
    .name = "Pursuit Throw",
    .description = "Throw. Deals 15 damage. +12 bonus damage to moving targets.",
    .skill_type = .throw,
    .mechanic = .windup,
    .energy_cost = 6,
    .activation_time_ms = 500,
    .aftercast_ms = 750,
    .recharge_time_ms = 6000,
    .damage = 15.0,
    .cast_range = 200.0,
    .effects = &chase_effect_array,
};

const exploit_chill_array = [_]effects.Effect{effects.EXPLOIT_WEAKNESS_EFFECT};

pub const PILE_ON_THROW = Skill{
    .name = "Pile On",
    .description = "Throw. Deals 12 damage. +15 bonus damage if target has any Chill.",
    .skill_type = .throw,
    .mechanic = .windup,
    .energy_cost = 5,
    .activation_time_ms = 500,
    .aftercast_ms = 750,
    .recharge_time_ms = 5000,
    .damage = 12.0,
    .cast_range = 180.0,
    .effects = &exploit_chill_array,
};

const finishing_effect_array = [_]effects.Effect{effects.FINISHING_BLOW_EFFECT};

pub const FINISHER = Skill{
    .name = "Finisher",
    .description = "Throw. Deals 20 damage. Deals DOUBLE damage to targets below 25% warmth.",
    .skill_type = .throw,
    .mechanic = .windup,
    .energy_cost = 8,
    .activation_time_ms = 1000,
    .aftercast_ms = 750,
    .recharge_time_ms = 15000,
    .damage = 20.0,
    .cast_range = 220.0,
    .effects = &finishing_effect_array,
};

// ----------------------------------------------------------------------------
// DERVISH-STYLE FLASH ENCHANTMENTS
// ----------------------------------------------------------------------------

const cozy_layers_array = [_]effects.Effect{effects.COZY_LAYERS_EFFECT};

pub const COZY_LAYERS = Skill{
    .name = "Cozy Layers",
    .description = "Stance. (15 seconds.) Take 25% less damage but move 25% slower. If removed early, adjacent foes are Slowed.",
    .skill_type = .stance,
    .mechanic = .shift,
    .energy_cost = 8,
    .activation_time_ms = 0,
    .aftercast_ms = 0,
    .recharge_time_ms = 20000,
    .target_type = .self,
    .duration_ms = 15000,
    .effects = &cozy_layers_array,
};

// ----------------------------------------------------------------------------
// REACTIVE SKILLS
// ----------------------------------------------------------------------------

const thorns_effect_array = [_]effects.Effect{effects.THORNS_EFFECT};

pub const PRICKLY_SCARF = Skill{
    .name = "Prickly Scarf",
    .description = "Stance. (12 seconds.) When hit, deal 10 damage back to attacker.",
    .skill_type = .stance,
    .mechanic = .shift,
    .energy_cost = 6,
    .activation_time_ms = 0,
    .aftercast_ms = 0,
    .recharge_time_ms = 18000,
    .target_type = .self,
    .duration_ms = 12000,
    .effects = &thorns_effect_array,
};

const counter_stance_array = [_]effects.Effect{effects.COUNTER_STANCE_EFFECT};

pub const COUNTER_STANCE = Skill{
    .name = "Counter Stance",
    .description = "Stance. (10 seconds.) After blocking, attack 50% faster for 3 seconds.",
    .skill_type = .stance,
    .mechanic = .shift,
    .energy_cost = 5,
    .activation_time_ms = 0,
    .aftercast_ms = 0,
    .recharge_time_ms = 15000,
    .target_type = .self,
    .duration_ms = 10000,
    .effects = &counter_stance_array,
};

// ----------------------------------------------------------------------------
// PARTY SUPPORT SKILLS
// ----------------------------------------------------------------------------

const rally_effect_array = [_]effects.Effect{effects.RALLY_CRY_EFFECT};

pub const TEAM_SPIRIT = Skill{
    .name = "Team Spirit",
    .description = "Call. (10 seconds.) Allies in earshot receive 25% more healing.",
    .skill_type = .call,
    .mechanic = .shout,
    .energy_cost = 10,
    .activation_time_ms = 0,
    .aftercast_ms = 0,
    .recharge_time_ms = 25000,
    .target_type = .ally,
    .aoe_type = .area,
    .aoe_radius = 250.0,
    .duration_ms = 10000,
    .effects = &rally_effect_array,
};

const intimidate_effect_array = [_]effects.Effect{effects.INTIMIDATING_PRESENCE_EFFECT};

pub const INTIMIDATING_SHOUT = Skill{
    .name = "Intimidating Shout",
    .description = "Call. (12 seconds.) Nearby foes deal 15% less damage.",
    .skill_type = .call,
    .mechanic = .shout,
    .energy_cost = 8,
    .activation_time_ms = 0,
    .aftercast_ms = 0,
    .recharge_time_ms = 20000,
    .target_type = .enemy,
    .aoe_type = .area,
    .aoe_radius = 200.0,
    .duration_ms = 12000,
    .effects = &intimidate_effect_array,
};

// ----------------------------------------------------------------------------
// SCHOOL-SPECIFIC CONDITIONAL SKILLS
// ----------------------------------------------------------------------------

const desperate_effect_array = [_]effects.Effect{effects.DESPERATE_MEASURES_EFFECT};

pub const CREDIT_CRUNCH = Skill{
    .name = "Credit Crunch",
    .description = "Throw. (Private School) Deals 18 damage. Deals 50% MORE damage while in debt!",
    .skill_type = .throw,
    .mechanic = .windup,
    .energy_cost = 6,
    .activation_time_ms = 750,
    .aftercast_ms = 750,
    .recharge_time_ms = 8000,
    .damage = 18.0,
    .cast_range = 200.0,
    .effects = &desperate_effect_array,
};

const grit_surge_array = [_]effects.Effect{effects.GRIT_SURGE_EFFECT};

pub const ADRENALINE_RUSH = Skill{
    .name = "Adrenaline Rush",
    .description = "Stance. (Public School) (8 seconds.) At 5 Grit: +30% damage and +20% attack speed.",
    .skill_type = .stance,
    .mechanic = .shift,
    .energy_cost = 5,
    .activation_time_ms = 0,
    .aftercast_ms = 0,
    .recharge_time_ms = 15000,
    .target_type = .self,
    .duration_ms = 8000,
    .effects = &grit_surge_array,
};

const rhythm_effect_array = [_]effects.Effect{effects.PERFECT_RHYTHM_EFFECT};

pub const FLOW_STATE = Skill{
    .name = "Flow State",
    .description = "Stance. (Waldorf) (10 seconds.) At 5 Rhythm: skills cost half and recharge 50% faster.",
    .skill_type = .stance,
    .mechanic = .shift,
    .energy_cost = 8,
    .activation_time_ms = 0,
    .aftercast_ms = 0,
    .recharge_time_ms = 25000,
    .target_type = .self,
    .duration_ms = 10000,
    .effects = &rhythm_effect_array,
};

const isolation_effect_array = [_]effects.Effect{effects.ISOLATION_POWER_EFFECT};

pub const LONER = Skill{
    .name = "Loner",
    .description = "Stance. (Homeschool) While isolated (no allies nearby): +40% damage, +20% armor.",
    .skill_type = .stance,
    .mechanic = .shift,
    .energy_cost = 5,
    .activation_time_ms = 0,
    .aftercast_ms = 0,
    .recharge_time_ms = 30000,
    .target_type = .self,
    .duration_ms = 20000,
    .effects = &isolation_effect_array,
};

const variety_effect_array = [_]effects.Effect{effects.VARIETY_BONUS_EFFECT};

pub const ADAPT = Skill{
    .name = "Adapt",
    .description = "Gesture. (Montessori) After using a different skill type: +8 damage and +25% energy regen for 5s.",
    .skill_type = .gesture,
    .mechanic = .ready,
    .energy_cost = 0,
    .activation_time_ms = 0,
    .aftercast_ms = 500,
    .recharge_time_ms = 12000,
    .target_type = .self,
    .effects = &variety_effect_array,
};

// ----------------------------------------------------------------------------
// TERRAIN-CONDITIONAL SKILLS
// ----------------------------------------------------------------------------

const ice_mastery_array = [_]effects.Effect{effects.ICE_MASTERY_EFFECT};

pub const ICE_SKATER = Skill{
    .name = "Ice Skater",
    .description = "Stance. While on ice: move 25% faster and gain 15% evasion.",
    .skill_type = .stance,
    .mechanic = .shift,
    .energy_cost = 5,
    .activation_time_ms = 0,
    .aftercast_ms = 0,
    .recharge_time_ms = 20000,
    .target_type = .self,
    .duration_ms = 15000,
    .effects = &ice_mastery_array,
};

const deep_snow_array = [_]effects.Effect{effects.DEEP_SNOW_ADVANTAGE_EFFECT};

pub const SNOWDRIFT_STRIKE = Skill{
    .name = "Snowdrift Strike",
    .description = "Throw. Deals 14 damage. +15 damage and +20% accuracy vs targets in deep snow.",
    .skill_type = .throw,
    .mechanic = .windup,
    .energy_cost = 7,
    .activation_time_ms = 750,
    .aftercast_ms = 750,
    .recharge_time_ms = 8000,
    .damage = 14.0,
    .cast_range = 200.0,
    .effects = &deep_snow_array,
};

// ----------------------------------------------------------------------------
// INTERRUPT/KNOCKDOWN SKILLS
// ----------------------------------------------------------------------------

const daze_followup_array = [_]effects.Effect{effects.DAZE_FOLLOWUP_EFFECT};

pub const GROUND_POUND = Skill{
    .name = "Ground Pound",
    .description = "Throw. Deals 16 damage. +50% damage to knocked down targets.",
    .skill_type = .throw,
    .mechanic = .windup,
    .energy_cost = 6,
    .activation_time_ms = 500,
    .aftercast_ms = 750,
    .recharge_time_ms = 6000,
    .damage = 16.0,
    .cast_range = 150.0,
    .effects = &daze_followup_array,
};

const interrupt_bonus_array = [_]effects.Effect{effects.INTERRUPT_BONUS_EFFECT};

pub const DISRUPTIVE_SHOT = Skill{
    .name = "Disruptive Shot",
    .description = "Throw. Deals 10 damage. Interrupts. On interrupt: double energy regen for 5s.",
    .skill_type = .throw,
    .mechanic = .windup,
    .energy_cost = 8,
    .activation_time_ms = 250, // Very fast for interrupting
    .aftercast_ms = 750,
    .recharge_time_ms = 12000,
    .damage = 10.0,
    .cast_range = 200.0,
    .interrupts = true,
    .effects = &interrupt_bonus_array,
};

// ============================================================================
// BLOCKING SKILLS - GW1-style defensive stances
// ============================================================================

const shield_effect_array = [_]effects.Effect{effects.SNOWBALL_SHIELD_EFFECT};

pub const SHIELD_STANCE = Skill{
    .name = "Shield Stance",
    .description = "Stance. (8 seconds.) 75% chance to block incoming snowballs.",
    .skill_type = .stance,
    .mechanic = .shift,
    .energy_cost = 5,
    .activation_time_ms = 0,
    .aftercast_ms = 0,
    .recharge_time_ms = 15000,
    .target_type = .self,
    .duration_ms = 8000,
    .effects = &shield_effect_array,
};

const reflexes_effect_array = [_]effects.Effect{effects.QUICK_REFLEXES_EFFECT};

pub const QUICK_DODGE = Skill{
    .name = "Quick Dodge",
    .description = "Stance. (10 seconds.) Block the next attack. After blocking, move 33% faster for 4s.",
    .skill_type = .stance,
    .mechanic = .shift,
    .energy_cost = 5,
    .activation_time_ms = 0,
    .aftercast_ms = 0,
    .recharge_time_ms = 12000,
    .target_type = .self,
    .duration_ms = 10000,
    .effects = &reflexes_effect_array,
};

const breaker_effect_array = [_]effects.Effect{effects.SHIELD_BREAKER_EFFECT};

pub const WILD_THROW = Skill{
    .name = "Wild Throw",
    .description = "Throw. Deals 18 damage. +50% damage against blocking targets.",
    .skill_type = .throw,
    .mechanic = .windup,
    .energy_cost = 7,
    .activation_time_ms = 750,
    .aftercast_ms = 750,
    .recharge_time_ms = 8000,
    .damage = 18.0,
    .cast_range = 200.0,
    .effects = &breaker_effect_array,
};

// ============================================================================
// SKILL DISABLE SKILLS - Snow-themed silence/daze
// ============================================================================

const brain_freeze_effect_array = [_]effects.Effect{effects.BRAIN_FREEZE_DISABLE_EFFECT};

pub const SNOW_MOUTHFUL = Skill{
    .name = "Snow Mouthful",
    .description = "Trick. Target eats snow and gets Brain Freeze (can't use skills) for 3 seconds.",
    .skill_type = .trick,
    .mechanic = .concentrate,
    .energy_cost = 15,
    .activation_time_ms = 1000,
    .aftercast_ms = 750,
    .recharge_time_ms = 25000,
    .damage = 5.0,
    .cast_range = 150.0,
    .effects = &brain_freeze_effect_array,
};

const numb_fingers_effect_array = [_]effects.Effect{effects.NUMB_FINGERS_EFFECT};

pub const FREEZING_GRIP = Skill{
    .name = "Freezing Grip",
    .description = "Trick. Target's hands go numb (can't use Throw skills) for 5 seconds.",
    .skill_type = .trick,
    .mechanic = .concentrate,
    .energy_cost = 10,
    .activation_time_ms = 750,
    .aftercast_ms = 750,
    .recharge_time_ms = 18000,
    .damage = 8.0,
    .cast_range = 180.0,
    .effects = &numb_fingers_effect_array,
};

const foggy_goggles_effect_array = [_]effects.Effect{effects.FOGGY_GOGGLES_EFFECT};

pub const FOG_BREATH = Skill{
    .name = "Fog Breath",
    .description = "Trick. Fog up target's goggles (can't use Trick/Gesture skills) for 4 seconds.",
    .skill_type = .trick,
    .mechanic = .concentrate,
    .energy_cost = 8,
    .activation_time_ms = 500,
    .aftercast_ms = 750,
    .recharge_time_ms = 15000,
    .damage = 5.0,
    .cast_range = 120.0, // Short range - need to breathe on them
    .effects = &foggy_goggles_effect_array,
};

// ============================================================================
// DURATION MODIFIER SKILLS
// ============================================================================

const lingering_cold_effect_array = [_]effects.Effect{effects.LINGERING_COLD_EFFECT};

pub const BITTER_COLD = Skill{
    .name = "Bitter Cold",
    .description = "Stance. (20 seconds.) Chills you apply last 50% longer.",
    .skill_type = .stance,
    .mechanic = .shift,
    .energy_cost = 5,
    .activation_time_ms = 0,
    .aftercast_ms = 0,
    .recharge_time_ms = 30000,
    .target_type = .self,
    .duration_ms = 20000,
    .effects = &lingering_cold_effect_array,
};

const cozy_aura_effect_array = [_]effects.Effect{effects.COZY_AURA_EFFECT};

pub const EXTRA_SNUG = Skill{
    .name = "Extra Snug",
    .description = "Stance. (30 seconds.) Cozy effects on you last 33% longer.",
    .skill_type = .stance,
    .mechanic = .shift,
    .energy_cost = 5,
    .activation_time_ms = 0,
    .aftercast_ms = 0,
    .recharge_time_ms = 45000,
    .target_type = .self,
    .duration_ms = 30000,
    .effects = &cozy_aura_effect_array,
};

const chill_resist_effect_array = [_]effects.Effect{effects.CHILL_RESISTANCE_EFFECT};

pub const TOUGH_IT_OUT = Skill{
    .name = "Tough It Out",
    .description = "Stance. (15 seconds.) Chills on you expire 50% faster.",
    .skill_type = .stance,
    .mechanic = .shift,
    .energy_cost = 5,
    .activation_time_ms = 0,
    .aftercast_ms = 0,
    .recharge_time_ms = 25000,
    .target_type = .self,
    .duration_ms = 15000,
    .effects = &chill_resist_effect_array,
};

// ============================================================================
// ENCHANTMENT-CONDITIONAL SKILLS
// ============================================================================

const fire_inside_strike_array = [_]effects.Effect{effects.FIRE_INSIDE_BONUS_EFFECT};

pub const INNER_FIRE_THROW = Skill{
    .name = "Inner Fire Throw",
    .description = "Throw. Deals 15 damage. +12 bonus damage while you have Fire Inside.",
    .skill_type = .throw,
    .mechanic = .windup,
    .energy_cost = 6,
    .activation_time_ms = 500,
    .aftercast_ms = 750,
    .recharge_time_ms = 6000,
    .damage = 15.0,
    .cast_range = 200.0,
    .effects = &fire_inside_strike_array,
};

const strip_cozy_effect_array = [_]effects.Effect{effects.STRIP_COZY_EFFECT};

pub const LAYER_STRIPPER = Skill{
    .name = "Layer Stripper",
    .description = "Throw. Deals 12 damage. +20 bonus damage against targets with Cozy effects.",
    .skill_type = .throw,
    .mechanic = .windup,
    .energy_cost = 8,
    .activation_time_ms = 750,
    .aftercast_ms = 750,
    .recharge_time_ms = 10000,
    .damage = 12.0,
    .cast_range = 220.0,
    .effects = &strip_cozy_effect_array,
};

// Default skill bar for new characters
pub const DEFAULT_SKILLS = [_]*const Skill{
    &QUICK_TOSS,
    &POWER_THROW,
    &SLUSH_BALL,
    &SNOW_IN_FACE,
    &BUNDLE_UP,
    &DODGE_ROLL,
    &WARM_UP,
    &GOGGLES_ON,
};

// ============================================================================
// ADVANCED PLACEMENT (AP) SKILLS - Build-Warping Elites
// ============================================================================
// AP skills FUNDAMENTALLY CHANGE how you play - they're not just "big damage".
// Like GW1's best elites:
// - Greater Conflagration: Changes all attacks in an area to fire damage
// - Illusionary Weaponry: Attacks can't miss/be blocked but deal fixed damage
// - Spiteful Spirit: Enemies damage themselves when they attack
//
// Good AP skills create:
// - New win conditions ("I win if X happens")
// - Synergy requirements ("I need allies who do Y")
// - Playstyle inversions ("I want enemies to attack me")
// - Positional gameplay ("The location of this effect matters")
// ============================================================================

// ----------------------------------------------------------------------------
// SLUSH ZONE (Ward-style AP) - Like Greater Conflagration
// ----------------------------------------------------------------------------
// Creates an area where ALL damage becomes Soggy (DoT). Changes team composition.
// You want allies with fast, weak attacks to apply maximum Soggy stacks.

/// [AP] SLUSH ZONE - All damage in area converts to Soggy stacks
/// Ward-style: creates persistent ground effect that changes combat rules
pub const SLUSH_ZONE = Skill{
    .name = "Slush Zone",
    .description = "[AP] Create a Slush Zone at target location for 20 seconds. ALL damage dealt within the zone (ally or enemy) is converted to Soggy stacks instead. 10 damage = 1 Soggy stack (5s DoT).",
    .skill_type = .trick,
    .mechanic = .concentrate,
    .energy_cost = 15,
    .activation_time_ms = 2000,
    .aftercast_ms = 750,
    .recharge_time_ms = 45000,
    .damage = 0.0, // No direct damage - converts damage to DoT
    .target_type = .ground,
    .aoe_type = .area,
    .aoe_radius = 200.0,
    .duration_ms = 20000,
    .terrain_effect = TerrainEffect.slush(.circle),
    .is_ap = true,
};

// ----------------------------------------------------------------------------
// PHANTOM THROW (Illusionary Weaponry-style AP)
// ----------------------------------------------------------------------------
// Your throws become phantoms - they ALWAYS hit, ignore blocks, but deal
// fixed damage regardless of buffs/conditions. Changes what you care about.

/// [AP] PHANTOM THROW - Attacks always hit but deal fixed damage
/// Stance: While active, throws can't miss or be blocked, but always deal exactly 12 damage
pub const PHANTOM_THROW = Skill{
    .name = "Phantom Throw",
    .description = "[AP] Stance. (30 seconds.) Your throws become phantoms. They cannot miss, cannot be blocked, and ignore armor. However, they ALWAYS deal exactly 12 damage regardless of any modifiers.",
    .skill_type = .stance,
    .mechanic = .shift,
    .energy_cost = 10,
    .activation_time_ms = 0,
    .aftercast_ms = 0,
    .recharge_time_ms = 30000,
    .damage = 12.0, // Fixed damage - this IS the damage, always
    .target_type = .self,
    .duration_ms = 30000,
    .is_ap = true,
};

// ----------------------------------------------------------------------------
// PRICKLY PRESENCE (Spiteful Spirit-style AP)
// ----------------------------------------------------------------------------
// Target damages THEMSELVES when they use skills. Complete playstyle inversion:
// you WANT the enemy to attack. Pairs with skills that force enemy actions.

const prickly_presence_effect_array = [_]effects.Effect{effects.THORNS_EFFECT};

/// [AP] PRICKLY PRESENCE - Target damages self when using skills
/// Hex: Target takes 15 damage each time they use a skill
pub const PRICKLY_PRESENCE = Skill{
    .name = "Prickly Presence",
    .description = "[AP] Hex target foe for 15 seconds. Each time target uses a skill, they take 15 damage. If they stop using skills, they take 5 damage per second instead.",
    .skill_type = .trick,
    .mechanic = .concentrate,
    .energy_cost = 15,
    .activation_time_ms = 1500,
    .aftercast_ms = 750,
    .recharge_time_ms = 25000,
    .damage = 15.0, // Damage per skill used
    .cast_range = 200.0,
    .duration_ms = 15000,
    .effects = &prickly_presence_effect_array,
    .is_ap = true,
};

// ----------------------------------------------------------------------------
// MIRROR MATCH (Copying/Stealing AP)
// ----------------------------------------------------------------------------
// Steal the TARGET'S equipped AP skill and use it against them.
// Creates mind games - do they equip a strong AP knowing you might steal it?

/// [AP] MIRROR MATCH - Steal and use target's AP skill
/// If target has an AP skill, you immediately use it on them
pub const MIRROR_MATCH = Skill{
    .name = "Mirror Match",
    .description = "[AP] Copy target foe's AP skill and immediately use it against them. If they have no AP skill, instead deal 25 damage and steal 5 energy.",
    .skill_type = .trick,
    .mechanic = .concentrate,
    .energy_cost = 10,
    .activation_time_ms = 1000, // Faster than most APs
    .aftercast_ms = 750,
    .recharge_time_ms = 30000,
    .damage = 25.0, // Fallback damage if no AP to steal
    .cast_range = 180.0,
    .is_ap = true,
};

// ----------------------------------------------------------------------------
// BUDDY SYSTEM (Team Synergy AP)
// ----------------------------------------------------------------------------
// Link yourself to an ally. You share damage taken (split 50/50) but ALSO
// share all Cozy effects. Creates positioning gameplay and target priority.

/// [AP] BUDDY SYSTEM - Link with ally to share damage and buffs
/// While linked: damage to either is split 50/50, Cozy effects apply to both
pub const BUDDY_SYSTEM = Skill{
    .name = "Buddy System",
    .description = "[AP] Link with target ally for 30 seconds. While linked: all damage to either of you is split 50/50 between both. All Cozy effects on either apply to both. Link breaks if you move more than 300 units apart.",
    .skill_type = .gesture,
    .mechanic = .ready,
    .energy_cost = 10,
    .activation_time_ms = 500,
    .aftercast_ms = 500,
    .recharge_time_ms = 40000,
    .target_type = .ally,
    .cast_range = 150.0,
    .duration_ms = 30000,
    .is_ap = true,
};

// ----------------------------------------------------------------------------
// SNOW FORT (Terrain Control AP)
// ----------------------------------------------------------------------------
// Build a wall that BLOCKS ALL PROJECTILES (ally and enemy). Creates zones
// of safety but also zones where YOU can't attack. Positional chess.

/// [AP] SNOW FORT - Create projectile-blocking wall
/// Wall blocks ALL projectiles passing through (both teams). Lasts 20 seconds.
pub const SNOW_FORT = Skill{
    .name = "Snow Fort",
    .description = "[AP] Build a snow fort wall in front of you. For 20 seconds, ALL projectiles (ally AND enemy) that hit the wall are destroyed. Wall has 100 health and can be destroyed by melee attacks.",
    .skill_type = .gesture,
    .mechanic = .concentrate,
    .energy_cost = 15,
    .activation_time_ms = 2000, // Takes time to build
    .aftercast_ms = 500,
    .recharge_time_ms = 35000,
    .target_type = .ground,
    .creates_wall = true,
    .wall_length = 200.0,
    .wall_height = 80.0,
    .wall_thickness = 30.0,
    .wall_distance_from_caster = 60.0,
    .duration_ms = 20000,
    .is_ap = true,
};

// ----------------------------------------------------------------------------
// COLD SHOULDER (Condition Transfer AP)
// ----------------------------------------------------------------------------
// ALL Chills on nearby ALLIES are transferred to target foe.
// Creates team play: allies intentionally get Chills knowing you'll dump them.

/// [AP] COLD SHOULDER - Transfer all ally Chills to target
/// Remove all Chills from allies in earshot and apply them to target foe
pub const COLD_SHOULDER = Skill{
    .name = "Cold Shoulder",
    .description = "[AP] Remove ALL Chill conditions from allies within earshot and apply them to target foe. Each transferred Chill deals 5 additional damage. Chills stack duration.",
    .skill_type = .call,
    .mechanic = .shout,
    .energy_cost = 15,
    .activation_time_ms = 0, // Instant shout
    .aftercast_ms = 750,
    .recharge_time_ms = 25000,
    .damage = 5.0, // Per chill transferred
    .target_type = .enemy,
    .aoe_radius = 250.0, // Earshot for ally check
    .cast_range = 200.0,
    .is_ap = true,
};

// ----------------------------------------------------------------------------
// KING OF THE HILL (Positional Dominance AP)
// ----------------------------------------------------------------------------
// While standing still, gain massive bonuses. Moving resets everything.
// Complete playstyle change: you become an immobile turret.

/// [AP] KING OF THE HILL - Massive bonuses while stationary
/// The longer you stand still, the stronger you get. Moving resets.
pub const KING_OF_THE_HILL = Skill{
    .name = "King of the Hill",
    .description = "[AP] Stance. (60 seconds.) While you don't move: +5% damage per second (max +50%), +5% damage reduction per second (max +50%), +2 energy regen. ANY movement resets all bonuses to 0%.",
    .skill_type = .stance,
    .mechanic = .shift,
    .energy_cost = 10,
    .activation_time_ms = 0,
    .aftercast_ms = 0,
    .recharge_time_ms = 60000, // Long cooldown - it's a commitment
    .target_type = .self,
    .duration_ms = 60000,
    .is_ap = true,
};

// ----------------------------------------------------------------------------
// FROSTBITE CHAIN (Spreading Condition AP)
// ----------------------------------------------------------------------------
// Target's Chills SPREAD to nearby foes when they expire.
// Changes how you apply conditions - hit one target, infect the group.

/// [AP] FROSTBITE CHAIN - Conditions spread on expiry
/// For 20 seconds, when any Chill expires on target, it spreads to 2 nearby foes
pub const FROSTBITE_CHAIN = Skill{
    .name = "Frostbite Chain",
    .description = "[AP] Hex target for 20 seconds. Whenever a Chill condition expires or is removed from target, it spreads to up to 2 nearby foes at full duration. Can chain indefinitely.",
    .skill_type = .trick,
    .mechanic = .concentrate,
    .energy_cost = 15,
    .activation_time_ms = 1500,
    .aftercast_ms = 750,
    .recharge_time_ms = 30000,
    .cast_range = 200.0,
    .duration_ms = 20000,
    .is_ap = true,
};

// ----------------------------------------------------------------------------
// HOT POTATO (Aggro Manipulation AP)
// ----------------------------------------------------------------------------
// Create a "hot potato" that bounces between foes. Whoever holds it when it
// explodes takes massive damage. Creates chaos and enemy decision-making.

/// [AP] HOT POTATO - Bouncing bomb between enemies
/// Mark target. After 3s, mark jumps to nearest enemy. After 5 jumps, explodes for 60 damage.
pub const HOT_POTATO = Skill{
    .name = "Hot Potato",
    .description = "[AP] Mark target foe with Hot Potato. Every 3 seconds, it jumps to the nearest enemy within 200 units. After 5 jumps (15 seconds), it EXPLODES dealing 60 damage to the holder and 30 to adjacent foes. If no valid target, explodes early.",
    .skill_type = .trick,
    .mechanic = .concentrate,
    .energy_cost = 15,
    .activation_time_ms = 1000,
    .aftercast_ms = 500,
    .recharge_time_ms = 35000,
    .damage = 60.0, // Explosion damage
    .cast_range = 200.0,
    .aoe_type = .adjacent,
    .aoe_radius = 100.0, // Explosion radius
    .duration_ms = 15000, // 5 jumps × 3 seconds
    .is_ap = true,
};

// ----------------------------------------------------------------------------
// LAST STAND (Risk/Reward AP)
// ----------------------------------------------------------------------------
// Become incredibly powerful but unable to be healed. At 1 HP you become
// invulnerable for 3 seconds then die. High risk, high reward.

/// [AP] LAST STAND - Power at the cost of healing
/// Massive damage boost but cannot receive healing. At 1 HP, 3s invuln then death.
pub const LAST_STAND = Skill{
    .name = "Last Stand",
    .description = "[AP] Stance. (Until cancelled or death.) Deal +50% damage, attack +30% faster. You CANNOT be healed by any source. When you would die, instead become invulnerable for 3 seconds, then die regardless of warmth.",
    .skill_type = .stance,
    .mechanic = .shift,
    .energy_cost = 5,
    .activation_time_ms = 0,
    .aftercast_ms = 0,
    .recharge_time_ms = 90000, // Very long CD - you probably died
    .target_type = .self,
    .duration_ms = 0, // Permanent until cancelled/death
    .is_ap = true,
};

// ----------------------------------------------------------------------------
// SNOW GLOBE (Complete Zone Control AP)
// ----------------------------------------------------------------------------
// Create a dome that traps everyone inside. No one enters or leaves for the
// duration. Forces a fight to the death in a confined space.

/// [AP] SNOW GLOBE - Trap everyone in a dome
/// Create impassable dome. No one inside can leave, no one outside can enter.
pub const SNOW_GLOBE = Skill{
    .name = "Snow Globe",
    .description = "[AP] Create an impassable Snow Globe centered on you for 10 seconds. All characters inside when cast are TRAPPED - they cannot leave. Characters outside cannot enter. Projectiles cannot pass through.",
    .skill_type = .trick,
    .mechanic = .concentrate,
    .energy_cost = 20,
    .activation_time_ms = 1500,
    .aftercast_ms = 500,
    .recharge_time_ms = 60000,
    .target_type = .self,
    .aoe_type = .area,
    .aoe_radius = 150.0,
    .duration_ms = 10000,
    .is_ap = true,
};

// ----------------------------------------------------------------------------
// REVERSE POLARITY (Healing Inversion AP)
// ----------------------------------------------------------------------------
// All healing on target becomes damage. All damage becomes healing.
// Completely inverts combat for one target - healers become killers.

/// [AP] REVERSE POLARITY - Swap healing and damage on target
/// Target receives damage from healing and healing from damage for 10 seconds
pub const REVERSE_POLARITY = Skill{
    .name = "Reverse Polarity",
    .description = "[AP] Hex target for 10 seconds. Healing received becomes damage. Damage received becomes healing. (Healing/damage is capped at 50 per instance to prevent one-shots.)",
    .skill_type = .trick,
    .mechanic = .concentrate,
    .energy_cost = 15,
    .activation_time_ms = 2000, // Slow cast - can be interrupted
    .aftercast_ms = 750,
    .recharge_time_ms = 45000,
    .cast_range = 200.0,
    .duration_ms = 10000,
    .is_ap = true,
};

// ============================================================================
// AP SKILL POOL - All Advanced Placement skills for factory/random selection
// ============================================================================

/// All AP skills in the game - used by factory for random AP skill assignment
pub const AP_SKILLS = [_]*const Skill{
    &SLUSH_ZONE,
    &PHANTOM_THROW,
    &PRICKLY_PRESENCE,
    &MIRROR_MATCH,
    &BUDDY_SYSTEM,
    &SNOW_FORT,
    &COLD_SHOULDER,
    &KING_OF_THE_HILL,
    &FROSTBITE_CHAIN,
    &HOT_POTATO,
    &LAST_STAND,
    &SNOW_GLOBE,
    &REVERSE_POLARITY,
};

/// Get a random AP skill from the pool
pub fn getRandomAPSkill(rng: *std.Random) *const Skill {
    const idx = rng.intRangeAtMost(usize, 0, AP_SKILLS.len - 1);
    return AP_SKILLS[idx];
}

/// Get the full AP skill pool (for iteration/UI)
pub fn getAPSkillPool() []const *const Skill {
    return &AP_SKILLS;
}
