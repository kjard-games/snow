const types = @import("../types.zig");
const effects = @import("../../effects.zig");
const Skill = types.Skill;

// ============================================================================
// WALDORF SKILLS - Blue: Rhythm, Timing, Harmony
// ============================================================================
// Theme: Rewards perfect timing, rhythm-based bonuses, team harmony
// Synergizes with: Skill chaining, timing windows, support roles
// Cooldowns: Rhythmic (5-15s)

const waldorf_hot_cocoa = [_]types.CozyEffect{.{
    .cozy = .hot_cocoa,
    .duration_ms = 12000,
    .stack_intensity = 1,
}};

const waldorf_goggles = [_]types.CozyEffect{.{
    .cozy = .snow_goggles,
    .duration_ms = 15000,
    .stack_intensity = 1,
}};

const waldorf_slippery = [_]types.ChillEffect{.{
    .chill = .slippery,
    .duration_ms = 5000,
    .stack_intensity = 1,
}};

const waldorf_insulated = [_]types.CozyEffect{.{
    .cozy = .insulated,
    .duration_ms = 12000,
    .stack_intensity = 1,
}};

const waldorf_bundled = [_]types.CozyEffect{.{
    .cozy = .bundled_up,
    .duration_ms = 10000,
    .stack_intensity = 1,
}};

// ============================================================================
// EFFECT DEFINITIONS - Composable effects for complex skill mechanics
// ============================================================================

// Find Your Rhythm (skill 1): Alternating skill types recharge 50% faster
const find_your_rhythm_mods = [_]effects.Modifier{.{
    .effect_type = .cooldown_reduction_percent,
    .value = .{ .float = 0.5 }, // 50% faster recharge
}};

const FIND_YOUR_RHYTHM_EFFECT = effects.Effect{
    .name = "Find Your Rhythm",
    .description = "Alternating skill types recharge 50% faster",
    .modifiers = &find_your_rhythm_mods,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 15000,
    .is_buff = true,
    .condition = .if_caster_used_different_type, // Only when alternating types
};

const find_your_rhythm_effects = [_]effects.Effect{FIND_YOUR_RHYTHM_EFFECT};

// Eurythmy (skill 5): Move 25% faster + next skill instant if 3+ rhythm
const eurythmy_speed_mods = [_]effects.Modifier{.{
    .effect_type = .move_speed_multiplier,
    .value = .{ .float = 1.25 }, // 25% faster
}};

const EURYTHMY_SPEED_EFFECT = effects.Effect{
    .name = "Eurythmy",
    .description = "Move 25% faster",
    .modifiers = &eurythmy_speed_mods,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 8000,
    .is_buff = true,
};

const eurythmy_instant_mods = [_]effects.Modifier{.{
    .effect_type = .next_skill_instant_cast,
    .value = .{ .int = 1 },
}};

const EURYTHMY_INSTANT_EFFECT = effects.Effect{
    .name = "Eurythmy Flow",
    .description = "Next skill activates instantly",
    .modifiers = &eurythmy_instant_mods,
    .timing = .on_cast,
    .affects = .self,
    .duration_ms = 8000, // Expires with stance if not used
    .is_buff = true,
    .condition = .if_caster_has_rhythm_3_plus,
};

const eurythmy_effects = [_]effects.Effect{ EURYTHMY_SPEED_EFFECT, EURYTHMY_INSTANT_EFFECT };

// Tempo Change (skill 10): Allies +25% speed, enemies -15% speed
const tempo_change_ally_mods = [_]effects.Modifier{.{
    .effect_type = .move_speed_multiplier,
    .value = .{ .float = 1.25 }, // 25% faster
}};

const TEMPO_CHANGE_ALLY_EFFECT = effects.Effect{
    .name = "Tempo Change",
    .description = "Move 25% faster",
    .modifiers = &tempo_change_ally_mods,
    .timing = .while_active,
    .affects = .allies_in_earshot,
    .duration_ms = 8000,
    .is_buff = true,
};

const tempo_change_enemy_mods = [_]effects.Modifier{.{
    .effect_type = .move_speed_multiplier,
    .value = .{ .float = 0.85 }, // 15% slower
}};

const TEMPO_CHANGE_ENEMY_EFFECT = effects.Effect{
    .name = "Tempo Disruption",
    .description = "Move 15% slower",
    .modifiers = &tempo_change_enemy_mods,
    .timing = .while_active,
    .affects = .foes_in_earshot,
    .duration_ms = 8000,
    .is_buff = false,
};

const tempo_change_effects = [_]effects.Effect{ TEMPO_CHANGE_ALLY_EFFECT, TEMPO_CHANGE_ENEMY_EFFECT };

// Meditative State (skill 12): +2 energy per second
const meditative_state_mods = [_]effects.Modifier{.{
    .effect_type = .energy_gain_per_second,
    .value = .{ .float = 2.0 },
}};

const MEDITATIVE_STATE_EFFECT = effects.Effect{
    .name = "Meditative State",
    .description = "Gain +2 energy per second",
    .modifiers = &meditative_state_mods,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 12000,
    .is_buff = true,
};

const meditative_state_effects = [_]effects.Effect{MEDITATIVE_STATE_EFFECT};

// Graceful Recovery (skill 14): Take 25% less damage + gain 1 rhythm when hit
const graceful_recovery_mods = [_]effects.Modifier{
    .{
        .effect_type = .damage_multiplier,
        .value = .{ .float = 0.75 }, // Take 25% less damage
    },
    .{
        .effect_type = .rhythm_on_take_damage,
        .value = .{ .float = 1.0 }, // Gain 1 rhythm when hit
    },
};

const GRACEFUL_RECOVERY_EFFECT = effects.Effect{
    .name = "Graceful Recovery",
    .description = "Take 25% less damage. Gain 1 Rhythm when hit.",
    .modifiers = &graceful_recovery_mods,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 10000,
    .is_buff = true,
};

const graceful_recovery_effects = [_]effects.Effect{GRACEFUL_RECOVERY_EFFECT};

// Perfect Form (skill 16): Skills cost no energy + 50% faster recharge
const perfect_form_mods = [_]effects.Modifier{
    .{
        .effect_type = .energy_cost_multiplier,
        .value = .{ .float = 0.0 }, // Skills cost nothing
    },
    .{
        .effect_type = .cooldown_reduction_percent,
        .value = .{ .float = 0.5 }, // 50% faster recharge
    },
};

const PERFECT_FORM_EFFECT = effects.Effect{
    .name = "Perfect Form",
    .description = "Skills cost no energy and recharge 50% faster",
    .modifiers = &perfect_form_mods,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 10000,
    .is_buff = true,
};

const perfect_form_effects = [_]effects.Effect{PERFECT_FORM_EFFECT};

// Tempo Mastery (AP 2): Per rhythm +5% damage, +5% speed, +5% CDR
// Note: This is a baseline effect - actual scaling per rhythm needs runtime
const tempo_mastery_mods = [_]effects.Modifier{
    .{
        .effect_type = .damage_multiplier,
        .value = .{ .float = 1.25 }, // Base +25% (assuming 5 rhythm)
    },
    .{
        .effect_type = .move_speed_multiplier,
        .value = .{ .float = 1.25 }, // Base +25%
    },
    .{
        .effect_type = .cooldown_reduction_percent,
        .value = .{ .float = 0.25 }, // Base 25% CDR
    },
};

const TEMPO_MASTERY_EFFECT = effects.Effect{
    .name = "Tempo Mastery",
    .description = "Per Rhythm: +5% damage, +5% speed, +5% CDR",
    .modifiers = &tempo_mastery_mods,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 30000,
    .is_buff = true,
    // NOTE: Actual per-rhythm scaling requires runtime calculation
};

const tempo_mastery_effects = [_]effects.Effect{TEMPO_MASTERY_EFFECT};

// Symphony of Snow (AP 1): All allies gain rhythm and energy passively
// Simplified from trigger-based to passive gain over time
const symphony_of_snow_mods = [_]effects.Modifier{
    .{
        .effect_type = .rhythm_gain_per_second,
        .value = .{ .float = 0.5 }, // Allies gain rhythm over time
    },
    .{
        .effect_type = .energy_gain_per_second,
        .value = .{ .float = 1.0 }, // Allies gain energy over time
    },
};

const SYMPHONY_OF_SNOW_EFFECT = effects.Effect{
    .name = "Symphony of Snow",
    .description = "All allies passively gain Rhythm and energy",
    .modifiers = &symphony_of_snow_mods,
    .timing = .while_active,
    .affects = .allies_in_earshot,
    .duration_ms = 20000,
    .is_buff = true,
};

const symphony_of_snow_effects = [_]effects.Effect{SYMPHONY_OF_SNOW_EFFECT};

// Resonant Link (AP 3): Share rhythm stacks with linked ally
// Simplified to just give the target rhythm gain per second
const resonant_link_mods = [_]effects.Modifier{.{
    .effect_type = .rhythm_gain_per_second,
    .value = .{ .float = 1.0 }, // Target gains rhythm over time
}};

const RESONANT_LINK_EFFECT = effects.Effect{
    .name = "Resonant Link",
    .description = "Target ally gains Rhythm over time",
    .modifiers = &resonant_link_mods,
    .timing = .while_active,
    .affects = .target,
    .duration_ms = 30000,
    .is_buff = true,
};

const resonant_link_effects = [_]effects.Effect{RESONANT_LINK_EFFECT};

// Ensemble Cast (skill 13): Team rhythm sharing
// Simplified from complex rhythm sharing to rhythm gain per second for allies
const ensemble_cast_mods = [_]effects.Modifier{.{
    .effect_type = .rhythm_gain_per_second,
    .value = .{ .float = 0.5 }, // Allies gain rhythm over time
}};

const ENSEMBLE_CAST_EFFECT = effects.Effect{
    .name = "Ensemble Cast",
    .description = "All allies build Rhythm over time",
    .modifiers = &ensemble_cast_mods,
    .timing = .while_active,
    .affects = .allies_in_earshot,
    .duration_ms = 10000,
    .is_buff = true,
};

const ensemble_cast_effects = [_]effects.Effect{ENSEMBLE_CAST_EFFECT};

pub const skills = [_]Skill{
    // 1. Rhythm buff - core mechanic
    .{
        .name = "Find Your Rhythm",
        .description = "Stance. (15 seconds.) Alternating skill types recharge 50% faster and build Rhythm.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 5,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 20000,
        .duration_ms = 15000,
        .grants_rhythm_on_cast = 1,
        .effects = &find_your_rhythm_effects,
    },

    // 2. Team heal - harmony
    .{
        .name = "Circle Time",
        .description = "Call. Heals party members for 30 Warmth.",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 10,
        .healing = 30.0,
        .cast_range = 250.0,
        .target_type = .ally,
        .aoe_type = .area,
        .aoe_radius = 250.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 25000,
        .grants_rhythm_on_cast = 1,
    },

    // 3. Timing-based damage - costs rhythm stacks
    .{
        .name = "Perfect Pitch",
        .description = "Throw. Requires 5 Rhythm. Costs no energy. Deals 20 damage.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 0,
        .requires_rhythm_stacks = 5,
        .damage = 20.0,
        .cast_range = 200.0,
        .activation_time_ms = 750,
        .aftercast_ms = 750,
        .recharge_time_ms = 8000,
    },

    // 4. Support buff
    .{
        .name = "Group Harmony",
        .description = "Call. (12 seconds.) Party members have Hot Cocoa regeneration.",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 8,
        .cast_range = 250.0,
        .target_type = .ally,
        .aoe_type = .area,
        .aoe_radius = 250.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 20000,
        .duration_ms = 12000,
        .cozies = &waldorf_hot_cocoa,
        .grants_rhythm_on_cast = 1,
    },

    // 5. Reactive skill - rhythmic movement
    .{
        .name = "Eurythmy",
        .description = "Stance. (8 seconds.) Move 25% faster. Your next skill activates instantly if you have 3+ Rhythm.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 5,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 15000,
        .duration_ms = 8000,
        .grants_rhythm_on_cast = 1,
        .effects = &eurythmy_effects,
    },

    // 6. Artistic trick - control
    .{
        .name = "Flowing Motion",
        .description = "Trick. Deals 10 damage. Inflicts Slippery (5 seconds).",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 7,
        .damage = 10.0,
        .cast_range = 200.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 12000,
        .chills = &waldorf_slippery,
        .grants_rhythm_on_cast = 1,
    },

    // 7. Vision support
    .{
        .name = "Clear Mind",
        .description = "Call. (15 seconds.) Party members gain Snow Goggles.",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 6,
        .cast_range = 250.0,
        .target_type = .ally,
        .aoe_type = .area,
        .aoe_radius = 250.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 25000,
        .duration_ms = 15000,
        .cozies = &waldorf_goggles,
        .grants_rhythm_on_cast = 1,
    },

    // 8. Rhythm finisher - builds with each skill
    .{
        .name = "Crescendo",
        .description = "Elite Trick. Deals 20 damage +5 damage per Rhythm stack. Consumes all Rhythm.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 8,
        .damage = 20.0,
        .cast_range = 220.0,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 15000,
        .consumes_all_rhythm = true,
        .damage_per_rhythm_consumed = 5.0,
    },

    // 9. WALL: Harmonic Wall - rhythmic wall that pulses
    .{
        .name = "Harmonic Wall",
        .description = "Call. Build a resonant wall. Grants 1 Rhythm on cast. Party members near the wall gain Hot Cocoa regeneration.",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 9,
        .target_type = .ground,
        .cast_range = 140.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 22000,
        .creates_wall = true,
        .wall_length = 65.0,
        .wall_height = 32.0,
        .wall_thickness = 20.0,
        .wall_distance_from_caster = 45.0,
        .grants_rhythm_on_cast = 1,
        .cozies = &waldorf_hot_cocoa, // Healing aura near wall
        // TODO: AOE healing aura around the wall for allies
    },

    // 10. Tempo Change - speed manipulation
    .{
        .name = "Tempo Change",
        .description = "Call. Requires 3 Rhythm. For 8 seconds, allies move 25% faster, enemies move 15% slower.",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 8,
        .requires_rhythm_stacks = 3,
        .target_type = .ally,
        .aoe_type = .area,
        .aoe_radius = 250.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 20000,
        .duration_ms = 8000,
        .grants_rhythm_on_cast = 1,
        .effects = &tempo_change_effects,
    },

    // 11. Syncopation - interrupt and gain rhythm
    .{
        .name = "Syncopation",
        .description = "Throw. Deals 12 damage. Interrupts. Gain 2 Rhythm on successful interrupt.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 6,
        .damage = 12.0,
        .cast_range = 200.0,
        .activation_time_ms = 500,
        .aftercast_ms = 750,
        .recharge_time_ms = 10000,
        .interrupts = true,
        .grants_rhythm_on_cast = 2,
    },

    // 12. Meditative State - energy recovery through rhythm
    .{
        .name = "Meditative State",
        .description = "Stance. (12 seconds.) Gain +2 energy per second. +1 additional per Rhythm stack.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 5,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 25000,
        .duration_ms = 12000,
        .cozies = &waldorf_insulated,
        .grants_rhythm_on_cast = 1,
        .effects = &meditative_state_effects,
        // NOTE: +1 per rhythm requires runtime calculation
    },

    // 13. Ensemble Cast - team rhythm sharing
    .{
        .name = "Ensemble Cast",
        .description = "Call. All allies gain 2 Rhythm. For 10 seconds, when any ally gains Rhythm, all allies gain 1.",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 10,
        .target_type = .ally,
        .aoe_type = .area,
        .aoe_radius = 300.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 30000,
        .duration_ms = 10000,
        .effects = &ensemble_cast_effects,
    },

    // 14. Graceful Recovery - defensive rhythm skill
    .{
        .name = "Graceful Recovery",
        .description = "Stance. (10 seconds.) Take 25% less damage. Gain 1 Rhythm when hit.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 5,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 18000,
        .duration_ms = 10000,
        .cozies = &waldorf_bundled,
        .effects = &graceful_recovery_effects,
    },

    // 15. Harmonic Resonance - AoE damage based on rhythm
    .{
        .name = "Harmonic Resonance",
        .description = "Trick. Requires 4 Rhythm. Deals 15 damage to all foes in area +3 per Rhythm. Consumes all Rhythm.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 10,
        .requires_rhythm_stacks = 4,
        .damage = 15.0,
        .cast_range = 200.0,
        .aoe_type = .area,
        .aoe_radius = 150.0,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 20000,
        .consumes_all_rhythm = true,
        .damage_per_rhythm_consumed = 3.0,
    },

    // 16. Perfect Form - ultimate rhythm expression
    .{
        .name = "Perfect Form",
        .description = "Stance. Requires 6 Rhythm. (10 seconds.) Skills cost no energy and recharge 50% faster.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 0,
        .requires_rhythm_stacks = 6,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 45000,
        .duration_ms = 10000,
        .effects = &perfect_form_effects,
    },

    // ========================================================================
    // WALDORF AP SKILLS (4 AP skills for 20% of 20 total)
    // ========================================================================

    // AP 1: Symphony of Snow - massive team coordination
    .{
        .name = "Symphony of Snow",
        .description = "[AP] Call. For 20 seconds, whenever any ally uses a skill, all allies gain 1 Rhythm and 2 energy.",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 15,
        .target_type = .ally,
        .aoe_type = .area,
        .aoe_radius = 400.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 60000,
        .duration_ms = 20000,
        .is_ap = true,
        .effects = &symphony_of_snow_effects,
    },

    // AP 2: Tempo Mastery - rhythm becomes permanent during stance
    .{
        .name = "Tempo Mastery",
        .description = "[AP] Stance. (30 seconds.) Rhythm does not decay. Each Rhythm grants +5% damage, +5% speed, and +5% cooldown reduction.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 10,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 45000,
        .duration_ms = 30000,
        .is_ap = true,
        .effects = &tempo_mastery_effects,
    },

    // AP 3: Resonant Link - share rhythm benefits with ally
    .{
        .name = "Resonant Link",
        .description = "[AP] Link with target ally for 30 seconds. You share Rhythm stacks. Skills that grant Rhythm grant to both.",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 10,
        .target_type = .ally,
        .cast_range = 200.0,
        .activation_time_ms = 500,
        .aftercast_ms = 500,
        .recharge_time_ms = 40000,
        .duration_ms = 30000,
        .is_ap = true,
        .effects = &resonant_link_effects,
    },

    // AP 4: Grand Finale - ultimate rhythm finisher
    .{
        .name = "Grand Finale",
        .description = "[AP] Trick. Requires 8 Rhythm. Deals 20 damage +10 per Rhythm to all foes in area. Heals all allies for same amount. Consumes all Rhythm.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 15,
        .requires_rhythm_stacks = 8,
        .damage = 20.0,
        .healing = 20.0,
        .cast_range = 250.0,
        .aoe_type = .area,
        .aoe_radius = 200.0,
        .activation_time_ms = 2000,
        .aftercast_ms = 750,
        .recharge_time_ms = 50000,
        .consumes_all_rhythm = true,
        .damage_per_rhythm_consumed = 10.0,
        .is_ap = true,
    },
};
