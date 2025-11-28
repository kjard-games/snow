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
    .name = "Ground Pound",
    .description = "Knockdown for 3 seconds",
    .modifiers = &earthquake_mods,
    .timing = .on_hit,
    .affects = .foes_near_target,
    .condition = .always,
    .duration_ms = 3000,
    .is_buff = false,
};

const earthquake_effects = [_]effects.Effect{EARTHQUAKE_EFFECT};

// Challenge - taunt effect, forces foe to target you
// This skill uses behavior: .taunt instead of modifiers - it's a whole mechanic
const challenge_mods = [_]effects.Modifier{.{
    .effect_type = .armor_add, // Placeholder - actual behavior is in skill.behavior
    .value = .{ .float = 0.0 },
}};

const CHALLENGE_EFFECT = effects.Effect{
    .name = "Challenge",
    .description = "Target must attack you",
    .modifiers = &challenge_mods,
    .timing = .while_active,
    .affects = .target,
    .condition = .always,
    .duration_ms = 5000,
    .is_buff = false,
};

const challenge_effects = [_]effects.Effect{CHALLENGE_EFFECT};

// Behavior: Force nearby enemies to target self (taunt)
const CHALLENGE_BEHAVIOR = types.Behavior{
    .trigger = .on_enemy_choose_target,
    .response = .force_target_self,
    .target = .foes_in_earshot,
    .duration_ms = 5000,
};

// Guardian Angel - redirect damage from ally to self
// This skill uses behavior: .damage_redirect instead of modifiers - it's a whole mechanic
const guardian_angel_mods = [_]effects.Modifier{.{
    .effect_type = .armor_add, // Placeholder - actual behavior is in skill.behavior
    .value = .{ .float = 0.0 },
}};

const GUARDIAN_ANGEL_EFFECT = effects.Effect{
    .name = "Guardian Angel",
    .description = "All damage target would take hits you instead",
    .modifiers = &guardian_angel_mods,
    .timing = .while_active,
    .affects = .target,
    .condition = .always,
    .duration_ms = 15000,
    .is_buff = true,
};

const guardian_angel_effects = [_]effects.Effect{GUARDIAN_ANGEL_EFFECT};

// Behavior: Redirect damage from linked ally to self
const GUARDIAN_ANGEL_BEHAVIOR = types.Behavior{
    .trigger = .on_ally_take_damage,
    .response = .redirect_to_self,
    .target = .target, // The ally you cast this on
    .duration_ms = 15000,
};

// ============================================================================
// SHOVELER SKILLS 17-20 + AP 5 EFFECT DEFINITIONS
// ============================================================================

// Snow Blanket - damage cap at 20 per hit
// Uses behavior to intercept damage and cap it
const SNOW_BLANKET_BEHAVIOR = types.Behavior{
    .trigger = .on_ally_take_damage,
    .response = .prevent, // Prevent excess damage (combat system checks cap)
    .target = .target, // The ally you cast on
    .duration_ms = 10000,
};

const snow_blanket_mods = [_]effects.Modifier{.{
    .effect_type = .armor_add, // Marker effect - actual cap is in behavior
    .value = .{ .float = 0.0 },
}};

const SNOW_BLANKET_EFFECT = effects.Effect{
    .name = "Snow Blanket",
    .description = "Cannot lose more than 20 Warmth per attack",
    .modifiers = &snow_blanket_mods,
    .timing = .while_active,
    .affects = .target,
    .condition = .always,
    .duration_ms = 10000,
    .is_buff = true,
};

const snow_blanket_effects = [_]effects.Effect{SNOW_BLANKET_EFFECT};

// Frostbite Feedback - heal when taking 15+ damage
// Uses behavior to trigger heal on big hit
const FROSTBITE_FEEDBACK_BEHAVIOR = types.Behavior{
    .trigger = .on_ally_take_damage,
    .response = .{ .heal_percent = .{ .percent = 0.0 } }, // Will heal flat 20 (combat checks threshold)
    .target = .target,
    .duration_ms = 10000,
};

const frostbite_feedback_mods = [_]effects.Modifier{.{
    .effect_type = .armor_add, // Marker effect - actual heal is in behavior
    .value = .{ .float = 0.0 },
}};

const FROSTBITE_FEEDBACK_EFFECT = effects.Effect{
    .name = "Frostbite Feedback",
    .description = "Heal 20 Warmth when taking 15+ damage",
    .modifiers = &frostbite_feedback_mods,
    .timing = .while_active,
    .affects = .target,
    .condition = .always,
    .duration_ms = 10000,
    .is_buff = true,
};

const frostbite_feedback_effects = [_]effects.Effect{FROSTBITE_FEEDBACK_EFFECT};

// Snowback - block next attack and heal for blocked damage
const SNOWBACK_BEHAVIOR = types.Behavior{
    .trigger = .on_ally_hit_by_projectile,
    .response = .prevent, // Block the attack
    .target = .target,
    .duration_ms = 10000,
    .max_activations = 1, // Block exactly one attack
};

const snowback_mods = [_]effects.Modifier{.{
    .effect_type = .block_next_attack,
    .value = .{ .float = 1.0 },
}};

const SNOWBACK_EFFECT = effects.Effect{
    .name = "Snowback",
    .description = "Block next attack. Heal for blocked damage.",
    .modifiers = &snowback_mods,
    .timing = .while_active,
    .affects = .target,
    .condition = .always,
    .duration_ms = 10000,
    .is_buff = true,
};

const snowback_effects = [_]effects.Effect{SNOWBACK_EFFECT};

// Soak Wall - wall with HP that absorbs damage for allies behind
const soak_wall_ally_mods = [_]effects.Modifier{.{
    .effect_type = .armor_multiplier,
    .value = .{ .float = 2.0 }, // 50% less damage = 2x armor
}};

const SOAK_WALL_EFFECT = effects.Effect{
    .name = "Behind Soak Wall",
    .description = "Take 50% less damage while behind the wall",
    .modifiers = &soak_wall_ally_mods,
    .timing = .while_active,
    .affects = .allies_near_target, // Allies near the wall
    .condition = .if_behind_wall,
    .duration_ms = 20000, // Wall duration
    .is_buff = true,
};

const soak_wall_effects = [_]effects.Effect{SOAK_WALL_EFFECT};

// Igloo Effect - party-wide damage reduction, energy cost per hit
const igloo_effect_mods = [_]effects.Modifier{.{
    .effect_type = .armor_multiplier,
    .value = .{ .float = 1.67 }, // 40% less damage = 1/0.6
}};

const IGLOO_EFFECT = effects.Effect{
    .name = "Igloo Effect",
    .description = "Take 40% less damage. Caster loses 5 energy per hit.",
    .modifiers = &igloo_effect_mods,
    .timing = .while_active,
    .affects = .allies_in_earshot,
    .condition = .always,
    .duration_ms = 15000,
    .is_buff = true,
};

const igloo_effect_effects = [_]effects.Effect{IGLOO_EFFECT};

// Igloo Effect behavior - drain caster energy on ally damage
const IGLOO_EFFECT_BEHAVIOR = types.Behavior{
    .trigger = .on_ally_take_damage,
    .response = .{
        .deal_damage = .{
            .amount = 0.0, // No damage, but will trigger energy drain
            .to = .self,
        },
    },
    .target = .allies_in_earshot,
    .duration_ms = 15000,
};

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
        .description = "Trick. Build a snow wall at target location. Walls block direct projectiles.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 7,
        .target_type = .ground,
        .cast_range = 200.0, // Increased for ground targeting
        .activation_time_ms = 1250, // Requires commitment - can be interrupted
        .aftercast_ms = 500,
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
        .behavior = &CHALLENGE_BEHAVIOR,
        .effects = &challenge_effects,
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
        .description = "Trick. Build a wall that also grants adjacent allies +20% armor.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 8,
        .target_type = .ground,
        .cast_range = 150.0,
        .activation_time_ms = 1500, // Requires commitment - can be interrupted
        .aftercast_ms = 500,
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
        .behavior = &GUARDIAN_ANGEL_BEHAVIOR,
        .effects = &guardian_angel_effects,
    },

    // AP 4: Earthquake - massive AoE knockdown
    .{
        .name = "Ground Pound",
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

    // ========================================================================
    // SHOVELER SKILLS 17-20 + AP 5 (Monk Protection analog - Pre-prot, Spirit Bond)
    // ========================================================================
    // Theme: Damage prevention, protective spirits, pre-emptive defense

    // 17. Snow Blanket - damage cap (like Protective Spirit)
    .{
        .name = "Snow Blanket",
        .description = "Gesture. Target ally cannot lose more than 20 Warmth from a single attack for 10 seconds.",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 8,
        .target_type = .ally,
        .cast_range = 180.0,
        .activation_time_ms = 500,
        .aftercast_ms = 750,
        .recharge_time_ms = 20000,
        .duration_ms = 10000,
        .behavior = &SNOW_BLANKET_BEHAVIOR,
        .effects = &snow_blanket_effects,
    },

    // 18. Frostbite Feedback - heal when taking big hit (like Spirit Bond)
    .{
        .name = "Frostbite Feedback",
        .description = "Gesture. For 10 seconds, whenever target ally takes 15+ damage, they heal 20 Warmth.",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 7,
        .target_type = .ally,
        .cast_range = 180.0,
        .activation_time_ms = 750,
        .aftercast_ms = 750,
        .recharge_time_ms = 15000,
        .duration_ms = 10000,
        .behavior = &FROSTBITE_FEEDBACK_BEHAVIOR,
        .effects = &frostbite_feedback_effects,
    },

    // 19. Snowback - heal equal to damage prevented (like RoF)
    .{
        .name = "Snowback",
        .description = "Gesture. Target ally blocks the next attack. Heal them for the damage that would have been dealt.",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 6,
        .target_type = .ally,
        .cast_range = 180.0,
        .activation_time_ms = 250,
        .aftercast_ms = 500,
        .recharge_time_ms = 4000,
        .behavior = &SNOWBACK_BEHAVIOR,
        .effects = &snowback_effects,
    },

    // 20. Soak Wall - damage reduction bubble (like Shield of Absorption)
    .{
        .name = "Soak Wall",
        .description = "Trick. Build a wall that absorbs 100 damage before breaking. Allies behind take 50% less damage.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 10,
        .target_type = .ground,
        .cast_range = 150.0,
        .activation_time_ms = 1500, // Requires commitment - can be interrupted
        .aftercast_ms = 500,
        .recharge_time_ms = 25000,
        .creates_wall = true,
        .wall_length = 80.0,
        .wall_height = 35.0,
        .wall_thickness = 20.0,
        .wall_distance_from_caster = 40.0,
        .effects = &soak_wall_effects,
    },

    // AP 5: Igloo Effect - party-wide damage prevention (like Shelter)
    .{
        .name = "Igloo Effect",
        .description = "[AP] Call. For 15 seconds, all allies take 40% less damage. Each time an ally would take damage, lose 5 energy instead.",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 15,
        .target_type = .ally,
        .aoe_type = .area,
        .aoe_radius = 250.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 60000,
        .duration_ms = 15000,
        .is_ap = true,
        .behavior = &IGLOO_EFFECT_BEHAVIOR,
        .effects = &igloo_effect_effects,
    },
};
