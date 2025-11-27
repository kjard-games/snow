const types = @import("../types.zig");
const Skill = types.Skill;
const effects = @import("../../effects.zig");

// ============================================================================
// SLEDDER SKILLS - Aggressive skirmisher (80-150 range)
// ============================================================================
// Synergizes with: Movement speed, close-range damage, rhythm skills
// Counterplay: Kiting, snares, keeping distance

const fire_inside_cozy = [_]types.CozyEffect{.{
    .cozy = .fire_inside,
    .duration_ms = 8000,
    .stack_intensity = 1,
}};

const numb_chill = [_]types.ChillEffect{.{
    .chill = .numb,
    .duration_ms = 5000,
    .stack_intensity = 1,
}};

const sledder_sure_footed = [_]types.CozyEffect{.{
    .cozy = .sure_footed,
    .duration_ms = 8000,
    .stack_intensity = 1,
}};

const sledder_slippery = [_]types.ChillEffect{.{
    .chill = .slippery,
    .duration_ms = 4000,
    .stack_intensity = 1,
}};

const sledder_fire = [_]types.CozyEffect{.{
    .cozy = .fire_inside,
    .duration_ms = 6000,
    .stack_intensity = 1,
}};

// ============================================================================
// EFFECT DEFINITIONS
// ============================================================================

// Adrenaline Rush - +50% damage, +33% speed
const adrenaline_rush_mods = [_]effects.Modifier{
    .{
        .effect_type = .damage_multiplier,
        .value = .{ .float = 1.50 },
    },
    .{
        .effect_type = .move_speed_multiplier,
        .value = .{ .float = 1.33 },
    },
};

const ADRENALINE_RUSH_EFFECT = effects.Effect{
    .name = "Adrenaline Rush",
    .description = "+50% damage and +33% speed",
    .modifiers = &adrenaline_rush_mods,
    .timing = .while_active,
    .affects = .self,
    .condition = .always,
    .duration_ms = 8000,
    .is_buff = true,
};

const adrenaline_rush_effects = [_]effects.Effect{ADRENALINE_RUSH_EFFECT};

// Crushing Blow - knockdown
const crushing_blow_mods = [_]effects.Modifier{.{
    .effect_type = .knockdown,
    .value = .{ .int = 1 },
}};

const CRUSHING_BLOW_EFFECT = effects.Effect{
    .name = "Knockdown",
    .description = "Target is knocked down",
    .modifiers = &crushing_blow_mods,
    .timing = .on_hit,
    .affects = .target,
    .condition = .always,
    .duration_ms = 2000, // 2 second knockdown
    .is_buff = false,
};

const crushing_blow_effects = [_]effects.Effect{CRUSHING_BLOW_EFFECT};

// Reckless Charge - self-damage
const reckless_charge_mods = [_]effects.Modifier{.{
    .effect_type = .damage_add,
    .value = .{ .float = -10.0 }, // Negative = self damage (conceptually)
}};

const RECKLESS_CHARGE_EFFECT = effects.Effect{
    .name = "Reckless Impact",
    .description = "You take 10 damage",
    .modifiers = &reckless_charge_mods,
    .timing = .on_cast,
    .affects = .self,
    .condition = .always,
    .duration_ms = 0,
    .is_buff = false,
};

const reckless_charge_effects = [_]effects.Effect{RECKLESS_CHARGE_EFFECT};

// Speed Demon - +100% speed
const speed_demon_mods = [_]effects.Modifier{.{
    .effect_type = .move_speed_multiplier,
    .value = .{ .float = 2.0 }, // 100% faster = 2x speed
}};

const SPEED_DEMON_EFFECT = effects.Effect{
    .name = "Speed Demon",
    .description = "Move 100% faster",
    .modifiers = &speed_demon_mods,
    .timing = .while_active,
    .affects = .self,
    .condition = .always,
    .duration_ms = 15000,
    .is_buff = true,
};

const speed_demon_effects = [_]effects.Effect{SPEED_DEMON_EFFECT};

// Pursuit Hunter - +50% damage to moving targets, +30% speed
const pursuit_hunter_mods = [_]effects.Modifier{
    .{
        .effect_type = .move_speed_multiplier,
        .value = .{ .float = 1.30 },
    },
};

const PURSUIT_HUNTER_EFFECT = effects.Effect{
    .name = "Pursuit Hunter",
    .description = "Move 30% faster toward enemies",
    .modifiers = &pursuit_hunter_mods,
    .timing = .while_active,
    .affects = .self,
    .condition = .always,
    .duration_ms = 20000,
    .is_buff = true,
};

// Bonus damage to moving targets
const pursuit_bonus_mods = [_]effects.Modifier{.{
    .effect_type = .damage_multiplier,
    .value = .{ .float = 1.50 },
}};

const PURSUIT_BONUS_EFFECT = effects.Effect{
    .name = "Chase Down",
    .description = "+50% damage to moving targets",
    .modifiers = &pursuit_bonus_mods,
    .timing = .on_hit,
    .affects = .target,
    .condition = .if_target_moving,
    .duration_ms = 0,
    .is_buff = false,
};

const pursuit_hunter_effects = [_]effects.Effect{ PURSUIT_HUNTER_EFFECT, PURSUIT_BONUS_EFFECT };

// Sled Crash - knockdown self and target
const sled_crash_target_mods = [_]effects.Modifier{.{
    .effect_type = .knockdown,
    .value = .{ .int = 1 },
}};

const SLED_CRASH_TARGET_EFFECT = effects.Effect{
    .name = "Sled Crash Knockdown",
    .description = "Target knocked down for 3 seconds",
    .modifiers = &sled_crash_target_mods,
    .timing = .on_hit,
    .affects = .target,
    .condition = .always,
    .duration_ms = 3000,
    .is_buff = false,
};

const sled_crash_self_mods = [_]effects.Modifier{.{
    .effect_type = .knockdown,
    .value = .{ .int = 1 },
}};

const SLED_CRASH_SELF_EFFECT = effects.Effect{
    .name = "Sled Crash Recovery",
    .description = "You are knocked down for 1 second",
    .modifiers = &sled_crash_self_mods,
    .timing = .on_cast,
    .affects = .self,
    .condition = .always,
    .duration_ms = 1000,
    .is_buff = false,
};

const sled_crash_effects = [_]effects.Effect{ SLED_CRASH_TARGET_EFFECT, SLED_CRASH_SELF_EFFECT };

// Second Strike - bonus damage if target was recently hit
const second_strike_mods = [_]effects.Modifier{.{
    .effect_type = .damage_add,
    .value = .{ .float = 12.0 },
}};

const SECOND_STRIKE_EFFECT = effects.Effect{
    .name = "Second Strike",
    .description = "+12 damage if target was hit by you in last 3 seconds",
    .modifiers = &second_strike_mods,
    .timing = .on_hit,
    .affects = .target,
    .condition = .if_target_recently_hit_by_caster,
    .duration_ms = 0,
    .is_buff = false,
};

const second_strike_effects = [_]effects.Effect{SECOND_STRIKE_EFFECT};

// Avalanche - damage increases per foe hit
const avalanche_mods = [_]effects.Modifier{
    .{
        .effect_type = .piercing,
        .value = .{ .int = 1 }, // Hit all in path
    },
    .{
        .effect_type = .damage_increase_per_foe_hit,
        .value = .{ .float = 10.0 }, // +10 damage per foe
    },
    .{
        .effect_type = .immune_to_interrupt,
        .value = .{ .int = 1 }, // Cannot be stopped
    },
};

const AVALANCHE_EFFECT = effects.Effect{
    .name = "Avalanche",
    .description = "Hit all foes in path. +10 damage per foe hit. Cannot be stopped.",
    .modifiers = &avalanche_mods,
    .timing = .on_hit,
    .affects = .target,
    .condition = .always,
    .duration_ms = 0,
    .is_buff = false,
};

const avalanche_effects = [_]effects.Effect{AVALANCHE_EFFECT};

pub const skills = [_]Skill{
    // 1. Gap closer - mobility + damage
    .{
        .name = "Downhill Charge",
        .description = "Throw. Deals 22 damage. Dash toward target before attacking.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 8,
        .damage = 22.0,
        .cast_range = 120.0,
        .activation_time_ms = 750,
        .aftercast_ms = 750,
        .recharge_time_ms = 10000,
        // TODO: Dash toward target before damage
    },

    // 2. Melee burst - highest damage at close range
    .{
        .name = "Ram",
        .description = "Throw. Deals 25 damage at close range.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 10,
        .damage = 28.0,
        .cast_range = 80.0,
        .activation_time_ms = 500,
        .aftercast_ms = 750,
        .recharge_time_ms = 8000,
    },

    // 3. AoE sweep - hits all nearby
    .{
        .name = "Snow Spray",
        .description = "Trick. Deals 10 damage to adjacent foes. Inflicts Numb condition (5 seconds).",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 7,
        .damage = 12.0,
        .cast_range = 100.0,
        .activation_time_ms = 500,
        .aftercast_ms = 750,
        .recharge_time_ms = 6000,
        .aoe_type = .adjacent,
    },

    // 4. Sustained aggression buff
    .{
        .name = "Adrenaline Rush",
        .description = "Stance. (8 seconds.) You deal +50% damage and move 33% faster.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 6,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 15000,
        .cozies = &fire_inside_cozy,
        .effects = &adrenaline_rush_effects,
    },

    // 5. Sliding attack - move while attacking
    .{
        .name = "Drift Strike",
        .description = "Throw. Deals 18 damage. Can be used while moving.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 6,
        .damage = 16.0,
        .cast_range = 110.0,
        .activation_time_ms = 500,
        .aftercast_ms = 750,
        .recharge_time_ms = 5000,
        // TODO: Can move during activation
    },

    // 6. Jump attack - unblockable
    .{
        .name = "Aerial Assault",
        .description = "Throw. Deals 20 damage. Unblockable.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 9,
        .damage = 20.0,
        .cast_range = 130.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 12000,
        .unblockable = true,
    },

    // 7. Debilitating strike - reduces enemy damage
    .{
        .name = "Crushing Blow",
        .description = "Throw. Deals 28 damage. Causes knockdown.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 7,
        .damage = 14.0,
        .cast_range = 100.0,
        .activation_time_ms = 750,
        .aftercast_ms = 750,
        .recharge_time_ms = 10000,
        .chills = &numb_chill,
        .effects = &crushing_blow_effects,
    },

    // 8. Speed boost stance
    .{
        .name = "Sprint",
        .description = "Stance. (10 seconds.) You move 50% faster.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 5,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 12000,
        .cozies = &sledder_sure_footed,
    },

    // 9. TERRAIN: Sled Carve - leave icy trail during charge
    .{
        .name = "Sled Carve",
        .description = "Stance. (6 seconds.) Leave an icy trail as you move. Foes crossing it slip.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 7,
        .cast_range = 0,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 18000,
        .duration_ms = 6000,
        .terrain_effect = types.TerrainEffect.ice(.trail),
    },

    // 10. TERRAIN: Powder Plume - create snow behind target
    .{
        .name = "Powder Plume",
        .description = "Throw. Deals 12 damage. Creates deep powder behind target, cutting off their retreat.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 8,
        .damage = 12.0,
        .cast_range = 140.0,
        .target_type = .enemy,
        .aoe_radius = 60.0,
        .activation_time_ms = 750,
        .aftercast_ms = 750,
        .recharge_time_ms = 14000,
        .terrain_effect = types.TerrainEffect.deepSnow(.circle),
    },

    // 11. WALL BREAKER: Breakthrough - ram through fortifications
    .{
        .name = "Breakthrough",
        .description = "Trick. Deals 18 damage. Destroys walls in area.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 8,
        .damage = 18.0,
        .cast_range = 100.0,
        .target_type = .ground,
        .aoe_type = .area,
        .aoe_radius = 80.0,
        .activation_time_ms = 500,
        .aftercast_ms = 750,
        .recharge_time_ms = 15000,
        .destroys_walls = true,
        .wall_damage_multiplier = 2.5,
    },

    // 12. WALL: Speed Ramp - angled wall for mobility
    .{
        .name = "Speed Ramp",
        .description = "Stance. Build an angled ramp at target location. You gain +25% movement speed for 8 seconds.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 7,
        .target_type = .ground,
        .cast_range = 200.0, // Increased for ground targeting
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 20000,
        .duration_ms = 8000,
        .creates_wall = true,
        .wall_length = 110.0, // Increased from 55 for better ramp
        .wall_height = 18.0, // Lower than normal walls
        .wall_thickness = 25.0,
        .wall_distance_from_caster = 30.0, // Legacy field (unused with ground targeting)
        .cozies = &sledder_sure_footed, // Speed boost
        // TODO: Make wall "ramp-shaped" instead of vertical
    },

    // 13. Hit and Run - attack while moving
    .{
        .name = "Hit and Run",
        .description = "Throw. Deals 15 damage. Gain +25% speed for 3 seconds.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 5,
        .damage = 15.0,
        .cast_range = 120.0,
        .activation_time_ms = 500,
        .aftercast_ms = 500,
        .recharge_time_ms = 6000,
        .cozies = &sledder_sure_footed,
    },

    // 14. Wipeout - AoE knockdown
    .{
        .name = "Wipeout",
        .description = "Trick. Deals 12 damage to adjacent foes. Inflicts Slippery (4 seconds).",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 8,
        .damage = 12.0,
        .cast_range = 80.0,
        .aoe_type = .adjacent,
        .aoe_radius = 100.0,
        .activation_time_ms = 500,
        .aftercast_ms = 750,
        .recharge_time_ms = 12000,
        .chills = &sledder_slippery,
    },

    // 15. Reckless Charge - damage but take damage
    .{
        .name = "Reckless Charge",
        .description = "Throw. Deals 30 damage. You take 10 damage.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 7,
        .damage = 30.0,
        .cast_range = 100.0,
        .activation_time_ms = 750,
        .aftercast_ms = 750,
        .recharge_time_ms = 10000,
        .effects = &reckless_charge_effects,
    },

    // 16. Second Strike - follow-up attack
    .{
        .name = "Second Strike",
        .description = "Throw. Deals 18 damage. +12 damage if target was hit by you in the last 3 seconds.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 5,
        .damage = 18.0,
        .cast_range = 110.0,
        .activation_time_ms = 500,
        .aftercast_ms = 750,
        .recharge_time_ms = 5000,
        .effects = &second_strike_effects,
    },

    // ========================================================================
    // SLEDDER AP SKILLS (4 AP skills for 20% of 20 total)
    // ========================================================================

    // AP 1: Avalanche - devastating charge
    .{
        .name = "Avalanche",
        .description = "[AP] Trick. Charge forward, dealing 25 damage to all foes in your path. Cannot be stopped. +10 damage per foe hit.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 15,
        .damage = 25.0,
        .cast_range = 200.0,
        .activation_time_ms = 500,
        .aftercast_ms = 750,
        .recharge_time_ms = 40000,
        .is_ap = true,
        .effects = &avalanche_effects,
    },

    // AP 2: Speed Demon - extreme mobility
    .{
        .name = "Speed Demon",
        .description = "[AP] Stance. (15 seconds.) Move 100% faster. Deal +5 damage per 50 units moved this stance.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 10,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 45000,
        .duration_ms = 15000,
        .is_ap = true,
        .effects = &speed_demon_effects,
    },

    // AP 3: Pursuit Hunter - anti-escape
    .{
        .name = "Pursuit Hunter",
        .description = "[AP] Stance. (20 seconds.) Deal +50% damage to moving targets. Move 30% faster toward enemies.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 10,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 35000,
        .duration_ms = 20000,
        .cozies = &sledder_fire,
        .is_ap = true,
        .effects = &pursuit_hunter_effects,
    },

    // AP 4: Sled Crash - massive melee hit
    .{
        .name = "Sled Crash",
        .description = "[AP] Throw. Close range only. Deals 50 damage. Knocks down target for 3 seconds. You are knocked down for 1 second.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 15,
        .damage = 50.0,
        .cast_range = 80.0,
        .activation_time_ms = 750,
        .aftercast_ms = 1000, // Self knockdown
        .recharge_time_ms = 30000,
        .is_ap = true,
        .effects = &sled_crash_effects,
    },
};
