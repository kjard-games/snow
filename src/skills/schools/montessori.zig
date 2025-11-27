const types = @import("../types.zig");
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
        // TODO: Track variety, grant bonuses
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
        // TODO: +2 energy if variety
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
        // TODO: Cooldowns reduced by 20%
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
