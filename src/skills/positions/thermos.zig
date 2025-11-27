const types = @import("../types.zig");
const Skill = types.Skill;

// ============================================================================
// THERMOS SKILLS - Healer/Support (150-200 range)
// ============================================================================
// Synergizes with: Healing bonuses, team buffs, rhythm skills
// Counterplay: Interrupt heals, focus healer first, spread damage

const hot_cocoa_cozy = [_]types.CozyEffect{.{
    .cozy = .hot_cocoa,
    .duration_ms = 12000,
    .stack_intensity = 1,
}};

const insulated_cozy = [_]types.CozyEffect{.{
    .cozy = .insulated,
    .duration_ms = 15000,
    .stack_intensity = 1,
}};

const snow_goggles_cozy = [_]types.CozyEffect{.{
    .cozy = .snow_goggles,
    .duration_ms = 10000,
    .stack_intensity = 1,
}};

const frost_eyes_chill = [_]types.ChillEffect{.{
    .chill = .frost_eyes,
    .duration_ms = 5000,
    .stack_intensity = 1,
}};

const thermos_sure_footed = [_]types.CozyEffect{.{
    .cozy = .sure_footed,
    .duration_ms = 8000,
    .stack_intensity = 1,
}};

const thermos_fortitude = [_]types.CozyEffect{.{
    .cozy = .frosty_fortitude,
    .duration_ms = 15000,
    .stack_intensity = 1,
}};

const bundled_up_cozy = [_]types.CozyEffect{.{
    .cozy = .bundled_up,
    .duration_ms = 10000,
    .stack_intensity = 1,
}};

pub const skills = [_]Skill{
    // 1. Single target heal - primary healing tool
    .{
        .name = "Share Cocoa",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 6,
        .healing = 35.0,
        .cast_range = 180.0,
        .target_type = .ally,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 3000,
    },

    // 2. AoE heal - team healing
    .{
        .name = "Cocoa Break",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 12,
        .healing = 25.0,
        .cast_range = 200.0,
        .target_type = .ally,
        .aoe_type = .area,
        .aoe_radius = 200.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 15000,
    },

    // 3. HoT buff - regeneration over time
    .{
        .name = "Hand Warmers",
        .description = "Trick. Removes all chills from target ally.",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 7,
        .cast_range = 180.0,
        .target_type = .ally,
        .activation_time_ms = 750,
        .aftercast_ms = 750,
        .recharge_time_ms = 10000,
        .cozies = &hot_cocoa_cozy,
    },

    // 4. Protective buff - armor
    .{
        .name = "Extra Layers",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 6,
        .cast_range = 170.0,
        .target_type = .ally,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 12000,
        .cozies = &bundled_up_cozy,
    },

    // 5. Condition removal
    .{
        .name = "Warm Embrace",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 8,
        .healing = 20.0,
        .cast_range = 180.0,
        .target_type = .ally,
        .activation_time_ms = 750,
        .aftercast_ms = 750,
        .recharge_time_ms = 10000,
        // TODO: Remove 1-2 chills from target
    },

    // 6. Energy support
    .{
        .name = "Energy Bar",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 5,
        .cast_range = 180.0,
        .target_type = .ally,
        .activation_time_ms = 500,
        .aftercast_ms = 750,
        .recharge_time_ms = 15000,
        .cozies = &insulated_cozy,
        // TODO: Target gains +5 energy immediately
    },

    // 7. Defensive utility - blind
    .{
        .name = "Snow Toss",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 5,
        .damage = 8.0,
        .cast_range = 160.0,
        .activation_time_ms = 500,
        .aftercast_ms = 750,
        .recharge_time_ms = 8000,
        .chills = &frost_eyes_chill,
    },

    // 8. Team buff - blind immunity
    .{
        .name = "Clear Vision",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 8,
        .cast_range = 200.0,
        .target_type = .ally,
        .aoe_type = .area,
        .aoe_radius = 200.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 25000,
        .cozies = &snow_goggles_cozy,
    },

    // 9. TERRAIN: Cocoa Puddle - healing slush zone
    .{
        .name = "Cocoa Puddle",
        .description = "Call. Create a slushy puddle. Allies standing in it are slowly healed.",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 10,
        .healing = 2.0, // Per second while standing in it
        .cast_range = 180.0,
        .target_type = .ground,
        .aoe_radius = 80.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 20000,
        .duration_ms = 15000,
        .terrain_effect = types.TerrainEffect.healingSlush(.circle),
    },

    // 10. TERRAIN: Warming Circle - remove chills with cleared ground
    .{
        .name = "Warming Circle",
        .description = "Call. Clear snow in an area. Allies inside lose chill conditions.",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 8,
        .cast_range = 200.0,
        .target_type = .ground,
        .aoe_radius = 100.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 25000,
        .terrain_effect = types.TerrainEffect.cleared(.circle),
    },

    // 11. WALL: Shelter - protective wall for allies
    .{
        .name = "Shelter",
        .description = "Gesture. Build a warm wall at target location. Protects allies from projectiles.",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 8,
        .target_type = .ground,
        .cast_range = 250.0, // Increased for ground targeting
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 18000,
        .creates_wall = true,
        .wall_length = 130.0, // Increased from 70 for better shelter coverage
        .wall_height = 30.0,
        .wall_thickness = 20.0,
        .wall_distance_from_caster = 50.0, // Legacy field (unused with ground targeting)
    },

    // 12. Encouraging Words - buff and heal
    .{
        .name = "Encouraging Words",
        .description = "Call. Target ally heals 20 Warmth and gains +15% damage for 10 seconds.",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 8,
        .healing = 20.0,
        .target_type = .ally,
        .cast_range = 200.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 12000,
        .duration_ms = 10000,
    },

    // 13. Quick Refill - instant ally heal
    .{
        .name = "Quick Refill",
        .description = "Gesture. Heal target ally for 25 Warmth instantly.",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 5,
        .healing = 25.0,
        .target_type = .ally,
        .cast_range = 180.0,
        .activation_time_ms = 0,
        .aftercast_ms = 750,
        .recharge_time_ms = 5000,
    },

    // 14. Group Hug - defensive AoE
    .{
        .name = "Group Hug",
        .description = "Call. All allies in range gain +25% armor for 8 seconds.",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 10,
        .target_type = .ally,
        .aoe_type = .area,
        .aoe_radius = 200.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 20000,
        .duration_ms = 8000,
        .cozies = &bundled_up_cozy,
    },

    // 15. Fortifying Brew - max warmth buff
    .{
        .name = "Fortifying Brew",
        .description = "Gesture. Target ally gains +30 max Warmth for 15 seconds.",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 7,
        .target_type = .ally,
        .cast_range = 180.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 18000,
        .cozies = &thermos_fortitude,
    },

    // 16. Escape Route - ally mobility
    .{
        .name = "Escape Route",
        .description = "Call. Target ally moves 40% faster for 8 seconds.",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 5,
        .target_type = .ally,
        .cast_range = 200.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 15000,
        .duration_ms = 8000,
        .cozies = &thermos_sure_footed,
    },

    // ========================================================================
    // THERMOS AP SKILLS (4 AP skills for 20% of 20 total)
    // ========================================================================

    // AP 1: Miracle Worker - massive heal burst
    .{
        .name = "Miracle Worker",
        .description = "[AP] Call. All allies heal to full Warmth. All Chills removed. 90 second cooldown.",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 20,
        .healing = 300.0,
        .target_type = .ally,
        .aoe_type = .area,
        .aoe_radius = 300.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 90000,
        .is_ap = true,
    },

    // AP 2: Spirit Link - share health pool
    .{
        .name = "Spirit Link",
        .description = "[AP] Trick. Link all allies for 15 seconds. Damage to any linked ally is split evenly among all.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 15,
        .target_type = .ally,
        .aoe_type = .area,
        .aoe_radius = 250.0,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 50000,
        .duration_ms = 15000,
        .is_ap = true,
    },

    // AP 3: Sanctuary - healing zone
    .{
        .name = "Sanctuary",
        .description = "[AP] Trick. Create a sanctuary for 20 seconds. Allies inside heal 8 Warmth/second and take 30% less damage.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 18,
        .healing = 8.0,
        .target_type = .ground,
        .cast_range = 200.0,
        .aoe_type = .area,
        .aoe_radius = 150.0,
        .activation_time_ms = 2000,
        .aftercast_ms = 750,
        .recharge_time_ms = 60000,
        .duration_ms = 20000,
        .terrain_effect = types.TerrainEffect.healingSlush(.circle),
        .is_ap = true,
    },

    // AP 4: Martyr - take damage for allies
    .{
        .name = "Martyr",
        .description = "[AP] Stance. (15 seconds.) Whenever an ally would die, they instead heal to 50% and you take 50 damage.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 10,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 60000,
        .duration_ms = 15000,
        .is_ap = true,
    },
};
