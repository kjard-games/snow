const types = @import("../types.zig");
const Skill = types.Skill;

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
        // TODO: Self-damage on cast
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
    },
};
