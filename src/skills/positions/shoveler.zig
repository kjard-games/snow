const types = @import("../types.zig");
const Skill = types.Skill;
const effects = @import("../../effects.zig");

// ============================================================================
// SHOVELER SKILLS - Tank/Defender (100-160 range)
// ============================================================================
// Synergizes with: Defensive buffs, health, fortifications
// Counterplay: Sustained damage, armor penetration, ignore and focus others

const bundled_up_cozy = [_]types.CozyEffect{.{
    .cozy = .bundled_up,
    .duration_ms = 10000,
    .stack_intensity = 1,
}};

const frosty_fortitude_cozy = [_]types.CozyEffect{.{
    .cozy = .frosty_fortitude,
    .duration_ms = 15000,
    .stack_intensity = 1,
}};

const snowball_shield_cozy = [_]types.CozyEffect{.{
    .cozy = .snowball_shield,
    .duration_ms = 8000,
    .stack_intensity = 1,
}};

const shoveler_hot_cocoa = [_]types.CozyEffect{.{
    .cozy = .hot_cocoa,
    .duration_ms = 10000,
    .stack_intensity = 1,
}};

const shoveler_numb = [_]types.ChillEffect{.{
    .chill = .numb,
    .duration_ms = 6000,
    .stack_intensity = 1,
}};

// ============================================================================
// EFFECT DEFINITIONS
// ============================================================================

// Dig In - +50 padding, immune to knockdown/movement
const dig_in_mods = [_]effects.Modifier{
    .{
        .effect_type = .armor_add,
        .value = .{ .float = 50.0 },
    },
    .{
        .effect_type = .immune_to_knockdown,
        .value = .{ .int = 1 },
    },
};

const DIG_IN_EFFECT = effects.Effect{
    .name = "Dig In",
    .description = "+50 padding and immune to knockdown",
    .modifiers = &dig_in_mods,
    .timing = .while_active,
    .affects = .self,
    .condition = .always,
    .duration_ms = 12000,
    .is_buff = true,
};

const dig_in_effects = [_]effects.Effect{DIG_IN_EFFECT};

// Fortify - 50% less damage
const fortify_mods = [_]effects.Modifier{.{
    .effect_type = .damage_multiplier,
    .value = .{ .float = 0.50 }, // Take 50% less = multiply incoming by 0.5
}};

const FORTIFY_EFFECT = effects.Effect{
    .name = "Fortify",
    .description = "Take 50% less damage",
    .modifiers = &fortify_mods,
    .timing = .while_active,
    .affects = .self,
    .condition = .always,
    .duration_ms = 15000,
    .is_buff = true,
};

const fortify_effects = [_]effects.Effect{FORTIFY_EFFECT};

// Retribution - reflect 25% damage
const retribution_mods = [_]effects.Modifier{.{
    .effect_type = .reflect_damage_percent,
    .value = .{ .float = 0.25 },
}};

const RETRIBUTION_EFFECT = effects.Effect{
    .name = "Retribution",
    .description = "Reflect 25% of damage back to attackers",
    .modifiers = &retribution_mods,
    .timing = .on_take_damage,
    .affects = .source_of_damage,
    .condition = .always,
    .duration_ms = 8000,
    .is_buff = true,
};

const retribution_effects = [_]effects.Effect{RETRIBUTION_EFFECT};

// Stand Your Ground - immobile, +30% damage, 50% less damage taken
const stand_your_ground_mods = [_]effects.Modifier{
    .{
        .effect_type = .damage_multiplier,
        .value = .{ .float = 1.30 }, // Deal 30% more damage
    },
    .{
        .effect_type = .move_speed_multiplier,
        .value = .{ .float = 0.0 }, // Cannot move
    },
    .{
        .effect_type = .armor_multiplier,
        .value = .{ .float = 1.50 }, // 50% more effective armor = 50% less damage
    },
};

const STAND_YOUR_GROUND_EFFECT = effects.Effect{
    .name = "Stand Your Ground",
    .description = "Cannot move, +30% damage, 50% less damage taken",
    .modifiers = &stand_your_ground_mods,
    .timing = .while_active,
    .affects = .self,
    .condition = .always,
    .duration_ms = 10000,
    .is_buff = true,
};

const stand_your_ground_effects = [_]effects.Effect{STAND_YOUR_GROUND_EFFECT};

// Cover Fire - allies take 25% less damage
const cover_fire_mods = [_]effects.Modifier{.{
    .effect_type = .armor_multiplier,
    .value = .{ .float = 1.25 }, // 25% more effective armor
}};

const COVER_FIRE_EFFECT = effects.Effect{
    .name = "Cover Fire",
    .description = "Allies near you take 25% less damage",
    .modifiers = &cover_fire_mods,
    .timing = .while_active,
    .affects = .allies_in_earshot,
    .condition = .always,
    .duration_ms = 8000,
    .is_buff = true,
};

const cover_fire_effects = [_]effects.Effect{COVER_FIRE_EFFECT};

// Entrench - 60% less damage, 50% slower
const entrench_mods = [_]effects.Modifier{
    .{
        .effect_type = .armor_multiplier,
        .value = .{ .float = 2.5 }, // 60% less damage = 2.5x armor effectiveness
    },
    .{
        .effect_type = .move_speed_multiplier,
        .value = .{ .float = 0.50 },
    },
};

const ENTRENCH_EFFECT = effects.Effect{
    .name = "Entrench",
    .description = "Take 60% less damage, move 50% slower",
    .modifiers = &entrench_mods,
    .timing = .while_active,
    .affects = .self,
    .condition = .always,
    .duration_ms = 15000,
    .is_buff = true,
};

const entrench_effects = [_]effects.Effect{ENTRENCH_EFFECT};

// Immovable Object - cannot die, cannot move, 75% less damage
const immovable_object_mods = [_]effects.Modifier{
    .{
        .effect_type = .armor_multiplier,
        .value = .{ .float = 4.0 }, // 75% less damage = 4x armor
    },
    .{
        .effect_type = .move_speed_multiplier,
        .value = .{ .float = 0.0 }, // Cannot move
    },
    .{
        .effect_type = .immune_to_knockdown,
        .value = .{ .int = 1 },
    },
};

const IMMOVABLE_OBJECT_EFFECT = effects.Effect{
    .name = "Immovable Object",
    .description = "Cannot die, cannot move, 75% less damage",
    .modifiers = &immovable_object_mods,
    .timing = .while_active,
    .affects = .self,
    .condition = .always,
    .duration_ms = 8000,
    .is_buff = true,
};

const immovable_object_effects = [_]effects.Effect{IMMOVABLE_OBJECT_EFFECT};

// Earthquake - AoE knockdown
const earthquake_mods = [_]effects.Modifier{.{
    .effect_type = .knockdown,
    .value = .{ .int = 1 },
}};

const EARTHQUAKE_EFFECT = effects.Effect{
    .name = "Earthquake",
    .description = "Knockdown for 3 seconds",
    .modifiers = &earthquake_mods,
    .timing = .on_hit,
    .affects = .foes_near_target,
    .condition = .always,
    .duration_ms = 3000,
    .is_buff = false,
};

const earthquake_effects = [_]effects.Effect{EARTHQUAKE_EFFECT};

pub const skills = [_]Skill{
    // 1. Armor stance - damage reduction
    .{
        .name = "Dig In",
        .description = "Stance. (12 seconds.) You have +50 padding and cannot be moved.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 6,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 20000,
        .cozies = &bundled_up_cozy,
        .effects = &dig_in_effects,
    },

    // 2. Health boost
    .{
        .name = "Fortify",
        .description = "Stance. (15 seconds.) You take 50% less damage.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 8,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 25000,
        .cozies = &frosty_fortitude_cozy,
        .effects = &fortify_effects,
    },

    // 3. Build snow wall
    .{
        .name = "Snow Wall",
        .description = "Stance. Build a snow wall at target location. Walls block direct projectiles.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 7,
        .target_type = .ground,
        .cast_range = 200.0, // Increased for ground targeting
        .activation_time_ms = 0,
        .aftercast_ms = 750,
        .recharge_time_ms = 12000,
        .creates_wall = true,
        .wall_length = 120.0, // Increased from 60 for better coverage
        .wall_height = 30.0,
        .wall_thickness = 20.0,
        .wall_distance_from_caster = 40.0, // Legacy field (unused with ground targeting)
    },

    // 4. Counter attack - damage when attacked
    .{
        .name = "Retribution",
        .description = "Stance. (8 seconds.) Reflects 25% of damage back to attackers.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 5,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 12000,
        .duration_ms = 8000,
        .effects = &retribution_effects,
    },

    // 5. Taunt - force enemies to target you
    .{
        .name = "Challenge",
        .description = "Shout. Target foe must attack you for 5 seconds.",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 6,
        .cast_range = 200.0,
        .aoe_type = .area,
        .aoe_radius = 200.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 20000,
        // TODO: Taunt mechanic
    },

    // 6. Moderate damage throw
    .{
        .name = "Shovel Toss",
        .description = "Throw. Deals 12 damage. Interrupts target.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 5,
        .damage = 14.0,
        .cast_range = 140.0,
        .activation_time_ms = 750,
        .aftercast_ms = 750,
        .recharge_time_ms = 5000,
    },

    // 7. Build ice wall
    .{
        .name = "Ice Wall",
        .description = "Trick. Build a tall ice wall at target location. Walls block direct projectiles and slow climbers.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 10,
        .cast_range = 300.0, // Increased for ground targeting - long range wall placement
        .target_type = .ground,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 20000,
        .creates_wall = true,
        .wall_length = 150.0, // Increased from 80 - massive ice wall
        .wall_height = 40.0,
        .wall_thickness = 25.0,
        .wall_distance_from_caster = 50.0, // Legacy field (unused with ground targeting)
        .terrain_effect = types.TerrainEffect.ice(.circle), // Also creates icy ground
        .aoe_radius = 30.0,
    },

    // 8. Self-heal
    .{
        .name = "Second Wind",
        .description = "Gesture. Heals for 40 Health.",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 0,
        .healing = 40.0,
        .target_type = .self,
        .activation_time_ms = 2000,
        .aftercast_ms = 750,
        .recharge_time_ms = 20000,
    },

    // 9. TERRAIN: Snow Pile - create defensive mound
    .{
        .name = "Snow Pile",
        .description = "Gesture. Shovel snow into a tall mound. Provides cover for allies.",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 8,
        .cast_range = 160.0,
        .target_type = .ground,
        .aoe_radius = 70.0,
        .activation_time_ms = 2000,
        .aftercast_ms = 750,
        .recharge_time_ms = 25000,
        .terrain_effect = types.TerrainEffect.deepSnow(.circle),
    },

    // 10. Heavy Swing - high damage slow attack
    .{
        .name = "Heavy Swing",
        .description = "Throw. Deals 22 damage. Inflicts Numb (6 seconds).",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 8,
        .damage = 22.0,
        .cast_range = 130.0,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 10000,
        .chills = &shoveler_numb,
    },

    // 11. Stand Your Ground - immobile but powerful
    .{
        .name = "Stand Your Ground",
        .description = "Stance. (10 seconds.) Cannot move. Take 50% less damage. Deal +30% damage.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 6,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 25000,
        .duration_ms = 10000,
        .effects = &stand_your_ground_effects,
    },

    // 12. Protective Barrier - ally protection
    .{
        .name = "Protective Barrier",
        .description = "Stance. Build a wall that also grants adjacent allies +20% armor.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 8,
        .target_type = .ground,
        .cast_range = 150.0,
        .activation_time_ms = 0,
        .aftercast_ms = 750,
        .recharge_time_ms = 18000,
        .creates_wall = true,
        .wall_length = 100.0,
        .wall_height = 35.0,
        .wall_thickness = 25.0,
        .wall_distance_from_caster = 40.0,
    },

    // 13. Shovel Bash - interrupt
    .{
        .name = "Shovel Bash",
        .description = "Throw. Deals 15 damage. Interrupts target.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 6,
        .damage = 15.0,
        .cast_range = 120.0,
        .activation_time_ms = 500,
        .aftercast_ms = 750,
        .recharge_time_ms = 8000,
        .interrupts = true,
    },

    // 14. Entrench - massive defense
    .{
        .name = "Entrench",
        .description = "Stance. (15 seconds.) Take 60% less damage. Move 50% slower.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 8,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 30000,
        .duration_ms = 15000,
        .cozies = &frosty_fortitude_cozy,
        .effects = &entrench_effects,
    },

    // 15. Cover Fire - protect allies
    .{
        .name = "Cover Fire",
        .description = "Call. (8 seconds.) Allies near you take 25% less damage.",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 10,
        .target_type = .ally,
        .aoe_type = .area,
        .aoe_radius = 150.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 25000,
        .duration_ms = 8000,
        .effects = &cover_fire_effects,
    },

    // 16. Regeneration - healing over time
    .{
        .name = "Regeneration",
        .description = "Gesture. Heal 40 Warmth over 10 seconds.",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 0,
        .target_type = .self,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 20000,
        .cozies = &shoveler_hot_cocoa,
    },

    // ========================================================================
    // SHOVELER AP SKILLS (4 AP skills for 20% of 20 total)
    // ========================================================================

    // AP 1: Fortress - create massive wall structure
    .{
        .name = "Fortress",
        .description = "[AP] Trick. Build a fortress of walls around target location. Creates 4 connected walls forming a square.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 20,
        .target_type = .ground,
        .cast_range = 150.0,
        .activation_time_ms = 3000,
        .aftercast_ms = 750,
        .recharge_time_ms = 60000,
        .creates_wall = true,
        .wall_length = 150.0,
        .wall_height = 40.0,
        .wall_thickness = 25.0,
        .wall_distance_from_caster = 60.0,
        .is_ap = true,
    },

    // AP 2: Immovable Object - cannot be killed while active
    .{
        .name = "Immovable Object",
        .description = "[AP] Stance. (8 seconds.) Cannot die (minimum 1 Warmth). Cannot move. Take 75% less damage.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 15,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 90000,
        .duration_ms = 8000,
        .is_ap = true,
        .effects = &immovable_object_effects,
    },

    // AP 3: Guardian Angel - protect ally completely
    .{
        .name = "Guardian Angel",
        .description = "[AP] Gesture. Link with target ally for 15 seconds. All damage they would take hits you instead.",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 10,
        .target_type = .ally,
        .cast_range = 200.0,
        .activation_time_ms = 500,
        .aftercast_ms = 500,
        .recharge_time_ms = 45000,
        .duration_ms = 15000,
        .is_ap = true,
    },

    // AP 4: Earthquake - massive AoE knockdown
    .{
        .name = "Earthquake",
        .description = "[AP] Trick. All enemies in area take 20 damage and are knocked down for 3 seconds.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 18,
        .damage = 20.0,
        .target_type = .ground,
        .cast_range = 150.0,
        .aoe_type = .area,
        .aoe_radius = 200.0,
        .activation_time_ms = 2000,
        .aftercast_ms = 1000,
        .recharge_time_ms = 50000,
        .is_ap = true,
        .effects = &earthquake_effects,
    },
};
