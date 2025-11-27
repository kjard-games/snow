const types = @import("../types.zig");
const effects = @import("../../effects.zig");
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

// ============================================================================
// EFFECT DEFINITIONS - Composable effects for complex skill mechanics
// ============================================================================

// Tackle (skill 6): Knockdown effect for 4 seconds
const tackle_knockdown_mods = [_]effects.Modifier{.{
    .effect_type = .knockdown,
    .value = .{ .int = 1 },
}};

const TACKLE_KNOCKDOWN_EFFECT = effects.Effect{
    .name = "Knocked Down",
    .description = "Tackled to the ground - can't act",
    .modifiers = &tackle_knockdown_mods,
    .timing = .on_hit,
    .affects = .target,
    .duration_ms = 4000,
    .is_buff = false,
};

const tackle_effects = [_]effects.Effect{TACKLE_KNOCKDOWN_EFFECT};

// All Out (skill 8): Take double damage for 5 seconds (self-debuff)
const all_out_vulnerability_mods = [_]effects.Modifier{.{
    .effect_type = .damage_multiplier,
    .value = .{ .float = 2.0 }, // Take 2x damage
}};

const ALL_OUT_VULNERABILITY_EFFECT = effects.Effect{
    .name = "All Out",
    .description = "Overextended - take double damage",
    .modifiers = &all_out_vulnerability_mods,
    .timing = .on_cast, // Applied when skill is cast
    .affects = .self,
    .duration_ms = 5000,
    .is_buff = false,
};

const all_out_effects = [_]effects.Effect{ALL_OUT_VULNERABILITY_EFFECT};

// Second Wind (skill 14): Next attack +10 damage
const second_wind_mods = [_]effects.Modifier{.{
    .effect_type = .next_attack_damage_add,
    .value = .{ .float = 10.0 },
}};

const SECOND_WIND_BUFF_EFFECT = effects.Effect{
    .name = "Second Wind",
    .description = "Next attack deals +10 damage",
    .modifiers = &second_wind_mods,
    .timing = .on_cast,
    .affects = .self,
    .duration_ms = 15000, // Expires after 15s if not used
    .is_buff = true,
};

const second_wind_effects = [_]effects.Effect{SECOND_WIND_BUFF_EFFECT};

// Brawler's Stance (skill 15): Take 20% less damage, gain 1 Grit when hit
const brawlers_stance_mods = [_]effects.Modifier{
    .{
        .effect_type = .damage_multiplier,
        .value = .{ .float = 0.8 }, // Take 20% less damage (0.8x)
    },
    .{
        .effect_type = .grit_on_take_damage,
        .value = .{ .float = 1.0 }, // Gain 1 Grit when hit
    },
};

const BRAWLERS_STANCE_EFFECT = effects.Effect{
    .name = "Brawler's Stance",
    .description = "Take 20% less damage. Gain 1 Grit when hit.",
    .modifiers = &brawlers_stance_mods,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 8000,
    .is_buff = true,
};

const brawlers_stance_effects = [_]effects.Effect{BRAWLERS_STANCE_EFFECT};

// Never Give Up (skill 16): Remove all chills from self
const never_give_up_mods = [_]effects.Modifier{.{
    .effect_type = .remove_all_chills,
    .value = .{ .int = 1 },
}};

const NEVER_GIVE_UP_EFFECT = effects.Effect{
    .name = "Never Give Up",
    .description = "Remove all Chills",
    .modifiers = &never_give_up_mods,
    .timing = .on_cast,
    .affects = .self,
    .duration_ms = 0, // Instant
    .is_buff = true,
};

const never_give_up_effects = [_]effects.Effect{NEVER_GIVE_UP_EFFECT};

// Berserker Rage (AP 1): +75% damage, +50% attack speed, +25% damage taken, +2 grit/sec
const berserker_rage_mods = [_]effects.Modifier{
    .{
        .effect_type = .damage_multiplier,
        .value = .{ .float = 1.75 }, // Deal 75% more damage
    },
    .{
        .effect_type = .attack_speed_multiplier,
        .value = .{ .float = 1.5 }, // Attack 50% faster
    },
    .{
        .effect_type = .armor_multiplier,
        .value = .{ .float = 0.75 }, // Take 25% more damage (armor reduced)
    },
    .{
        .effect_type = .grit_gain_per_second,
        .value = .{ .float = 2.0 }, // Gain 2 Grit per second
    },
};

const BERSERKER_RAGE_EFFECT = effects.Effect{
    .name = "Berserker Rage",
    .description = "+75% damage, +50% attack speed, take 25% more damage, gain 2 Grit/sec",
    .modifiers = &berserker_rage_mods,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 15000,
    .is_buff = true,
};

const berserker_rage_effects = [_]effects.Effect{BERSERKER_RAGE_EFFECT};

// Unstoppable Force (AP 4): Immune to CC, +25% damage, -2 warmth/sec
const unstoppable_force_mods = [_]effects.Modifier{
    .{
        .effect_type = .immune_to_interrupt,
        .value = .{ .int = 1 },
    },
    .{
        .effect_type = .immune_to_knockdown,
        .value = .{ .int = 1 },
    },
    .{
        .effect_type = .immune_to_slow,
        .value = .{ .int = 1 },
    },
    .{
        .effect_type = .damage_multiplier,
        .value = .{ .float = 1.25 }, // Deal 25% more damage
    },
    .{
        .effect_type = .warmth_drain_per_second,
        .value = .{ .float = 2.0 }, // Lose 2 Warmth per second
    },
};

const UNSTOPPABLE_FORCE_EFFECT = effects.Effect{
    .name = "Unstoppable Force",
    .description = "Cannot be interrupted, knocked down, or slowed. +25% damage. Lose 2 Warmth/sec.",
    .modifiers = &unstoppable_force_mods,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 20000,
    .is_buff = true,
};

const unstoppable_force_effects = [_]effects.Effect{UNSTOPPABLE_FORCE_EFFECT};

// Underdog (skill 12): +3 Grit per second while outnumbered
const underdog_mods = [_]effects.Modifier{.{
    .effect_type = .grit_gain_per_second,
    .value = .{ .float = 3.0 },
}};

const UNDERDOG_EFFECT = effects.Effect{
    .name = "Underdog",
    .description = "Gain 3 Grit per second while outnumbered",
    .modifiers = &underdog_mods,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 12000,
    .is_buff = true,
    .condition = .if_caster_outnumbered,
};

const underdog_effects = [_]effects.Effect{UNDERDOG_EFFECT};

// Pile On (skill 5): +10 damage if target has a chill
const pile_on_bonus_mods = [_]effects.Modifier{.{
    .effect_type = .damage_add,
    .value = .{ .float = 10.0 },
}};

const PILE_ON_BONUS_EFFECT = effects.Effect{
    .name = "Pile On",
    .description = "+10 damage if target has a Chill",
    .modifiers = &pile_on_bonus_mods,
    .timing = .on_hit,
    .affects = .target,
    .duration_ms = 0, // Instant
    .is_buff = false,
    .condition = .if_target_has_any_chill,
};

const pile_on_effects = [_]effects.Effect{PILE_ON_BONUS_EFFECT};

// Relentless (skill 4): Recharges instantly if it hits
const relentless_mods = [_]effects.Modifier{.{
    .effect_type = .recharge_on_hit,
    .value = .{ .int = 1 },
}};

const RELENTLESS_EFFECT = effects.Effect{
    .name = "Relentless",
    .description = "Recharges instantly if it hits",
    .modifiers = &relentless_mods,
    .timing = .on_hit,
    .affects = .self,
    .duration_ms = 0, // Instant
    .is_buff = true,
};

const relentless_effects = [_]effects.Effect{RELENTLESS_EFFECT};

// Final Push (AP 2): consumes all grit, bonus damage per grit, reset on kill
// Note: Uses skill fields for grit mechanics, effect only handles the recharge_on_kill
const final_push_mods = [_]effects.Modifier{.{
    .effect_type = .recharge_on_kill,
    .value = .{ .int = 1 },
}};

const FINAL_PUSH_EFFECT = effects.Effect{
    .name = "Final Push",
    .description = "Resets cooldown if target dies",
    .modifiers = &final_push_mods,
    .timing = .on_hit,
    .affects = .self,
    .duration_ms = 0, // Instant
    .is_buff = true,
    .condition = .if_target_died,
};

const final_push_effects = [_]effects.Effect{FINAL_PUSH_EFFECT};

// Rally the Troops (AP 3): Team grit buff + grit on ally hits
// Note: grit_gain_per_second approximates "gain grit when allies hit"
const rally_the_troops_mods = [_]effects.Modifier{.{
    .effect_type = .grit_gain_per_second,
    .value = .{ .float = 0.5 }, // Passive grit generation while buff is active
}};

const RALLY_THE_TROOPS_EFFECT = effects.Effect{
    .name = "Rally the Troops",
    .description = "All allies generate Grit over time",
    .modifiers = &rally_the_troops_mods,
    .timing = .while_active,
    .affects = .allies_in_earshot,
    .duration_ms = 12000,
    .is_buff = true,
};

const rally_the_troops_effects = [_]effects.Effect{RALLY_THE_TROOPS_EFFECT};

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
        .effects = &relentless_effects,
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
        .effects = &pile_on_effects,
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
        .effects = &tackle_effects,
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
        .effects = &all_out_effects,
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
        .effects = &underdog_effects,
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
        .effects = &second_wind_effects,
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
        .effects = &brawlers_stance_effects,
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
        .effects = &never_give_up_effects,
        // TODO: Gain 2 energy per chill removed (requires runtime counting)
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
        .effects = &berserker_rage_effects,
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
        .requires_grit_stacks = 5,
        .consumes_all_grit = true,
        .damage_per_grit_consumed = 8.0,
        .effects = &final_push_effects,
    },

    // AP 3: Rally the Troops - team grit sharing
    .{
        .name = "Rally the Troops",
        .description = "[AP] Call. All allies gain 5 Grit. For 12 seconds, allies passively generate Grit.",
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
        .grants_grit_to_allies_on_cast = 5,
        .effects = &rally_the_troops_effects,
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
        .effects = &unstoppable_force_effects,
    },
};
