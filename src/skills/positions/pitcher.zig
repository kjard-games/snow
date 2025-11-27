const types = @import("../types.zig");
const Skill = types.Skill;
const effects = @import("../../effects.zig");

// ============================================================================
// PITCHER SKILLS - Long-range damage dealer (200-300 range)
// ============================================================================
// Synergizes with: Throw buffs, damage amplifiers, energy management
// Counterplay: Close the gap, interrupt long casts, drain energy

const windburn_chill = [_]types.ChillEffect{.{
    .chill = .windburn,
    .duration_ms = 5000,
    .stack_intensity = 1,
}};

const soggy_chill = [_]types.ChillEffect{.{
    .chill = .soggy,
    .duration_ms = 6000,
    .stack_intensity = 1,
}};

const pitcher_fire = [_]types.CozyEffect{.{
    .cozy = .fire_inside,
    .duration_ms = 10000,
    .stack_intensity = 1,
}};

const pitcher_frost_eyes = [_]types.ChillEffect{.{
    .chill = .frost_eyes,
    .duration_ms = 4000,
    .stack_intensity = 1,
}};

// ============================================================================
// EFFECT DEFINITIONS
// ============================================================================

// Ice Fastball - +15 damage if target has any chill
const ice_fastball_bonus_mods = [_]effects.Modifier{.{
    .effect_type = .damage_add,
    .value = .{ .float = 15.0 },
}};

const ICE_FASTBALL_BONUS = effects.Effect{
    .name = "Chill Exploit",
    .description = "+15 damage to chilled targets",
    .modifiers = &ice_fastball_bonus_mods,
    .timing = .on_hit,
    .affects = .target,
    .condition = .if_target_has_any_chill,
    .duration_ms = 0,
    .is_buff = false,
};

const ice_fastball_effects = [_]effects.Effect{ICE_FASTBALL_BONUS};

// Headshot - +20 damage if target below 50% warmth
const headshot_bonus_mods = [_]effects.Modifier{.{
    .effect_type = .damage_add,
    .value = .{ .float = 20.0 },
}};

const HEADSHOT_BONUS = effects.Effect{
    .name = "Execute",
    .description = "+20 damage to low warmth targets",
    .modifiers = &headshot_bonus_mods,
    .timing = .on_hit,
    .affects = .target,
    .condition = .if_target_below_50_percent_warmth,
    .duration_ms = 0,
    .is_buff = false,
};

const headshot_effects = [_]effects.Effect{HEADSHOT_BONUS};

// Pitcher's Focus - +25% damage buff
const pitchers_focus_mods = [_]effects.Modifier{.{
    .effect_type = .damage_multiplier,
    .value = .{ .float = 1.25 },
}};

const PITCHERS_FOCUS_EFFECT = effects.Effect{
    .name = "Pitcher's Focus",
    .description = "+25% throw damage",
    .modifiers = &pitchers_focus_mods,
    .timing = .while_active,
    .affects = .self,
    .condition = .always,
    .duration_ms = 12000,
    .is_buff = true,
};

const pitchers_focus_effects = [_]effects.Effect{PITCHERS_FOCUS_EFFECT};

// Called Shot - +15 damage if target below 50% warmth
const called_shot_bonus_mods = [_]effects.Modifier{.{
    .effect_type = .damage_add,
    .value = .{ .float = 15.0 },
}};

const CALLED_SHOT_BONUS = effects.Effect{
    .name = "Perfect Shot",
    .description = "+15 damage to low warmth targets",
    .modifiers = &called_shot_bonus_mods,
    .timing = .on_hit,
    .affects = .target,
    .condition = .if_target_below_50_percent_warmth,
    .duration_ms = 0,
    .is_buff = false,
};

const called_shot_effects = [_]effects.Effect{CALLED_SHOT_BONUS};

// Perfect Game - recharge on kill
const perfect_game_mods = [_]effects.Modifier{.{
    .effect_type = .recharge_on_kill,
    .value = .{ .int = 1 },
}};

const PERFECT_GAME_EFFECT = effects.Effect{
    .name = "Perfect Game Reset",
    .description = "Reset cooldown if target dies",
    .modifiers = &perfect_game_mods,
    .timing = .on_kill,
    .affects = .self,
    .condition = .if_target_died,
    .duration_ms = 0,
    .is_buff = true,
};

const perfect_game_effects = [_]effects.Effect{PERFECT_GAME_EFFECT};

// Gatling Arm - no cast time, instant recharge, but fixed 8 damage
const gatling_arm_mods = [_]effects.Modifier{
    .{
        .effect_type = .cast_speed_multiplier,
        .value = .{ .float = 100.0 }, // Effectively instant
    },
    .{
        .effect_type = .cooldown_reduction_percent,
        .value = .{ .float = 1.0 }, // 100% CDR = instant recharge
    },
};

const GATLING_ARM_EFFECT = effects.Effect{
    .name = "Gatling Arm",
    .description = "Throws have no cast time and recharge instantly",
    .modifiers = &gatling_arm_mods,
    .timing = .while_active,
    .affects = .self,
    .condition = .always,
    .duration_ms = 10000,
    .is_buff = true,
};

const gatling_arm_effects = [_]effects.Effect{GATLING_ARM_EFFECT};

// Sniper's Eye - double damage, 100% soak on next throw
const snipers_eye_mods = [_]effects.Modifier{
    .{
        .effect_type = .next_attack_damage_multiplier,
        .value = .{ .float = 2.0 },
    },
};

const SNIPERS_EYE_EFFECT = effects.Effect{
    .name = "Sniper's Eye",
    .description = "Next throw deals double damage and soaks all padding",
    .modifiers = &snipers_eye_mods,
    .timing = .while_active,
    .affects = .self,
    .condition = .always,
    .duration_ms = 20000,
    .is_buff = true,
};

const snipers_eye_effects = [_]effects.Effect{SNIPERS_EYE_EFFECT};

// Curveball - 50% chance to be unblockable
const curveball_mods = [_]effects.Modifier{.{
    .effect_type = .unblockable_chance,
    .value = .{ .float = 0.50 }, // 50% unblockable
}};

const CURVEBALL_EFFECT = effects.Effect{
    .name = "Curveball",
    .description = "50% chance to be unblockable",
    .modifiers = &curveball_mods,
    .timing = .on_hit,
    .affects = .target,
    .condition = .always,
    .duration_ms = 0,
    .is_buff = false,
};

const curveball_effects = [_]effects.Effect{CURVEBALL_EFFECT};

// Artillery Strike - massive AoE
const artillery_strike_mods = [_]effects.Modifier{.{
    .effect_type = .ignore_cover,
    .value = .{ .int = 1 },
}};

const ARTILLERY_STRIKE_EFFECT = effects.Effect{
    .name = "Artillery Strike",
    .description = "Arcs over walls and cover",
    .modifiers = &artillery_strike_mods,
    .timing = .on_hit,
    .affects = .target,
    .condition = .always,
    .duration_ms = 0,
    .is_buff = false,
};

const artillery_strike_effects = [_]effects.Effect{ARTILLERY_STRIKE_EFFECT};

// ============================================================================
// INTERRUPT/PUNISHMENT EFFECT DEFINITIONS
// ============================================================================

// Punishing Throw - target loses 8 energy on successful interrupt
const punishing_throw_mods = [_]effects.Modifier{.{
    .effect_type = .energy_burn_on_interrupt,
    .value = .{ .float = 8.0 },
}};

const PUNISHING_THROW_EFFECT = effects.Effect{
    .name = "Punishing Interrupt",
    .description = "Target loses 8 energy if interrupted",
    .modifiers = &punishing_throw_mods,
    .timing = .on_interrupt,
    .affects = .target,
    .condition = .if_this_skill_interrupted,
    .duration_ms = 0,
    .is_buff = false,
};

const punishing_throw_effects = [_]effects.Effect{PUNISHING_THROW_EFFECT};

// Distracting Throw - disable interrupted skill for 15 seconds
const distracting_throw_mods = [_]effects.Modifier{.{
    .effect_type = .skill_disable_duration_ms,
    .value = .{ .int = 15000 },
}};

const DISTRACTING_THROW_EFFECT = effects.Effect{
    .name = "Skill Disruption",
    .description = "Interrupted skill disabled for 15 seconds",
    .modifiers = &distracting_throw_mods,
    .timing = .on_interrupt,
    .affects = .target,
    .condition = .if_this_skill_interrupted,
    .duration_ms = 0,
    .is_buff = false,
};

const distracting_throw_effects = [_]effects.Effect{DISTRACTING_THROW_EFFECT};

// Tracking Shot - +12 damage if target is moving
const tracking_shot_mods = [_]effects.Modifier{.{
    .effect_type = .damage_if_target_moving,
    .value = .{ .float = 12.0 },
}};

const TRACKING_SHOT_EFFECT = effects.Effect{
    .name = "Moving Target Bonus",
    .description = "+12 damage if target is moving",
    .modifiers = &tracking_shot_mods,
    .timing = .on_hit,
    .affects = .target,
    .condition = .if_target_moving,
    .duration_ms = 0,
    .is_buff = false,
};

const tracking_shot_effects = [_]effects.Effect{TRACKING_SHOT_EFFECT};

// Concussion Throw - apply Dazed for 5 seconds on interrupt
const concussion_throw_mods = [_]effects.Modifier{.{
    .effect_type = .daze_on_interrupt_duration_ms,
    .value = .{ .int = 5000 },
}};

const CONCUSSION_THROW_EFFECT = effects.Effect{
    .name = "Concussion",
    .description = "Target is Dazed for 5 seconds if interrupted",
    .modifiers = &concussion_throw_mods,
    .timing = .on_interrupt,
    .affects = .target,
    .condition = .if_this_skill_interrupted,
    .duration_ms = 0,
    .is_buff = false,
};

const concussion_throw_effects = [_]effects.Effect{CONCUSSION_THROW_EFFECT};

// Silencing Strike - apply 8s Daze if target was casting
const silencing_strike_mods = [_]effects.Modifier{.{
    .effect_type = .daze_on_interrupt_duration_ms,
    .value = .{ .int = 8000 },
}};

const SILENCING_STRIKE_EFFECT = effects.Effect{
    .name = "Silencing Strike",
    .description = "Target is Dazed for 8 seconds if they were casting",
    .modifiers = &silencing_strike_mods,
    .timing = .on_interrupt,
    .affects = .target,
    .condition = .if_target_was_interrupted,
    .duration_ms = 0,
    .is_buff = false,
};

const silencing_strike_effects = [_]effects.Effect{SILENCING_STRIKE_EFFECT};

// Pitcher's Mound - damage bonus on elevated terrain
const pitchers_mound_mods = [_]effects.Modifier{.{
    .effect_type = .damage_bonus_on_elevated,
    .value = .{ .float = 10.0 }, // +10 damage when on elevated terrain
}};

const PITCHERS_MOUND_EFFECT = effects.Effect{
    .name = "High Ground",
    .description = "+10 damage when on elevated terrain",
    .modifiers = &pitchers_mound_mods,
    .timing = .while_active,
    .affects = .self,
    .condition = .always, // Terrain check happens at damage time
    .duration_ms = 30000, // Mound persists for 30s
    .is_buff = true,
};

const pitchers_mound_effects = [_]effects.Effect{PITCHERS_MOUND_EFFECT};

pub const skills = [_]Skill{
    // 1. Fast, reliable damage - your bread and butter
    .{
        .name = "Fastball",
        .description = "Throw. Deals 18 damage.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 5,
        .damage = 18.0,
        .cast_range = 250.0,
        .activation_time_ms = 750,
        .aftercast_ms = 750,
        .recharge_time_ms = 4000,
    },

    // 2. Conditional burst - high damage if target is chilled
    .{
        .name = "Ice Fastball",
        .description = "Throw. Deals 15 damage. Deals +15 damage if target foe has a chill.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 8,
        .damage = 15.0, // +15 more if target has a chill = 30 total
        .cast_range = 250.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 8000,
        .effects = &ice_fastball_effects,
    },

    // 3. AoE pressure - hits adjacent foes
    .{
        .name = "Slushball Barrage",
        .description = "Throw. Deals 12 damage to target and adjacent foes. Inflicts Soggy condition (6 seconds).",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 10,
        .damage = 12.0,
        .cast_range = 260.0,
        .activation_time_ms = 1250,
        .aftercast_ms = 750,
        .recharge_time_ms = 12000,
        .aoe_type = .adjacent,
        .chills = &soggy_chill,
    },

    // 4. Interrupt tool - fast cast, low damage, disrupts
    .{
        .name = "Snipe",
        .description = "Throw. Interrupts an action. Deals 10 damage.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 7,
        .damage = 10.0,
        .cast_range = 280.0,
        .activation_time_ms = 500,
        .aftercast_ms = 750,
        .recharge_time_ms = 10000,
        .interrupts = true,
    },

    // 5. Maximum range poke - safe but slow, arcs over walls
    .{
        .name = "Lob",
        .description = "Throw. Deals 14 damage. Maximum range. Arcs over walls (ignores cover).",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 6,
        .damage = 14.0,
        .cast_range = 300.0,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 6000,
        .projectile_type = .arcing, // Ignores cover
    },

    // 6. Execute - bonus damage vs low health
    .{
        .name = "Headshot",
        .description = "Throw. Deals 20 damage. Deals +20 damage if target foe is below 50% Health. Soaks through half their padding.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 12,
        .damage = 20.0, // +20 more if target below 50% = 40 total
        .cast_range = 240.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 15000,
        .soak = 0.5,
        .effects = &headshot_effects,
    },

    // 7. DoT application - sustained pressure
    .{
        .name = "Windburn Throw",
        .description = "Throw. Deals 10 damage. Inflicts Windburn condition (5 seconds).",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 8,
        .damage = 10.0,
        .cast_range = 250.0,
        .activation_time_ms = 750,
        .aftercast_ms = 750,
        .recharge_time_ms = 8000,
        .chills = &windburn_chill,
    },

    // 8. Energy efficient spam - low cost, low cooldown
    .{
        .name = "Quick Toss",
        .description = "Throw. Deals 12 damage.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 3,
        .damage = 12.0,
        .cast_range = 220.0,
        .activation_time_ms = 500,
        .aftercast_ms = 750,
        .recharge_time_ms = 3000,
    },

    // 9. TERRAIN: Powder Burst - create deep snow at range
    .{
        .name = "Powder Burst",
        .description = "Throw. Deals 8 damage. Creates deep powder on impact, slowing foes in the area.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 10,
        .damage = 8.0,
        .cast_range = 280.0,
        .target_type = .ground,
        .aoe_radius = 80.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 15000,
        .terrain_effect = types.TerrainEffect.deepSnow(.circle),
    },

    // 10. TERRAIN: Ice Shot - create icy ground at range
    .{
        .name = "Ice Shot",
        .description = "Throw. Creates an icy patch. Foes on ice move faster but are easier to knock down.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 8,
        .cast_range = 250.0,
        .target_type = .ground,
        .aoe_radius = 70.0,
        .activation_time_ms = 1250,
        .aftercast_ms = 750,
        .recharge_time_ms = 20000,
        .terrain_effect = types.TerrainEffect.ice(.circle),
    },

    // 11. WALL BREAKER: Demolition - destroy walls with powerful AOE
    .{
        .name = "Demolition",
        .description = "Trick. Deals 25 damage in area. Deals triple damage to walls.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 12,
        .damage = 25.0,
        .cast_range = 260.0,
        .target_type = .ground,
        .aoe_type = .area,
        .aoe_radius = 100.0,
        .activation_time_ms = 2000,
        .aftercast_ms = 750,
        .recharge_time_ms = 25000,
        .destroys_walls = true,
        .wall_damage_multiplier = 3.0,
    },

    // 12. WALL: Pitcher's Mound - elevated pitching platform
    .{
        .name = "Pitcher's Mound",
        .description = "Gesture. Build an elevated mound. Grants high ground advantage (+10 damage from elevated terrain).",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 8,
        .target_type = .ground,
        .cast_range = 150.0, // Increased for ground targeting
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 25000,
        .creates_wall = true,
        .wall_length = 80.0, // Increased from 40 - more useful mound
        .wall_height = 20.0,
        .wall_thickness = 30.0, // Wider base
        .wall_distance_from_caster = 20.0, // Legacy field (unused with ground targeting)
        .terrain_effect = types.TerrainEffect.packedSnow(.circle),
        .aoe_radius = 40.0,
        .effects = &pitchers_mound_effects,
    },

    // 13. Curveball - hard to block
    .{
        .name = "Curveball",
        .description = "Throw. Deals 16 damage. 50% chance to be unblockable.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 6,
        .damage = 16.0,
        .cast_range = 240.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 6000,
        .effects = &curveball_effects,
    },

    // 14. Blinding Throw - utility
    .{
        .name = "Blinding Throw",
        .description = "Throw. Deals 10 damage. Inflicts Frost Eyes (4 seconds).",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 7,
        .damage = 10.0,
        .cast_range = 260.0,
        .activation_time_ms = 750,
        .aftercast_ms = 750,
        .recharge_time_ms = 12000,
        .chills = &pitcher_frost_eyes,
    },

    // 15. Pitcher's Focus - damage buff
    .{
        .name = "Pitcher's Focus",
        .description = "Stance. (12 seconds.) Your throws deal +25% damage and have +10% range.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 6,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 20000,
        .duration_ms = 12000,
        .cozies = &pitcher_fire,
        .effects = &pitchers_focus_effects,
    },

    // 16. Called Shot - bonus damage to marked target
    .{
        .name = "Perfect Shot",
        .description = "Throw. Deals 25 damage. +15 damage if target is below 50% Warmth.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 10,
        .damage = 25.0,
        .bonus_damage_if_foe_below_50_warmth = 15.0,
        .cast_range = 250.0,
        .activation_time_ms = 1250,
        .aftercast_ms = 750,
        .recharge_time_ms = 12000,
        .effects = &called_shot_effects,
    },

    // ========================================================================
    // PITCHER AP SKILLS (4 AP skills for 20% of 20 total)
    // ========================================================================

    // AP 1: Perfect Game - massive single-target damage
    .{
        .name = "Perfect Game",
        .description = "[AP] Throw. Deals 60 damage. Cannot be blocked or evaded. If target dies, reset cooldown.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 15,
        .damage = 60.0,
        .cast_range = 280.0,
        .activation_time_ms = 2000,
        .aftercast_ms = 750,
        .recharge_time_ms = 45000,
        .unblockable = true,
        .is_ap = true,
        .effects = &perfect_game_effects,
    },

    // AP 2: Gatling Arm - rapid fire mode
    .{
        .name = "Gatling Arm",
        .description = "[AP] Stance. (10 seconds.) Your throws have no cast time and recharge instantly, but deal only 8 damage.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 15,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 60000,
        .duration_ms = 10000,
        .is_ap = true,
        .effects = &gatling_arm_effects,
    },

    // AP 3: Artillery Strike - long range AoE
    .{
        .name = "Artillery Strike",
        .description = "[AP] Throw. Maximum range. Deals 30 damage to all foes in area. Arcs over walls.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 18,
        .damage = 30.0,
        .cast_range = 350.0,
        .target_type = .ground,
        .aoe_type = .area,
        .aoe_radius = 120.0,
        .activation_time_ms = 2500,
        .aftercast_ms = 750,
        .recharge_time_ms = 35000,
        .projectile_type = .arcing,
        .is_ap = true,
        .effects = &artillery_strike_effects,
    },

    // AP 4: Sniper's Eye - guaranteed critical on next throw
    .{
        .name = "Sniper's Eye",
        .description = "[AP] Stance. (20 seconds.) Your next throw deals double damage and soaks through all padding. After that throw, stance ends.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 10,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 40000,
        .duration_ms = 20000,
        .soak = 1.0,
        .is_ap = true,
        .effects = &snipers_eye_effects,
    },

    // ========================================================================
    // PITCHER MESMER-ANALOG SKILLS - Domination/Punishment Focus
    // ========================================================================
    // These skills punish enemies for casting and reward interrupt timing.
    // Pairs well with Waldorf for a "Domination Sniper" playstyle.

    // 17. Punishing Shot analog - bonus damage + energy loss on interrupt
    .{
        .name = "Punishing Throw",
        .description = "Throw. Deals 14 damage. Interrupts. If this interrupts, target loses 8 energy.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 8,
        .damage = 14.0,
        .cast_range = 260.0,
        .activation_time_ms = 500,
        .aftercast_ms = 750,
        .recharge_time_ms = 10000,
        .interrupts = true,
        .effects = &punishing_throw_effects,
    },

    // 18. Distracting Shot analog - disables skill on interrupt
    .{
        .name = "Distracting Throw",
        .description = "Throw. Deals 10 damage. Interrupts. If this interrupts, target's interrupted skill is disabled for 15 seconds.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 10,
        .damage = 10.0,
        .cast_range = 280.0,
        .activation_time_ms = 250,
        .aftercast_ms = 750,
        .recharge_time_ms = 15000,
        .interrupts = true,
        .effects = &distracting_throw_effects,
    },

    // 19. Savage Shot analog - bonus damage if target moving
    .{
        .name = "Tracking Shot",
        .description = "Throw. Deals 16 damage. Deals +12 damage if target is moving. Cannot be blocked.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 7,
        .damage = 16.0,
        .cast_range = 270.0,
        .activation_time_ms = 750,
        .aftercast_ms = 750,
        .recharge_time_ms = 8000,
        .unblockable = true,
        .effects = &tracking_shot_effects,
    },

    // 20. Concussion Shot analog - daze on interrupt
    .{
        .name = "Concussion Throw",
        .description = "Throw. Deals 12 damage. Interrupts. If this interrupts, target is Dazed for 5 seconds.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 9,
        .damage = 12.0,
        .cast_range = 250.0,
        .activation_time_ms = 500,
        .aftercast_ms = 750,
        .recharge_time_ms = 12000,
        .interrupts = true,
        .effects = &concussion_throw_effects,
    },

    // AP 5: Broad Head Arrow analog - daze on any hit while casting
    .{
        .name = "Silencing Strike",
        .description = "[AP] Throw. Deals 20 damage. If target is casting, they are interrupted and Dazed for 8 seconds. Unblockable.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 15,
        .damage = 20.0,
        .cast_range = 280.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 25000,
        .interrupts = true,
        .unblockable = true,
        .is_ap = true,
        .effects = &silencing_strike_effects,
    },
};
