const std = @import("std");
const skills = @import("skills.zig");
const effects = @import("effects.zig");

// ============================================================================
// COLOR PIE DESIGN - Magic: The Gathering style identity system
// ============================================================================
//
// Each School has primary/secondary/tertiary access to:
// - Skill Types (throw, trick, stance, call, gesture)
// - Effect Categories (what kinds of modifiers/conditions they can use)
// - Damage ranges
// - Cooldown ranges
//
// Each Position specializes within these constraints.
//
// The color pie now integrates with the composable effects system in effects.zig.
// Schools have access levels to EFFECT CATEGORIES rather than specific chills/cozies.
// This allows the same modifier (e.g., damage_multiplier) to be flavored differently
// per school while maintaining mechanical balance.
//
// ============================================================================

pub const AccessLevel = enum {
    none,
    tertiary, // Conditional/rare access
    secondary, // Common but not core
    primary, // Core identity

    /// Returns a multiplier for effect potency based on access level
    /// Primary access = full power, secondary = 75%, tertiary = 50%
    pub fn potencyMultiplier(self: AccessLevel) f32 {
        return switch (self) {
            .none => 0.0,
            .tertiary => 0.5,
            .secondary => 0.75,
            .primary => 1.0,
        };
    }

    /// Returns max duration multiplier for effects at this access level
    pub fn durationMultiplier(self: AccessLevel) f32 {
        return switch (self) {
            .none => 0.0,
            .tertiary => 0.6,
            .secondary => 0.8,
            .primary => 1.0,
        };
    }
};

// ============================================================================
// SCHOOL COLOR PIE (5 schools = 5 colors)
// ============================================================================
//
// Each school maps to an MTG color philosophy:
//
// PRIVATE SCHOOL (White: Order, Privilege, Resources)
// - Effect Focus: Defense (armor, blocking), Resource efficiency (energy regen)
// - Debuff Access: Limited (only defensive/retaliatory)
// - Buff Access: Primary (damage reduction, max health, shields)
// - Conditionals: "While not in debt", "if ally nearby"
// - Damage Range: 8-15 (consistent, reliable)
// - Cooldowns: Long (15-30s) but powerful
// - Theme: "Money solves problems" - expensive but effective buffs
//
// PUBLIC SCHOOL (Red: Aggression, Grit, Combat)
// - Effect Focus: Damage (multipliers, flat bonuses), Speed (attack, movement)
// - Debuff Access: Primary (DoT, slows, accuracy reduction)
// - Buff Access: Tertiary (fire_inside only, gained through combat)
// - Conditionals: "if has Grit", "if target moving", "on hit"
// - Damage Range: 12-25 (high variance, risk/reward)
// - Cooldowns: Short (3-8s) but requires Grit stacks
// - Theme: "Scrappy fighter" - high damage, minimal defense
//
// MONTESSORI (Green: Adaptation, Variety, Growth)
// - Effect Focus: Versatility (all modifier types at secondary)
// - Debuff Access: Secondary (varied, but not extreme)
// - Buff Access: Secondary (varied, rewards diversity)
// - Conditionals: "if used different skill type", terrain conditions
// - Damage Range: 10-18 (scales with variety)
// - Cooldowns: Medium (8-15s) rewards diversity
// - Theme: "Self-directed learning" - rewarded for trying different things
//
// HOMESCHOOL (Black: Sacrifice, Power, Isolation)
// - Effect Focus: Extreme effects (big numbers), Resource conversion
// - Debuff Access: Primary (crippling: max health, energy degen, skill disable)
// - Buff Access: None (self-reliant, no external help)
// - Conditionals: "if caster isolated", "if sacrificed recently", "if target below X%"
// - Damage Range: 15-30 (pays health for damage)
// - Cooldowns: Very long (20-40s) but devastating
// - Theme: "Sacrifice for power" - hurt yourself to hurt them more
//
// WALDORF (Blue: Rhythm, Timing, Harmony)
// - Effect Focus: Timing (cast speed, cooldowns), Team synergy
// - Debuff Access: Secondary (control: slows, accuracy)
// - Buff Access: Primary (team-wide, healing amplification)
// - Conditionals: "if has Rhythm", "on block", "on interrupt", skill type chains
// - Damage Range: 5-20 (depends on timing)
// - Cooldowns: Rhythmic (must alternate skill types for bonuses)
// - Theme: "Flow state" - chaining skills in rhythm

// ============================================================================
// POSITION SPECIALIZATIONS (6 positions)
// ============================================================================
//
// Positions define HOW effects are delivered:
// - Range (close/medium/long)
// - Targeting (self, single, adjacent, AoE, allies)
// - Timing (proactive vs reactive, on_hit vs on_cast)
// - Skill type preferences
//
// School x Position = Full character identity
//
// PITCHER (Pure Damage Dealer)
// - Primary Schools: Public School, Homeschool
// - Skill Types: Throw (primary), Gesture (finishers)
// - Targeting: Single target, long range (200-300 units)
// - Timing: Proactive (on_hit, on_kill, on_crit)
// - Effect Delivery: Direct damage, DoT application
// - Theme: The kid with the cannon arm
//
// FIELDER (Balanced Generalist)
// - Primary Schools: Montessori, Public School
// - Skill Types: Throw, Stance (equal mix)
// - Targeting: Flexible (single + adjacent), medium range (150-220 units)
// - Timing: Mixed (on_hit + while_active)
// - Effect Delivery: Moderate everything
// - Theme: Athletic all-rounder, adapts to the situation
//
// SLEDDER (Aggressive Skirmisher)
// - Primary Schools: Public School, Waldorf
// - Skill Types: Throw (close), Stance (mobility)
// - Targeting: Adjacent AoE, close range (80-150 units)
// - Timing: Proactive + reactive (on_hit, on_take_damage)
// - Effect Delivery: Burst damage, self-buffs, control
// - Theme: Uses sled for mobility and ramming attacks
//
// SHOVELER (Tank/Defender)
// - Primary Schools: Private School, Homeschool
// - Skill Types: Stance (defensive), Gesture (fortifications)
// - Targeting: Self + allies_near_target, short-medium range (100-160 units)
// - Timing: Reactive (on_take_damage, on_block, while_active)
// - Effect Delivery: Damage reduction, blocking, reflects
// - Theme: Digs in, builds walls, the immovable kid
//
// ANIMATOR (Summoner/Necromancer)
// - Primary Schools: Homeschool, Waldorf
// - Skill Types: Trick (summons), Call (commands)
// - Targeting: Pet, all_summons, ground-targeted
// - Timing: On_cast, while_active (sustained summons)
// - Effect Delivery: Summon creatures, command effects
// - Theme: Brings snowmen to life (Calvin and Hobbes grotesque snowmen)
//
// THERMOS (Healer/Support)
// - Primary Schools: Waldorf, Private School
// - Skill Types: Call (team buffs), Gesture (healing)
// - Targeting: Allies_in_earshot, allies_near_target, backline (150-200 units)
// - Timing: On_cast (instant team support), while_active (auras)
// - Effect Delivery: Healing, team buffs, condition cleanse
// - Theme: Kid who brings thermoses of hot cocoa, hand warmers, extra scarves

// ============================================================================
// EFFECT CATEGORIES - Grouped by mechanical purpose
// ============================================================================
// These map to EffectModifier types in effects.zig but grouped for color pie access

pub const EffectCategory = enum {
    // === OFFENSIVE (Debuffs / Chills) ===
    damage_over_time, // soggy, windburn - maps to damage_add with timing
    movement_impair, // slippery - maps to move_speed_multiplier < 1.0
    accuracy_impair, // frost_eyes - maps to accuracy_multiplier < 1.0
    damage_amp, // numb (target takes more) - maps to damage_multiplier > 1.0 on target
    resource_drain, // brain_freeze - maps to energy_regen_multiplier < 1.0
    max_health_reduce, // packed_snow - maps to armor_add < 0 (effectively)
    skill_disable, // dazed, brain_freeze_disable - maps to skills_disabled

    // === DEFENSIVE (Buffs / Cozies) ===
    damage_reduction, // bundled_up - maps to damage_multiplier < 1.0 on self (incoming)
    healing_over_time, // hot_cocoa - maps to healing via timing
    damage_boost, // fire_inside - maps to damage_multiplier > 1.0 on attacks
    condition_immunity, // snow_goggles - maps to specific immunity flags
    resource_boost, // insulated - maps to energy_regen_multiplier > 1.0
    movement_boost, // sure_footed - maps to move_speed_multiplier > 1.0
    max_health_boost, // frosty_fortitude - maps to armor_add > 0
    blocking, // snowball_shield - maps to block_chance, block_next_attack

    // === UTILITY ===
    cooldown_reduction, // maps to cooldown_reduction_percent
    cast_speed, // maps to cast_speed_multiplier
    attack_speed, // maps to attack_speed_multiplier
    evasion, // maps to evasion_percent

    // === DURATION MODIFICATION ===
    extend_debuffs, // lingering cold - maps to chill_duration_multiplier > 1.0
    extend_buffs, // cozy aura - maps to cozy_duration_multiplier > 1.0
    shorten_debuffs, // chill resistance - maps to chill_duration_multiplier < 1.0
};

// ============================================================================
// CONDITION CATEGORIES - Grouped by what they check
// ============================================================================
// These map to EffectCondition in effects.zig

pub const ConditionCategory = enum {
    // === WARMTH (Health) ===
    target_warmth, // if_target_above/below_X_percent_warmth
    caster_warmth, // if_caster_above/below_X_percent_warmth
    relative_warmth, // if_target_has_more/less_warmth

    // === STATUS EFFECTS ===
    target_has_debuff, // if_target_has_any_chill, if_target_has_chill_X
    target_has_buff, // if_target_has_any_cozy, if_target_has_cozy_X
    caster_has_debuff, // if_caster_has_any_chill
    caster_has_buff, // if_caster_has_cozy_X (for "while enchanted" effects)

    // === MOVEMENT ===
    target_movement, // if_target_moving, if_target_not_moving
    caster_movement, // if_caster_moving, if_caster_not_moving

    // === COMBAT STATE ===
    target_casting, // if_target_casting, if_target_not_casting
    target_blocking, // if_target_blocking
    target_knocked_down, // if_target_knocked_down

    // === SCHOOL RESOURCES ===
    private_debt, // if_caster_in_debt, if_caster_not_in_debt
    public_grit, // if_caster_has_grit, if_caster_has_grit_X_plus
    waldorf_rhythm, // if_caster_has_rhythm, if_caster_has_rhythm_X_plus
    montessori_variety, // if_caster_used_different_type, if_caster_used_same_type
    homeschool_sacrifice, // if_caster_sacrificed_recently, if_caster_isolated

    // === POSITIONAL ===
    near_terrain, // if_near_wall, if_behind_wall
    near_allies, // if_near_ally, if_caster_isolated
    target_isolation, // if_target_near_ally, if_target_isolated

    // === TERRAIN ===
    caster_terrain, // if_on_ice, if_on_deep_snow, etc.
    target_terrain, // if_target_on_ice, if_target_on_deep_snow

    // === SKILL CHAINS ===
    last_skill_type, // if_last_skill_was_throw/trick/stance/call/gesture
};

// ============================================================================
// TARGETING CATEGORIES - For position access
// ============================================================================

pub const TargetingCategory = enum {
    self_only, // self
    single_target, // target
    adjacent_to_self, // adjacent_to_self (melee cleave)
    adjacent_to_target, // adjacent_to_target (ranged AoE)
    allies_nearby, // allies_near_target, allies_in_earshot
    foes_nearby, // foes_near_target, foes_in_earshot
    reactive_source, // source_of_damage (reflects/revenge)
    summons, // pet, all_summons
};

// ============================================================================
// TIMING CATEGORIES - For position access
// ============================================================================

pub const TimingCategory = enum {
    on_hit, // Standard attack effects
    on_cast, // Instant on skill use
    on_end, // When duration expires
    on_removed_early, // Dervish-style flash enchants
    while_active, // Continuous auras/stances
    reactive, // on_take_damage, on_block, on_miss, on_interrupted
    proactive, // on_deal_damage, on_kill, on_crit, on_interrupt
};

// ============================================================================
// SCHOOL EFFECT ACCESS - What effect categories each school can use
// ============================================================================

pub const SchoolEffectAccess = struct {
    // Offensive (Debuffs)
    damage_over_time: AccessLevel,
    movement_impair: AccessLevel,
    accuracy_impair: AccessLevel,
    damage_amp: AccessLevel,
    resource_drain: AccessLevel,
    max_health_reduce: AccessLevel,
    skill_disable: AccessLevel,

    // Defensive (Buffs)
    damage_reduction: AccessLevel,
    healing_over_time: AccessLevel,
    damage_boost: AccessLevel,
    condition_immunity: AccessLevel,
    resource_boost: AccessLevel,
    movement_boost: AccessLevel,
    max_health_boost: AccessLevel,
    blocking: AccessLevel,

    // Utility
    cooldown_reduction: AccessLevel,
    cast_speed: AccessLevel,
    attack_speed: AccessLevel,
    evasion: AccessLevel,

    // Duration Mods
    extend_debuffs: AccessLevel,
    extend_buffs: AccessLevel,
    shorten_debuffs: AccessLevel,
};

pub const SchoolConditionAccess = struct {
    // Warmth checks
    target_warmth: AccessLevel,
    caster_warmth: AccessLevel,
    relative_warmth: AccessLevel,

    // Status checks
    target_has_debuff: AccessLevel,
    target_has_buff: AccessLevel,
    caster_has_buff: AccessLevel,

    // Movement checks
    target_movement: AccessLevel,

    // Combat state
    target_casting: AccessLevel,
    target_blocking: AccessLevel,
    target_knocked_down: AccessLevel,

    // School-specific (each school has primary access to their own resource)
    own_resource: AccessLevel, // grit/rhythm/debt/variety/sacrifice

    // Positional (shared with position access)
    isolation: AccessLevel,
    terrain: AccessLevel,
};

// ============================================================================
// POSITION EFFECT ACCESS - How effects are delivered
// ============================================================================

pub const PositionTargetingAccess = struct {
    self_only: AccessLevel,
    single_target: AccessLevel,
    adjacent_to_self: AccessLevel,
    adjacent_to_target: AccessLevel,
    allies_nearby: AccessLevel,
    foes_nearby: AccessLevel,
    reactive_source: AccessLevel,
    summons: AccessLevel,
};

pub const PositionTimingAccess = struct {
    on_hit: AccessLevel,
    on_cast: AccessLevel,
    on_end: AccessLevel,
    on_removed_early: AccessLevel,
    while_active: AccessLevel,
    reactive: AccessLevel,
    proactive: AccessLevel,
};

pub const PositionRangeProfile = struct {
    min_range: f32,
    max_range: f32,
    preferred_range: f32,
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

const School = @import("school.zig").School;

pub fn getSchoolEffectAccess(school: School) SchoolEffectAccess {
    return switch (school) {
        .private_school => .{
            // Offensive - Limited (defensive school)
            .damage_over_time = .none,
            .movement_impair = .none,
            .accuracy_impair = .none,
            .damage_amp = .tertiary, // Only when defending
            .resource_drain = .none,
            .max_health_reduce = .none,
            .skill_disable = .none,
            // Defensive - Primary identity
            .damage_reduction = .primary,
            .healing_over_time = .secondary,
            .damage_boost = .none,
            .condition_immunity = .secondary,
            .resource_boost = .primary, // Wealth = resources
            .movement_boost = .none,
            .max_health_boost = .primary,
            .blocking = .secondary,
            // Utility
            .cooldown_reduction = .secondary,
            .cast_speed = .none,
            .attack_speed = .none,
            .evasion = .none,
            // Duration
            .extend_debuffs = .none,
            .extend_buffs = .primary, // Make buffs last longer
            .shorten_debuffs = .secondary,
        },
        .public_school => .{
            // Offensive - Primary identity
            .damage_over_time = .primary, // soggy, windburn
            .movement_impair = .secondary, // slippery
            .accuracy_impair = .secondary, // frost_eyes
            .damage_amp = .secondary,
            .resource_drain = .none,
            .max_health_reduce = .none,
            .skill_disable = .none,
            // Defensive - Very limited
            .damage_reduction = .none,
            .healing_over_time = .none,
            .damage_boost = .tertiary, // fire_inside via Grit
            .condition_immunity = .none,
            .resource_boost = .none,
            .movement_boost = .secondary, // sure_footed
            .max_health_boost = .none,
            .blocking = .none,
            // Utility
            .cooldown_reduction = .secondary, // Fast skills
            .cast_speed = .none,
            .attack_speed = .secondary,
            .evasion = .none,
            // Duration
            .extend_debuffs = .secondary, // DoTs last longer
            .extend_buffs = .none,
            .shorten_debuffs = .none,
        },
        .montessori => .{
            // Offensive - Secondary across the board (versatile)
            .damage_over_time = .secondary,
            .movement_impair = .secondary,
            .accuracy_impair = .secondary,
            .damage_amp = .secondary,
            .resource_drain = .secondary,
            .max_health_reduce = .secondary,
            .skill_disable = .tertiary,
            // Defensive - Secondary across the board
            .damage_reduction = .secondary,
            .healing_over_time = .secondary,
            .damage_boost = .secondary,
            .condition_immunity = .secondary,
            .resource_boost = .secondary,
            .movement_boost = .primary, // sure_footed is core
            .max_health_boost = .secondary,
            .blocking = .secondary,
            // Utility - Primary (variety = efficiency)
            .cooldown_reduction = .secondary,
            .cast_speed = .secondary,
            .attack_speed = .secondary,
            .evasion = .secondary,
            // Duration
            .extend_debuffs = .secondary,
            .extend_buffs = .secondary,
            .shorten_debuffs = .secondary,
        },
        .homeschool => .{
            // Offensive - Primary (crippling debuffs)
            .damage_over_time = .secondary,
            .movement_impair = .none,
            .accuracy_impair = .none,
            .damage_amp = .primary, // Exploit weakness
            .resource_drain = .primary, // brain_freeze
            .max_health_reduce = .primary, // packed_snow
            .skill_disable = .primary, // Dark arts
            // Defensive - None (solo, no external help)
            .damage_reduction = .none,
            .healing_over_time = .none,
            .damage_boost = .secondary, // fire_inside via sacrifice
            .condition_immunity = .none,
            .resource_boost = .none,
            .movement_boost = .none,
            .max_health_boost = .none,
            .blocking = .none,
            // Utility - Limited
            .cooldown_reduction = .none,
            .cast_speed = .none,
            .attack_speed = .secondary,
            .evasion = .none,
            // Duration
            .extend_debuffs = .primary, // Curses last forever
            .extend_buffs = .none,
            .shorten_debuffs = .none,
        },
        .waldorf => .{
            // Offensive - Secondary (control, not damage)
            .damage_over_time = .none,
            .movement_impair = .secondary, // slippery
            .accuracy_impair = .tertiary,
            .damage_amp = .none,
            .resource_drain = .none,
            .max_health_reduce = .none,
            .skill_disable = .tertiary, // On perfect timing
            // Defensive - Primary (team support)
            .damage_reduction = .secondary,
            .healing_over_time = .primary, // hot_cocoa
            .damage_boost = .none,
            .condition_immunity = .primary, // snow_goggles (team)
            .resource_boost = .secondary,
            .movement_boost = .secondary,
            .max_health_boost = .none,
            .blocking = .tertiary, // Perfect timing only
            // Utility - Primary (rhythm = efficiency)
            .cooldown_reduction = .primary, // Flow state
            .cast_speed = .primary, // Rhythm bonuses
            .attack_speed = .secondary,
            .evasion = .secondary,
            // Duration
            .extend_debuffs = .none,
            .extend_buffs = .secondary,
            .shorten_debuffs = .secondary,
        },
    };
}

pub fn getSchoolConditionAccess(school: School) SchoolConditionAccess {
    return switch (school) {
        .private_school => .{
            .target_warmth = .secondary,
            .caster_warmth = .secondary,
            .relative_warmth = .none,
            .target_has_debuff = .none,
            .target_has_buff = .secondary, // Check if ally buffed
            .caster_has_buff = .primary, // "While enchanted"
            .target_movement = .none,
            .target_casting = .none,
            .target_blocking = .secondary,
            .target_knocked_down = .none,
            .own_resource = .primary, // Debt conditions
            .isolation = .none,
            .terrain = .tertiary,
        },
        .public_school => .{
            .target_warmth = .secondary, // Execute low health
            .caster_warmth = .tertiary,
            .relative_warmth = .secondary,
            .target_has_debuff = .primary, // Exploit conditions
            .target_has_buff = .none,
            .caster_has_buff = .tertiary,
            .target_movement = .primary, // Chase down
            .target_casting = .secondary, // Interrupt
            .target_blocking = .secondary,
            .target_knocked_down = .secondary,
            .own_resource = .primary, // Grit conditions
            .isolation = .none,
            .terrain = .tertiary,
        },
        .montessori => .{
            .target_warmth = .secondary,
            .caster_warmth = .secondary,
            .relative_warmth = .secondary,
            .target_has_debuff = .secondary,
            .target_has_buff = .secondary,
            .caster_has_buff = .secondary,
            .target_movement = .secondary,
            .target_casting = .secondary,
            .target_blocking = .secondary,
            .target_knocked_down = .secondary,
            .own_resource = .primary, // Variety conditions
            .isolation = .secondary,
            .terrain = .primary, // Terrain mastery
        },
        .homeschool => .{
            .target_warmth = .primary, // Finishing blow
            .caster_warmth = .primary, // Sacrifice thresholds
            .relative_warmth = .primary,
            .target_has_debuff = .secondary,
            .target_has_buff = .primary, // Strip enchantments
            .caster_has_buff = .none,
            .target_movement = .none,
            .target_casting = .secondary,
            .target_blocking = .none,
            .target_knocked_down = .primary, // Kick when down
            .own_resource = .primary, // Sacrifice/isolation
            .isolation = .primary, // Isolation power
            .terrain = .none,
        },
        .waldorf => .{
            .target_warmth = .secondary,
            .caster_warmth = .none,
            .relative_warmth = .none,
            .target_has_debuff = .secondary,
            .target_has_buff = .secondary,
            .caster_has_buff = .primary, // "While enchanted"
            .target_movement = .secondary,
            .target_casting = .primary, // Interrupt timing
            .target_blocking = .primary, // Counter-play
            .target_knocked_down = .secondary,
            .own_resource = .primary, // Rhythm conditions
            .isolation = .none,
            .terrain = .secondary,
        },
    };
}

pub fn getSkillTypeAccess(school: School) SkillTypeAccess {
    return switch (school) {
        .private_school => .{
            .throw = .secondary,
            .trick = .none,
            .stance = .primary, // Defensive stances
            .call = .secondary,
            .gesture = .primary, // Signets (free utility)
        },
        .public_school => .{
            .throw = .primary, // Core attack type
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
            .throw = .tertiary, // On rhythm only
            .trick = .primary, // Artistic expression
            .stance = .secondary,
            .call = .primary, // Team harmony (shouts)
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

pub fn getCooldownRange(school: School) CooldownRange {
    return switch (school) {
        .private_school => .{ .min_ms = 15000, .max_ms = 30000 }, // Long but powerful
        .public_school => .{ .min_ms = 3000, .max_ms = 8000 }, // Fast, requires Grit
        .montessori => .{ .min_ms = 8000, .max_ms = 15000 }, // Medium
        .homeschool => .{ .min_ms = 20000, .max_ms = 40000 }, // Very long, devastating
        .waldorf => .{ .min_ms = 5000, .max_ms = 15000 }, // Rhythmic
    };
}

// ============================================================================
// POSITION ACCESS TABLES
// ============================================================================

const Position = @import("position.zig").Position;

pub fn getPositionTargetingAccess(position: Position) PositionTargetingAccess {
    return switch (position) {
        .pitcher => .{
            .self_only = .tertiary,
            .single_target = .primary, // Sniper
            .adjacent_to_self = .none,
            .adjacent_to_target = .secondary, // Some AoE
            .allies_nearby = .none,
            .foes_nearby = .secondary,
            .reactive_source = .none,
            .summons = .none,
        },
        .fielder => .{
            .self_only = .secondary,
            .single_target = .primary,
            .adjacent_to_self = .secondary, // Flexible
            .adjacent_to_target = .secondary,
            .allies_nearby = .tertiary, // Some team support
            .foes_nearby = .secondary,
            .reactive_source = .tertiary,
            .summons = .none,
        },
        .sledder => .{
            .self_only = .secondary, // Self-buffs
            .single_target = .primary,
            .adjacent_to_self = .primary, // Melee cleave
            .adjacent_to_target = .secondary,
            .allies_nearby = .none,
            .foes_nearby = .secondary,
            .reactive_source = .secondary, // Counter-attacks
            .summons = .none,
        },
        .shoveler => .{
            .self_only = .primary, // Self-defense
            .single_target = .secondary,
            .adjacent_to_self = .secondary,
            .adjacent_to_target = .tertiary,
            .allies_nearby = .secondary, // Protect allies
            .foes_nearby = .tertiary,
            .reactive_source = .primary, // Reflects/revenge
            .summons = .none,
        },
        .animator => .{
            .self_only = .secondary,
            .single_target = .secondary,
            .adjacent_to_self = .tertiary,
            .adjacent_to_target = .secondary,
            .allies_nearby = .none,
            .foes_nearby = .tertiary,
            .reactive_source = .none,
            .summons = .primary, // Core identity
        },
        .thermos => .{
            .self_only = .secondary,
            .single_target = .primary, // Single heals
            .adjacent_to_self = .tertiary,
            .adjacent_to_target = .tertiary,
            .allies_nearby = .primary, // Team healer
            .foes_nearby = .none,
            .reactive_source = .none,
            .summons = .none,
        },
    };
}

pub fn getPositionTimingAccess(position: Position) PositionTimingAccess {
    return switch (position) {
        .pitcher => .{
            .on_hit = .primary,
            .on_cast = .secondary,
            .on_end = .tertiary,
            .on_removed_early = .none,
            .while_active = .secondary,
            .reactive = .none,
            .proactive = .primary, // on_kill, on_crit
        },
        .fielder => .{
            .on_hit = .primary,
            .on_cast = .secondary,
            .on_end = .secondary,
            .on_removed_early = .tertiary,
            .while_active = .secondary,
            .reactive = .secondary,
            .proactive = .secondary,
        },
        .sledder => .{
            .on_hit = .primary,
            .on_cast = .secondary,
            .on_end = .secondary,
            .on_removed_early = .secondary, // Flash enchants
            .while_active = .primary, // Stances
            .reactive = .secondary, // Counter on hit
            .proactive = .primary, // Aggressive
        },
        .shoveler => .{
            .on_hit = .secondary,
            .on_cast = .secondary,
            .on_end = .secondary,
            .on_removed_early = .secondary,
            .while_active = .primary, // Defensive stances
            .reactive = .primary, // on_take_damage, on_block
            .proactive = .tertiary,
        },
        .animator => .{
            .on_hit = .secondary,
            .on_cast = .primary, // Summons trigger on cast
            .on_end = .secondary, // Summon expiry
            .on_removed_early = .secondary,
            .while_active = .primary, // Sustained summons
            .reactive = .tertiary,
            .proactive = .secondary,
        },
        .thermos => .{
            .on_hit = .tertiary,
            .on_cast = .primary, // Instant heals
            .on_end = .secondary,
            .on_removed_early = .tertiary,
            .while_active = .primary, // Auras, HoTs
            .reactive = .secondary, // Emergency heals
            .proactive = .none,
        },
    };
}

pub fn getPositionRangeProfile(position: Position) PositionRangeProfile {
    return switch (position) {
        .pitcher => .{ .min_range = 200.0, .max_range = 300.0, .preferred_range = 250.0 },
        .fielder => .{ .min_range = 150.0, .max_range = 220.0, .preferred_range = 180.0 },
        .sledder => .{ .min_range = 80.0, .max_range = 150.0, .preferred_range = 100.0 },
        .shoveler => .{ .min_range = 100.0, .max_range = 160.0, .preferred_range = 130.0 },
        .animator => .{ .min_range = 180.0, .max_range = 240.0, .preferred_range = 200.0 },
        .thermos => .{ .min_range = 150.0, .max_range = 200.0, .preferred_range = 175.0 },
    };
}

// ============================================================================
// COMBINED ACCESS HELPERS
// ============================================================================

/// Check if a school+position combination has access to an effect category
/// Returns the effective access level (minimum of school and position requirements)
pub fn getEffectCategoryAccess(school: School, position: Position, category: EffectCategory) AccessLevel {
    const school_access = getSchoolEffectAccess(school);
    const pos_targeting = getPositionTargetingAccess(position);
    const pos_timing = getPositionTimingAccess(position);

    // Get the school's access to this effect category
    const school_level: AccessLevel = switch (category) {
        .damage_over_time => school_access.damage_over_time,
        .movement_impair => school_access.movement_impair,
        .accuracy_impair => school_access.accuracy_impair,
        .damage_amp => school_access.damage_amp,
        .resource_drain => school_access.resource_drain,
        .max_health_reduce => school_access.max_health_reduce,
        .skill_disable => school_access.skill_disable,
        .damage_reduction => school_access.damage_reduction,
        .healing_over_time => school_access.healing_over_time,
        .damage_boost => school_access.damage_boost,
        .condition_immunity => school_access.condition_immunity,
        .resource_boost => school_access.resource_boost,
        .movement_boost => school_access.movement_boost,
        .max_health_boost => school_access.max_health_boost,
        .blocking => school_access.blocking,
        .cooldown_reduction => school_access.cooldown_reduction,
        .cast_speed => school_access.cast_speed,
        .attack_speed => school_access.attack_speed,
        .evasion => school_access.evasion,
        .extend_debuffs => school_access.extend_debuffs,
        .extend_buffs => school_access.extend_buffs,
        .shorten_debuffs => school_access.shorten_debuffs,
    };

    // Some categories require specific position capabilities
    // E.g., healing_over_time is gated by allies_nearby targeting
    const pos_gate: AccessLevel = switch (category) {
        .healing_over_time => pos_targeting.allies_nearby,
        .damage_over_time => pos_timing.on_hit,
        .blocking => pos_timing.reactive,
        .damage_amp => pos_timing.proactive,
        else => .primary, // No position gate
    };

    // Return the minimum of school access and position gate
    return minAccessLevel(school_level, pos_gate);
}

/// Returns the minimum of two access levels
fn minAccessLevel(a: AccessLevel, b: AccessLevel) AccessLevel {
    const a_val: u8 = switch (a) {
        .none => 0,
        .tertiary => 1,
        .secondary => 2,
        .primary => 3,
    };
    const b_val: u8 = switch (b) {
        .none => 0,
        .tertiary => 1,
        .secondary => 2,
        .primary => 3,
    };
    const min_val = @min(a_val, b_val);
    return switch (min_val) {
        0 => .none,
        1 => .tertiary,
        2 => .secondary,
        else => .primary,
    };
}

/// Check if a school+position has at least tertiary access to a category
pub fn hasAccess(school: School, position: Position, category: EffectCategory) bool {
    return getEffectCategoryAccess(school, position, category) != .none;
}

/// Get recommended effect categories for a school+position combination
/// Returns categories where access is at least secondary
pub fn getStrongCategories(school: School, position: Position) []const EffectCategory {
    // Note: In real implementation, this would filter based on access
    // For now, return empty - caller should iterate EffectCategory and check access
    _ = school;
    _ = position;
    return &[_]EffectCategory{};
}

// ============================================================================
// ADVANCED PLACEMENT (AP) SKILL DESIGN PHILOSOPHY
// ============================================================================
//
// AP skills are BUILD-WARPING abilities that fundamentally change how you play.
// They're NOT just "big damage" versions of normal skills.
//
// Like GW1's best elites:
// - Greater Conflagration: Changes ALL attacks in area to fire damage
// - Illusionary Weaponry: Attacks can't miss/be blocked but deal fixed damage
// - Spiteful Spirit: Enemies damage themselves when they attack
//
// Good AP skills create:
// - NEW WIN CONDITIONS ("I win if X happens")
// - SYNERGY REQUIREMENTS ("I need allies who do Y")
// - PLAYSTYLE INVERSIONS ("I want enemies to attack me")
// - POSITIONAL GAMEPLAY ("The location of this effect matters")
// - ENEMY DECISION POINTS ("Do I attack and trigger the trap?")
//
// ============================================================================

/// AP skill category - defines the BUILD-WARPING mechanism
pub const ApCategory = enum {
    // === ZONE CONTROL (Positional gameplay) ===
    damage_conversion_zone, // All damage in area becomes something else (Slush Zone)
    projectile_blocking_zone, // Create walls that block ALL projectiles (Snow Fort)
    trap_zone, // Area that traps everyone inside (Snow Globe)

    // === COMBAT RULE CHANGES ===
    attack_modification, // Change how your attacks fundamentally work (Phantom Throw)
    healing_inversion, // Healing becomes damage, damage becomes healing (Reverse Polarity)
    skill_punishment, // Target damages self when using skills (Prickly Presence)

    // === CONDITION MANIPULATION ===
    condition_transfer, // Move conditions between targets (Cold Shoulder)
    condition_spreading, // Conditions spread to nearby foes (Frostbite Chain)

    // === TEAM SYNERGY ===
    ally_linking, // Share damage/effects with linked ally (Buddy System)
    team_wide_cleanse, // Remove conditions from entire team

    // === POSITIONAL DOMINANCE ===
    stationary_power, // Gain power by not moving (King of the Hill)
    movement_punishment, // Punish enemies for moving
    forced_movement, // Force enemies to move or stay

    // === CHAOS/MIND GAMES ===
    bouncing_effect, // Effect bounces between targets (Hot Potato)
    skill_stealing, // Copy/steal enemy skills (Mirror Match)
    random_targeting, // Unpredictable effects

    // === RISK/REWARD ===
    power_at_cost, // Massive power with severe drawback (Last Stand)
    resource_gambling, // Spend everything for big effect
    death_prevention, // Cheat death but with consequences

    // === SUMMONING ===
    army_summon, // Multiple persistent summons
    sacrifice_summons, // Destroy summons for big effect
    summon_enhancement, // Make summons do something unique
};

/// AP design profile - what build-warping mechanics each school favors
pub const ApDesignProfile = struct {
    /// Primary mechanism - the signature warp for this school
    primary_warp: ApCategory,
    /// Secondary mechanism - alternate warp option
    secondary_warp: ApCategory,
    /// What the school CANNOT do as an AP (intentional weakness)
    forbidden_warp: ApCategory,

    /// Design philosophy for this school's APs
    philosophy: [:0]const u8,

    /// Example skill concept
    example_concept: [:0]const u8,
};

/// Get the AP design profile for a school
pub fn getSchoolApDesign(school: School) ApDesignProfile {
    return switch (school) {
        .private_school => .{
            .primary_warp = .ally_linking, // "Money connects us"
            .secondary_warp = .projectile_blocking_zone, // "Build expensive walls"
            .forbidden_warp = .power_at_cost, // Never sacrifice themselves
            .philosophy = "Private School APs create INFRASTRUCTURE and CONNECTIONS. They build things that benefit the team, but never risk themselves personally.",
            .example_concept = "Buddy System: Link with ally to share damage and buffs - the ultimate networking",
        },
        .public_school => .{
            .primary_warp = .power_at_cost, // "Everything on the line"
            .secondary_warp = .condition_spreading, // "Spread the pain"
            .forbidden_warp = .ally_linking, // Fight alone, die alone
            .philosophy = "Public School APs are HIGH RISK / HIGH REWARD. They go all-in, betting everything on one big play. They fight alone.",
            .example_concept = "Last Stand: Massive damage boost but cannot be healed, and death is certain",
        },
        .montessori => .{
            .primary_warp = .damage_conversion_zone, // "Change the rules"
            .secondary_warp = .attack_modification, // "Adapt my approach"
            .forbidden_warp = .stationary_power, // Never stay still
            .philosophy = "Montessori APs CHANGE THE RULES of combat. They create zones or stances that alter fundamental game mechanics.",
            .example_concept = "Slush Zone: All damage in area converts to DoT stacks - changes what attacks are good",
        },
        .homeschool => .{
            .primary_warp = .skill_punishment, // "Punish them for trying"
            .secondary_warp = .healing_inversion, // "Twist their support"
            .forbidden_warp = .team_wide_cleanse, // No helping others
            .philosophy = "Homeschool APs are HEXES that punish enemies for playing normally. They turn the enemy's strengths against them.",
            .example_concept = "Prickly Presence: Target damages self when using skills - makes them afraid to act",
        },
        .waldorf => .{
            .primary_warp = .bouncing_effect, // "Rhythm and flow"
            .secondary_warp = .skill_stealing, // "Learn from others"
            .forbidden_warp = .power_at_cost, // Harmony, not sacrifice
            .philosophy = "Waldorf APs create PATTERNS and RHYTHMS. Effects that bounce, chain, or build over time. They learn from and adapt to enemies.",
            .example_concept = "Hot Potato: Bouncing bomb that creates chaos and forces enemy decisions",
        },
    };
}

/// Get what AP categories a position naturally gravitates toward
pub fn getPositionApAffinity(position: Position) struct {
    preferred: [2]ApCategory,
    forbidden: ApCategory,
    gameplay_focus: [:0]const u8,
} {
    return switch (position) {
        .pitcher => .{
            .preferred = .{ .attack_modification, .condition_spreading },
            .forbidden = .ally_linking,
            .gameplay_focus = "Pitchers want APs that make their throws MORE IMPACTFUL - changing how throws work or what they leave behind",
        },
        .fielder => .{
            .preferred = .{ .damage_conversion_zone, .bouncing_effect },
            .forbidden = .stationary_power,
            .gameplay_focus = "Fielders want APs that reward FLEXIBILITY - zones they can adapt to, or effects that chain between targets",
        },
        .sledder => .{
            .preferred = .{ .trap_zone, .forced_movement },
            .forbidden = .projectile_blocking_zone,
            .gameplay_focus = "Sledders want APs that CONTROL SPACE - trapping enemies or forcing them to move where you want",
        },
        .shoveler => .{
            .preferred = .{ .projectile_blocking_zone, .stationary_power },
            .forbidden = .bouncing_effect,
            .gameplay_focus = "Shovelers want APs that reward HOLDING GROUND - walls, anchors, and power from not moving",
        },
        .animator => .{
            .preferred = .{ .army_summon, .sacrifice_summons },
            .forbidden = .healing_inversion,
            .gameplay_focus = "Animators want APs that multiply their PRESENCE - many summons or ways to sacrifice them for big effects",
        },
        .thermos => .{
            .preferred = .{ .ally_linking, .team_wide_cleanse },
            .forbidden = .skill_punishment,
            .gameplay_focus = "Thermos wants APs that PROTECT THE TEAM - links, cleanses, and shared survival",
        },
    };
}
