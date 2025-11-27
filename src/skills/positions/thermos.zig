const types = @import("../types.zig");
const Skill = types.Skill;
const effects = @import("../../effects.zig");

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

// ============================================================================
// EFFECT DEFINITIONS
// ============================================================================

// Hand Warmers - remove all chills from ally
const hand_warmers_mods = [_]effects.Modifier{.{
    .effect_type = .remove_all_chills,
    .value = .{ .int = 1 },
}};

const HAND_WARMERS_EFFECT = effects.Effect{
    .name = "Hand Warmers",
    .description = "Remove all chills from target",
    .modifiers = &hand_warmers_mods,
    .timing = .on_cast,
    .affects = .target,
    .condition = .always,
    .duration_ms = 0,
    .is_buff = true,
};

const hand_warmers_effects = [_]effects.Effect{HAND_WARMERS_EFFECT};

// Warm Embrace - remove 1-2 chills
const warm_embrace_mods = [_]effects.Modifier{.{
    .effect_type = .remove_random_chill,
    .value = .{ .int = 2 },
}};

const WARM_EMBRACE_EFFECT = effects.Effect{
    .name = "Warm Embrace",
    .description = "Remove 1-2 chills from target",
    .modifiers = &warm_embrace_mods,
    .timing = .on_cast,
    .affects = .target,
    .condition = .always,
    .duration_ms = 0,
    .is_buff = true,
};

const warm_embrace_effects = [_]effects.Effect{WARM_EMBRACE_EFFECT};

// Energy Bar - target gains energy
const energy_bar_mods = [_]effects.Modifier{.{
    .effect_type = .energy_gain_per_second,
    .value = .{ .float = 2.0 }, // Faster energy regen for duration
}};

const ENERGY_BAR_EFFECT = effects.Effect{
    .name = "Energy Bar",
    .description = "Target gains energy faster",
    .modifiers = &energy_bar_mods,
    .timing = .while_active,
    .affects = .target,
    .condition = .always,
    .duration_ms = 15000,
    .is_buff = true,
};

const energy_bar_effects = [_]effects.Effect{ENERGY_BAR_EFFECT};

// Encouraging Words - +15% damage
const encouraging_words_mods = [_]effects.Modifier{.{
    .effect_type = .damage_multiplier,
    .value = .{ .float = 1.15 },
}};

const ENCOURAGING_WORDS_EFFECT = effects.Effect{
    .name = "Encouraged",
    .description = "+15% damage",
    .modifiers = &encouraging_words_mods,
    .timing = .while_active,
    .affects = .target,
    .condition = .always,
    .duration_ms = 10000,
    .is_buff = true,
};

const encouraging_words_effects = [_]effects.Effect{ENCOURAGING_WORDS_EFFECT};

// Group Hug - +25% armor to allies
const group_hug_mods = [_]effects.Modifier{.{
    .effect_type = .armor_multiplier,
    .value = .{ .float = 1.25 },
}};

const GROUP_HUG_EFFECT = effects.Effect{
    .name = "Group Hug",
    .description = "+25% armor to allies",
    .modifiers = &group_hug_mods,
    .timing = .while_active,
    .affects = .allies_in_earshot,
    .condition = .always,
    .duration_ms = 8000,
    .is_buff = true,
};

const group_hug_effects = [_]effects.Effect{GROUP_HUG_EFFECT};

// Fortifying Brew - +30 max warmth
const fortifying_brew_mods = [_]effects.Modifier{.{
    .effect_type = .max_warmth_add,
    .value = .{ .float = 30.0 },
}};

const FORTIFYING_BREW_EFFECT = effects.Effect{
    .name = "Fortifying Brew",
    .description = "+30 max warmth",
    .modifiers = &fortifying_brew_mods,
    .timing = .while_active,
    .affects = .target,
    .condition = .always,
    .duration_ms = 15000,
    .is_buff = true,
};

const fortifying_brew_effects = [_]effects.Effect{FORTIFYING_BREW_EFFECT};

// Escape Route - +40% speed
const escape_route_mods = [_]effects.Modifier{.{
    .effect_type = .move_speed_multiplier,
    .value = .{ .float = 1.40 },
}};

const ESCAPE_ROUTE_EFFECT = effects.Effect{
    .name = "Escape Route",
    .description = "+40% movement speed",
    .modifiers = &escape_route_mods,
    .timing = .while_active,
    .affects = .target,
    .condition = .always,
    .duration_ms = 8000,
    .is_buff = true,
};

const escape_route_effects = [_]effects.Effect{ESCAPE_ROUTE_EFFECT};

// Miracle Worker - remove all chills from allies
const miracle_worker_mods = [_]effects.Modifier{.{
    .effect_type = .remove_all_chills,
    .value = .{ .int = 1 },
}};

const MIRACLE_WORKER_EFFECT = effects.Effect{
    .name = "Miracle Worker",
    .description = "Remove all chills from allies",
    .modifiers = &miracle_worker_mods,
    .timing = .on_cast,
    .affects = .allies_in_earshot,
    .condition = .always,
    .duration_ms = 0,
    .is_buff = true,
};

const miracle_worker_effects = [_]effects.Effect{MIRACLE_WORKER_EFFECT};

// Sanctuary - heal 8/sec, 30% less damage
const sanctuary_ally_mods = [_]effects.Modifier{
    .{
        .effect_type = .warmth_gain_per_second,
        .value = .{ .float = 8.0 },
    },
    .{
        .effect_type = .armor_multiplier,
        .value = .{ .float = 1.43 }, // ~30% less damage = 1/0.7
    },
};

const SANCTUARY_EFFECT = effects.Effect{
    .name = "Sanctuary",
    .description = "Heal 8/sec, take 30% less damage",
    .modifiers = &sanctuary_ally_mods,
    .timing = .while_active,
    .affects = .allies_near_target,
    .condition = .always,
    .duration_ms = 20000,
    .is_buff = true,
};

const sanctuary_effects = [_]effects.Effect{SANCTUARY_EFFECT};

// Martyr - prevent ally death
const martyr_mods = [_]effects.Modifier{.{
    .effect_type = .healing_multiplier,
    .value = .{ .float = 1.0 }, // Placeholder - actual logic is special
}};

const MARTYR_EFFECT = effects.Effect{
    .name = "Martyr",
    .description = "Prevent ally death at cost of your warmth",
    .modifiers = &martyr_mods,
    .timing = .while_active,
    .affects = .self,
    .condition = .always,
    .duration_ms = 15000,
    .is_buff = true,
};

const martyr_effects = [_]effects.Effect{MARTYR_EFFECT};

// Spirit Link - share damage among all linked allies
// This skill uses behavior: .spirit_link instead of modifiers - it's a whole mechanic
// The effect here just indicates the link is active
const spirit_link_mods = [_]effects.Modifier{.{
    .effect_type = .armor_add, // Placeholder - actual behavior is in skill.behavior
    .value = .{ .float = 0.0 },
}};

const SPIRIT_LINK_EFFECT = effects.Effect{
    .name = "Spirit Link",
    .description = "Damage to any linked ally is split evenly among all",
    .modifiers = &spirit_link_mods,
    .timing = .while_active,
    .affects = .allies_in_earshot,
    .condition = .always,
    .duration_ms = 15000,
    .is_buff = true,
};

const spirit_link_effects = [_]effects.Effect{SPIRIT_LINK_EFFECT};

// ============================================================================
// BEHAVIOR DEFINITIONS
// ============================================================================

// Spirit Link behavior - share damage among linked allies
const SPIRIT_LINK_BEHAVIOR = types.Behavior.spiritLink(15000, 1.0);

// ============================================================================
// THERMOS SKILLS 17-20 + AP 5 EFFECT DEFINITIONS
// ============================================================================

// Hot Hands - weapon spell that heals on hit
const hot_hands_mods = [_]effects.Modifier{.{
    .effect_type = .warmth_gain_per_second, // Marker - actual heal is on_deal_damage
    .value = .{ .float = 0.0 },
}};

const HOT_HANDS_HEAL_EFFECT = effects.Effect{
    .name = "Hot Hands Heal",
    .description = "Heal 5 Warmth on hit",
    .modifiers = &hot_hands_mods,
    .timing = .on_deal_damage, // Trigger when ally deals damage
    .affects = .self, // Ally heals self
    .condition = .always,
    .duration_ms = 15000,
    .is_buff = true,
};

const hot_hands_effects = [_]effects.Effect{HOT_HANDS_HEAL_EFFECT};

// Hot Hands behavior - heal ally on their hit
const HOT_HANDS_BEHAVIOR = types.Behavior{
    .trigger = .on_ally_cast, // When ally attacks
    .response = .{ .heal_percent = .{ .percent = 0.0 } }, // Heal flat 5 (combat handles)
    .target = .target, // The ally with hot hands
    .duration_ms = 15000,
};

// Warmth Siphon - life steal on damage taken
const warmth_siphon_steal_mods = [_]effects.Modifier{.{
    .effect_type = .energy_steal_on_hit, // Marker - actual life steal is in behavior
    .value = .{ .float = 5.0 },
}};

const WARMTH_SIPHON_EFFECT = effects.Effect{
    .name = "Warmth Siphon",
    .description = "When hit, steal 5 Warmth from attacker",
    .modifiers = &warmth_siphon_steal_mods,
    .timing = .on_take_damage,
    .affects = .source_of_damage, // Damage the attacker
    .condition = .always,
    .duration_ms = 10000,
    .is_buff = true,
};

const warmth_siphon_effects = [_]effects.Effect{WARMTH_SIPHON_EFFECT};

// Warmth Siphon behavior - damage attacker and heal ally when ally takes damage
const WARMTH_SIPHON_BEHAVIOR = types.Behavior{
    .trigger = .on_ally_take_damage,
    .response = .{
        .deal_damage = .{
            .amount = 5.0, // Damage the attacker
            .to = .source_of_damage,
        },
    },
    .target = .target, // The ally with siphon
    .duration_ms = 10000,
};

// Steam Cloud - AoE HoT
const steam_cloud_mods = [_]effects.Modifier{.{
    .effect_type = .warmth_gain_per_second,
    .value = .{ .float = 4.0 }, // 4 Warmth per second
}};

const STEAM_CLOUD_EFFECT = effects.Effect{
    .name = "Steam Cloud",
    .description = "Heal 4 Warmth per second",
    .modifiers = &steam_cloud_mods,
    .timing = .while_active,
    .affects = .allies_in_earshot,
    .condition = .always,
    .duration_ms = 8000,
    .is_buff = true,
};

const steam_cloud_effects = [_]effects.Effect{STEAM_CLOUD_EFFECT};

// Battery Pack - gain energy when ally takes damage
const battery_pack_mods = [_]effects.Modifier{.{
    .effect_type = .energy_on_hit, // Marker - actual energy gain is in behavior
    .value = .{ .float = 1.0 },
}};

const BATTERY_PACK_EFFECT = effects.Effect{
    .name = "Battery Pack",
    .description = "Gain 1 energy when linked ally takes damage",
    .modifiers = &battery_pack_mods,
    .timing = .on_take_damage, // When ally takes damage
    .affects = .self, // Caster gains energy
    .condition = .always,
    .duration_ms = 20000,
    .is_buff = true,
};

const battery_pack_effects = [_]effects.Effect{BATTERY_PACK_EFFECT};

// Battery Pack behavior - caster gains energy when ally takes damage
const BATTERY_PACK_BEHAVIOR = types.Behavior{
    .trigger = .on_ally_take_damage,
    .response = .{ .grant_effect = &BATTERY_PACK_EFFECT },
    .target = .target, // The ally being watched
    .duration_ms = 20000,
};

// Cocoa Fountain - summon healing spirit
const cocoa_fountain_heal_mods = [_]effects.Modifier{.{
    .effect_type = .warmth_gain_per_second,
    .value = .{ .float = 3.0 }, // 6 every 2 seconds = 3/sec
}};

const COCOA_FOUNTAIN_EFFECT = effects.Effect{
    .name = "Cocoa Fountain",
    .description = "Heal 6 Warmth every 2 seconds",
    .modifiers = &cocoa_fountain_heal_mods,
    .timing = .while_active,
    .affects = .allies_near_target, // Allies near the spirit
    .condition = .always,
    .duration_ms = 25000,
    .is_buff = true,
};

const cocoa_fountain_effects = [_]effects.Effect{COCOA_FOUNTAIN_EFFECT};

// Cocoa Fountain behavior - summon healing spirit
const COCOA_FOUNTAIN_BEHAVIOR = types.Behavior.summonCreature(.{
    .summon_type = .snow_fort, // Use snow_fort as spirit stand-in
    .count = 1,
    .level = 1,
    .duration_ms = 25000,
    .damage_per_attack = 0.0, // Spirit doesn't attack
});

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
        .effects = &hand_warmers_effects,
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
        .effects = &warm_embrace_effects,
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
        .effects = &energy_bar_effects,
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
        .name = "Snow Shelter",
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
        .effects = &encouraging_words_effects,
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
        .effects = &group_hug_effects,
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
        .effects = &fortifying_brew_effects,
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
        .effects = &escape_route_effects,
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
        .effects = &miracle_worker_effects,
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
        .behavior = &SPIRIT_LINK_BEHAVIOR,
        .effects = &spirit_link_effects,
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
        .effects = &sanctuary_effects,
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
        .effects = &martyr_effects,
    },

    // ========================================================================
    // THERMOS SKILLS 17-20 + AP 5 (Ritualist Restoration analog - Weapon spells, life steal)
    // ========================================================================
    // Theme: Weapon enchantments, life stealing redirects, binding spirits

    // 17. Hot Hands - weapon spell that heals on hit (like Weapon of Warding)
    .{
        .name = "Hot Hands",
        .description = "Gesture. Target ally's attacks heal them for 5 Warmth for 15 seconds.",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 8,
        .target_type = .ally,
        .cast_range = 180.0,
        .activation_time_ms = 750,
        .aftercast_ms = 750,
        .recharge_time_ms = 20000,
        .duration_ms = 15000,
        .behavior = &HOT_HANDS_BEHAVIOR,
        .effects = &hot_hands_effects,
    },

    // 18. Warmth Siphon - steal health from attacker (like Vampiric Spirit)
    .{
        .name = "Warmth Siphon",
        .description = "Gesture. For 10 seconds, when target ally takes damage, the attacker loses 5 Warmth and ally heals 5.",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 8,
        .target_type = .ally,
        .cast_range = 180.0,
        .activation_time_ms = 750,
        .aftercast_ms = 750,
        .recharge_time_ms = 18000,
        .duration_ms = 10000,
        .behavior = &WARMTH_SIPHON_BEHAVIOR,
        .effects = &warmth_siphon_effects,
    },

    // 19. Steam Cloud - AoE HoT (like Recovery)
    .{
        .name = "Steam Cloud",
        .description = "Call. All allies heal 4 Warmth per second for 8 seconds.",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 10,
        .target_type = .ally,
        .aoe_type = .area,
        .aoe_radius = 250.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 25000,
        .duration_ms = 8000,
        .effects = &steam_cloud_effects,
    },

    // 20. Battery Pack - gain energy when ally takes damage (like Essence Bond)
    .{
        .name = "Battery Pack",
        .description = "Gesture. For 20 seconds, gain 1 energy whenever target ally takes damage.",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 5,
        .target_type = .ally,
        .cast_range = 200.0,
        .activation_time_ms = 500,
        .aftercast_ms = 750,
        .recharge_time_ms = 25000,
        .duration_ms = 20000,
        .behavior = &BATTERY_PACK_BEHAVIOR,
        .effects = &battery_pack_effects,
    },

    // AP 5: Cocoa Fountain - summon healing spirit (like Ritual Lord + Recovery)
    .{
        .name = "Cocoa Fountain",
        .description = "[AP] Trick. Create a Cocoa Spirit at target location for 25 seconds. Spirit heals all allies within 150 range for 6 Warmth every 2 seconds.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 18,
        .target_type = .ground,
        .cast_range = 200.0,
        .aoe_type = .area,
        .aoe_radius = 150.0,
        .activation_time_ms = 2000,
        .aftercast_ms = 750,
        .recharge_time_ms = 60000,
        .duration_ms = 25000,
        .terrain_effect = types.TerrainEffect.healingSlush(.circle),
        .is_ap = true,
        .behavior = &COCOA_FOUNTAIN_BEHAVIOR,
        .effects = &cocoa_fountain_effects,
    },
};
