const types = @import("../types.zig");
const Skill = types.Skill;

// ============================================================================
// PUBLIC SCHOOL SKILLS - Red: Aggression, Grit, Combat
// ============================================================================
// Theme: No passive regen, gain energy from combat, fast cooldowns, high damage
// Synergizes with: Aggressive positions, damage dealers, close combat
// Cooldowns: 3-8s

const public_soggy = [_]types.ChillEffect{.{
    .chill = .soggy,
    .duration_ms = 6000,
    .stack_intensity = 1,
}};

const public_windburn = [_]types.ChillEffect{.{
    .chill = .windburn,
    .duration_ms = 5000,
    .stack_intensity = 1,
}};

const public_fire = [_]types.CozyEffect{.{
    .cozy = .fire_inside,
    .duration_ms = 8000,
    .stack_intensity = 1,
}};

const public_slippery = [_]types.ChillEffect{.{
    .chill = .slippery,
    .duration_ms = 4000,
    .stack_intensity = 1,
}};

const public_numb = [_]types.ChillEffect{.{
    .chill = .numb,
    .duration_ms = 6000,
    .stack_intensity = 1,
}};

const public_bundled = [_]types.CozyEffect{.{
    .cozy = .bundled_up,
    .duration_ms = 6000,
    .stack_intensity = 1,
}};

pub const skills = [_]Skill{
    // 1. Grit builder - spam attack
    .{
        .name = "Scrap",
        .description = "Throw. Deals 10 damage. Gain 2 Grit on hit.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 4,
        .damage = 10.0,
        .cast_range = 180.0,
        .activation_time_ms = 500,
        .aftercast_ms = 750,
        .recharge_time_ms = 4000,
        .grants_grit_on_hit = 2,
    },

    // 2. Fast aggressive buff - instant Grit
    .{
        .name = "Riled Up",
        .description = "Stance. (8 seconds.) You deal +33% damage. Gain 3 Grit.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 5,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 8000,
        .cozies = &public_fire,
        .grants_grit_on_cast = 3,
    },

    // 3. DoT spam
    .{
        .name = "Dirty Snowball",
        .description = "Throw. Deals 12 damage. Inflicts Soggy (6 seconds).",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 5,
        .damage = 12.0,
        .cast_range = 160.0,
        .activation_time_ms = 500,
        .aftercast_ms = 750,
        .recharge_time_ms = 5000,
        .chills = &public_soggy,
    },

    // 4. Fast cooldown pressure - Grit spender
    .{
        .name = "Relentless",
        .description = "Throw. Costs 2 Grit. Deals 18 damage. Recharges instantly if it hits.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 4,
        .grit_cost = 2,
        .damage = 18.0,
        .cast_range = 170.0,
        .activation_time_ms = 750,
        .aftercast_ms = 750,
        .recharge_time_ms = 3000,
    },

    // 5. Bonus damage if target damaged recently - Grit spender
    .{
        .name = "Pile On",
        .description = "Throw. Costs 3 Grit. Deals 22 damage. +10 damage if target has a Chill.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 5,
        .grit_cost = 3,
        .damage = 22.0,
        .cast_range = 180.0,
        .activation_time_ms = 750,
        .aftercast_ms = 750,
        .recharge_time_ms = 6000,
        // TODO: +10 damage if target has a chill
    },

    // 6. Knockdown effect
    .{
        .name = "Tackle",
        .description = "Throw. Costs 4 Grit. Deals 16 damage. Inflicts Slippery and knockdown (4 seconds).",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 6,
        .grit_cost = 4,
        .damage = 16.0,
        .cast_range = 120.0,
        .activation_time_ms = 500,
        .aftercast_ms = 750,
        .recharge_time_ms = 8000,
        .chills = &public_slippery,
        // TODO: Knockdown effect
    },

    // 7. Burn through - damage over time
    .{
        .name = "Friction Burn",
        .description = "Throw. Deals 8 damage. Inflicts Windburn (5 seconds).",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 5,
        .damage = 8.0,
        .cast_range = 160.0,
        .activation_time_ms = 500,
        .aftercast_ms = 750,
        .recharge_time_ms = 7000,
        .chills = &public_windburn,
    },

    // 8. All-in attack - high risk high reward Grit finisher
    .{
        .name = "All Out",
        .description = "Elite Throw. Costs 5 Grit. Deals 30 damage. You take double damage for 5 seconds.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 5,
        .grit_cost = 5,
        .damage = 30.0,
        .cast_range = 150.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 8000,
        // TODO: You take double damage for 5s
    },

    // 9. WALL: Scrappy Barricade - fast, aggressive wall
    .{
        .name = "Scrappy Barricade",
        .description = "Trick. Costs 3 Grit. Build a rough barricade. Gain 2 Grit on cast.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 6,
        .grit_cost = 3,
        .target_type = .ground,
        .cast_range = 100.0,
        .activation_time_ms = 750,
        .aftercast_ms = 750,
        .recharge_time_ms = 12000, // Fast cooldown
        .creates_wall = true,
        .wall_length = 50.0,
        .wall_height = 28.0,
        .wall_thickness = 18.0, // Thinner, scrappier wall
        .wall_distance_from_caster = 35.0,
        .grants_grit_on_cast = 2, // Get some Grit back
    },

    // 10. Sucker Punch - fast opener
    .{
        .name = "Sucker Punch",
        .description = "Throw. Deals 16 damage. Fast activation. Gain 2 Grit.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 4,
        .damage = 16.0,
        .cast_range = 150.0,
        .activation_time_ms = 250,
        .aftercast_ms = 750,
        .recharge_time_ms = 6000,
        .grants_grit_on_hit = 2,
    },

    // 11. Dig Deep - heal that costs grit
    .{
        .name = "Dig Deep",
        .description = "Gesture. Costs 4 Grit. Heals for 35 Warmth. Gain 5 energy.",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 0,
        .grit_cost = 4,
        .healing = 35.0,
        .target_type = .self,
        .activation_time_ms = 500,
        .aftercast_ms = 750,
        .recharge_time_ms = 15000,
        .grants_energy_on_hit = 5,
    },

    // 12. Underdog - bonus when outnumbered
    .{
        .name = "Underdog",
        .description = "Stance. (12 seconds.) Gain +3 Grit per second while outnumbered.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 5,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 25000,
        .duration_ms = 12000,
        .cozies = &public_fire,
    },

    // 13. Haymaker - high damage grit spender
    .{
        .name = "Haymaker",
        .description = "Throw. Costs 6 Grit. Deals 35 damage. Inflicts Numb (6 seconds).",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 8,
        .grit_cost = 6,
        .damage = 35.0,
        .cast_range = 120.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 12000,
        .chills = &public_numb,
    },

    // 14. Second Wind - sustain for fighters
    .{
        .name = "Second Wind",
        .description = "Gesture. Costs 3 Grit. Heals for 25 Warmth. Your next attack deals +10 damage.",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 0,
        .grit_cost = 3,
        .healing = 25.0,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 750,
        .recharge_time_ms = 12000,
    },

    // 15. Brawler's Stance - defensive with counterattack
    .{
        .name = "Brawler's Stance",
        .description = "Stance. (8 seconds.) Take 20% less damage. Gain 1 Grit when hit.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 5,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 18000,
        .duration_ms = 8000,
        .cozies = &public_bundled,
    },

    // 16. Never Give Up - resistance to conditions
    .{
        .name = "Never Give Up",
        .description = "Call. Costs 5 Grit. Remove all Chills from yourself. Gain 2 energy per Chill removed.",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 0,
        .grit_cost = 5,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 20000,
        // TODO: Remove all chills, gain 2 energy per chill
    },

    // ========================================================================
    // PUBLIC SCHOOL AP SKILLS (4 AP skills for 20% of 20 total)
    // ========================================================================

    // AP 1: Berserker Rage - massive damage boost but dangerous
    .{
        .name = "Berserker Rage",
        .description = "[AP] Stance. (15 seconds.) Deal +75% damage. Attack 50% faster. Take 25% more damage. Gain 2 Grit per second.",
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

    // AP 2: Final Push - execute with massive grit dump
    .{
        .name = "Final Push",
        .description = "[AP] Throw. Costs ALL Grit (min 5). Deals 10 damage +8 per Grit spent. If target dies, reset cooldown.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 10,
        .damage = 10.0,
        .cast_range = 180.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 30000,
        .is_ap = true,
    },

    // AP 3: Rally the Troops - team grit sharing
    .{
        .name = "Rally the Troops",
        .description = "[AP] Call. All allies gain 5 Grit. For 12 seconds, when any ally hits a foe, all allies gain 1 Grit.",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 15,
        .target_type = .ally,
        .aoe_type = .area,
        .aoe_radius = 300.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 50000,
        .duration_ms = 12000,
        .is_ap = true,
    },

    // AP 4: Unstoppable Force - immune to control while attacking
    .{
        .name = "Unstoppable Force",
        .description = "[AP] Stance. (20 seconds.) Cannot be interrupted, knocked down, or slowed. +25% damage. Lose 2 Warmth per second.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 10,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 60000,
        .duration_ms = 20000,
        .is_ap = true,
    },
};
