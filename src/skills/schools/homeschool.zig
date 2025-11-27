const types = @import("../types.zig");
const effects = @import("../../effects.zig");
const Skill = types.Skill;

// ============================================================================
// HOMESCHOOL SKILLS - Black: Sacrifice, Power, Isolation
// ============================================================================
// Theme: Pay health for power, devastating single-target, isolation bonuses
// Synergizes with: High damage, life sacrifice, solo play
// Cooldowns: 20-40s (long but devastating)

const homeschool_brain_freeze = [_]types.ChillEffect{.{
    .chill = .brain_freeze,
    .duration_ms = 10000,
    .stack_intensity = 1,
}};

const homeschool_packed = [_]types.ChillEffect{.{
    .chill = .packed_snow,
    .duration_ms = 12000,
    .stack_intensity = 1,
}};

const homeschool_fire = [_]types.CozyEffect{.{
    .cozy = .fire_inside,
    .duration_ms = 10000,
    .stack_intensity = 1,
}};

const homeschool_windburn = [_]types.ChillEffect{.{
    .chill = .windburn,
    .duration_ms = 8000,
    .stack_intensity = 1,
}};

const homeschool_numb = [_]types.ChillEffect{.{
    .chill = .numb,
    .duration_ms = 8000,
    .stack_intensity = 1,
}};

// ============================================================================
// EFFECT DEFINITIONS - Composable effects for complex skill mechanics
// ============================================================================

// Obsession (skill 6): +50% damage, -1 warmth/sec
const obsession_mods = [_]effects.Modifier{
    .{
        .effect_type = .damage_multiplier,
        .value = .{ .float = 1.5 }, // +50% damage
    },
    .{
        .effect_type = .warmth_drain_per_second,
        .value = .{ .float = 1.0 }, // Lose 1 Warmth per second
    },
};

const OBSESSION_EFFECT = effects.Effect{
    .name = "Obsession",
    .description = "+50% damage. Lose 1 Warmth per second.",
    .modifiers = &obsession_mods,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 12000,
    .is_buff = true,
};

const obsession_effects = [_]effects.Effect{OBSESSION_EFFECT};

// Solitary Strength (skill 12): +40% damage, -20% damage taken when isolated
const solitary_strength_mods = [_]effects.Modifier{
    .{
        .effect_type = .damage_multiplier,
        .value = .{ .float = 1.4 }, // +40% damage
    },
    .{
        .effect_type = .armor_multiplier,
        .value = .{ .float = 1.2 }, // Take 20% less damage (armor boost)
    },
};

const SOLITARY_STRENGTH_EFFECT = effects.Effect{
    .name = "Solitary Strength",
    .description = "+40% damage, take 20% less when no allies nearby",
    .modifiers = &solitary_strength_mods,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 20000,
    .is_buff = true,
    .condition = .if_caster_isolated,
};

const solitary_strength_effects = [_]effects.Effect{SOLITARY_STRENGTH_EFFECT};

// Self-Reliance (skill 14): Reduce max warmth by 10% permanently
// Note: This is a permanent debuff - the max_warmth_multiplier is permanent
const self_reliance_mods = [_]effects.Modifier{.{
    .effect_type = .max_warmth_multiplier,
    .value = .{ .float = 0.9 }, // -10% max warmth (permanent via long duration)
}};

const SELF_RELIANCE_EFFECT = effects.Effect{
    .name = "Self-Reliance Cost",
    .description = "-10% maximum Warmth",
    .modifiers = &self_reliance_mods,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 600000, // 10 minutes (effectively permanent for a match)
    .is_buff = false,
};

const self_reliance_effects = [_]effects.Effect{SELF_RELIANCE_EFFECT};

// Sugar Rush (AP 1): No energy cost, +30% damage
const sugar_rush_mods = [_]effects.Modifier{
    .{
        .effect_type = .energy_cost_multiplier,
        .value = .{ .float = 0.0 }, // Skills cost no energy
    },
    .{
        .effect_type = .damage_multiplier,
        .value = .{ .float = 1.3 }, // +30% damage
    },
    // Note: 5% warmth cost per skill requires runtime implementation
};

const SUGAR_RUSH_EFFECT = effects.Effect{
    .name = "Sugar Rush",
    .description = "Skills cost no energy but 5% Warmth. +30% damage.",
    .modifiers = &sugar_rush_mods,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 30000,
    .is_buff = true,
};

const sugar_rush_effects = [_]effects.Effect{SUGAR_RUSH_EFFECT};

// Lone Wolf (AP 4): +60% damage, +40% armor, +50% energy regen when isolated
const lone_wolf_mods = [_]effects.Modifier{
    .{
        .effect_type = .damage_multiplier,
        .value = .{ .float = 1.6 }, // +60% damage
    },
    .{
        .effect_type = .armor_multiplier,
        .value = .{ .float = 1.4 }, // +40% armor (less damage taken)
    },
    .{
        .effect_type = .energy_regen_multiplier,
        .value = .{ .float = 1.5 }, // +50% energy regen
    },
};

const LONE_WOLF_EFFECT = effects.Effect{
    .name = "Lone Wolf",
    .description = "+60% damage, +40% armor, +50% energy regen when isolated",
    .modifiers = &lone_wolf_mods,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 60000,
    .is_buff = true,
    .condition = .if_caster_isolated,
};

const lone_wolf_effects = [_]effects.Effect{LONE_WOLF_EFFECT};

// Desperate Gambit (AP 2): Damage = 50% of current warmth sacrificed
// Note: Actual damage calculation requires runtime, effect documents the mechanic
const desperate_gambit_mods = [_]effects.Modifier{.{
    .effect_type = .damage_multiplier,
    .value = .{ .float = 1.0 }, // Base multiplier, actual damage from warmth sacrifice
}};

const DESPERATE_GAMBIT_EFFECT = effects.Effect{
    .name = "Desperate Gambit",
    .description = "Deal damage equal to 50% of sacrificed Warmth",
    .modifiers = &desperate_gambit_mods,
    .timing = .on_cast,
    .affects = .target,
    .duration_ms = 0,
    .is_buff = false,
};

const desperate_gambit_effects = [_]effects.Effect{DESPERATE_GAMBIT_EFFECT};

// Infectious Isolation (AP 3): Apply chills to nearby foes when target takes damage
// This is simplified from "spread chills" to "apply chill debuffs to nearby foes"
const infectious_isolation_mods = [_]effects.Modifier{.{
    .effect_type = .damage_add, // Placeholder - main effect is via timing/affects
    .value = .{ .float = 0.0 },
}};

const INFECTIOUS_ISOLATION_EFFECT = effects.Effect{
    .name = "Infectious Isolation",
    .description = "When target takes damage, apply debuff to nearby foes",
    .modifiers = &infectious_isolation_mods,
    .timing = .on_take_damage,
    .affects = .foes_near_target,
    .duration_ms = 15000,
    .is_buff = false,
};

const infectious_isolation_effects = [_]effects.Effect{INFECTIOUS_ISOLATION_EFFECT};

// Cramming (skill 10): Next attack +50% damage
const dark_knowledge_mods = [_]effects.Modifier{.{
    .effect_type = .next_attack_damage_multiplier,
    .value = .{ .float = 1.5 },
}};

const DARK_KNOWLEDGE_EFFECT = effects.Effect{
    .name = "Dark Knowledge",
    .description = "Next attack deals +50% damage",
    .modifiers = &dark_knowledge_mods,
    .timing = .on_cast,
    .affects = .self,
    .duration_ms = 15000, // Expires if not used
    .is_buff = true,
};

const dark_knowledge_effects = [_]effects.Effect{DARK_KNOWLEDGE_EFFECT};

// Taking One for the Team (skill 16): Allies gain +25% damage
const martyrdom_mods = [_]effects.Modifier{.{
    .effect_type = .damage_multiplier,
    .value = .{ .float = 1.25 },
}};

const MARTYRDOM_EFFECT = effects.Effect{
    .name = "Taking One for the Team",
    .description = "+25% damage",
    .modifiers = &martyrdom_mods,
    .timing = .while_active,
    .affects = .allies_in_earshot,
    .duration_ms = 12000,
    .is_buff = true,
};

const martyrdom_effects = [_]effects.Effect{MARTYRDOM_EFFECT};

// ============================================================================
// MESMER-ANALOG EFFECT DEFINITIONS - Energy Denial/Inspiration Focus
// ============================================================================

// Mind Numbing - target loses 15 energy (energy burn)
const mind_numbing_mods = [_]effects.Modifier{.{
    .effect_type = .energy_burn,
    .value = .{ .float = 15.0 },
}};

const MIND_NUMBING_EFFECT = effects.Effect{
    .name = "Mind Numbing",
    .description = "Target loses 15 energy",
    .modifiers = &mind_numbing_mods,
    .timing = .on_hit,
    .affects = .target,
    .condition = .always,
    .duration_ms = 0,
    .is_buff = false,
};

const mind_numbing_effects = [_]effects.Effect{MIND_NUMBING_EFFECT};

// Empty Thoughts - +20 damage if target below 25% energy
const empty_thoughts_mods = [_]effects.Modifier{.{
    .effect_type = .damage_if_target_low_energy,
    .value = .{ .float = 20.0 },
}};

const EMPTY_THOUGHTS_EFFECT = effects.Effect{
    .name = "Empty Thoughts",
    .description = "+20 damage if target below 25% energy",
    .modifiers = &empty_thoughts_mods,
    .timing = .on_hit,
    .affects = .target,
    .condition = .always, // Condition check happens at damage time
    .duration_ms = 0,
    .is_buff = false,
};

const empty_thoughts_effects = [_]effects.Effect{EMPTY_THOUGHTS_EFFECT};

// Aura of Exhaustion - nearby foes lose 2 energy/sec
const aura_of_exhaustion_mods = [_]effects.Modifier{.{
    .effect_type = .energy_drain_per_second_aoe,
    .value = .{ .float = 2.0 },
}};

const AURA_OF_EXHAUSTION_EFFECT = effects.Effect{
    .name = "Aura of Exhaustion",
    .description = "Nearby foes lose 2 energy per second",
    .modifiers = &aura_of_exhaustion_mods,
    .timing = .while_active,
    .affects = .foes_in_earshot,
    .condition = .always,
    .duration_ms = 15000,
    .is_buff = false,
};

const aura_of_exhaustion_effects = [_]effects.Effect{AURA_OF_EXHAUSTION_EFFECT};

// Intellectual Theft - next skill costs double if brought below 10 energy
const intellectual_theft_mods = [_]effects.Modifier{
    .{
        .effect_type = .energy_steal_on_hit,
        .value = .{ .float = 12.0 },
    },
    .{
        .effect_type = .next_skill_cost_multiplier,
        .value = .{ .float = 2.0 }, // Conditional: only if below 10 energy
    },
};

const INTELLECTUAL_THEFT_EFFECT = effects.Effect{
    .name = "Intellectual Theft",
    .description = "Steal 12 energy. Next skill costs double if target below 10 energy.",
    .modifiers = &intellectual_theft_mods,
    .timing = .on_hit,
    .affects = .target,
    .condition = .always,
    .duration_ms = 8000, // Next skill cost debuff duration
    .is_buff = false,
};

const intellectual_theft_effects = [_]effects.Effect{INTELLECTUAL_THEFT_EFFECT};

// Mental Collapse - AoE energy burn, damage = energy lost
const mental_collapse_mods = [_]effects.Modifier{
    .{
        .effect_type = .energy_burn,
        .value = .{ .float = 20.0 },
    },
    .{
        .effect_type = .damage_per_current_energy, // Damage scales with energy burned
        .value = .{ .float = 1.0 }, // 1:1 ratio - damage = energy lost
    },
};

const MENTAL_COLLAPSE_EFFECT = effects.Effect{
    .name = "Mental Collapse",
    .description = "All foes in area lose 20 energy. Deals damage equal to energy lost.",
    .modifiers = &mental_collapse_mods,
    .timing = .on_hit,
    .affects = .foes_in_earshot, // AoE
    .condition = .always,
    .duration_ms = 0,
    .is_buff = false,
};

const mental_collapse_effects = [_]effects.Effect{MENTAL_COLLAPSE_EFFECT};

pub const skills = [_]Skill{
    // 1. Warmth for damage
    .{
        .name = "Pinky Promise",
        .description = "Trick. Sacrifice 15% of your max Warmth. Deals 35 damage.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 5,
        .warmth_cost_percent = 0.15,
        .min_warmth_percent = 0.20, // Can't cast below 20% warmth
        .damage = 35.0,
        .cast_range = 220.0,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 25000,
    },

    // 2. Convert warmth to energy
    .{
        .name = "Isolated Study",
        .description = "Gesture. Sacrifice 20% of your max Warmth. Gain 15 energy.",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 0,
        .warmth_cost_percent = 0.20,
        .min_warmth_percent = 0.25, // Can't cast below 25% warmth
        .target_type = .self,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 30000,
        .grants_energy_on_hit = 15, // Grants on cast complete
    },

    // 3. Crippling curse
    .{
        .name = "Skipped Lunch",
        .description = "Trick. Sacrifice 10% of your max Warmth. Deals 12 damage. Inflicts Packed Snow (12 seconds).",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 8,
        .warmth_cost_percent = 0.10,
        .min_warmth_percent = 0.15,
        .damage = 12.0,
        .cast_range = 200.0,
        .activation_time_ms = 2000,
        .aftercast_ms = 750,
        .recharge_time_ms = 30000,
        .chills = &homeschool_packed,
    },

    // 4. Execute - kills low warmth targets (no sacrifice - pure energy)
    .{
        .name = "Final Exam",
        .description = "Throw. Deals 25 damage. Deals double damage if target foe is below 30% Warmth. Completely soaks through padding.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 12,
        .damage = 25.0,
        .bonus_damage_if_foe_below_50_warmth = 25.0, // Double damage vs low warmth
        .cast_range = 220.0,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 35000,
        .soak = 1.0,
    },

    // 5. Energy drain with sacrifice
    .{
        .name = "Social Anxiety",
        .description = "Trick. Sacrifice 8% of your max Warmth. Deals 10 damage. Inflicts Brain Freeze and steals 8 energy.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 6,
        .warmth_cost_percent = 0.08,
        .min_warmth_percent = 0.10,
        .damage = 10.0,
        .cast_range = 200.0,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 20000,
        .chills = &homeschool_brain_freeze,
        .grants_energy_on_hit = 8, // Steals energy
    },

    // 6. Power at a cost - constant warmth drain
    .{
        .name = "Obsession",
        .description = "Stance. Sacrifice 12% of your max Warmth. (12 seconds.) You deal +50% damage. You lose 1 Warmth per second.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 8,
        .warmth_cost_percent = 0.12,
        .min_warmth_percent = 0.15,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 40000,
        .duration_ms = 12000,
        .cozies = &homeschool_fire,
        .effects = &obsession_effects, // +50% damage, -1 warmth/sec
    },

    // 7. Life steal - no sacrifice, sustain skill
    .{
        .name = "Heat Leech",
        .description = "Throw. Deals 20 damage. You gain 20 Warmth.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 8,
        .damage = 20.0,
        .healing = 20.0,
        .cast_range = 180.0,
        .target_type = .self,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 25000,
    },

    // 8. Devastating AoE with massive warmth cost
    .{
        .name = "Meltdown",
        .description = "Elite Trick. Sacrifice 25% of your max Warmth. Deals 35 damage to target and nearby foes.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 12,
        .warmth_cost_percent = 0.25,
        .min_warmth_percent = 0.30,
        .damage = 35.0,
        .cast_range = 240.0,
        .activation_time_ms = 3000,
        .aftercast_ms = 750,
        .recharge_time_ms = 40000,
        .aoe_type = .area,
        .aoe_radius = 180.0,
    },

    // 9. WALL: Blood Wall - powerful wall at health cost
    .{
        .name = "Desperation Fort",
        .description = "Trick. Sacrifice 18% of your max Warmth. Build a tall, jagged wall of ice.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 8,
        .warmth_cost_percent = 0.18,
        .min_warmth_percent = 0.22,
        .target_type = .ground,
        .cast_range = 150.0,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 35000,
        .creates_wall = true,
        .wall_length = 70.0,
        .wall_height = 45.0, // Very tall wall - paid in blood
        .wall_thickness = 22.0,
        .wall_distance_from_caster = 45.0,
        // KNOWN SIMPLIFICATION: Damaging walls require wall collision damage system.
        // Currently creates standard wall without touch damage.
    },

    // 10. Dark Knowledge - sacrifice for energy and damage buff
    .{
        .name = "Dark Knowledge",
        .description = "Gesture. Sacrifice 15% Warmth. Gain 10 energy. Your next attack deals +50% damage.",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 0,
        .warmth_cost_percent = 0.15,
        .min_warmth_percent = 0.20,
        .target_type = .self,
        .activation_time_ms = 500,
        .aftercast_ms = 500,
        .recharge_time_ms = 20000,
        .grants_energy_on_hit = 10,
        .cozies = &homeschool_fire,
        .effects = &dark_knowledge_effects, // Next attack +50% damage
    },

    // 11. Forbidden Technique - high damage with heavy sacrifice
    .{
        .name = "Secret Move",
        .description = "Throw. Sacrifice 20% Warmth. Deals 45 damage. Unblockable.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 10,
        .warmth_cost_percent = 0.20,
        .min_warmth_percent = 0.25,
        .damage = 45.0,
        .cast_range = 200.0,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 25000,
        .unblockable = true,
    },

    // 12. Solitary Strength - bonus when alone
    .{
        .name = "Solitary Strength",
        .description = "Stance. (20 seconds.) While no allies are nearby, deal +40% damage and take 20% less.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 5,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 30000,
        .duration_ms = 20000,
        .effects = &solitary_strength_effects, // +40% damage, -20% damage taken when isolated
    },

    // 13. Bitter Cold - powerful DoT
    .{
        .name = "Bitter Lesson",
        .description = "Trick. Sacrifice 8% Warmth. Deals 10 damage. Inflicts Windburn (8 seconds).",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 6,
        .warmth_cost_percent = 0.08,
        .min_warmth_percent = 0.12,
        .damage = 10.0,
        .cast_range = 200.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 15000,
        .chills = &homeschool_windburn,
    },

    // 14. Self-Reliance - powerful self-heal at a cost
    .{
        .name = "Self-Reliance",
        .description = "Gesture. Sacrifice 10% max Warmth permanently. Heal to full Warmth.",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 0,
        .healing = 200.0,
        .target_type = .self,
        .activation_time_ms = 2000,
        .aftercast_ms = 750,
        .recharge_time_ms = 60000,
        .effects = &self_reliance_effects, // -10% max warmth (permanent via long duration)
    },

    // 15. Crushing Isolation - debuff spread
    .{
        .name = "Crushing Isolation",
        .description = "Trick. Sacrifice 5% Warmth. Deals 12 damage. Inflicts Numb (8 seconds). +50% duration if target has no allies nearby.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 8,
        .warmth_cost_percent = 0.05,
        .min_warmth_percent = 0.08,
        .damage = 12.0,
        .cast_range = 180.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 18000,
        .chills = &homeschool_numb,
    },

    // 16. Martyrdom - damage self to buff allies
    .{
        .name = "Taking One for the Team",
        .description = "Call. Sacrifice 25% Warmth. All allies gain +25% damage and heal 20 Warmth.",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 10,
        .warmth_cost_percent = 0.25,
        .min_warmth_percent = 0.30,
        .healing = 20.0,
        .target_type = .ally,
        .aoe_type = .area,
        .aoe_radius = 250.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 35000,
        .duration_ms = 12000,
        .effects = &martyrdom_effects, // Allies gain +25% damage
    },

    // ========================================================================
    // HOMESCHOOL AP SKILLS (4 AP skills for 20% of 20 total)
    // ========================================================================

    // AP 1: Sugar Rush - convert warmth directly to damage
    .{
        .name = "Sugar Rush",
        .description = "[AP] Stance. (30 seconds.) Your skills cost no energy but cost 5% max Warmth instead. Deal +30% damage.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 0,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 60000,
        .duration_ms = 30000,
        .is_ap = true,
        .effects = &sugar_rush_effects, // No energy cost, +30% damage (5% warmth cost handled at runtime)
    },

    // AP 2: Desperate Gambit - trade warmth for power
    .{
        .name = "Desperate Gambit",
        .description = "[AP] Trick. Sacrifice 50% of your current Warmth. Deal that amount as damage to target. Cannot kill yourself.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 5,
        .cast_range = 200.0,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 30000,
        .is_ap = true,
        .effects = &desperate_gambit_effects,
    },

    // AP 3: Infectious Isolation - spread debuffs
    .{
        .name = "Infectious Isolation",
        .description = "[AP] Trick. For 15 seconds, whenever target takes damage, the Chills on them spread to the nearest foe.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 12,
        .cast_range = 200.0,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 40000,
        .duration_ms = 15000,
        .is_ap = true,
        .effects = &infectious_isolation_effects,
    },

    // AP 4: Lone Wolf - massive solo power
    .{
        .name = "Lone Wolf",
        .description = "[AP] Stance. While no allies are within 300 units: +60% damage, +40% armor, +50% energy regen. Lose all bonuses if ally comes near.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 10,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 45000,
        .duration_ms = 60000,
        .is_ap = true,
        .effects = &lone_wolf_effects, // +60% damage, +40% armor, +50% energy regen when isolated
    },

    // ========================================================================
    // HOMESCHOOL MESMER-ANALOG SKILLS - Energy Denial/Inspiration Focus
    // ========================================================================
    // These skills drain, burn, and punish low energy states.
    // Pairs well with Animator for a "Energy Denial Curser" playstyle.

    // 17. Energy Burn - pure energy destruction
    .{
        .name = "Mind Numbing",
        .description = "Trick. Sacrifice 8% Warmth. Target loses 15 energy (not stolen, just lost).",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 5,
        .warmth_cost_percent = 0.08,
        .min_warmth_percent = 0.12,
        .damage = 5.0,
        .cast_range = 200.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 15000,
        .effects = &mind_numbing_effects,
    },

    // 18. Punishment for low energy - bonus damage
    .{
        .name = "Empty Thoughts",
        .description = "Trick. Sacrifice 5% Warmth. Deals 12 damage. Deals +20 damage if target is below 25% energy.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 6,
        .warmth_cost_percent = 0.05,
        .min_warmth_percent = 0.08,
        .damage = 12.0,
        .cast_range = 200.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 12000,
        .effects = &empty_thoughts_effects,
    },

    // 19. Energy drain aura - nearby foes lose energy over time
    .{
        .name = "Aura of Exhaustion",
        .description = "Stance. Sacrifice 15% Warmth. (15 seconds.) Nearby foes lose 2 energy per second.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 8,
        .warmth_cost_percent = 0.15,
        .min_warmth_percent = 0.20,
        .target_type = .self,
        .aoe_type = .area,
        .aoe_radius = 150.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 30000,
        .duration_ms = 15000,
        .effects = &aura_of_exhaustion_effects,
    },

    // 20. Energy steal + skill disable combo
    .{
        .name = "Intellectual Theft",
        .description = "Trick. Sacrifice 10% Warmth. Steal 12 energy from target. If this brings them below 10 energy, their next skill costs double.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 5,
        .warmth_cost_percent = 0.10,
        .min_warmth_percent = 0.15,
        .damage = 8.0,
        .cast_range = 200.0,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 18000,
        .effects = &intellectual_theft_effects,
    },

    // AP 5: Energy Surge analog - AoE energy burn + damage
    .{
        .name = "Mental Collapse",
        .description = "[AP] Trick. Sacrifice 20% Warmth. All foes in area lose 20 energy. Deals damage equal to energy lost.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 10,
        .warmth_cost_percent = 0.20,
        .min_warmth_percent = 0.25,
        .cast_range = 220.0,
        .aoe_type = .area,
        .aoe_radius = 180.0,
        .activation_time_ms = 2000,
        .aftercast_ms = 750,
        .recharge_time_ms = 40000,
        .is_ap = true,
        .effects = &mental_collapse_effects,
    },
};
