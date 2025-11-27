const types = @import("../types.zig");
const Skill = types.Skill;
const effects = @import("../../effects.zig");

// ============================================================================
// ANIMATOR SKILLS - Summoner/Necromancer (180-240 range)
// ============================================================================
// Synergizes with: Summon buffs, corpse mechanics, isolation bonuses
// Counterplay: AoE damage, focus summons first, dispel
// TODO: Implement proper summon mechanics

const brain_freeze_chill = [_]types.ChillEffect{.{
    .chill = .brain_freeze,
    .duration_ms = 8000,
    .stack_intensity = 1,
}};

const packed_snow_chill = [_]types.ChillEffect{.{
    .chill = .packed_snow,
    .duration_ms = 10000,
    .stack_intensity = 1,
}};

const animator_windburn = [_]types.ChillEffect{.{
    .chill = .windburn,
    .duration_ms = 8000,
    .stack_intensity = 1,
}};

const animator_numb = [_]types.ChillEffect{.{
    .chill = .numb,
    .duration_ms = 6000,
    .stack_intensity = 1,
}};

// ============================================================================
// EFFECT DEFINITIONS
// ============================================================================

// Unholy Strength - summons deal +50% damage
const unholy_strength_mods = [_]effects.Modifier{.{
    .effect_type = .damage_multiplier,
    .value = .{ .float = 1.50 },
}};

const UNHOLY_STRENGTH_EFFECT = effects.Effect{
    .name = "Unholy Strength",
    .description = "Summons deal +50% damage",
    .modifiers = &unholy_strength_mods,
    .timing = .while_active,
    .affects = .all_summons,
    .condition = .always,
    .duration_ms = 10000,
    .is_buff = true,
};

const unholy_strength_effects = [_]effects.Effect{UNHOLY_STRENGTH_EFFECT};

// Sap Will - steal energy
const sap_will_mods = [_]effects.Modifier{.{
    .effect_type = .energy_steal_on_hit,
    .value = .{ .float = 5.0 },
}};

const SAP_WILL_EFFECT = effects.Effect{
    .name = "Sap Will",
    .description = "Steal 5 energy from target",
    .modifiers = &sap_will_mods,
    .timing = .on_hit,
    .affects = .target,
    .condition = .always,
    .duration_ms = 0,
    .is_buff = false,
};

const sap_will_effects = [_]effects.Effect{SAP_WILL_EFFECT};

// Death's Embrace - life steal (heal for damage dealt)
// Note: Healing is already on skill, this effect is for documentation
const deaths_embrace_mods = [_]effects.Modifier{.{
    .effect_type = .healing_multiplier,
    .value = .{ .float = 0.50 }, // Heal for 50% of damage dealt
}};

const DEATHS_EMBRACE_EFFECT = effects.Effect{
    .name = "Life Drain",
    .description = "Heal for 50% of damage dealt",
    .modifiers = &deaths_embrace_mods,
    .timing = .on_hit,
    .affects = .self,
    .condition = .always,
    .duration_ms = 0,
    .is_buff = true,
};

const deaths_embrace_effects = [_]effects.Effect{DEATHS_EMBRACE_EFFECT};

// Dark Bargain - +25% damage buff after sacrifice
const dark_bargain_mods = [_]effects.Modifier{.{
    .effect_type = .damage_multiplier,
    .value = .{ .float = 1.25 },
}};

const DARK_BARGAIN_EFFECT = effects.Effect{
    .name = "Dark Bargain",
    .description = "+25% damage after sacrificing a snowman",
    .modifiers = &dark_bargain_mods,
    .timing = .while_active,
    .affects = .self,
    .condition = .always,
    .duration_ms = 8000,
    .is_buff = true,
};

const dark_bargain_effects = [_]effects.Effect{DARK_BARGAIN_EFFECT};

// Weaken - target deals 20% less damage
const weaken_mods = [_]effects.Modifier{.{
    .effect_type = .damage_multiplier,
    .value = .{ .float = 0.80 },
}};

const WEAKEN_EFFECT = effects.Effect{
    .name = "Weaken",
    .description = "Target deals 20% less damage",
    .modifiers = &weaken_mods,
    .timing = .while_active,
    .affects = .target,
    .condition = .always,
    .duration_ms = 6000,
    .is_buff = false,
};

const weaken_effects = [_]effects.Effect{WEAKEN_EFFECT};

// Master Animator - summons double damage, double health, +50% attack speed
const master_animator_mods = [_]effects.Modifier{
    .{
        .effect_type = .damage_multiplier,
        .value = .{ .float = 2.0 },
    },
    .{
        .effect_type = .max_warmth_multiplier,
        .value = .{ .float = 2.0 },
    },
    .{
        .effect_type = .attack_speed_multiplier,
        .value = .{ .float = 1.50 },
    },
};

const MASTER_ANIMATOR_EFFECT = effects.Effect{
    .name = "Master Animator",
    .description = "Summons deal double damage, have double health, attack 50% faster",
    .modifiers = &master_animator_mods,
    .timing = .while_active,
    .affects = .all_summons,
    .condition = .always,
    .duration_ms = 30000,
    .is_buff = true,
};

const master_animator_effects = [_]effects.Effect{MASTER_ANIMATOR_EFFECT};

// Plague of Frost - spreading curse damage
const plague_of_frost_mods = [_]effects.Modifier{.{
    .effect_type = .warmth_drain_per_second,
    .value = .{ .float = 2.0 }, // DoT effect
}};

const PLAGUE_OF_FROST_EFFECT = effects.Effect{
    .name = "Plague of Frost",
    .description = "Curse spreads when target takes damage",
    .modifiers = &plague_of_frost_mods,
    .timing = .on_take_damage,
    .affects = .foes_near_target,
    .condition = .always,
    .duration_ms = 15000,
    .is_buff = false,
};

const plague_of_frost_effects = [_]effects.Effect{PLAGUE_OF_FROST_EFFECT};

pub const skills = [_]Skill{
    // 1. Basic summon - weak but cheap
    .{
        .name = "Snowman Minion",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 8,
        .cast_range = 200.0,
        .target_type = .ground,
        .activation_time_ms = 2000,
        .aftercast_ms = 750,
        .recharge_time_ms = 15000,
        .duration_ms = 30000,
        // TODO: Summon level 1-5 snowman, attacks for 5 damage
    },

    // 2. Elite summon - powerful but expensive
    .{
        .name = "Grotesque Abomination",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 15,
        .cast_range = 220.0,
        .target_type = .ground,
        .activation_time_ms = 3000,
        .aftercast_ms = 750,
        .recharge_time_ms = 45000,
        .duration_ms = 45000,
        // TODO: Summon level 10-15 abomination, attacks for 15 damage
    },

    // 3. Exploding summon - dies and damages
    .{
        .name = "Suicide Snowman",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 10,
        .cast_range = 200.0,
        .target_type = .ground,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 20000,
        .duration_ms = 15000,
        // TODO: Summon snowman that explodes on death for AoE damage
    },

    // 4. Buff summons
    .{
        .name = "Unholy Strength",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 6,
        .cast_range = 300.0,
        .aoe_type = .area,
        .aoe_radius = 300.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 20000,
        .duration_ms = 10000,
        .effects = &unholy_strength_effects,
    },

    // 5. Heal summons
    .{
        .name = "Restore Construct",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 8,
        .healing = 60.0,
        .cast_range = 240.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 10000,
        // TODO: Target allied summon only
    },

    // 6. Corpse exploitation - use dead bodies
    .{
        .name = "Soul Harvest",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 5,
        .cast_range = 200.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 5000,
        // TODO: Gain energy from nearby corpses (3 per corpse)
    },

    // 7. Crippling curse
    .{
        .name = "Withering Curse",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 10,
        .damage = 8.0,
        .cast_range = 220.0,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 15000,
        .chills = &packed_snow_chill,
    },

    // 8. Energy drain
    .{
        .name = "Sap Will",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 7,
        .damage = 10.0,
        .cast_range = 200.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 12000,
        .chills = &brain_freeze_chill,
        .effects = &sap_will_effects,
    },

    // 9. TERRAIN: Grave Snow - create "graves" for snowman corpses
    .{
        .name = "Grave Snow",
        .description = "Trick. Create deep powder burial mounds. Snowmen built here are stronger.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 12,
        .cast_range = 220.0,
        .target_type = .ground,
        .aoe_radius = 90.0,
        .activation_time_ms = 2000,
        .aftercast_ms = 750,
        .recharge_time_ms = 30000,
        .terrain_effect = types.TerrainEffect.deepSnow(.circle),
    },

    // 10. TERRAIN: Frozen Ground - boost snowmen with ice
    .{
        .name = "Frozen Ground",
        .description = "Trick. Freeze the ground. Snowmen on ice attack faster.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 10,
        .cast_range = 200.0,
        .target_type = .ground,
        .aoe_radius = 100.0,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 25000,
        .terrain_effect = types.TerrainEffect.ice(.circle),
    },

    // 11. WALL: Snowman Wall - animated defensive barrier
    .{
        .name = "Snowman Wall",
        .description = "Trick. Build a wall of snowmen at target location. They provide cover.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 10,
        .target_type = .ground,
        .cast_range = 250.0, // Increased for ground targeting
        .activation_time_ms = 2000,
        .aftercast_ms = 750,
        .recharge_time_ms = 25000,
        .creates_wall = true,
        .wall_length = 140.0, // Increased from 70 - snowmen spread out
        .wall_height = 35.0,
        .wall_thickness = 25.0,
        .wall_distance_from_caster = 45.0, // Legacy field (unused with ground targeting)
    },

    // 12. Curse of Cold - DoT curse
    .{
        .name = "Curse of Cold",
        .description = "Trick. Deals 10 damage. Inflicts Windburn (8 seconds).",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 8,
        .damage = 10.0,
        .cast_range = 220.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 12000,
        .chills = &animator_windburn,
    },

    // 13. Death's Embrace - life drain
    .{
        .name = "Death's Embrace",
        .description = "Trick. Deals 15 damage. You heal for 50% of damage dealt.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 7,
        .damage = 15.0,
        .healing = 7.5,
        .cast_range = 200.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 10000,
        .effects = &deaths_embrace_effects,
    },

    // 14. Summon Reinforcement - quick minion
    .{
        .name = "Summon Reinforcement",
        .description = "Trick. Summon a weak snowman that explodes after 10 seconds for 15 damage.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 6,
        .damage = 15.0,
        .cast_range = 180.0,
        .target_type = .ground,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 15000,
        .duration_ms = 10000,
    },

    // 15. Dark Bargain - sacrifice summon for power
    .{
        .name = "Dark Bargain",
        .description = "Trick. Destroy one of your snowmen. Gain 10 energy and +25% damage for 8 seconds.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 0,
        .target_type = .ally,
        .cast_range = 200.0,
        .activation_time_ms = 500,
        .aftercast_ms = 500,
        .recharge_time_ms = 15000,
        .grants_energy_on_hit = 10,
        .effects = &dark_bargain_effects,
    },

    // 16. Weaken - debuff enemy
    .{
        .name = "Weaken",
        .description = "Trick. Deals 8 damage. Inflicts Numb (6 seconds). Target deals 20% less damage.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 7,
        .damage = 8.0,
        .cast_range = 200.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 15000,
        .chills = &animator_numb,
        .effects = &weaken_effects,
    },

    // ========================================================================
    // ANIMATOR AP SKILLS (4 AP skills for 20% of 20 total)
    // ========================================================================

    // AP 1: Army of Snow - summon many minions
    .{
        .name = "Army of Snow",
        .description = "[AP] Trick. Summon 5 snowmen around you. Each attacks nearby enemies for 8 damage. Lasts 20 seconds.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 20,
        .damage = 8.0,
        .target_type = .ground,
        .cast_range = 100.0,
        .aoe_type = .area,
        .aoe_radius = 150.0,
        .activation_time_ms = 3000,
        .aftercast_ms = 750,
        .recharge_time_ms = 60000,
        .duration_ms = 20000,
        .is_ap = true,
    },

    // AP 2: Plague of Frost - spreading DoT
    .{
        .name = "Plague of Frost",
        .description = "[AP] Trick. Curse target. When they take damage, the curse spreads to the nearest unmarked enemy. Each spread deals 10 damage.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 15,
        .damage = 10.0,
        .cast_range = 200.0,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 40000,
        .duration_ms = 15000,
        .is_ap = true,
        .effects = &plague_of_frost_effects,
    },

    // AP 3: Master Animator - empower all summons
    .{
        .name = "Master Animator",
        .description = "[AP] Stance. (30 seconds.) Your snowmen deal double damage, have double health, and attack 50% faster.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 15,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 60000,
        .duration_ms = 30000,
        .is_ap = true,
        .effects = &master_animator_effects,
    },

    // AP 4: Death Nova - explode enemies on death
    .{
        .name = "Death Nova",
        .description = "[AP] Trick. Curse target. If they die within 20 seconds, they explode dealing 40 damage to nearby foes.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 12,
        .damage = 40.0,
        .cast_range = 200.0,
        .aoe_type = .area,
        .aoe_radius = 120.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 35000,
        .duration_ms = 20000,
        .is_ap = true,
    },
};
