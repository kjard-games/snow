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
    knocked_down, // Can't move or use skills (fallen in snow)
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
// AUTO-CAST CONDITIONS - For Boss Phase Transitions & Reactive Skills
// ============================================================================
// AutoCastCondition enables skills to trigger automatically when conditions are met.
// Primary use case: Boss phase transitions (e.g., "at 50% warmth, cast Enrage")
// Also supports: Reactive abilities, auras that pulse, etc.
//
// The AI system checks these conditions and auto-casts matching skills.
// This is DATA, not code - new phase behaviors are just new skill definitions.

/// Condition that triggers automatic skill casting
pub const AutoCastCondition = union(enum) {
    /// Never auto-cast (default for player skills)
    none,

    /// Cast when self warmth crosses below threshold (e.g., phase transitions)
    /// Only triggers once per threshold crossing (not continuously)
    warmth_below_percent: struct {
        threshold: f32, // 0.0 to 1.0 (e.g., 0.5 = 50%)
        only_once: bool = true, // Only trigger once per combat
    },

    /// Cast when self warmth crosses above threshold
    warmth_above_percent: struct {
        threshold: f32,
        only_once: bool = true,
    },

    /// Cast periodically while in combat
    periodic: struct {
        interval_ms: u32, // Time between casts
        start_delay_ms: u32 = 0, // Delay before first cast
    },

    /// Cast when a certain number of allies die
    ally_death_count: struct {
        count: u8, // Number of ally deaths to trigger
        within_radius: f32 = 0.0, // 0 = any ally, >0 = allies within radius
    },

    /// Cast when combat starts (good for opening moves / buffs)
    on_combat_start,

    /// Cast when entering aggro (when first player enters aggro radius)
    on_aggro,

    /// Cast when target acquired
    on_target_acquired,

    /// Cast when a specific number of enemies are in range
    enemies_in_range: struct {
        count: u8,
        range: f32,
    },

    /// Cast when any ally's warmth drops below threshold
    any_ally_warmth_below: struct {
        threshold: f32,
        cooldown_ms: u32 = 5000, // Don't spam heals
    },

    // Helper constructors
    pub fn phaseAt(health_percent: f32) AutoCastCondition {
        return .{ .warmth_below_percent = .{ .threshold = health_percent, .only_once = true } };
    }

    pub fn every(interval_ms: u32) AutoCastCondition {
        return .{ .periodic = .{ .interval_ms = interval_ms } };
    }

    pub fn everyWithDelay(interval_ms: u32, delay_ms: u32) AutoCastCondition {
        return .{ .periodic = .{ .interval_ms = interval_ms, .start_delay_ms = delay_ms } };
    }
};

// ============================================================================
// SKILL BEHAVIORS - Composable Trigger + Response System
// ============================================================================
// Behaviors intercept game events and respond with actions. They compose from:
// - BehaviorTrigger: WHEN does this activate? (on_would_die, on_take_damage, etc.)
// - BehaviorResponse: WHAT happens? (prevent, redirect, heal, summon, etc.)
// - EffectCondition: IF what condition? (reuses existing condition system)
// - EffectTarget: WHO is affected? (reuses existing targeting system)
//
// Philosophy: Effects modify stats. Behaviors intercept and redirect game flow.
//
// Adding new trigger/response types requires code. Combining existing ones is data.

/// When does this behavior activate?
pub const BehaviorTrigger = enum {
    // ========== Death/Damage Intercepts ==========
    on_would_die, // Before death is applied (prevent death skills)
    on_take_damage, // Before damage is applied to self
    on_ally_take_damage, // When a nearby/linked ally takes damage

    // ========== Projectile Intercepts ==========
    on_hit_by_projectile, // Before projectile damage hits self
    on_ally_hit_by_projectile, // Before projectile hits ally

    // ========== Targeting Intercepts ==========
    on_enemy_choose_target, // When enemy AI/player selects a target (taunt)

    // ========== Skill Intercepts ==========
    on_enemy_cast_nearby, // When enemy begins casting near self
    on_ally_cast, // When ally casts any skill

    // ========== Resource Intercepts ==========
    on_would_spend_energy, // Before energy is spent
    on_gain_rhythm, // Waldorf: when rhythm is gained
    on_gain_grit, // Public: when grit is gained

    // ========== Periodic/Passive ==========
    while_active, // Continuous effect while behavior is active (auras)
    on_skill_end, // When the skill's duration expires
};

/// How should damage be split among targets?
pub const SplitType = enum {
    equal, // Divide evenly among all targets
    proportional_max_warmth, // Split based on max warmth ratios
    absorb_remainder, // Primary target takes remainder after split
};

/// What type of summon to create?
pub const SummonType = enum {
    snowman, // Basic snowman minion
    abomination, // Large tanky creature
    suicide_snowman, // Explodes on death
    snow_fort, // Stationary turret-like summon
};

/// Parameters for summoning behaviors
pub const SummonParams = struct {
    summon_type: SummonType,
    count: u8 = 1,
    level: u8 = 1,
    duration_ms: u32 = 30000,
    damage_per_attack: f32 = 5.0,
    explode_damage: f32 = 0.0,
    explode_radius: f32 = 0.0,
};

/// What happens when the behavior triggers?
pub const BehaviorResponse = union(enum) {
    // ========== Prevention ==========
    prevent, // Stop the triggering event entirely (block damage, prevent death)

    // ========== Redirection ==========
    redirect_to_self, // Transfer the effect to self (Guardian Angel)
    redirect_to_source, // Send it back to whoever caused it (projectile return)
    redirect_to_target: effects.EffectTarget, // Redirect to specified target type

    // ========== Distribution ==========
    split_damage: struct {
        among: effects.EffectTarget, // Who to split among
        split_type: SplitType = .equal,
        share_percent: f32 = 1.0, // How much of the damage to share (1.0 = 100%)
    },

    // ========== Replacement ==========
    heal_percent: struct {
        percent: f32, // Heal to this % of max warmth
        grant_effect: ?*const effects.Effect = null, // Optional effect to grant after healing
    },
    grant_effect: *const effects.Effect, // Apply an effect instead
    deal_damage: struct {
        amount: f32,
        to: effects.EffectTarget = .source_of_damage, // Default: damage whoever triggered this
    },

    // ========== Forced Targeting ==========
    force_target_self, // Make enemies target self (taunt)

    // ========== Summoning ==========
    summon: SummonParams,

    // ========== Chaining ==========
    chain: *const Behavior, // Trigger another behavior after this one
};

/// A composable behavior: trigger + response + conditions
pub const Behavior = struct {
    /// What event triggers this behavior?
    trigger: BehaviorTrigger,

    /// What happens when triggered?
    response: BehaviorResponse,

    /// Optional condition that must be true for behavior to activate
    /// Reuses the existing EffectCondition system
    condition: effects.EffectCondition = .always,

    /// Who does this behavior affect/monitor?
    /// Reuses the existing EffectTarget system
    target: effects.EffectTarget = .self,

    /// How long does this behavior last? (0 = one-shot/instant)
    duration_ms: u32 = 0,

    /// Cooldown before behavior can trigger again (0 = no cooldown)
    cooldown_ms: u32 = 0,

    /// Max times this can activate (0 = unlimited)
    max_activations: u8 = 0,

    // ========================================================================
    // PREDEFINED BEHAVIOR INSTANCES
    // ========================================================================

    /// Taunt: Forces nearby enemies to target self
    pub fn taunt(duration_ms: u32) Behavior {
        return .{
            .trigger = .on_enemy_choose_target,
            .response = .force_target_self,
            .target = .foes_in_earshot,
            .duration_ms = duration_ms,
        };
    }

    /// Prevent Death: When you would die, heal to X% instead
    /// Optionally grants an effect (like invulnerability) after healing
    pub fn preventDeath(heal_to_percent: f32, invuln_effect: ?*const effects.Effect) Behavior {
        return .{
            .trigger = .on_would_die,
            .response = .{ .heal_percent = .{
                .percent = heal_to_percent,
                .grant_effect = invuln_effect,
            } },
            .max_activations = 1,
        };
    }

    /// Spirit Link: Share damage among linked allies
    pub fn spiritLink(duration_ms: u32, share_percent: f32) Behavior {
        return .{
            .trigger = .on_ally_take_damage,
            .response = .{ .split_damage = .{
                .among = .linked_allies,
                .split_type = .equal,
                .share_percent = share_percent,
            } },
            .target = .linked_allies,
            .duration_ms = duration_ms,
        };
    }

    /// Guardian Angel: Redirect damage from target ally to self
    pub fn guardianAngel(duration_ms: u32, redirect_percent: f32) Behavior {
        _ = redirect_percent; // TODO: Use this in split_damage
        return .{
            .trigger = .on_ally_take_damage,
            .response = .redirect_to_self,
            .target = .target, // The ally you cast this on
            .duration_ms = duration_ms,
        };
    }

    /// Catch and Return: Block next projectile and send it back
    pub fn projectileReturn(return_damage: f32) Behavior {
        return .{
            .trigger = .on_hit_by_projectile,
            .response = .{ .deal_damage = .{
                .amount = return_damage,
                .to = .source_of_damage,
            } },
            .max_activations = 1,
        };
    }

    /// Summon: Create minions
    pub fn summonCreature(params: SummonParams) Behavior {
        return .{
            .trigger = .while_active, // Summons persist while active
            .response = .{ .summon = params },
            .duration_ms = params.duration_ms,
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

    // Complex skill behavior (summons, links, redirects, etc.)
    // A skill can have at most ONE behavior. These need dedicated combat system handling.
    // null = no special behavior (most skills)
    behavior: ?*const Behavior = null,

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
