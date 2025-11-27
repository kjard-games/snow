const types = @import("../types.zig");
const Skill = types.Skill;

// ============================================================================
// WALDORF SKILLS - Blue: Rhythm, Timing, Harmony
// ============================================================================
// Theme: Rewards perfect timing, rhythm-based bonuses, team harmony
// Synergizes with: Skill chaining, timing windows, support roles
// Cooldowns: Rhythmic (5-15s)

const waldorf_hot_cocoa = [_]types.CozyEffect{.{
    .cozy = .hot_cocoa,
    .duration_ms = 12000,
    .stack_intensity = 1,
}};

const waldorf_goggles = [_]types.CozyEffect{.{
    .cozy = .snow_goggles,
    .duration_ms = 15000,
    .stack_intensity = 1,
}};

const waldorf_slippery = [_]types.ChillEffect{.{
    .chill = .slippery,
    .duration_ms = 5000,
    .stack_intensity = 1,
}};

const waldorf_insulated = [_]types.CozyEffect{.{
    .cozy = .insulated,
    .duration_ms = 12000,
    .stack_intensity = 1,
}};

const waldorf_bundled = [_]types.CozyEffect{.{
    .cozy = .bundled_up,
    .duration_ms = 10000,
    .stack_intensity = 1,
}};

pub const skills = [_]Skill{
    // 1. Rhythm buff - core mechanic
    .{
        .name = "Find Your Rhythm",
        .description = "Stance. (15 seconds.) Alternating skill types recharge 50% faster and build Rhythm.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 5,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 20000,
        .duration_ms = 15000,
        .grants_rhythm_on_cast = 1,
        // TODO: Alternating skill types recharge 50% faster
    },

    // 2. Team heal - harmony
    .{
        .name = "Circle Time",
        .description = "Call. Heals party members for 30 Warmth.",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 10,
        .healing = 30.0,
        .cast_range = 250.0,
        .target_type = .ally,
        .aoe_type = .area,
        .aoe_radius = 250.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 25000,
        .grants_rhythm_on_cast = 1,
    },

    // 3. Timing-based damage - costs rhythm stacks
    .{
        .name = "Perfect Pitch",
        .description = "Throw. Requires 5 Rhythm. Costs no energy. Deals 20 damage.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 0,
        .requires_rhythm_stacks = 5,
        .damage = 20.0,
        .cast_range = 200.0,
        .activation_time_ms = 750,
        .aftercast_ms = 750,
        .recharge_time_ms = 8000,
    },

    // 4. Support buff
    .{
        .name = "Group Harmony",
        .description = "Call. (12 seconds.) Party members have Hot Cocoa regeneration.",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 8,
        .cast_range = 250.0,
        .target_type = .ally,
        .aoe_type = .area,
        .aoe_radius = 250.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 20000,
        .duration_ms = 12000,
        .cozies = &waldorf_hot_cocoa,
        .grants_rhythm_on_cast = 1,
    },

    // 5. Reactive skill - rhythmic movement
    .{
        .name = "Eurythmy",
        .description = "Stance. (8 seconds.) Move 25% faster. Your next skill activates instantly if you have 3+ Rhythm.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 5,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 15000,
        .duration_ms = 8000,
        .grants_rhythm_on_cast = 1,
        // TODO: Next skill instant cast if 3+ rhythm
    },

    // 6. Artistic trick - control
    .{
        .name = "Flowing Motion",
        .description = "Trick. Deals 10 damage. Inflicts Slippery (5 seconds).",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 7,
        .damage = 10.0,
        .cast_range = 200.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 12000,
        .chills = &waldorf_slippery,
        .grants_rhythm_on_cast = 1,
    },

    // 7. Vision support
    .{
        .name = "Clear Mind",
        .description = "Call. (15 seconds.) Party members gain Snow Goggles.",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 6,
        .cast_range = 250.0,
        .target_type = .ally,
        .aoe_type = .area,
        .aoe_radius = 250.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 25000,
        .duration_ms = 15000,
        .cozies = &waldorf_goggles,
        .grants_rhythm_on_cast = 1,
    },

    // 8. Rhythm finisher - builds with each skill
    .{
        .name = "Crescendo",
        .description = "Elite Trick. Deals 20 damage +5 damage per Rhythm stack. Consumes all Rhythm.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 8,
        .damage = 20.0,
        .cast_range = 220.0,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 15000,
        .consumes_all_rhythm = true,
        .damage_per_rhythm_consumed = 5.0,
    },

    // 9. WALL: Harmonic Wall - rhythmic wall that pulses
    .{
        .name = "Harmonic Wall",
        .description = "Call. Build a resonant wall. Grants 1 Rhythm on cast. Party members near the wall gain Hot Cocoa regeneration.",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 9,
        .target_type = .ground,
        .cast_range = 140.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 22000,
        .creates_wall = true,
        .wall_length = 65.0,
        .wall_height = 32.0,
        .wall_thickness = 20.0,
        .wall_distance_from_caster = 45.0,
        .grants_rhythm_on_cast = 1,
        .cozies = &waldorf_hot_cocoa, // Healing aura near wall
        // TODO: AOE healing aura around the wall for allies
    },

    // 10. Tempo Change - speed manipulation
    .{
        .name = "Tempo Change",
        .description = "Call. Requires 3 Rhythm. For 8 seconds, allies move 25% faster, enemies move 15% slower.",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 8,
        .requires_rhythm_stacks = 3,
        .target_type = .ally,
        .aoe_type = .area,
        .aoe_radius = 250.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 20000,
        .duration_ms = 8000,
        .grants_rhythm_on_cast = 1,
    },

    // 11. Syncopation - interrupt and gain rhythm
    .{
        .name = "Syncopation",
        .description = "Throw. Deals 12 damage. Interrupts. Gain 2 Rhythm on successful interrupt.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 6,
        .damage = 12.0,
        .cast_range = 200.0,
        .activation_time_ms = 500,
        .aftercast_ms = 750,
        .recharge_time_ms = 10000,
        .interrupts = true,
        .grants_rhythm_on_cast = 2,
    },

    // 12. Meditative State - energy recovery through rhythm
    .{
        .name = "Meditative State",
        .description = "Stance. (12 seconds.) Gain +2 energy per second. +1 additional per Rhythm stack.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 5,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 25000,
        .duration_ms = 12000,
        .cozies = &waldorf_insulated,
        .grants_rhythm_on_cast = 1,
    },

    // 13. Ensemble Cast - team rhythm sharing
    .{
        .name = "Ensemble Cast",
        .description = "Call. All allies gain 2 Rhythm. For 10 seconds, when any ally gains Rhythm, all allies gain 1.",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 10,
        .target_type = .ally,
        .aoe_type = .area,
        .aoe_radius = 300.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 30000,
        .duration_ms = 10000,
    },

    // 14. Graceful Recovery - defensive rhythm skill
    .{
        .name = "Graceful Recovery",
        .description = "Stance. (10 seconds.) Take 25% less damage. Gain 1 Rhythm when hit.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 5,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 18000,
        .duration_ms = 10000,
        .cozies = &waldorf_bundled,
    },

    // 15. Harmonic Resonance - AoE damage based on rhythm
    .{
        .name = "Harmonic Resonance",
        .description = "Trick. Requires 4 Rhythm. Deals 15 damage to all foes in area +3 per Rhythm. Consumes all Rhythm.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 10,
        .requires_rhythm_stacks = 4,
        .damage = 15.0,
        .cast_range = 200.0,
        .aoe_type = .area,
        .aoe_radius = 150.0,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 20000,
        .consumes_all_rhythm = true,
        .damage_per_rhythm_consumed = 3.0,
    },

    // 16. Perfect Form - ultimate rhythm expression
    .{
        .name = "Perfect Form",
        .description = "Stance. Requires 6 Rhythm. (10 seconds.) Skills cost no energy and recharge 50% faster.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 0,
        .requires_rhythm_stacks = 6,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 45000,
        .duration_ms = 10000,
    },

    // ========================================================================
    // WALDORF AP SKILLS (4 AP skills for 20% of 20 total)
    // ========================================================================

    // AP 1: Symphony of Snow - massive team coordination
    .{
        .name = "Symphony of Snow",
        .description = "[AP] Call. For 20 seconds, whenever any ally uses a skill, all allies gain 1 Rhythm and 2 energy.",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 15,
        .target_type = .ally,
        .aoe_type = .area,
        .aoe_radius = 400.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 60000,
        .duration_ms = 20000,
        .is_ap = true,
    },

    // AP 2: Tempo Mastery - rhythm becomes permanent during stance
    .{
        .name = "Tempo Mastery",
        .description = "[AP] Stance. (30 seconds.) Rhythm does not decay. Each Rhythm grants +5% damage, +5% speed, and +5% cooldown reduction.",
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

    // AP 3: Resonant Link - share rhythm benefits with ally
    .{
        .name = "Resonant Link",
        .description = "[AP] Link with target ally for 30 seconds. You share Rhythm stacks. Skills that grant Rhythm grant to both.",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 10,
        .target_type = .ally,
        .cast_range = 200.0,
        .activation_time_ms = 500,
        .aftercast_ms = 500,
        .recharge_time_ms = 40000,
        .duration_ms = 30000,
        .is_ap = true,
    },

    // AP 4: Grand Finale - ultimate rhythm finisher
    .{
        .name = "Grand Finale",
        .description = "[AP] Trick. Requires 8 Rhythm. Deals 20 damage +10 per Rhythm to all foes in area. Heals all allies for same amount. Consumes all Rhythm.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 15,
        .requires_rhythm_stacks = 8,
        .damage = 20.0,
        .healing = 20.0,
        .cast_range = 250.0,
        .aoe_type = .area,
        .aoe_radius = 200.0,
        .activation_time_ms = 2000,
        .aftercast_ms = 750,
        .recharge_time_ms = 50000,
        .consumes_all_rhythm = true,
        .damage_per_rhythm_consumed = 10.0,
        .is_ap = true,
    },
};
