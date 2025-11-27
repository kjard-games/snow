const types = @import("../types.zig");
const effects = @import("../../effects.zig");
const Skill = types.Skill;

// ============================================================================
// MONTESSORI SKILLS - Green: Adaptation, Variety, Growth
// ============================================================================
// Theme: Rewards using different skill types, versatile, scaling
// Synergizes with: Fielder, variety in skill bar, adaptation
// Cooldowns: 8-15s

const montessori_sure = [_]types.CozyEffect{.{
    .cozy = .sure_footed,
    .duration_ms = 8000,
    .stack_intensity = 1,
}};

const montessori_multi_chill = [_]types.ChillEffect{.{
    .chill = .slippery,
    .duration_ms = 3000,
    .stack_intensity = 1,
}};

const montessori_fire = [_]types.CozyEffect{.{
    .cozy = .fire_inside,
    .duration_ms = 8000,
    .stack_intensity = 1,
}};

const montessori_bundled = [_]types.CozyEffect{.{
    .cozy = .bundled_up,
    .duration_ms = 10000,
    .stack_intensity = 1,
}};

const montessori_soggy = [_]types.ChillEffect{.{
    .chill = .soggy,
    .duration_ms = 5000,
    .stack_intensity = 1,
}};

// ============================================================================
// EFFECT DEFINITIONS - Composable effects for complex skill mechanics
// ============================================================================

// Self Directed (skill 1): +10% damage when using different skill types
const self_directed_mods = [_]effects.Modifier{
    .{
        .effect_type = .damage_multiplier,
        .value = .{ .float = 1.1 }, // +10% damage
    },
    .{
        .effect_type = .energy_on_hit,
        .value = .{ .float = 1.0 }, // +1 energy on hit
    },
};

const SELF_DIRECTED_EFFECT = effects.Effect{
    .name = "Self Directed",
    .description = "+10% damage and +1 energy when using different skill types",
    .modifiers = &self_directed_mods,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 20000,
    .is_buff = true,
    .condition = .if_caster_used_different_type,
};

const self_directed_effects = [_]effects.Effect{SELF_DIRECTED_EFFECT};

// Versatile Throw (skill 2): +2 energy if last skill was different type
const versatile_throw_mods = [_]effects.Modifier{.{
    .effect_type = .energy_on_hit,
    .value = .{ .float = 2.0 },
}};

const VERSATILE_THROW_EFFECT = effects.Effect{
    .name = "Versatility Bonus",
    .description = "+2 energy when used after different skill type",
    .modifiers = &versatile_throw_mods,
    .timing = .on_hit,
    .affects = .self,
    .duration_ms = 0, // Instant
    .is_buff = true,
    .condition = .if_caster_used_different_type,
};

const versatile_throw_effects = [_]effects.Effect{VERSATILE_THROW_EFFECT};

// Explore (skill 4): Move 33% faster
const explore_mods = [_]effects.Modifier{.{
    .effect_type = .move_speed_multiplier,
    .value = .{ .float = 1.33 },
}};

const EXPLORE_EFFECT = effects.Effect{
    .name = "Explore",
    .description = "Move 33% faster",
    .modifiers = &explore_mods,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 8000,
    .is_buff = true,
};

const explore_effects = [_]effects.Effect{EXPLORE_EFFECT};

// Growth Mindset (skill 5): 20% cooldown reduction
const growth_mindset_mods = [_]effects.Modifier{.{
    .effect_type = .cooldown_reduction_percent,
    .value = .{ .float = 0.2 },
}};

const GROWTH_MINDSET_EFFECT = effects.Effect{
    .name = "Growth Mindset",
    .description = "Skills recharge 20% faster",
    .modifiers = &growth_mindset_mods,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 15000,
    .is_buff = true,
};

const growth_mindset_effects = [_]effects.Effect{GROWTH_MINDSET_EFFECT};

// Hands-On Learning (skill 13): +10 damage if different skill type last
const hands_on_learning_mods = [_]effects.Modifier{.{
    .effect_type = .damage_add,
    .value = .{ .float = 10.0 },
}};

const HANDS_ON_LEARNING_EFFECT = effects.Effect{
    .name = "Hands-On Learning",
    .description = "+10 damage when used after different skill type",
    .modifiers = &hands_on_learning_mods,
    .timing = .on_hit,
    .affects = .target,
    .duration_ms = 0, // Instant
    .is_buff = false,
    .condition = .if_caster_used_different_type,
};

const hands_on_learning_effects = [_]effects.Effect{HANDS_ON_LEARNING_EFFECT};

// Field Trip (skill 16): Move 40% faster
const field_trip_mods = [_]effects.Modifier{.{
    .effect_type = .move_speed_multiplier,
    .value = .{ .float = 1.4 },
}};

const FIELD_TRIP_EFFECT = effects.Effect{
    .name = "Field Trip",
    .description = "Move 40% faster",
    .modifiers = &field_trip_mods,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 12000,
    .is_buff = true,
};

const field_trip_effects = [_]effects.Effect{FIELD_TRIP_EFFECT};

// Emergent Curriculum (AP 3): +30% damage to target, -20% damage from target
const emergent_curriculum_offense_mods = [_]effects.Modifier{.{
    .effect_type = .damage_multiplier,
    .value = .{ .float = 1.3 }, // Deal +30% damage to target
}};

const EMERGENT_CURRICULUM_OFFENSE_EFFECT = effects.Effect{
    .name = "Analyzed: Offense",
    .description = "Deal +30% damage to this target",
    .modifiers = &emergent_curriculum_offense_mods,
    .timing = .while_active,
    .affects = .self, // Applies to caster's damage against target
    .duration_ms = 15000,
    .is_buff = true,
};

const emergent_curriculum_defense_mods = [_]effects.Modifier{.{
    .effect_type = .damage_multiplier,
    .value = .{ .float = 0.8 }, // Take 20% less damage from target
}};

const EMERGENT_CURRICULUM_DEFENSE_EFFECT = effects.Effect{
    .name = "Analyzed: Defense",
    .description = "Take 20% less damage from this target",
    .modifiers = &emergent_curriculum_defense_mods,
    .timing = .while_active,
    .affects = .self, // Reduces damage taken from analyzed target
    .duration_ms = 15000,
    .is_buff = true,
};

const emergent_curriculum_effects = [_]effects.Effect{ EMERGENT_CURRICULUM_OFFENSE_EFFECT, EMERGENT_CURRICULUM_DEFENSE_EFFECT };

// Quick Learner (skill 10): Next skill recharges 50% faster if different type
const quick_learner_mods = [_]effects.Modifier{.{
    .effect_type = .next_skill_cooldown_multiplier,
    .value = .{ .float = 0.5 },
}};

const QUICK_LEARNER_EFFECT = effects.Effect{
    .name = "Quick Learner",
    .description = "Next skill recharges 50% faster if different type",
    .modifiers = &quick_learner_mods,
    .timing = .on_cast,
    .affects = .self,
    .duration_ms = 10000, // Expires if not used
    .is_buff = true,
    .condition = .if_caster_used_different_type,
};

const quick_learner_effects = [_]effects.Effect{QUICK_LEARNER_EFFECT};

// Peer Teaching (skill 15): +15% damage to both caster and ally
const peer_teaching_mods = [_]effects.Modifier{.{
    .effect_type = .damage_multiplier,
    .value = .{ .float = 1.15 },
}};

const PEER_TEACHING_SELF_EFFECT = effects.Effect{
    .name = "Peer Teaching",
    .description = "+15% damage",
    .modifiers = &peer_teaching_mods,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 10000,
    .is_buff = true,
};

const PEER_TEACHING_ALLY_EFFECT = effects.Effect{
    .name = "Peer Teaching",
    .description = "+15% damage",
    .modifiers = &peer_teaching_mods,
    .timing = .while_active,
    .affects = .target, // Target ally
    .duration_ms = 10000,
    .is_buff = true,
};

const peer_teaching_effects = [_]effects.Effect{ PEER_TEACHING_SELF_EFFECT, PEER_TEACHING_ALLY_EFFECT };

pub const skills = [_]Skill{
    // 1. Variety buff - core mechanic
    .{
        .name = "Self Directed",
        .description = "Stance. (20 seconds.) Using different skill types grants +1 energy and +10% damage.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 5,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 15000,
        .duration_ms = 20000,
        .effects = &self_directed_effects,
    },

    // 2. Swiss army knife - does many things
    .{
        .name = "Versatile Throw",
        .description = "Throw. Deals 14 damage. Inflicts Slippery (3 seconds). Gains +2 energy if last skill was different type.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 6,
        .damage = 14.0,
        .cast_range = 180.0,
        .activation_time_ms = 750,
        .aftercast_ms = 750,
        .recharge_time_ms = 8000,
        .chills = &montessori_multi_chill,
        .effects = &versatile_throw_effects,
    },

    // 3. Adapts to situation
    .{
        .name = "Improvise",
        .description = "Trick. Gain a random beneficial effect based on your current situation.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 7,
        .cast_range = 200.0,
        .target_type = .self,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 12000,
        // TODO: Random beneficial effect based on situation
    },

    // 4. Movement skill
    .{
        .name = "Explore",
        .description = "Stance. (8 seconds.) Move 33% faster.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 4,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 10000,
        .duration_ms = 8000,
        .cozies = &montessori_sure,
        .effects = &explore_effects,
    },

    // 5. Learns from experience
    .{
        .name = "Growth Mindset",
        .description = "Stance. (15 seconds.) Your skills recharge 20% faster.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 6,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 20000,
        .duration_ms = 15000,
        .effects = &growth_mindset_effects,
    },

    // 6. Does everything okay
    .{
        .name = "Jack of All Trades",
        .description = "Throw. Deals 15 damage.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 5,
        .damage = 15.0,
        .cast_range = 180.0,
        .activation_time_ms = 750,
        .aftercast_ms = 750,
        .recharge_time_ms = 6000,
    },

    // 7. Utility - can target ally or enemy
    .{
        .name = "Flexible Response",
        .description = "Trick. Heals ally for 30 Warmth OR deals 20 damage to foe.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 8,
        .damage = 20.0,
        .healing = 30.0,
        .cast_range = 200.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 15000,
        // TODO: Heal ally OR damage enemy based on target
    },

    // 8. Bonus if haven't repeated skills
    .{
        .name = "Fresh Perspective",
        .description = "Gesture. Gain 2 energy for each different skill type used in the last 10 seconds (maximum 10 energy).",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 0,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 750,
        .recharge_time_ms = 15000,
        // TODO: Gain energy equal to number of different skill types used recently
    },

    // 9. WALL: Adaptive Barrier - wall that changes based on situation
    .{
        .name = "Adaptive Barrier",
        .description = "Stance. Build a versatile wall. Shape and height adapt to terrain.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 7,
        .target_type = .ground,
        .cast_range = 120.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 18000,
        .creates_wall = true,
        .wall_length = 60.0,
        .wall_height = 30.0,
        .wall_thickness = 20.0,
        .wall_distance_from_caster = 40.0,
        // TODO: Wall height/shape adapts to underlying terrain
    },

    // 10. Quick Learner - faster cooldowns after using different skills
    .{
        .name = "Quick Learner",
        .description = "Gesture. Your next skill recharges 50% faster if it's a different type than your last.",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 0,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 500,
        .recharge_time_ms = 8000,
        .effects = &quick_learner_effects,
    },

    // 11. Balanced Approach - damage and healing in one
    .{
        .name = "Balanced Approach",
        .description = "Trick. Deals 15 damage to foe. Heals self for 15 Warmth.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 7,
        .damage = 15.0,
        .healing = 15.0,
        .cast_range = 180.0,
        .target_type = .enemy,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 10000,
    },

    // 12. Try Everything - random beneficial effect
    .{
        .name = "Try Everything",
        .description = "Stance. (10 seconds.) Each second, gain a random small buff: +5% damage, +5% armor, +5% speed, or +1 energy.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 6,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 20000,
        .duration_ms = 10000,
    },

    // 13. Hands-On Learning - close range power spike
    .{
        .name = "Hands-On Learning",
        .description = "Throw. Deals 20 damage. +10 damage if you used a different skill type last.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 6,
        .damage = 20.0,
        .cast_range = 150.0,
        .activation_time_ms = 750,
        .aftercast_ms = 750,
        .recharge_time_ms = 8000,
        .effects = &hands_on_learning_effects,
    },

    // 14. Natural Consequence - DoT that rewards variety
    .{
        .name = "Natural Consequence",
        .description = "Trick. Inflicts Soggy (5 seconds). +3 seconds duration per different skill type used recently.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 6,
        .damage = 8.0,
        .cast_range = 200.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 12000,
        .chills = &montessori_soggy,
    },

    // 15. Peer Teaching - buff ally and self
    .{
        .name = "Peer Teaching",
        .description = "Call. You and target ally both gain +15% damage for 10 seconds.",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 8,
        .target_type = .ally,
        .cast_range = 200.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 18000,
        .duration_ms = 10000,
        .cozies = &montessori_fire,
        .effects = &peer_teaching_effects,
    },

    // 16. Field Trip - movement and exploration
    .{
        .name = "Field Trip",
        .description = "Stance. (12 seconds.) Move 40% faster. Gain 2 energy when you change terrain types.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 5,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 20000,
        .duration_ms = 12000,
        .cozies = &montessori_sure,
        .effects = &field_trip_effects,
        // NOTE: +2 energy on terrain change requires runtime tracking
    },

    // ========================================================================
    // MONTESSORI AP SKILLS (4 AP skills for 20% of 20 total)
    // ========================================================================

    // AP 1: Mastery Through Practice - skills get stronger with use
    .{
        .name = "Mastery Through Practice",
        .description = "[AP] Stance. (30 seconds.) Each time you use a skill, that skill type deals +10% damage (stacks up to +50%).",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 10,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 45000,
        .duration_ms = 30000,
        .is_ap = true,
    },

    // AP 2: Polymath - use skills from other schools
    .{
        .name = "Polymath",
        .description = "[AP] Gesture. For 20 seconds, you can use skills from any school at -25% effectiveness.",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 15,
        .target_type = .self,
        .activation_time_ms = 500,
        .aftercast_ms = 500,
        .recharge_time_ms = 60000,
        .duration_ms = 20000,
        .is_ap = true,
    },

    // AP 3: Emergent Curriculum - adapt to enemy weaknesses
    .{
        .name = "Emergent Curriculum",
        .description = "[AP] Trick. Analyze target. For 15 seconds, deal +30% damage to that target and take 20% less from them.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 10,
        .cast_range = 200.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 500,
        .recharge_time_ms = 30000,
        .duration_ms = 15000,
        .is_ap = true,
        .effects = &emergent_curriculum_effects,
    },

    // AP 4: Prepared Environment - create optimal zone
    .{
        .name = "Prepared Environment",
        .description = "[AP] Trick. Create a learning zone for 20 seconds. Allies inside deal +20% damage, have +30% skill recharge, and heal 3 Warmth/second.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 15,
        .target_type = .ground,
        .cast_range = 200.0,
        .aoe_type = .area,
        .aoe_radius = 150.0,
        .activation_time_ms = 2000,
        .aftercast_ms = 750,
        .recharge_time_ms = 50000,
        .duration_ms = 20000,
        .terrain_effect = types.TerrainEffect.packedSnow(.circle),
        .is_ap = true,
    },
};
