const std = @import("std");

/// Composable effect modifiers that can be combined on a single effect
/// This allows skills like "take double damage for 5s" or "grant 20% move speed"
/// without needing new condition enum entries
pub const EffectModifier = enum {
    // Damage modifiers
    damage_multiplier, // value: f32 (e.g., 2.0 = double damage, 0.5 = half damage)
    damage_add, // value: f32 (flat damage added/reduced)

    // Movement/speed modifiers
    move_speed_multiplier, // value: f32 (e.g., 1.5 = 50% faster)
    attack_speed_multiplier, // value: f32 (affects attack animation speed)
    cast_speed_multiplier, // value: f32 (affects activation time)

    // Defense modifiers
    armor_multiplier, // value: f32 (e.g., 1.5 = 50% more effective armor)
    armor_add, // value: f32 (flat armor padding added/reduced)

    // Energy/resource modifiers
    energy_regen_multiplier, // value: f32 (affects energy regeneration rate)
    energy_cost_multiplier, // value: f32 (e.g., 2.0 = skills cost 2x energy)

    // Cooldown modifiers
    cooldown_reduction, // value: f32 (in milliseconds, subtracts from recharge)
    cooldown_reduction_percent, // value: f32 (e.g., 0.2 = 20% cooldown reduction)

    // Healing modifiers
    healing_multiplier, // value: f32 (e.g., 1.5 = skills heal 50% more)

    // Utility modifiers
    evasion_percent, // value: f32 (e.g., 0.3 = 30% chance to dodge)
    accuracy_multiplier, // value: f32 (hit chance modifier)

    // Blocking modifiers (GW1-style)
    block_chance, // value: f32 (e.g., 0.75 = 75% block chance)
    block_next_attack, // value: f32 (1.0 = block exactly one attack, then expires)

    // Skill disable modifiers
    skills_disabled, // value: int (1 = all skills disabled while active)
    attack_skills_disabled, // value: int (1 = throw skills disabled)
    spell_skills_disabled, // value: int (1 = trick/gesture skills disabled)

    // Duration modifiers (affects applied conditions/cozies)
    chill_duration_multiplier, // value: f32 (e.g., 1.5 = chills last 50% longer)
    cozy_duration_multiplier, // value: f32 (e.g., 0.5 = cozies last half as long)

    // ========================================================================
    // PHASE 1 ADDITIONS - Enabling more skills
    // ========================================================================

    // Knockdown/CC effects
    knockdown, // value: int (1 = knocked down, can't act)

    // Single-use modifiers (consumed after triggering once)
    next_attack_damage_add, // value: f32 (bonus damage on next attack, then consumed)
    next_attack_damage_multiplier, // value: f32 (multiplier on next attack, then consumed)
    next_skill_instant_cast, // value: int (1 = next skill has 0 activation time)
    next_skill_no_cost, // value: int (1 = next skill costs no energy)
    next_skill_cooldown_multiplier, // value: f32 (e.g., 0.5 = 50% faster recharge on next skill)

    // Periodic effects (applied each tick while active)
    warmth_drain_per_second, // value: f32 (lose X warmth per second)
    warmth_gain_per_second, // value: f32 (gain X warmth per second - like hot_cocoa but composable)
    energy_drain_per_second, // value: f32 (lose X energy per second)
    energy_gain_per_second, // value: f32 (gain X energy per second)
    grit_gain_per_second, // value: f32 (gain X grit per second - for Underdog, Berserker Rage)
    rhythm_gain_per_second, // value: f32 (gain X rhythm per second)

    // Max resource modifiers
    max_warmth_add, // value: f32 (flat +/- max warmth)
    max_warmth_multiplier, // value: f32 (e.g., 1.5 = 50% more max warmth)
    max_energy_add, // value: f32 (flat +/- max energy)
    max_energy_multiplier, // value: f32 (e.g., 2.0 = double max energy)

    // Resource gain on events
    grit_on_hit, // value: f32 (gain X grit when this effect's skill hits)
    grit_on_take_damage, // value: f32 (gain X grit when taking damage)
    rhythm_on_hit, // value: f32 (gain X rhythm when hitting)
    rhythm_on_take_damage, // value: f32 (gain X rhythm when taking damage)
    energy_on_hit, // value: f32 (gain X energy when hitting)

    // Cooldown manipulation
    recharge_on_hit, // value: int (1 = reset this skill's cooldown if it hits)
    recharge_on_kill, // value: int (1 = reset this skill's cooldown if target dies)

    // Chill/Cozy removal
    remove_all_chills, // value: int (1 = remove all chills from target)
    remove_all_cozies, // value: int (1 = remove all cozies from target)
    remove_random_chill, // value: int (N = remove N random chills)
    remove_random_cozy, // value: int (N = remove N random cozies)

    // CC Immunity
    immune_to_knockdown, // value: int (1 = can't be knocked down)
    immune_to_interrupt, // value: int (1 = can't be interrupted)
    immune_to_slow, // value: int (1 = can't be slowed below base speed)
    immune_to_chill, // value: int (1 = can't receive new chills)

    // Damage reflection/thorns
    reflect_damage_percent, // value: f32 (e.g., 0.5 = reflect 50% of damage taken)
    reflect_damage_flat, // value: f32 (reflect flat X damage when hit)

    // Energy stealing
    energy_steal_on_hit, // value: f32 (steal X energy from target on hit)
};

/// A modifier value can be a float or integer depending on context
pub const ModifierValue = union(enum) {
    float: f32,
    int: i32,
};

/// Single modifier on an effect with its value
pub const Modifier = struct {
    effect_type: EffectModifier,
    value: ModifierValue,
};

// ============================================================================
// EFFECT TIMING - WHEN effects trigger (the temporal dimension)
// ============================================================================

/// When an effect triggers during skill/buff lifecycle
/// This is the "verb tense" of effects - past, present, or future
pub const EffectTiming = enum {
    on_hit, // When skill lands on target (default for attacks)
    on_cast, // When skill is cast (regardless of hit) - initial effects
    on_end, // When duration expires naturally - end effects
    on_removed_early, // When stripped/ended before duration (Dervish-style)
    while_active, // Continuous while buff/debuff present (auras)
    on_take_damage, // Reactive trigger when receiving damage
    on_deal_damage, // Proactive trigger when dealing damage
    on_kill, // Finisher bonus when target dies
    on_block, // Defensive reactive when blocking
    on_miss, // Whiff punishment/reward
    on_crit, // Critical hit trigger
    on_interrupt, // When you interrupt a target
    on_interrupted, // When you get interrupted
    on_knockdown, // When you knock down a target
    on_knocked_down, // When you get knocked down

    pub fn isReactive(self: EffectTiming) bool {
        return switch (self) {
            .on_take_damage, .on_block, .on_miss, .on_interrupted, .on_knocked_down => true,
            else => false,
        };
    }

    pub fn isProactive(self: EffectTiming) bool {
        return switch (self) {
            .on_hit, .on_deal_damage, .on_kill, .on_crit, .on_interrupt, .on_knockdown => true,
            else => false,
        };
    }
};

// ============================================================================
// EFFECT TARGET - WHO is affected (the spatial dimension)
// ============================================================================

/// Who the effect applies to - enables AoE and chain effects
/// This is the "subject" of the effect sentence
pub const EffectTarget = enum {
    self, // Caster only
    target, // Single target (default)
    adjacent_to_target, // GW1's "adjacent foes" - melee range from target
    adjacent_to_self, // Melee cleave - foes near caster
    allies_in_earshot, // Party members in large radius (shouts/calls)
    foes_in_earshot, // All enemies in large radius
    allies_near_target, // Support spike - allies near your target
    foes_near_target, // AoE centered on target
    source_of_damage, // Reflect/revenge - whoever just hit you
    pet, // Your animal companion/summon
    all_summons, // All your summoned creatures

    pub fn isAoE(self: EffectTarget) bool {
        return switch (self) {
            .target, .self, .source_of_damage, .pet => false,
            else => true,
        };
    }

    pub fn affectsFoes(self: EffectTarget) bool {
        return switch (self) {
            .target, .adjacent_to_target, .adjacent_to_self, .foes_in_earshot, .foes_near_target, .source_of_damage => true,
            else => false,
        };
    }

    pub fn affectsAllies(self: EffectTarget) bool {
        return switch (self) {
            .self, .allies_in_earshot, .allies_near_target, .pet, .all_summons => true,
            else => false,
        };
    }
};

// ============================================================================
// EFFECT CONDITION - IF the effect applies (the qualitative gate)
// ============================================================================

/// Conditional check for applying effects based on game state
/// This is the "horsemanship" - the qualitative gate that creates variety
/// Examples: "if target below 50% warmth", "if target has condition X", etc.
pub const EffectCondition = enum {
    // Always apply (no condition)
    always,

    // ========== WARMTH (Health) CONDITIONS ==========
    // Target warmth
    if_target_above_75_percent_warmth,
    if_target_above_50_percent_warmth,
    if_target_below_50_percent_warmth,
    if_target_below_25_percent_warmth,

    // Caster warmth
    if_caster_above_75_percent_warmth,
    if_caster_above_50_percent_warmth,
    if_caster_below_50_percent_warmth,
    if_caster_below_25_percent_warmth,

    // Relative warmth
    if_target_has_more_warmth,
    if_target_has_less_warmth,

    // ========== STATUS CONDITIONS (Chills/Cozies) ==========
    // Target status - general
    if_target_has_any_chill,
    if_target_has_any_cozy,
    if_target_has_no_chill,
    if_target_has_no_cozy,

    // Target status - specific chills
    if_target_has_chill_soggy,
    if_target_has_chill_slippery,
    if_target_has_chill_numb,
    if_target_has_chill_frost_eyes,
    if_target_has_chill_windburn,
    if_target_has_chill_brain_freeze,
    if_target_has_chill_packed_snow,
    if_target_has_chill_dazed,

    // Target status - specific cozies
    if_target_has_cozy_bundled_up,
    if_target_has_cozy_hot_cocoa,
    if_target_has_cozy_fire_inside,
    if_target_has_cozy_snow_goggles,
    if_target_has_cozy_insulated,
    if_target_has_cozy_sure_footed,
    if_target_has_cozy_frosty_fortitude,
    if_target_has_cozy_snowball_shield,

    // Caster status
    if_caster_has_any_chill,
    if_caster_has_any_cozy,
    if_caster_has_no_chill,
    if_caster_has_no_cozy,

    // Caster status - specific cozies (for "while enchanted with X" conditions)
    if_caster_has_cozy_bundled_up,
    if_caster_has_cozy_hot_cocoa,
    if_caster_has_cozy_fire_inside,
    if_caster_has_cozy_snow_goggles,
    if_caster_has_cozy_insulated,
    if_caster_has_cozy_sure_footed,
    if_caster_has_cozy_frosty_fortitude,
    if_caster_has_cozy_snowball_shield,

    // ========== MOVEMENT CONDITIONS ==========
    if_target_moving,
    if_target_not_moving,
    if_caster_moving,
    if_caster_not_moving,

    // ========== COMBAT STATE CONDITIONS ==========
    if_target_casting,
    if_target_not_casting,
    if_target_attacking,
    if_target_knocked_down,
    if_caster_attacking,
    if_target_blocking, // Target is actively blocking (stance/shield)
    if_caster_blocking, // Caster is actively blocking

    // ========== RESOURCE CONDITIONS (School-specific) ==========
    // Private School - Credit/Debt
    if_caster_in_debt,
    if_caster_not_in_debt,

    // Public School - Grit
    if_caster_has_grit, // 1+ stacks
    if_caster_has_grit_3_plus, // 3+ stacks
    if_caster_has_grit_5_plus, // 5+ stacks (max)
    if_caster_has_no_grit,

    // Waldorf - Rhythm
    if_caster_has_rhythm, // 1+ stacks
    if_caster_has_rhythm_3_plus, // 3+ stacks
    if_caster_has_rhythm_5_plus, // 5+ stacks
    if_caster_has_no_rhythm,

    // Montessori - Variety (used different skill type recently)
    if_caster_used_different_type,
    if_caster_used_same_type,

    // Homeschool - Sacrifice/Isolation
    if_caster_sacrificed_recently, // Used warmth cost skill in last 5s
    if_caster_isolated, // No allies within earshot

    // ========== POSITIONAL CONDITIONS ==========
    if_near_wall, // Within 50 units of a snow wall
    if_behind_wall, // Wall between caster and target
    if_near_ally, // Ally within adjacent range
    if_near_foe, // Foe within adjacent range
    if_target_near_ally, // Target has ally nearby
    if_target_isolated, // Target has no allies nearby

    // ========== TERRAIN CONDITIONS ==========
    if_on_ice,
    if_on_deep_snow,
    if_on_packed_snow,
    if_on_slush,
    if_target_on_ice,
    if_target_on_deep_snow,

    // ========== SKILL TYPE CONDITIONS ==========
    if_last_skill_was_throw,
    if_last_skill_was_trick,
    if_last_skill_was_stance,
    if_last_skill_was_call,
    if_last_skill_was_gesture,

    // ========== PHASE 1 ADDITIONS ==========

    // Energy threshold conditions
    if_caster_below_25_percent_energy,
    if_caster_below_50_percent_energy,
    if_caster_above_50_percent_energy,
    if_caster_above_75_percent_energy,

    // Team composition conditions
    if_caster_outnumbered, // More nearby foes than allies
    if_caster_has_numerical_advantage, // More allies than foes nearby
    if_target_is_ally, // For dual-purpose skills (heal ally OR damage enemy)
    if_target_is_enemy, // For dual-purpose skills

    // Variety tracking (Montessori)
    if_last_two_skills_different_types, // Used different types for last 2 skills
    if_last_three_skills_different_types, // Used 3 different types recently
    if_used_all_five_skill_types_recently, // Mastery bonus - used all types in window

    // Interrupt conditions
    if_target_was_interrupted, // Skill just interrupted target
    if_this_skill_interrupted, // For bonus effects on successful interrupt

    // Kill conditions
    if_target_died, // Target was killed by this skill
};

/// Main effect structure - composable modifiers with duration
/// Can represent buffs, debuffs, or special effects
///
/// The four dimensions of an effect:
/// - WHAT: modifiers (quantitative changes)
/// - WHEN: timing (trigger moment)
/// - WHO: affects (targeting)
/// - IF: condition (qualitative gate)
pub const Effect = struct {
    name: [:0]const u8,
    description: [:0]const u8 = "",

    // ========== WHAT happens (the "kicker" - quantitative) ==========
    /// Modifiers to apply
    modifiers: []const Modifier,

    // ========== WHEN it triggers (timing) ==========
    /// When this effect triggers during skill/buff lifecycle
    timing: EffectTiming = .on_hit,

    // ========== WHO it affects (targeting) ==========
    /// Who this effect applies to
    affects: EffectTarget = .target,

    // ========== IF it applies (the "horsemanship" - qualitative gate) ==========
    /// Condition for applying this effect
    condition: EffectCondition = .always,

    // ========== HOW LONG ==========
    /// Duration in milliseconds (0 = instant/one-shot)
    duration_ms: u32,

    /// Is this a beneficial effect (buff) or harmful (debuff)?
    is_buff: bool = false,

    // ========== STACKING RULES ==========
    /// Maximum stacks (0 = doesn't stack, resets duration instead)
    /// If > 0, multiple applications can stack up to this limit
    max_stacks: u8 = 0,

    /// How stacks combine: refresh duration, add intensity, etc.
    stack_behavior: StackBehavior = .refresh_duration,

    /// Priority for applying over other effects (higher = applies first)
    priority: i8 = 0,

    // ========== EFFECT CHAINS (Dervish-style) ==========
    /// Effect to apply when this effect ends naturally (on_end timing)
    on_end_effect: ?*const Effect = null,

    /// Effect to apply when this effect is removed early (stripped/interrupted)
    on_removed_early_effect: ?*const Effect = null,

    /// Effect to apply at the start (on_cast timing) - for "initial effect" patterns
    initial_effect: ?*const Effect = null,

    // ========== HELPER METHODS ==========

    /// Returns true if this effect has any chained effects
    pub fn hasChainedEffects(self: *const Effect) bool {
        return self.on_end_effect != null or
            self.on_removed_early_effect != null or
            self.initial_effect != null;
    }

    /// Returns true if this effect is instant (duration 0)
    pub fn isInstant(self: *const Effect) bool {
        return self.duration_ms == 0;
    }

    /// Returns true if this is an AoE effect
    pub fn isAoE(self: *const Effect) bool {
        return self.affects.isAoE();
    }

    /// Returns true if this effect triggers reactively (in response to something)
    pub fn isReactive(self: *const Effect) bool {
        return self.timing.isReactive();
    }
};

pub const StackBehavior = enum {
    refresh_duration, // New stack just refreshes the duration
    add_intensity, // Stacks add together, increasing effect potency
    ignore_if_active, // New stack is ignored if effect already active
};

/// An active effect on a character at runtime
/// Tracks the effect, remaining time, and current stack count
pub const ActiveEffect = struct {
    effect: *const Effect,
    time_remaining_ms: u32,
    stack_count: u8 = 1,
    source_character_id: ?u32 = null, // Who applied it (for tracking)
};

/// Evaluate if a conditional applies to a target
/// Note: caster_warmth_percent and target_warmth_percent are 0.0 to 1.0
/// This is the simple version - for warmth-only conditions
pub fn evaluateCondition(
    condition: EffectCondition,
    caster_warmth_percent: f32,
    target_warmth_percent: f32,
) bool {
    return switch (condition) {
        .always => true,

        // Target warmth
        .if_target_above_75_percent_warmth => target_warmth_percent >= 0.75,
        .if_target_above_50_percent_warmth => target_warmth_percent >= 0.5,
        .if_target_below_50_percent_warmth => target_warmth_percent < 0.5,
        .if_target_below_25_percent_warmth => target_warmth_percent < 0.25,

        // Caster warmth
        .if_caster_above_75_percent_warmth => caster_warmth_percent >= 0.75,
        .if_caster_above_50_percent_warmth => caster_warmth_percent >= 0.5,
        .if_caster_below_50_percent_warmth => caster_warmth_percent < 0.5,
        .if_caster_below_25_percent_warmth => caster_warmth_percent < 0.25,

        // Relative warmth
        .if_target_has_more_warmth => target_warmth_percent > caster_warmth_percent,
        .if_target_has_less_warmth => target_warmth_percent < caster_warmth_percent,

        // All other conditions require more context - return true and let
        // the combat system do the full evaluation
        else => true,
    };
}

// ============================================================================
// FULL CONDITION EVALUATION CONTEXT
// ============================================================================

/// Full context for evaluating complex conditions
/// Pass this to evaluateConditionFull for complete condition checking
pub const ConditionContext = struct {
    // Warmth (health) - as percentages 0.0 to 1.0
    caster_warmth_percent: f32 = 1.0,
    target_warmth_percent: f32 = 1.0,

    // Movement state
    caster_moving: bool = false,
    target_moving: bool = false,

    // Combat state
    caster_attacking: bool = false,
    target_attacking: bool = false,
    target_casting: bool = false,
    target_knocked_down: bool = false,
    target_blocking: bool = false,
    caster_blocking: bool = false,

    // Status effects (counts)
    caster_chill_count: u8 = 0,
    caster_cozy_count: u8 = 0,
    target_chill_count: u8 = 0,
    target_cozy_count: u8 = 0,

    // Specific chill/cozy flags (bitfields would be more efficient but less clear)
    target_has_soggy: bool = false,
    target_has_slippery: bool = false,
    target_has_numb: bool = false,
    target_has_frost_eyes: bool = false,
    target_has_windburn: bool = false,
    target_has_brain_freeze: bool = false,
    target_has_packed_snow: bool = false,
    target_has_dazed: bool = false,

    target_has_bundled_up: bool = false,
    target_has_hot_cocoa: bool = false,
    target_has_fire_inside: bool = false,
    target_has_snow_goggles: bool = false,
    target_has_insulated: bool = false,
    target_has_sure_footed: bool = false,
    target_has_frosty_fortitude: bool = false,
    target_has_snowball_shield: bool = false,

    // Caster-specific cozy flags (for "while enchanted" conditions)
    caster_has_bundled_up: bool = false,
    caster_has_hot_cocoa: bool = false,
    caster_has_fire_inside: bool = false,
    caster_has_snow_goggles: bool = false,
    caster_has_insulated: bool = false,
    caster_has_sure_footed: bool = false,
    caster_has_frosty_fortitude: bool = false,
    caster_has_snowball_shield: bool = false,

    // School-specific resources
    caster_credit_debt: u8 = 0, // Private School
    caster_grit_stacks: u8 = 0, // Public School
    caster_rhythm_stacks: u8 = 0, // Waldorf
    caster_used_different_skill_type: bool = false, // Montessori
    caster_sacrificed_recently: bool = false, // Homeschool

    // Positional
    caster_near_wall: bool = false,
    target_behind_wall: bool = false,
    caster_near_ally: bool = false,
    caster_near_foe: bool = false,
    target_near_ally: bool = false,
    caster_isolated: bool = false,
    target_isolated: bool = false,

    // Terrain
    caster_on_ice: bool = false,
    caster_on_deep_snow: bool = false,
    caster_on_packed_snow: bool = false,
    caster_on_slush: bool = false,
    target_on_ice: bool = false,
    target_on_deep_snow: bool = false,

    // Last skill type used
    last_skill_type: ?@import("skills.zig").SkillType = null,

    // ========== PHASE 1 ADDITIONS ==========

    // Energy thresholds (0.0 to 1.0)
    caster_energy_percent: f32 = 1.0,

    // Team composition
    nearby_allies_count: u8 = 0,
    nearby_foes_count: u8 = 0,

    // Target relationship
    target_is_ally: bool = false,
    target_is_enemy: bool = true,

    // Variety tracking (Montessori) - tracks last few skill types used
    skill_type_history: [5]?@import("skills.zig").SkillType = .{ null, null, null, null, null },
    unique_skill_types_in_window: u8 = 0, // Count of different types used recently

    // Interrupt/kill tracking
    target_was_interrupted: bool = false,
    target_died: bool = false,
};

/// Full condition evaluation with complete context
/// Use this when you have access to the full game state
pub fn evaluateConditionFull(condition: EffectCondition, ctx: ConditionContext) bool {
    return switch (condition) {
        .always => true,

        // Warmth conditions
        .if_target_above_75_percent_warmth => ctx.target_warmth_percent >= 0.75,
        .if_target_above_50_percent_warmth => ctx.target_warmth_percent >= 0.5,
        .if_target_below_50_percent_warmth => ctx.target_warmth_percent < 0.5,
        .if_target_below_25_percent_warmth => ctx.target_warmth_percent < 0.25,
        .if_caster_above_75_percent_warmth => ctx.caster_warmth_percent >= 0.75,
        .if_caster_above_50_percent_warmth => ctx.caster_warmth_percent >= 0.5,
        .if_caster_below_50_percent_warmth => ctx.caster_warmth_percent < 0.5,
        .if_caster_below_25_percent_warmth => ctx.caster_warmth_percent < 0.25,
        .if_target_has_more_warmth => ctx.target_warmth_percent > ctx.caster_warmth_percent,
        .if_target_has_less_warmth => ctx.target_warmth_percent < ctx.caster_warmth_percent,

        // Status conditions - general
        .if_target_has_any_chill => ctx.target_chill_count > 0,
        .if_target_has_any_cozy => ctx.target_cozy_count > 0,
        .if_target_has_no_chill => ctx.target_chill_count == 0,
        .if_target_has_no_cozy => ctx.target_cozy_count == 0,
        .if_caster_has_any_chill => ctx.caster_chill_count > 0,
        .if_caster_has_any_cozy => ctx.caster_cozy_count > 0,
        .if_caster_has_no_chill => ctx.caster_chill_count == 0,
        .if_caster_has_no_cozy => ctx.caster_cozy_count == 0,

        // Caster specific cozies
        .if_caster_has_cozy_bundled_up => ctx.caster_has_bundled_up,
        .if_caster_has_cozy_hot_cocoa => ctx.caster_has_hot_cocoa,
        .if_caster_has_cozy_fire_inside => ctx.caster_has_fire_inside,
        .if_caster_has_cozy_snow_goggles => ctx.caster_has_snow_goggles,
        .if_caster_has_cozy_insulated => ctx.caster_has_insulated,
        .if_caster_has_cozy_sure_footed => ctx.caster_has_sure_footed,
        .if_caster_has_cozy_frosty_fortitude => ctx.caster_has_frosty_fortitude,
        .if_caster_has_cozy_snowball_shield => ctx.caster_has_snowball_shield,

        // Specific chills
        .if_target_has_chill_soggy => ctx.target_has_soggy,
        .if_target_has_chill_slippery => ctx.target_has_slippery,
        .if_target_has_chill_numb => ctx.target_has_numb,
        .if_target_has_chill_frost_eyes => ctx.target_has_frost_eyes,
        .if_target_has_chill_windburn => ctx.target_has_windburn,
        .if_target_has_chill_brain_freeze => ctx.target_has_brain_freeze,
        .if_target_has_chill_packed_snow => ctx.target_has_packed_snow,
        .if_target_has_chill_dazed => ctx.target_has_dazed,

        // Specific cozies
        .if_target_has_cozy_bundled_up => ctx.target_has_bundled_up,
        .if_target_has_cozy_hot_cocoa => ctx.target_has_hot_cocoa,
        .if_target_has_cozy_fire_inside => ctx.target_has_fire_inside,
        .if_target_has_cozy_snow_goggles => ctx.target_has_snow_goggles,
        .if_target_has_cozy_insulated => ctx.target_has_insulated,
        .if_target_has_cozy_sure_footed => ctx.target_has_sure_footed,
        .if_target_has_cozy_frosty_fortitude => ctx.target_has_frosty_fortitude,
        .if_target_has_cozy_snowball_shield => ctx.target_has_snowball_shield,

        // Movement conditions
        .if_target_moving => ctx.target_moving,
        .if_target_not_moving => !ctx.target_moving,
        .if_caster_moving => ctx.caster_moving,
        .if_caster_not_moving => !ctx.caster_moving,

        // Combat state
        .if_target_casting => ctx.target_casting,
        .if_target_not_casting => !ctx.target_casting,
        .if_target_attacking => ctx.target_attacking,
        .if_target_knocked_down => ctx.target_knocked_down,
        .if_caster_attacking => ctx.caster_attacking,
        .if_target_blocking => ctx.target_blocking,
        .if_caster_blocking => ctx.caster_blocking,

        // Resource conditions
        .if_caster_in_debt => ctx.caster_credit_debt > 0,
        .if_caster_not_in_debt => ctx.caster_credit_debt == 0,
        .if_caster_has_grit => ctx.caster_grit_stacks > 0,
        .if_caster_has_grit_3_plus => ctx.caster_grit_stacks >= 3,
        .if_caster_has_grit_5_plus => ctx.caster_grit_stacks >= 5,
        .if_caster_has_no_grit => ctx.caster_grit_stacks == 0,
        .if_caster_has_rhythm => ctx.caster_rhythm_stacks > 0,
        .if_caster_has_rhythm_3_plus => ctx.caster_rhythm_stacks >= 3,
        .if_caster_has_rhythm_5_plus => ctx.caster_rhythm_stacks >= 5,
        .if_caster_has_no_rhythm => ctx.caster_rhythm_stacks == 0,
        .if_caster_used_different_type => ctx.caster_used_different_skill_type,
        .if_caster_used_same_type => !ctx.caster_used_different_skill_type,
        .if_caster_sacrificed_recently => ctx.caster_sacrificed_recently,
        .if_caster_isolated => ctx.caster_isolated,

        // Positional
        .if_near_wall => ctx.caster_near_wall,
        .if_behind_wall => ctx.target_behind_wall,
        .if_near_ally => ctx.caster_near_ally,
        .if_near_foe => ctx.caster_near_foe,
        .if_target_near_ally => ctx.target_near_ally,
        .if_target_isolated => ctx.target_isolated,

        // Terrain
        .if_on_ice => ctx.caster_on_ice,
        .if_on_deep_snow => ctx.caster_on_deep_snow,
        .if_on_packed_snow => ctx.caster_on_packed_snow,
        .if_on_slush => ctx.caster_on_slush,
        .if_target_on_ice => ctx.target_on_ice,
        .if_target_on_deep_snow => ctx.target_on_deep_snow,

        // Skill type conditions
        .if_last_skill_was_throw => ctx.last_skill_type == .throw,
        .if_last_skill_was_trick => ctx.last_skill_type == .trick,
        .if_last_skill_was_stance => ctx.last_skill_type == .stance,
        .if_last_skill_was_call => ctx.last_skill_type == .call,
        .if_last_skill_was_gesture => ctx.last_skill_type == .gesture,

        // ========== PHASE 1 ADDITIONS ==========

        // Energy threshold conditions
        .if_caster_below_25_percent_energy => ctx.caster_energy_percent < 0.25,
        .if_caster_below_50_percent_energy => ctx.caster_energy_percent < 0.5,
        .if_caster_above_50_percent_energy => ctx.caster_energy_percent >= 0.5,
        .if_caster_above_75_percent_energy => ctx.caster_energy_percent >= 0.75,

        // Team composition conditions
        .if_caster_outnumbered => ctx.nearby_foes_count > ctx.nearby_allies_count,
        .if_caster_has_numerical_advantage => ctx.nearby_allies_count > ctx.nearby_foes_count,
        .if_target_is_ally => ctx.target_is_ally,
        .if_target_is_enemy => ctx.target_is_enemy,

        // Variety tracking (Montessori)
        .if_last_two_skills_different_types => blk: {
            if (ctx.skill_type_history[0] == null or ctx.skill_type_history[1] == null) break :blk false;
            break :blk ctx.skill_type_history[0] != ctx.skill_type_history[1];
        },
        .if_last_three_skills_different_types => blk: {
            if (ctx.skill_type_history[0] == null or ctx.skill_type_history[1] == null or ctx.skill_type_history[2] == null) break :blk false;
            const t0 = ctx.skill_type_history[0].?;
            const t1 = ctx.skill_type_history[1].?;
            const t2 = ctx.skill_type_history[2].?;
            break :blk t0 != t1 and t1 != t2 and t0 != t2;
        },
        .if_used_all_five_skill_types_recently => ctx.unique_skill_types_in_window >= 5,

        // Interrupt/kill conditions
        .if_target_was_interrupted => ctx.target_was_interrupted,
        .if_this_skill_interrupted => ctx.target_was_interrupted,
        .if_target_died => ctx.target_died,
    };
}

/// Helper to create a simple effect with a single modifier
pub fn createSimpleEffect(
    name: [:0]const u8,
    modifier_type: EffectModifier,
    modifier_value: ModifierValue,
    duration_ms: u32,
    is_buff: bool,
) Effect {
    _ = modifier_type;
    _ = modifier_value;
    // Note: In real implementation, you'd allocate modifiers array properly
    // This is a simplified example
    return .{
        .name = name,
        .modifiers = &[_]Modifier{},
        .duration_ms = duration_ms,
        .is_buff = is_buff,
    };
}

// Example effects for common use cases

/// Double damage effect (damage multiplier x2)
pub const DOUBLE_DAMAGE_MODIFIER = Modifier{
    .effect_type = .damage_multiplier,
    .value = .{ .float = 2.0 },
};

/// Half damage effect (damage multiplier x0.5)
pub const HALF_DAMAGE_MODIFIER = Modifier{
    .effect_type = .damage_multiplier,
    .value = .{ .float = 0.5 },
};

/// 50% move speed boost
pub const SPEED_BOOST_MODIFIER = Modifier{
    .effect_type = .move_speed_multiplier,
    .value = .{ .float = 1.5 },
};

/// 20% cooldown reduction
pub const CDR_MODIFIER = Modifier{
    .effect_type = .cooldown_reduction_percent,
    .value = .{ .float = 0.2 },
};

/// 30% evasion
pub const EVASION_MODIFIER = Modifier{
    .effect_type = .evasion_percent,
    .value = .{ .float = 0.3 },
};

// ============================================================================
// Example composable effects for skills
// These demonstrate how to combine modifiers for complex skill mechanics
// ============================================================================

// Example: "Soggy Hit" - take double damage for 5 seconds (soaked through)
const soggy_hit_modifiers = [_]Modifier{
    .{
        .effect_type = .damage_multiplier,
        .value = .{ .float = 2.0 },
    },
};

pub const SOAKED_THROUGH_EFFECT = Effect{
    .name = "Soaked Through",
    .description = "Wet clothes make you vulnerable - take 2x damage",
    .modifiers = &soggy_hit_modifiers,
    .timing = .on_hit,
    .affects = .target,
    .duration_ms = 5000,
    .is_buff = false,
    .condition = .always,
    .max_stacks = 1,
    .stack_behavior = .refresh_duration,
};

// Example: "Momentum" - 50% movement speed increase and 20% cooldown reduction for 6 seconds
const momentum_modifiers = [_]Modifier{
    .{
        .effect_type = .move_speed_multiplier,
        .value = .{ .float = 1.5 },
    },
    .{
        .effect_type = .cooldown_reduction_percent,
        .value = .{ .float = 0.2 },
    },
};

pub const MOMENTUM_EFFECT = Effect{
    .name = "Momentum",
    .description = "You're in the zone - move 50% faster and skills recharge 20% quicker",
    .modifiers = &momentum_modifiers,
    .timing = .on_hit,
    .affects = .self,
    .duration_ms = 6000,
    .is_buff = true,
    .condition = .always,
    .max_stacks = 2,
    .stack_behavior = .add_intensity,
};

// Example: "Cold Stiff" - armor effectiveness reduced (conditional on low health)
const cold_stiff_modifiers = [_]Modifier{
    .{
        .effect_type = .armor_multiplier,
        .value = .{ .float = 0.5 }, // 50% effective padding
    },
};

pub const COLD_STIFF_EFFECT = Effect{
    .name = "Cold Stiff",
    .description = "Muscles frozen - padding only 50% effective",
    .modifiers = &cold_stiff_modifiers,
    .timing = .on_hit,
    .affects = .target,
    .duration_ms = 8000,
    .is_buff = false,
    .condition = .if_target_below_50_percent_warmth, // Only on low health targets
    .max_stacks = 1,
    .stack_behavior = .refresh_duration,
};

// Example: "In The Zone" - 30% faster attacks and spells
const zone_flow_modifiers = [_]Modifier{
    .{
        .effect_type = .attack_speed_multiplier,
        .value = .{ .float = 1.3 },
    },
    .{
        .effect_type = .cast_speed_multiplier,
        .value = .{ .float = 1.3 },
    },
};

pub const IN_THE_ZONE_EFFECT = Effect{
    .name = "In The Zone",
    .description = "Perfect rhythm - attacks and casts 30% faster",
    .modifiers = &zone_flow_modifiers,
    .timing = .on_hit,
    .affects = .self,
    .duration_ms = 12000,
    .is_buff = true,
    .condition = .always,
    .max_stacks = 1,
    .stack_behavior = .refresh_duration,
};

// Example: "Wind Knocked" - increased energy costs for spells
const wind_knocked_modifiers = [_]Modifier{
    .{
        .effect_type = .energy_cost_multiplier,
        .value = .{ .float = 1.5 }, // Skills cost 50% more energy
    },
};

pub const WIND_KNOCKED_EFFECT = Effect{
    .name = "Wind Knocked",
    .description = "Breath knocked out - skills cost 50% more energy to use",
    .modifiers = &wind_knocked_modifiers,
    .timing = .on_hit,
    .affects = .target,
    .duration_ms = 7000,
    .is_buff = false,
    .condition = .always,
    .max_stacks = 1,
    .stack_behavior = .refresh_duration,
};

// Example: "Fired Up" - faster energy regeneration
const fired_up_modifiers = [_]Modifier{
    .{
        .effect_type = .energy_regen_multiplier,
        .value = .{ .float = 2.0 }, // 2x energy regen
    },
};

pub const FIRED_UP_EFFECT = Effect{
    .name = "Fired Up",
    .description = "Inner warmth blazing - energy regenerates twice as fast",
    .modifiers = &fired_up_modifiers,
    .timing = .on_hit,
    .affects = .self,
    .duration_ms = 15000,
    .is_buff = true,
    .condition = .always,
    .max_stacks = 1,
    .stack_behavior = .refresh_duration,
};

// ============================================================================
// NEW COMPOSABLE EFFECTS - Demonstrating the full system
// ============================================================================

// ----------------------------------------------------------------------------
// DERVISH-STYLE FLASH ENCHANTMENTS (Initial + Active + End effects)
// ----------------------------------------------------------------------------

// "Cozy Layers" end effect - apply Slippery to adjacent foes when stripped
const cozy_layers_shed_modifiers = [_]Modifier{
    .{
        .effect_type = .move_speed_multiplier,
        .value = .{ .float = 0.66 }, // 33% slow
    },
};

pub const COZY_LAYERS_SHED_EFFECT = Effect{
    .name = "Shed Layers",
    .description = "Discarded clothes trip up nearby foes",
    .modifiers = &cozy_layers_shed_modifiers,
    .timing = .on_removed_early,
    .affects = .adjacent_to_self,
    .duration_ms = 4000,
    .is_buff = false,
    .condition = .always,
};

// "Cozy Layers" main effect - damage reduction but slower
const cozy_layers_modifiers = [_]Modifier{
    .{
        .effect_type = .damage_multiplier,
        .value = .{ .float = 0.75 }, // Take 25% less damage
    },
    .{
        .effect_type = .move_speed_multiplier,
        .value = .{ .float = 0.75 }, // 25% slower
    },
};

pub const COZY_LAYERS_EFFECT = Effect{
    .name = "Cozy Layers",
    .description = "Extra padding protects you but slows you down. Strip early to trip foes.",
    .modifiers = &cozy_layers_modifiers,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 15000,
    .is_buff = true,
    .condition = .always,
    .on_removed_early_effect = &COZY_LAYERS_SHED_EFFECT,
};

// ----------------------------------------------------------------------------
// CONDITIONAL EFFECTS - Different outcomes based on game state
// ----------------------------------------------------------------------------

// "Exploit Weakness" - bonus damage if target is chilled
const exploit_weakness_modifiers = [_]Modifier{
    .{
        .effect_type = .damage_add,
        .value = .{ .float = 15.0 }, // +15 bonus damage
    },
};

pub const EXPLOIT_WEAKNESS_EFFECT = Effect{
    .name = "Exploit Weakness",
    .description = "Deal bonus damage to chilled targets",
    .modifiers = &exploit_weakness_modifiers,
    .timing = .on_hit,
    .affects = .target,
    .duration_ms = 0, // Instant damage bonus
    .is_buff = false,
    .condition = .if_target_has_any_chill,
};

// "Finishing Blow" - massive damage to low warmth targets
const finishing_blow_modifiers = [_]Modifier{
    .{
        .effect_type = .damage_multiplier,
        .value = .{ .float = 2.0 }, // Double damage
    },
};

pub const FINISHING_BLOW_EFFECT = Effect{
    .name = "Finishing Blow",
    .description = "Deal double damage to nearly frozen targets",
    .modifiers = &finishing_blow_modifiers,
    .timing = .on_hit,
    .affects = .target,
    .duration_ms = 0,
    .is_buff = false,
    .condition = .if_target_below_25_percent_warmth,
};

// ----------------------------------------------------------------------------
// MOVEMENT-CONDITIONAL EFFECTS
// ----------------------------------------------------------------------------

// "Chase Down" - bonus damage to moving targets
const chase_down_modifiers = [_]Modifier{
    .{
        .effect_type = .damage_add,
        .value = .{ .float = 12.0 },
    },
};

pub const CHASE_DOWN_EFFECT = Effect{
    .name = "Chase Down",
    .description = "Deal bonus damage to fleeing targets",
    .modifiers = &chase_down_modifiers,
    .timing = .on_hit,
    .affects = .target,
    .duration_ms = 0,
    .is_buff = false,
    .condition = .if_target_moving,
};

// "Standing Target" - bonus damage to stationary targets
const standing_target_modifiers = [_]Modifier{
    .{
        .effect_type = .damage_add,
        .value = .{ .float = 10.0 },
    },
};

pub const STANDING_TARGET_EFFECT = Effect{
    .name = "Standing Target",
    .description = "Deal bonus damage to stationary targets",
    .modifiers = &standing_target_modifiers,
    .timing = .on_hit,
    .affects = .target,
    .duration_ms = 0,
    .is_buff = false,
    .condition = .if_target_not_moving,
};

// ----------------------------------------------------------------------------
// RESOURCE-CONDITIONAL EFFECTS (School-specific)
// ----------------------------------------------------------------------------

// Private School: "Desperate Measures" - bonus when in debt
const desperate_measures_modifiers = [_]Modifier{
    .{
        .effect_type = .damage_multiplier,
        .value = .{ .float = 1.5 }, // 50% more damage
    },
};

pub const DESPERATE_MEASURES_EFFECT = Effect{
    .name = "Desperate Measures",
    .description = "Deal 50% more damage while in debt",
    .modifiers = &desperate_measures_modifiers,
    .timing = .on_hit,
    .affects = .target,
    .duration_ms = 0,
    .is_buff = false,
    .condition = .if_caster_in_debt,
};

// Public School: "Grit Surge" - power spike at high grit
const grit_surge_modifiers = [_]Modifier{
    .{
        .effect_type = .damage_multiplier,
        .value = .{ .float = 1.3 },
    },
    .{
        .effect_type = .attack_speed_multiplier,
        .value = .{ .float = 1.2 },
    },
};

pub const GRIT_SURGE_EFFECT = Effect{
    .name = "Grit Surge",
    .description = "At 5 Grit: +30% damage and +20% attack speed",
    .modifiers = &grit_surge_modifiers,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 8000,
    .is_buff = true,
    .condition = .if_caster_has_grit_5_plus,
};

// Waldorf: "Perfect Rhythm" - bonus at high rhythm stacks
const perfect_rhythm_modifiers = [_]Modifier{
    .{
        .effect_type = .cooldown_reduction_percent,
        .value = .{ .float = 0.5 }, // 50% CDR
    },
    .{
        .effect_type = .energy_cost_multiplier,
        .value = .{ .float = 0.5 }, // Skills cost half
    },
};

pub const PERFECT_RHYTHM_EFFECT = Effect{
    .name = "Perfect Rhythm",
    .description = "At 5 Rhythm: skills cost half and recharge 50% faster",
    .modifiers = &perfect_rhythm_modifiers,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 10000,
    .is_buff = true,
    .condition = .if_caster_has_rhythm_5_plus,
};

// Homeschool: "Isolation Power" - bonus when alone
const isolation_power_modifiers = [_]Modifier{
    .{
        .effect_type = .damage_multiplier,
        .value = .{ .float = 1.4 }, // 40% more damage
    },
    .{
        .effect_type = .armor_multiplier,
        .value = .{ .float = 1.2 }, // 20% more armor
    },
};

pub const ISOLATION_POWER_EFFECT = Effect{
    .name = "Isolation Power",
    .description = "Deal 40% more damage and take 20% less when isolated",
    .modifiers = &isolation_power_modifiers,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 0, // Permanent while condition is true
    .is_buff = true,
    .condition = .if_caster_isolated,
};

// Montessori: "Variety Bonus" - reward for using different skill types
const variety_bonus_modifiers = [_]Modifier{
    .{
        .effect_type = .damage_add,
        .value = .{ .float = 8.0 },
    },
    .{
        .effect_type = .energy_regen_multiplier,
        .value = .{ .float = 1.25 },
    },
};

pub const VARIETY_BONUS_EFFECT = Effect{
    .name = "Variety Bonus",
    .description = "+8 damage and +25% energy regen after using a different skill type",
    .modifiers = &variety_bonus_modifiers,
    .timing = .on_hit,
    .affects = .self,
    .duration_ms = 5000,
    .is_buff = true,
    .condition = .if_caster_used_different_type,
};

// ----------------------------------------------------------------------------
// AOE EFFECTS - Party buffs and enemy debuffs
// ----------------------------------------------------------------------------

// "Rally Cry" - party-wide healing buff
const rally_cry_modifiers = [_]Modifier{
    .{
        .effect_type = .healing_multiplier,
        .value = .{ .float = 1.25 }, // 25% more healing received
    },
};

pub const RALLY_CRY_EFFECT = Effect{
    .name = "Rally Cry",
    .description = "Allies in earshot receive 25% more healing",
    .modifiers = &rally_cry_modifiers,
    .timing = .on_cast,
    .affects = .allies_in_earshot,
    .duration_ms = 10000,
    .is_buff = true,
    .condition = .always,
};

// "Intimidating Presence" - AoE debuff
const intimidating_presence_modifiers = [_]Modifier{
    .{
        .effect_type = .damage_multiplier,
        .value = .{ .float = 0.85 }, // Enemies deal 15% less damage
    },
};

pub const INTIMIDATING_PRESENCE_EFFECT = Effect{
    .name = "Intimidating Presence",
    .description = "Nearby foes deal 15% less damage",
    .modifiers = &intimidating_presence_modifiers,
    .timing = .while_active,
    .affects = .foes_in_earshot,
    .duration_ms = 12000,
    .is_buff = false,
    .condition = .always,
};

// ----------------------------------------------------------------------------
// REACTIVE EFFECTS - Triggered by taking damage, blocking, etc.
// ----------------------------------------------------------------------------

// "Thorns" - damage attackers
const thorns_modifiers = [_]Modifier{
    .{
        .effect_type = .damage_add,
        .value = .{ .float = 10.0 }, // Reflect 10 damage
    },
};

pub const THORNS_EFFECT = Effect{
    .name = "Thorns",
    .description = "When hit, deal 10 damage back to attacker",
    .modifiers = &thorns_modifiers,
    .timing = .on_take_damage,
    .affects = .source_of_damage,
    .duration_ms = 0, // Instant
    .is_buff = false,
    .condition = .always,
};

// "Counter Stance" - buff self when blocking
const counter_stance_modifiers = [_]Modifier{
    .{
        .effect_type = .attack_speed_multiplier,
        .value = .{ .float = 1.5 }, // 50% faster attacks
    },
};

pub const COUNTER_STANCE_EFFECT = Effect{
    .name = "Counter Stance",
    .description = "After blocking, attack 50% faster for 3 seconds",
    .modifiers = &counter_stance_modifiers,
    .timing = .on_block,
    .affects = .self,
    .duration_ms = 3000,
    .is_buff = true,
    .condition = .always,
};

// ----------------------------------------------------------------------------
// TERRAIN-CONDITIONAL EFFECTS
// ----------------------------------------------------------------------------

// "Ice Mastery" - bonus on icy terrain
const ice_mastery_modifiers = [_]Modifier{
    .{
        .effect_type = .move_speed_multiplier,
        .value = .{ .float = 1.25 }, // 25% faster on ice
    },
    .{
        .effect_type = .evasion_percent,
        .value = .{ .float = 0.15 }, // 15% evasion on ice
    },
};

pub const ICE_MASTERY_EFFECT = Effect{
    .name = "Ice Mastery",
    .description = "On ice: move 25% faster and 15% evasion",
    .modifiers = &ice_mastery_modifiers,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 0, // Permanent while on ice
    .is_buff = true,
    .condition = .if_on_ice,
};

// "Deep Snow Advantage" - bonus against targets in deep snow
const deep_snow_advantage_modifiers = [_]Modifier{
    .{
        .effect_type = .damage_add,
        .value = .{ .float = 15.0 },
    },
    .{
        .effect_type = .accuracy_multiplier,
        .value = .{ .float = 1.2 }, // 20% more accurate
    },
};

pub const DEEP_SNOW_ADVANTAGE_EFFECT = Effect{
    .name = "Deep Snow Advantage",
    .description = "+15 damage and +20% accuracy vs targets in deep snow",
    .modifiers = &deep_snow_advantage_modifiers,
    .timing = .on_hit,
    .affects = .target,
    .duration_ms = 0,
    .is_buff = false,
    .condition = .if_target_on_deep_snow,
};

// ----------------------------------------------------------------------------
// INTERRUPT/KNOCKDOWN EFFECTS
// ----------------------------------------------------------------------------

// "Daze Follow-up" - bonus damage to knocked down targets
const daze_followup_modifiers = [_]Modifier{
    .{
        .effect_type = .damage_multiplier,
        .value = .{ .float = 1.5 },
    },
};

pub const DAZE_FOLLOWUP_EFFECT = Effect{
    .name = "Daze Follow-up",
    .description = "+50% damage to knocked down targets",
    .modifiers = &daze_followup_modifiers,
    .timing = .on_hit,
    .affects = .target,
    .duration_ms = 0,
    .is_buff = false,
    .condition = .if_target_knocked_down,
};

// "Interrupt Bonus" - reward for successful interrupt
const interrupt_bonus_modifiers = [_]Modifier{
    .{
        .effect_type = .energy_regen_multiplier,
        .value = .{ .float = 2.0 },
    },
};

pub const INTERRUPT_BONUS_EFFECT = Effect{
    .name = "Interrupt Bonus",
    .description = "Double energy regen for 5s after interrupting",
    .modifiers = &interrupt_bonus_modifiers,
    .timing = .on_interrupt,
    .affects = .self,
    .duration_ms = 5000,
    .is_buff = true,
    .condition = .always,
};

// ============================================================================
// BLOCKING EFFECTS - GW1-style block stances and anti-block
// ============================================================================

// "Snowball Shield" - 75% block chance stance
const snowball_shield_modifiers = [_]Modifier{
    .{
        .effect_type = .block_chance,
        .value = .{ .float = 0.75 }, // 75% block chance
    },
};

pub const SNOWBALL_SHIELD_EFFECT = Effect{
    .name = "Snowball Shield",
    .description = "75% chance to block incoming snowballs",
    .modifiers = &snowball_shield_modifiers,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 8000,
    .is_buff = true,
    .condition = .always,
};

// "Quick Reflexes" - block exactly one attack then gain speed
const quick_reflexes_modifiers = [_]Modifier{
    .{
        .effect_type = .block_next_attack,
        .value = .{ .float = 1.0 }, // Block 1 attack
    },
};

const quick_reflexes_followup_modifiers = [_]Modifier{
    .{
        .effect_type = .move_speed_multiplier,
        .value = .{ .float = 1.33 }, // 33% speed boost after block
    },
};

pub const QUICK_REFLEXES_FOLLOWUP_EFFECT = Effect{
    .name = "Quick Dodge",
    .description = "Move 33% faster after dodging",
    .modifiers = &quick_reflexes_followup_modifiers,
    .timing = .on_block,
    .affects = .self,
    .duration_ms = 4000,
    .is_buff = true,
    .condition = .always,
};

pub const QUICK_REFLEXES_EFFECT = Effect{
    .name = "Quick Reflexes",
    .description = "Block the next attack. After blocking, move 33% faster for 4s.",
    .modifiers = &quick_reflexes_modifiers,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 10000, // Expires if not triggered
    .is_buff = true,
    .condition = .always,
    .on_end_effect = &QUICK_REFLEXES_FOLLOWUP_EFFECT, // Triggers on successful block
};

// "Shield Breaker" - bonus damage vs blocking targets
const shield_breaker_modifiers = [_]Modifier{
    .{
        .effect_type = .damage_multiplier,
        .value = .{ .float = 1.5 }, // 50% more damage vs blockers
    },
};

pub const SHIELD_BREAKER_EFFECT = Effect{
    .name = "Shield Breaker",
    .description = "+50% damage against blocking targets",
    .modifiers = &shield_breaker_modifiers,
    .timing = .on_hit,
    .affects = .target,
    .duration_ms = 0,
    .is_buff = false,
    .condition = .if_target_blocking,
};

// ============================================================================
// SKILL DISABLE EFFECTS - Silence/Daze equivalents
// ============================================================================

// "Brain Freeze" - can't use skills (ate too much snow)
const brain_freeze_modifiers = [_]Modifier{
    .{
        .effect_type = .skills_disabled,
        .value = .{ .int = 1 }, // All skills disabled
    },
};

pub const BRAIN_FREEZE_DISABLE_EFFECT = Effect{
    .name = "Brain Freeze",
    .description = "Can't use any skills (brain freeze from eating snow)",
    .modifiers = &brain_freeze_modifiers,
    .timing = .while_active,
    .affects = .target,
    .duration_ms = 3000, // 3 seconds
    .is_buff = false,
    .condition = .always,
};

// "Numb Fingers" - can't throw (hands too cold)
const numb_fingers_modifiers = [_]Modifier{
    .{
        .effect_type = .attack_skills_disabled,
        .value = .{ .int = 1 }, // Throw skills disabled
    },
};

pub const NUMB_FINGERS_EFFECT = Effect{
    .name = "Numb Fingers",
    .description = "Can't use Throw skills (hands too cold)",
    .modifiers = &numb_fingers_modifiers,
    .timing = .while_active,
    .affects = .target,
    .duration_ms = 5000, // 5 seconds
    .is_buff = false,
    .condition = .always,
};

// "Foggy Goggles" - can't use tricks (can't see properly)
const foggy_goggles_modifiers = [_]Modifier{
    .{
        .effect_type = .spell_skills_disabled,
        .value = .{ .int = 1 }, // Trick/Gesture skills disabled
    },
};

pub const FOGGY_GOGGLES_EFFECT = Effect{
    .name = "Foggy Goggles",
    .description = "Can't use Trick or Gesture skills (goggles fogged up)",
    .modifiers = &foggy_goggles_modifiers,
    .timing = .while_active,
    .affects = .target,
    .duration_ms = 4000, // 4 seconds
    .is_buff = false,
    .condition = .always,
};

// ============================================================================
// DURATION MODIFIER EFFECTS - Affect how long conditions last
// ============================================================================

// "Lingering Cold" - chills you apply last longer
const lingering_cold_modifiers = [_]Modifier{
    .{
        .effect_type = .chill_duration_multiplier,
        .value = .{ .float = 1.5 }, // Chills last 50% longer
    },
};

pub const LINGERING_COLD_EFFECT = Effect{
    .name = "Lingering Cold",
    .description = "Chills you apply last 50% longer",
    .modifiers = &lingering_cold_modifiers,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 20000, // 20 second buff
    .is_buff = true,
    .condition = .always,
};

// "Cozy Aura" - cozies on you last longer
const cozy_aura_modifiers = [_]Modifier{
    .{
        .effect_type = .cozy_duration_multiplier,
        .value = .{ .float = 1.33 }, // Cozies last 33% longer
    },
};

pub const COZY_AURA_EFFECT = Effect{
    .name = "Cozy Aura",
    .description = "Cozy effects on you last 33% longer",
    .modifiers = &cozy_aura_modifiers,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 30000, // 30 second buff
    .is_buff = true,
    .condition = .always,
};

// "Chill Resistance" - chills on you expire faster
const chill_resistance_modifiers = [_]Modifier{
    .{
        .effect_type = .chill_duration_multiplier,
        .value = .{ .float = 0.5 }, // Chills last half as long on you
    },
};

pub const CHILL_RESISTANCE_EFFECT = Effect{
    .name = "Chill Resistance",
    .description = "Chills on you expire 50% faster",
    .modifiers = &chill_resistance_modifiers,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 15000,
    .is_buff = true,
    .condition = .always,
};

// ============================================================================
// ENCHANTMENT-CONDITIONAL EFFECTS (if caster has cozy X)
// ============================================================================

// "Fire Inside Bonus" - bonus damage while you have Fire Inside cozy
const fire_inside_bonus_modifiers = [_]Modifier{
    .{
        .effect_type = .damage_add,
        .value = .{ .float = 12.0 }, // +12 damage
    },
};

pub const FIRE_INSIDE_BONUS_EFFECT = Effect{
    .name = "Inner Fire Strike",
    .description = "+12 damage while you have Fire Inside",
    .modifiers = &fire_inside_bonus_modifiers,
    .timing = .on_hit,
    .affects = .target,
    .duration_ms = 0,
    .is_buff = false,
    .condition = .if_caster_has_cozy_fire_inside,
};

// "Bundled Defense" - reflect damage while Bundled Up
const bundled_defense_modifiers = [_]Modifier{
    .{
        .effect_type = .damage_add,
        .value = .{ .float = 8.0 }, // Reflect 8 damage
    },
};

pub const BUNDLED_DEFENSE_EFFECT = Effect{
    .name = "Padded Revenge",
    .description = "While Bundled Up, reflect 8 damage when hit",
    .modifiers = &bundled_defense_modifiers,
    .timing = .on_take_damage,
    .affects = .source_of_damage,
    .duration_ms = 0,
    .is_buff = false,
    .condition = .if_caster_has_cozy_bundled_up,
};

// "Cocoa Healing Boost" - heal more while you have Hot Cocoa
const cocoa_healing_modifiers = [_]Modifier{
    .{
        .effect_type = .healing_multiplier,
        .value = .{ .float = 1.5 }, // 50% more healing
    },
};

pub const COCOA_HEALING_BOOST_EFFECT = Effect{
    .name = "Cocoa Warmth",
    .description = "While you have Hot Cocoa, healing is 50% more effective",
    .modifiers = &cocoa_healing_modifiers,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 0, // Permanent while condition met
    .is_buff = true,
    .condition = .if_caster_has_cozy_hot_cocoa,
};

// "Strip Cozy" - bonus damage if target has any cozy (for enchantment removal)
const strip_cozy_modifiers = [_]Modifier{
    .{
        .effect_type = .damage_add,
        .value = .{ .float = 20.0 }, // +20 damage vs enchanted
    },
};

pub const STRIP_COZY_EFFECT = Effect{
    .name = "Strip Layers",
    .description = "+20 damage against targets with Cozy effects",
    .modifiers = &strip_cozy_modifiers,
    .timing = .on_hit,
    .affects = .target,
    .duration_ms = 0,
    .is_buff = false,
    .condition = .if_target_has_any_cozy,
};

// ============================================================================
// GENERIC REUSABLE MODIFIER ARRAYS
// ============================================================================
// These are building blocks that skills can reference directly or use as
// examples for composing their own modifier arrays.

// Single-modifier arrays for common patterns
pub const MOD_KNOCKDOWN = [_]Modifier{.{ .effect_type = .knockdown, .value = .{ .int = 1 } }};
pub const MOD_REMOVE_ALL_CHILLS = [_]Modifier{.{ .effect_type = .remove_all_chills, .value = .{ .int = 1 } }};
pub const MOD_REMOVE_ALL_COZIES = [_]Modifier{.{ .effect_type = .remove_all_cozies, .value = .{ .int = 1 } }};

// ============================================================================
// Helper functions to query and apply effects
// ============================================================================

/// Query a specific modifier type from an effect
/// Returns the modifier value if found, or null if not present
pub fn getModifier(effect: *const Effect, modifier_type: EffectModifier) ?ModifierValue {
    for (effect.modifiers) |mod| {
        if (mod.effect_type == modifier_type) {
            return mod.value;
        }
    }
    return null;
}

/// Calculate aggregate damage multiplier from active effects
/// Combines all damage_multiplier modifiers on a character
pub fn calculateDamageMultiplier(active_effects: []const ?ActiveEffect, effect_count: u8) f32 {
    var multiplier: f32 = 1.0;

    for (active_effects[0..effect_count]) |maybe_effect| {
        if (maybe_effect) |active| {
            if (getModifier(active.effect, .damage_multiplier)) |value| {
                if (value == .float) {
                    multiplier *= value.float;
                }
            }
        }
    }

    return multiplier;
}

/// Calculate aggregate armor/padding multiplier from active effects
pub fn calculateArmorMultiplier(active_effects: []const ?ActiveEffect, effect_count: u8) f32 {
    var multiplier: f32 = 1.0;

    for (active_effects[0..effect_count]) |maybe_effect| {
        if (maybe_effect) |active| {
            if (getModifier(active.effect, .armor_multiplier)) |value| {
                if (value == .float) {
                    multiplier *= value.float;
                }
            }
        }
    }

    return multiplier;
}

/// Calculate aggregate movement speed multiplier from active effects
pub fn calculateMoveSpeedMultiplier(active_effects: []const ?ActiveEffect, effect_count: u8) f32 {
    var multiplier: f32 = 1.0;

    for (active_effects[0..effect_count]) |maybe_effect| {
        if (maybe_effect) |active| {
            if (getModifier(active.effect, .move_speed_multiplier)) |value| {
                if (value == .float) {
                    multiplier *= value.float;
                }
            }
        }
    }

    return multiplier;
}

/// Calculate aggregate energy cost multiplier from active effects
pub fn calculateEnergyCostMultiplier(active_effects: []const ?ActiveEffect, effect_count: u8) f32 {
    var multiplier: f32 = 1.0;

    for (active_effects[0..effect_count]) |maybe_effect| {
        if (maybe_effect) |active| {
            if (getModifier(active.effect, .energy_cost_multiplier)) |value| {
                if (value == .float) {
                    multiplier *= value.float;
                }
            }
        }
    }

    return multiplier;
}

/// Calculate aggregate energy regen multiplier from active effects
pub fn calculateEnergyRegenMultiplier(active_effects: []const ?ActiveEffect, effect_count: u8) f32 {
    var multiplier: f32 = 1.0;

    for (active_effects[0..effect_count]) |maybe_effect| {
        if (maybe_effect) |active| {
            if (getModifier(active.effect, .energy_regen_multiplier)) |value| {
                if (value == .float) {
                    multiplier *= value.float;
                }
            }
        }
    }

    return multiplier;
}

/// Calculate aggregate cooldown reduction percent from active effects
pub fn calculateCooldownReductionPercent(active_effects: []const ?ActiveEffect, effect_count: u8) f32 {
    var total_reduction: f32 = 0.0;

    for (active_effects[0..effect_count]) |maybe_effect| {
        if (maybe_effect) |active| {
            if (getModifier(active.effect, .cooldown_reduction_percent)) |value| {
                if (value == .float) {
                    total_reduction += value.float;
                }
            }
        }
    }

    // Cap at 80% reduction (can't go below 20% of original cooldown)
    return @min(total_reduction, 0.8);
}

// ============================================================================
// PHASE 1 HELPER FUNCTIONS - New effect calculations
// ============================================================================

/// Calculate total warmth drain per second from active effects
/// Used for skills like Obsession, Unstoppable Force
pub fn calculateWarmthDrainPerSecond(active_effects: []const ?ActiveEffect, effect_count: u8) f32 {
    var total_drain: f32 = 0.0;

    for (active_effects[0..effect_count]) |maybe_effect| {
        if (maybe_effect) |active| {
            if (getModifier(active.effect, .warmth_drain_per_second)) |value| {
                if (value == .float) {
                    total_drain += value.float;
                }
            }
        }
    }

    return total_drain;
}

/// Calculate total warmth gain per second from active effects
pub fn calculateWarmthGainPerSecond(active_effects: []const ?ActiveEffect, effect_count: u8) f32 {
    var total_gain: f32 = 0.0;

    for (active_effects[0..effect_count]) |maybe_effect| {
        if (maybe_effect) |active| {
            if (getModifier(active.effect, .warmth_gain_per_second)) |value| {
                if (value == .float) {
                    total_gain += value.float;
                }
            }
        }
    }

    return total_gain;
}

/// Calculate total energy gain per second from active effects
pub fn calculateEnergyGainPerSecond(active_effects: []const ?ActiveEffect, effect_count: u8) f32 {
    var total_gain: f32 = 0.0;

    for (active_effects[0..effect_count]) |maybe_effect| {
        if (maybe_effect) |active| {
            if (getModifier(active.effect, .energy_gain_per_second)) |value| {
                if (value == .float) {
                    total_gain += value.float;
                }
            }
        }
    }

    return total_gain;
}

/// Calculate total grit gain per second from active effects (Public School)
pub fn calculateGritGainPerSecond(active_effects: []const ?ActiveEffect, effect_count: u8) f32 {
    var total_gain: f32 = 0.0;

    for (active_effects[0..effect_count]) |maybe_effect| {
        if (maybe_effect) |active| {
            if (getModifier(active.effect, .grit_gain_per_second)) |value| {
                if (value == .float) {
                    total_gain += value.float;
                }
            }
        }
    }

    return total_gain;
}

/// Calculate total rhythm gain per second from active effects (Waldorf)
pub fn calculateRhythmGainPerSecond(active_effects: []const ?ActiveEffect, effect_count: u8) f32 {
    var total_gain: f32 = 0.0;

    for (active_effects[0..effect_count]) |maybe_effect| {
        if (maybe_effect) |active| {
            if (getModifier(active.effect, .rhythm_gain_per_second)) |value| {
                if (value == .float) {
                    total_gain += value.float;
                }
            }
        }
    }

    return total_gain;
}

/// Calculate max warmth modifier (additive) from active effects
pub fn calculateMaxWarmthAdd(active_effects: []const ?ActiveEffect, effect_count: u8) f32 {
    var total_add: f32 = 0.0;

    for (active_effects[0..effect_count]) |maybe_effect| {
        if (maybe_effect) |active| {
            if (getModifier(active.effect, .max_warmth_add)) |value| {
                if (value == .float) {
                    total_add += value.float;
                }
            }
        }
    }

    return total_add;
}

/// Calculate max warmth multiplier from active effects
pub fn calculateMaxWarmthMultiplier(active_effects: []const ?ActiveEffect, effect_count: u8) f32 {
    var multiplier: f32 = 1.0;

    for (active_effects[0..effect_count]) |maybe_effect| {
        if (maybe_effect) |active| {
            if (getModifier(active.effect, .max_warmth_multiplier)) |value| {
                if (value == .float) {
                    multiplier *= value.float;
                }
            }
        }
    }

    return multiplier;
}

/// Calculate max energy modifier (additive) from active effects
pub fn calculateMaxEnergyAdd(active_effects: []const ?ActiveEffect, effect_count: u8) f32 {
    var total_add: f32 = 0.0;

    for (active_effects[0..effect_count]) |maybe_effect| {
        if (maybe_effect) |active| {
            if (getModifier(active.effect, .max_energy_add)) |value| {
                if (value == .float) {
                    total_add += value.float;
                }
            }
        }
    }

    return total_add;
}

/// Calculate max energy multiplier from active effects (Private School: Trust Fund Baby)
pub fn calculateMaxEnergyMultiplier(active_effects: []const ?ActiveEffect, effect_count: u8) f32 {
    var multiplier: f32 = 1.0;

    for (active_effects[0..effect_count]) |maybe_effect| {
        if (maybe_effect) |active| {
            if (getModifier(active.effect, .max_energy_multiplier)) |value| {
                if (value == .float) {
                    multiplier *= value.float;
                }
            }
        }
    }

    return multiplier;
}

/// Check if character is knocked down from active effects
pub fn isKnockedDown(active_effects: []const ?ActiveEffect, effect_count: u8) bool {
    for (active_effects[0..effect_count]) |maybe_effect| {
        if (maybe_effect) |active| {
            if (getModifier(active.effect, .knockdown)) |value| {
                if (value == .int and value.int == 1) {
                    return true;
                }
            }
        }
    }
    return false;
}

/// Check if character is immune to knockdown
pub fn isImmuneToKnockdown(active_effects: []const ?ActiveEffect, effect_count: u8) bool {
    for (active_effects[0..effect_count]) |maybe_effect| {
        if (maybe_effect) |active| {
            if (getModifier(active.effect, .immune_to_knockdown)) |value| {
                if (value == .int and value.int == 1) {
                    return true;
                }
            }
        }
    }
    return false;
}

/// Check if character is immune to interrupts
pub fn isImmuneToInterrupt(active_effects: []const ?ActiveEffect, effect_count: u8) bool {
    for (active_effects[0..effect_count]) |maybe_effect| {
        if (maybe_effect) |active| {
            if (getModifier(active.effect, .immune_to_interrupt)) |value| {
                if (value == .int and value.int == 1) {
                    return true;
                }
            }
        }
    }
    return false;
}

/// Check if character is immune to slows
pub fn isImmuneToSlow(active_effects: []const ?ActiveEffect, effect_count: u8) bool {
    for (active_effects[0..effect_count]) |maybe_effect| {
        if (maybe_effect) |active| {
            if (getModifier(active.effect, .immune_to_slow)) |value| {
                if (value == .int and value.int == 1) {
                    return true;
                }
            }
        }
    }
    return false;
}

/// Check if character is immune to new chills
pub fn isImmuneToChill(active_effects: []const ?ActiveEffect, effect_count: u8) bool {
    for (active_effects[0..effect_count]) |maybe_effect| {
        if (maybe_effect) |active| {
            if (getModifier(active.effect, .immune_to_chill)) |value| {
                if (value == .int and value.int == 1) {
                    return true;
                }
            }
        }
    }
    return false;
}

/// Get "next attack" damage bonus (single-use, should be consumed after use)
/// Returns the bonus and the index of the effect to remove
pub fn getNextAttackDamageBonus(active_effects: []const ?ActiveEffect, effect_count: u8) struct { add: f32, multiplier: f32, effect_indices: [2]?usize } {
    var result = .{ .add = 0.0, .multiplier = 1.0, .effect_indices = .{ null, null } };

    for (active_effects[0..effect_count], 0..) |maybe_effect, i| {
        if (maybe_effect) |active| {
            if (getModifier(active.effect, .next_attack_damage_add)) |value| {
                if (value == .float) {
                    result.add += value.float;
                    result.effect_indices[0] = i;
                }
            }
            if (getModifier(active.effect, .next_attack_damage_multiplier)) |value| {
                if (value == .float) {
                    result.multiplier *= value.float;
                    result.effect_indices[1] = i;
                }
            }
        }
    }

    return result;
}

/// Calculate total damage reflection (flat + percent)
pub fn calculateDamageReflection(active_effects: []const ?ActiveEffect, effect_count: u8, damage_taken: f32) f32 {
    var total_reflect: f32 = 0.0;

    for (active_effects[0..effect_count]) |maybe_effect| {
        if (maybe_effect) |active| {
            if (getModifier(active.effect, .reflect_damage_flat)) |value| {
                if (value == .float) {
                    total_reflect += value.float;
                }
            }
            if (getModifier(active.effect, .reflect_damage_percent)) |value| {
                if (value == .float) {
                    total_reflect += damage_taken * value.float;
                }
            }
        }
    }

    return total_reflect;
}

/// Check if any effect wants to remove all chills
pub fn shouldRemoveAllChills(active_effects: []const ?ActiveEffect, effect_count: u8) bool {
    for (active_effects[0..effect_count]) |maybe_effect| {
        if (maybe_effect) |active| {
            if (getModifier(active.effect, .remove_all_chills)) |value| {
                if (value == .int and value.int == 1) {
                    return true;
                }
            }
        }
    }
    return false;
}

/// Check if any effect wants to remove all cozies
pub fn shouldRemoveAllCozies(active_effects: []const ?ActiveEffect, effect_count: u8) bool {
    for (active_effects[0..effect_count]) |maybe_effect| {
        if (maybe_effect) |active| {
            if (getModifier(active.effect, .remove_all_cozies)) |value| {
                if (value == .int and value.int == 1) {
                    return true;
                }
            }
        }
    }
    return false;
}

/// Calculate aggregate attack speed multiplier from active effects
pub fn calculateAttackSpeedMultiplier(active_effects: []const ?ActiveEffect, effect_count: u8) f32 {
    var multiplier: f32 = 1.0;

    for (active_effects[0..effect_count]) |maybe_effect| {
        if (maybe_effect) |active| {
            if (getModifier(active.effect, .attack_speed_multiplier)) |value| {
                if (value == .float) {
                    multiplier *= value.float;
                }
            }
        }
    }

    return multiplier;
}

/// Calculate aggregate cast speed multiplier from active effects
pub fn calculateCastSpeedMultiplier(active_effects: []const ?ActiveEffect, effect_count: u8) f32 {
    var multiplier: f32 = 1.0;

    for (active_effects[0..effect_count]) |maybe_effect| {
        if (maybe_effect) |active| {
            if (getModifier(active.effect, .cast_speed_multiplier)) |value| {
                if (value == .float) {
                    multiplier *= value.float;
                }
            }
        }
    }

    return multiplier;
}
