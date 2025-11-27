const types = @import("../types.zig");
const Skill = types.Skill;
const effects = @import("../../effects.zig");

// ============================================================================
// FIELDER SKILLS - Balanced generalist (150-220 range)
// ============================================================================
// Synergizes with: Variety bonuses, adaptability, versatile skill types
// Counterplay: Specialization beats generalization

const slippery_chill = [_]types.ChillEffect{.{
    .chill = .slippery,
    .duration_ms = 4000,
    .stack_intensity = 1,
}};

const sure_footed_cozy = [_]types.CozyEffect{.{
    .cozy = .sure_footed,
    .duration_ms = 6000,
    .stack_intensity = 1,
}};

const fielder_bundled = [_]types.CozyEffect{.{
    .cozy = .bundled_up,
    .duration_ms = 8000,
    .stack_intensity = 1,
}};

const fielder_soggy = [_]types.ChillEffect{.{
    .chill = .soggy,
    .duration_ms = 5000,
    .stack_intensity = 1,
}};

// ============================================================================
// EFFECT DEFINITIONS
// ============================================================================

// Dive Roll - evasion effect
const dive_roll_mods = [_]effects.Modifier{
    .{
        .effect_type = .evasion_percent,
        .value = .{ .float = 0.75 }, // 75% evade chance
    },
    .{
        .effect_type = .move_speed_multiplier,
        .value = .{ .float = 1.25 }, // +25% speed
    },
};

const DIVE_ROLL_EFFECT = effects.Effect{
    .name = "Dive Roll",
    .description = "Evading attacks and moving faster",
    .modifiers = &dive_roll_mods,
    .timing = .while_active,
    .affects = .self,
    .condition = .always,
    .duration_ms = 6000,
    .is_buff = true,
};

const dive_roll_effects = [_]effects.Effect{DIVE_ROLL_EFFECT};

// Point Blank - +10 damage if within melee range
const point_blank_bonus_mods = [_]effects.Modifier{.{
    .effect_type = .damage_add,
    .value = .{ .float = 10.0 },
}};

const POINT_BLANK_BONUS = effects.Effect{
    .name = "Point Blank",
    .description = "+10 damage at close range",
    .modifiers = &point_blank_bonus_mods,
    .timing = .on_hit,
    .affects = .target,
    .condition = .if_near_foe, // Close range check
    .duration_ms = 0,
    .is_buff = false,
};

const point_blank_effects = [_]effects.Effect{POINT_BLANK_BONUS};

// Shake It Off - remove one chill
const shake_it_off_mods = [_]effects.Modifier{.{
    .effect_type = .remove_random_chill,
    .value = .{ .int = 1 },
}};

const SHAKE_IT_OFF_EFFECT = effects.Effect{
    .name = "Shake It Off",
    .description = "Remove one chill",
    .modifiers = &shake_it_off_mods,
    .timing = .on_cast,
    .affects = .self,
    .condition = .always,
    .duration_ms = 0,
    .is_buff = true,
};

const shake_it_off_effects = [_]effects.Effect{SHAKE_IT_OFF_EFFECT};

// Rally - +5 damage to allies
const rally_mods = [_]effects.Modifier{.{
    .effect_type = .damage_add,
    .value = .{ .float = 5.0 },
}};

const RALLY_EFFECT = effects.Effect{
    .name = "Rally",
    .description = "+5 damage to allies",
    .modifiers = &rally_mods,
    .timing = .while_active,
    .affects = .allies_in_earshot,
    .condition = .always,
    .duration_ms = 10000,
    .is_buff = true,
};

const rally_effects = [_]effects.Effect{RALLY_EFFECT};

// Team Player - +20% damage, +15% armor
const team_player_mods = [_]effects.Modifier{
    .{
        .effect_type = .damage_multiplier,
        .value = .{ .float = 1.20 },
    },
    .{
        .effect_type = .armor_multiplier,
        .value = .{ .float = 1.15 },
    },
};

const TEAM_PLAYER_EFFECT = effects.Effect{
    .name = "Team Player",
    .description = "+20% damage and +15% armor",
    .modifiers = &team_player_mods,
    .timing = .while_active,
    .affects = .target, // Single ally target
    .condition = .always,
    .duration_ms = 10000,
    .is_buff = true,
};

const team_player_effects = [_]effects.Effect{TEAM_PLAYER_EFFECT};

// Defensive Slide - 30% less damage, 20% faster
const defensive_slide_mods = [_]effects.Modifier{
    .{
        .effect_type = .damage_multiplier,
        .value = .{ .float = 0.70 }, // Take 30% less damage
    },
    .{
        .effect_type = .move_speed_multiplier,
        .value = .{ .float = 1.20 },
    },
};

const DEFENSIVE_SLIDE_EFFECT = effects.Effect{
    .name = "Defensive Slide",
    .description = "Take 30% less damage, move 20% faster",
    .modifiers = &defensive_slide_mods,
    .timing = .while_active,
    .affects = .self,
    .condition = .always,
    .duration_ms = 6000,
    .is_buff = true,
};

const defensive_slide_effects = [_]effects.Effect{DEFENSIVE_SLIDE_EFFECT};

// MVP - +30% everything
const mvp_mods = [_]effects.Modifier{
    .{
        .effect_type = .damage_multiplier,
        .value = .{ .float = 1.30 },
    },
    .{
        .effect_type = .armor_multiplier,
        .value = .{ .float = 1.30 },
    },
    .{
        .effect_type = .move_speed_multiplier,
        .value = .{ .float = 1.30 },
    },
    .{
        .effect_type = .energy_regen_multiplier,
        .value = .{ .float = 1.30 },
    },
};

const MVP_EFFECT = effects.Effect{
    .name = "MVP",
    .description = "+30% damage, armor, speed, energy regen",
    .modifiers = &mvp_mods,
    .timing = .while_active,
    .affects = .self,
    .condition = .always,
    .duration_ms = 15000,
    .is_buff = true,
};

const mvp_effects = [_]effects.Effect{MVP_EFFECT};

// Utility Belt - -30% effectiveness
const utility_belt_mods = [_]effects.Modifier{.{
    .effect_type = .damage_multiplier,
    .value = .{ .float = 0.70 },
}};

const UTILITY_BELT_EFFECT = effects.Effect{
    .name = "Utility Belt",
    .description = "Skills at -30% effectiveness",
    .modifiers = &utility_belt_mods,
    .timing = .while_active,
    .affects = .self,
    .condition = .always,
    .duration_ms = 20000,
    .is_buff = true,
};

const utility_belt_effects = [_]effects.Effect{UTILITY_BELT_EFFECT};

// Center Field - allies +20% damage, enemies take +20% damage
const center_field_ally_mods = [_]effects.Modifier{.{
    .effect_type = .damage_multiplier,
    .value = .{ .float = 1.20 },
}};

const CENTER_FIELD_ALLY_EFFECT = effects.Effect{
    .name = "Center Field Boost",
    .description = "Allies deal +20% damage",
    .modifiers = &center_field_ally_mods,
    .timing = .while_active,
    .affects = .allies_near_target,
    .condition = .always,
    .duration_ms = 15000,
    .is_buff = true,
};

const center_field_enemy_mods = [_]effects.Modifier{.{
    .effect_type = .damage_multiplier,
    .value = .{ .float = 1.20 }, // Take 20% more damage
}};

const CENTER_FIELD_ENEMY_EFFECT = effects.Effect{
    .name = "Center Field Debuff",
    .description = "Enemies take +20% damage",
    .modifiers = &center_field_enemy_mods,
    .timing = .while_active,
    .affects = .foes_near_target,
    .condition = .always,
    .duration_ms = 15000,
    .is_buff = false,
};

const center_field_effects = [_]effects.Effect{ CENTER_FIELD_ALLY_EFFECT, CENTER_FIELD_ENEMY_EFFECT };

// Catch and Return - block projectile and throw back
// This skill uses behavior: .projectile_return instead of modifiers - it's a whole mechanic
const catch_and_return_mods = [_]effects.Modifier{.{
    .effect_type = .armor_add, // Placeholder - actual behavior is in skill.behavior
    .value = .{ .float = 0.0 },
}};

const CATCH_AND_RETURN_EFFECT = effects.Effect{
    .name = "Catch and Return",
    .description = "Block next projectile. If blocked, throw it back for 20 damage.",
    .modifiers = &catch_and_return_mods,
    .timing = .while_active,
    .affects = .self,
    .condition = .always,
    .duration_ms = 5000,
    .is_buff = true,
};

const catch_and_return_effects = [_]effects.Effect{CATCH_AND_RETURN_EFFECT};

// Behavior: Block projectile and return it for 20 damage
const CATCH_AND_RETURN_BEHAVIOR = types.Behavior{
    .trigger = .on_hit_by_projectile,
    .response = .{ .deal_damage = .{
        .amount = 20.0,
        .to = .source_of_damage,
    } },
    .max_activations = 1,
    .duration_ms = 5000,
};

// Grand Slam - +10 damage per foe hit
const grand_slam_mods = [_]effects.Modifier{
    .{
        .effect_type = .piercing,
        .value = .{ .int = 1 }, // Hits all in line
    },
    .{
        .effect_type = .damage_increase_per_foe_hit,
        .value = .{ .float = 10.0 }, // +10 damage per foe hit
    },
};

const GRAND_SLAM_EFFECT = effects.Effect{
    .name = "Grand Slam",
    .description = "Hit all foes in line. +10 damage per foe hit (stacks).",
    .modifiers = &grand_slam_mods,
    .timing = .on_hit,
    .affects = .target,
    .condition = .always,
    .duration_ms = 0,
    .is_buff = false,
};

const grand_slam_effects = [_]effects.Effect{GRAND_SLAM_EFFECT};

// ============================================================================
// FIELDER SKILLS 17-20 + AP 5 EFFECT DEFINITIONS
// ============================================================================

// First Throw - self next attack bonus, then ally bonus if it hits
const first_throw_self_mods = [_]effects.Modifier{.{
    .effect_type = .next_attack_damage_add,
    .value = .{ .float = 15.0 },
}};

const FIRST_THROW_SELF_EFFECT = effects.Effect{
    .name = "First Throw",
    .description = "Your next attack deals +15 damage",
    .modifiers = &first_throw_self_mods,
    .timing = .on_cast,
    .affects = .self,
    .condition = .always,
    .duration_ms = 8000, // 8 seconds to use it
    .is_buff = true,
};

const first_throw_ally_mods = [_]effects.Modifier{.{
    .effect_type = .next_attack_damage_add,
    .value = .{ .float = 10.0 },
}};

const FIRST_THROW_ALLY_EFFECT = effects.Effect{
    .name = "First Throw Boost",
    .description = "Your next attack deals +10 damage",
    .modifiers = &first_throw_ally_mods,
    .timing = .on_hit, // Triggered when First Throw hits
    .affects = .allies_in_earshot,
    .condition = .always,
    .duration_ms = 8000,
    .is_buff = true,
};

const first_throw_effects = [_]effects.Effect{ FIRST_THROW_SELF_EFFECT, FIRST_THROW_ALLY_EFFECT };

// Tag Team - ally follow-up attack trigger
// This uses a behavior to trigger ally attack
const TAG_TEAM_BEHAVIOR = types.Behavior{
    .trigger = .on_hit_by_projectile, // Piggyback on hit detection
    .response = .{
        .deal_damage = .{
            .amount = 10.0,
            .to = .target, // Same target as caster
        },
    },
    .target = .allies_near_target, // Nearby ally attacks
    .duration_ms = 0, // Instant
    .max_activations = 1,
};

// Huddle Up - aura buff for allies
const huddle_up_mods = [_]effects.Modifier{
    .{
        .effect_type = .damage_multiplier,
        .value = .{ .float = 1.10 }, // +10% damage
    },
    .{
        .effect_type = .move_speed_multiplier,
        .value = .{ .float = 1.10 }, // +10% speed
    },
};

const HUDDLE_UP_EFFECT = effects.Effect{
    .name = "Huddle Up",
    .description = "Allies deal +10% damage and move 10% faster",
    .modifiers = &huddle_up_mods,
    .timing = .while_active,
    .affects = .allies_in_earshot,
    .condition = .always,
    .duration_ms = 15000,
    .is_buff = true,
};

const huddle_up_effects = [_]effects.Effect{HUDDLE_UP_EFFECT};

// Got Your Back - bonus damage + interrupt if target attacking ally
const got_your_back_bonus_mods = [_]effects.Modifier{.{
    .effect_type = .damage_add,
    .value = .{ .float = 8.0 },
}};

const GOT_YOUR_BACK_BONUS_EFFECT = effects.Effect{
    .name = "Got Your Back",
    .description = "+8 damage if target is attacking an ally",
    .modifiers = &got_your_back_bonus_mods,
    .timing = .on_hit,
    .affects = .target,
    .condition = .if_target_attacking, // Attacking (presumably an ally)
    .duration_ms = 0,
    .is_buff = false,
};

const got_your_back_effects = [_]effects.Effect{GOT_YOUR_BACK_BONUS_EFFECT};

// Final Huddle - ultimate party buff
const final_huddle_mods = [_]effects.Modifier{
    .{
        .effect_type = .damage_multiplier,
        .value = .{ .float = 1.25 }, // +25% damage
    },
    .{
        .effect_type = .move_speed_multiplier,
        .value = .{ .float = 1.25 }, // +25% speed
    },
};

const FINAL_HUDDLE_EFFECT = effects.Effect{
    .name = "Final Huddle",
    .description = "+25% damage and +25% speed",
    .modifiers = &final_huddle_mods,
    .timing = .while_active,
    .affects = .allies_in_earshot,
    .condition = .always,
    .duration_ms = 12000,
    .is_buff = true,
};

const final_huddle_effects = [_]effects.Effect{FINAL_HUDDLE_EFFECT};

pub const skills = [_]Skill{
    // 1. Versatile throw - good at everything
    .{
        .name = "All-Rounder",
        .description = "Throw. Deals 15 damage.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 5,
        .damage = 15.0,
        .cast_range = 180.0,
        .activation_time_ms = 750,
        .aftercast_ms = 750,
        .recharge_time_ms = 5000,
    },

    // 2. Repositioning tool - mobility + utility
    .{
        .name = "Dive Roll",
        .description = "Stance. (6 seconds.) You move 25% faster and evade attacks.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 5,
        .cast_range = 0,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 10000,
        .cozies = &sure_footed_cozy,
        .effects = &dive_roll_effects,
    },

    // 3. Control tool - slows enemies
    .{
        .name = "Trip Up",
        .description = "Throw. Deals 8 damage. Inflicts Slippery condition (4 seconds).",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 6,
        .damage = 8.0,
        .cast_range = 160.0,
        .activation_time_ms = 500,
        .aftercast_ms = 750,
        .recharge_time_ms = 8000,
        .chills = &slippery_chill,
    },

    // 4. Long range option - can play like pitcher
    .{
        .name = "Long Toss",
        .description = "Throw. Deals 13 damage.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 6,
        .damage = 13.0,
        .cast_range = 220.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 6000,
    },

    // 5. Close range option - can play like sledder
    .{
        .name = "Point Blank",
        .description = "Throw. Deals 18 damage. Deals +10 damage if you are within melee range.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 7,
        .damage = 18.0,
        .cast_range = 150.0,
        .activation_time_ms = 500,
        .aftercast_ms = 750,
        .recharge_time_ms = 7000,
        .effects = &point_blank_effects,
    },

    // 6. Utility trick - removes chill from self
    .{
        .name = "Shake It Off",
        .description = "Gesture. Removes one chill from yourself.",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 0,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 750,
        .recharge_time_ms = 15000,
        .effects = &shake_it_off_effects,
    },

    // 7. Team call - provides minor buff
    .{
        .name = "Rally",
        .description = "Shout. Allies in earshot gain +5 damage for 10 seconds.",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 8,
        .cast_range = 200.0,
        .target_type = .ally,
        .aoe_type = .area,
        .aoe_radius = 200.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 20000,
        .effects = &rally_effects,
    },

    // 8. Fast response - instant cast
    .{
        .name = "Snap Throw",
        .description = "Throw. Deals 11 damage.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 4,
        .damage = 11.0,
        .cast_range = 170.0,
        .activation_time_ms = 0,
        .aftercast_ms = 750,
        .recharge_time_ms = 4000,
    },

    // 9. TERRAIN: Quick Clear - instant escape tool
    .{
        .name = "Quick Clear",
        .description = "Stance. Clear snow at your feet. You move 15% faster for 4 seconds.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 5,
        .cast_range = 0,
        .target_type = .self,
        .aoe_radius = 50.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 12000,
        .terrain_effect = types.TerrainEffect.cleared(.circle),
    },

    // 10. TERRAIN: Packed Trail - mobility while moving
    .{
        .name = "Packed Trail",
        .description = "Stance. (8 seconds.) Leave packed snow behind you as you run.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 6,
        .cast_range = 0,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 15000,
        .duration_ms = 8000,
        .terrain_effect = types.TerrainEffect.packedSnow(.trail),
    },

    // 11. WALL: Quick Barrier - fast defensive wall
    .{
        .name = "Quick Barrier",
        .description = "Stance. Build a small wall at target location.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 5,
        .target_type = .ground,
        .cast_range = 200.0, // Increased for ground targeting
        .activation_time_ms = 0,
        .aftercast_ms = 750,
        .recharge_time_ms = 15000,
        .creates_wall = true,
        .wall_length = 100.0, // Increased from 50 for better coverage
        .wall_height = 25.0,
        .wall_thickness = 15.0,
        .wall_distance_from_caster = 35.0, // Legacy field (unused with ground targeting)
    },

    // 12. Catch and Return - defensive counter
    .{
        .name = "Catch and Return",
        .description = "Stance. (5 seconds.) Block the next projectile. If blocked, immediately throw it back for 20 damage.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 6,
        .damage = 20.0,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 15000,
        .duration_ms = 5000,
        .behavior = &CATCH_AND_RETURN_BEHAVIOR,
        .effects = &catch_and_return_effects,
    },

    // 13. Outfield Throw - DoT applicator
    .{
        .name = "Outfield Throw",
        .description = "Throw. Deals 12 damage. Inflicts Soggy (5 seconds).",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 6,
        .damage = 12.0,
        .cast_range = 200.0,
        .activation_time_ms = 750,
        .aftercast_ms = 750,
        .recharge_time_ms = 8000,
        .chills = &fielder_soggy,
    },

    // 14. Team Player - ally support
    .{
        .name = "Team Player",
        .description = "Call. Target ally gains +20% damage and +15% armor for 10 seconds.",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 8,
        .target_type = .ally,
        .cast_range = 200.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 18000,
        .duration_ms = 10000,
        .effects = &team_player_effects,
    },

    // 15. Defensive Slide - movement + defense
    .{
        .name = "Defensive Slide",
        .description = "Stance. (6 seconds.) Take 30% less damage. Move 20% faster.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 5,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 15000,
        .duration_ms = 6000,
        .cozies = &fielder_bundled,
        .effects = &defensive_slide_effects,
    },

    // 16. Double Play - attack two targets
    .{
        .name = "Double Play",
        .description = "Throw. Deals 14 damage to target and nearest other foe.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 8,
        .damage = 14.0,
        .cast_range = 180.0,
        .aoe_type = .adjacent,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 10000,
    },

    // ========================================================================
    // FIELDER AP SKILLS (4 AP skills for 20% of 20 total)
    // ========================================================================

    // AP 1: MVP - massive all-around buff
    .{
        .name = "MVP",
        .description = "[AP] Stance. (15 seconds.) +30% damage, +30% armor, +30% speed, +30% energy regen.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 15,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 60000,
        .duration_ms = 15000,
        .is_ap = true,
        .effects = &mvp_effects,
    },

    // AP 2: Utility Belt - use any skill type at reduced power
    .{
        .name = "Utility Belt",
        .description = "[AP] Stance. (20 seconds.) You can use skills from any position at -30% effectiveness.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 12,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 45000,
        .duration_ms = 20000,
        .is_ap = true,
        .effects = &utility_belt_effects,
    },

    // AP 3: Center Field - massive AoE presence
    .{
        .name = "Center Field",
        .description = "[AP] Trick. Create a zone for 15 seconds. Allies inside deal +20% damage, enemies inside take +20% damage.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 15,
        .target_type = .ground,
        .cast_range = 200.0,
        .aoe_type = .area,
        .aoe_radius = 180.0,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 50000,
        .duration_ms = 15000,
        .is_ap = true,
        .effects = &center_field_effects,
    },

    // AP 4: Grand Slam - powerful finisher
    .{
        .name = "Grand Slam",
        .description = "[AP] Throw. Deals 25 damage to all foes in a line. +10 damage per foe hit (stacks).",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 15,
        .damage = 25.0,
        .cast_range = 250.0,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 40000,
        .is_ap = true,
        .effects = &grand_slam_effects,
    },

    // ========================================================================
    // FIELDER SKILLS 17-20 + AP 5 (Paragon Leadership analog - Commands, Echoes)
    // ========================================================================
    // Theme: Leadership, coordination, command skills, team synergy

    // 17. First Throw - bonus when leading attack (like "Go for the Eyes!")
    .{
        .name = "First Throw",
        .description = "Call. Your next attack deals +15 damage. If it hits, nearby allies' next attacks deal +10 damage.",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 6,
        .target_type = .self,
        .aoe_type = .area,
        .aoe_radius = 200.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 12000,
        .duration_ms = 8000,
        .effects = &first_throw_effects,
    },

    // 18. Tag Team - attack that buffs ally attack (like "Anthem of Flame")
    .{
        .name = "Tag Team",
        .description = "Throw. Deals 14 damage. Target ally within 150 range attacks the same target for 10 damage.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 8,
        .damage = 14.0,
        .cast_range = 180.0,
        .activation_time_ms = 750,
        .aftercast_ms = 500,
        .recharge_time_ms = 10000,
        .behavior = &TAG_TEAM_BEHAVIOR,
    },

    // 19. Huddle Up - passive aura buff (like "Aggressive Refrain")
    .{
        .name = "Huddle Up",
        .description = "Stance. (15 seconds.) Allies within range deal +10% damage and move 10% faster.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 8,
        .target_type = .self,
        .aoe_type = .area,
        .aoe_radius = 200.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 25000,
        .duration_ms = 15000,
        .effects = &huddle_up_effects,
    },

    // 20. Got Your Back - help ally with fast attack (like "Soldier's Fury")
    .{
        .name = "Got Your Back",
        .description = "Throw. Deals 12 damage. If target is attacking an ally, deal +8 damage and interrupt.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 5,
        .damage = 12.0,
        .cast_range = 180.0,
        .activation_time_ms = 250,
        .aftercast_ms = 500,
        .recharge_time_ms = 6000,
        .interrupts = true,
        .effects = &got_your_back_effects,
    },

    // AP 5: Final Huddle - ultimate leadership buff (like "Incoming!")
    .{
        .name = "Final Huddle",
        .description = "[AP] Call. All allies heal 25 Warmth, gain +25% damage, and move 25% faster for 12 seconds.",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 15,
        .healing = 25.0,
        .target_type = .ally,
        .aoe_type = .area,
        .aoe_radius = 300.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 50000,
        .duration_ms = 12000,
        .is_ap = true,
        .effects = &final_huddle_effects,
    },
};
