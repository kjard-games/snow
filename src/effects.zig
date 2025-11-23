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

/// Conditional check for applying effects based on game state
/// Examples: "if target below 50% warmth", "if target has condition X", etc.
pub const EffectCondition = enum {
    // Target health conditions
    if_target_above_50_percent_warmth,
    if_target_below_50_percent_warmth,
    if_target_above_75_percent_warmth,
    if_target_below_25_percent_warmth,

    // Caster health conditions (for self-buffs)
    if_caster_above_50_percent_warmth,
    if_caster_below_50_percent_warmth,

    // Always apply (no condition)
    always,
};

/// Main effect structure - composable modifiers with duration
/// Can represent buffs, debuffs, or special effects
pub const Effect = struct {
    name: [:0]const u8,
    description: [:0]const u8 = "",

    /// Modifiers to apply
    modifiers: []const Modifier,

    /// Duration in milliseconds (0 = infinite/permanent for this hit)
    duration_ms: u32,

    /// Is this a beneficial effect (buff) or harmful (debuff)?
    is_buff: bool = false,

    /// Condition for applying this effect
    condition: EffectCondition = .always,

    /// Maximum stacks (0 = doesn't stack, resets duration instead)
    /// If > 0, multiple applications can stack up to this limit
    max_stacks: u8 = 0,

    /// How stacks combine: refresh duration, add intensity, etc.
    stack_behavior: StackBehavior = .refresh_duration,

    /// Priority for applying over other effects (higher = applies first)
    priority: i8 = 0,
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
pub fn evaluateCondition(
    condition: EffectCondition,
    caster_warmth_percent: f32,
    target_warmth_percent: f32,
) bool {
    return switch (condition) {
        .if_target_above_50_percent_warmth => target_warmth_percent >= 0.5,
        .if_target_below_50_percent_warmth => target_warmth_percent < 0.5,
        .if_target_above_75_percent_warmth => target_warmth_percent >= 0.75,
        .if_target_below_25_percent_warmth => target_warmth_percent < 0.25,
        .if_caster_above_50_percent_warmth => caster_warmth_percent >= 0.5,
        .if_caster_below_50_percent_warmth => caster_warmth_percent < 0.5,
        .always => true,
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
    .duration_ms = 15000,
    .is_buff = true,
    .condition = .always,
    .max_stacks = 1,
    .stack_behavior = .refresh_duration,
};

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
