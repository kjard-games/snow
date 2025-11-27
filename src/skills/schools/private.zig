const types = @import("../types.zig");
const effects = @import("../../effects.zig");
const Skill = types.Skill;

// ============================================================================
// PRIVATE SCHOOL SKILLS - Gold: Wealth, Power, Credit
// ============================================================================
// Mechanic: CREDIT/DEBT - Spend max energy for powerful effects
// - High base energy pool (60) and regen (1.5/s)
// - Some skills cost "credit" - temporarily reduce max energy (like spending on credit)
// - Max energy recovers at 1 point per 3 seconds (paying back debt)
// - Some skills get bonus effects when you're "in debt" (credit > 0)
// Theme: "Trust fund spending" - burn through your pool for powerful effects
// Synergizes with: High burst damage, defensive positions, managing debt
// Cooldowns: 12-30s

const private_bundled_up = [_]types.CozyEffect{.{
    .cozy = .bundled_up,
    .duration_ms = 12000,
    .stack_intensity = 1,
}};

const private_insulated = [_]types.CozyEffect{.{
    .cozy = .insulated,
    .duration_ms = 20000,
    .stack_intensity = 1,
}};

const private_fortitude = [_]types.CozyEffect{.{
    .cozy = .frosty_fortitude,
    .duration_ms = 18000,
    .stack_intensity = 1,
}};

const private_shield = [_]types.CozyEffect{.{
    .cozy = .snowball_shield,
    .duration_ms = 10000,
    .stack_intensity = 1,
}};

const private_fire_inside = [_]types.CozyEffect{.{
    .cozy = .fire_inside,
    .duration_ms = 10000,
    .stack_intensity = 1,
}};

const private_hot_cocoa = [_]types.CozyEffect{.{
    .cozy = .hot_cocoa,
    .duration_ms = 15000,
    .stack_intensity = 1,
}};

const private_brain_freeze = [_]types.ChillEffect{.{
    .chill = .brain_freeze,
    .duration_ms = 8000,
    .stack_intensity = 1,
}};

// ============================================================================
// EFFECT DEFINITIONS - Composable effects for complex skill mechanics
// ============================================================================

// Desperate Spending (skill 4): +15 damage if in debt
const desperate_spending_mods = [_]effects.Modifier{.{
    .effect_type = .damage_add,
    .value = .{ .float = 15.0 },
}};

const DESPERATE_SPENDING_EFFECT = effects.Effect{
    .name = "Desperate Spending",
    .description = "+15 damage while in debt",
    .modifiers = &desperate_spending_mods,
    .timing = .on_hit,
    .affects = .target,
    .duration_ms = 0, // Instant
    .is_buff = false,
    .condition = .if_caster_in_debt,
};

const desperate_spending_effects = [_]effects.Effect{DESPERATE_SPENDING_EFFECT};

// Golden Shield (skill 5): 75% block chance for 15 seconds
const golden_shield_mods = [_]effects.Modifier{.{
    .effect_type = .block_chance,
    .value = .{ .float = 0.75 }, // 75% block chance
}};

const GOLDEN_SHIELD_EFFECT = effects.Effect{
    .name = "Golden Shield",
    .description = "75% chance to block incoming attacks",
    .modifiers = &golden_shield_mods,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 15000,
    .is_buff = true,
};

const golden_shield_effects = [_]effects.Effect{GOLDEN_SHIELD_EFFECT};

// Call Mom (skill 8): Remove all chills
const call_mom_mods = [_]effects.Modifier{.{
    .effect_type = .remove_all_chills,
    .value = .{ .int = 1 },
}};

const CALL_MOM_EFFECT = effects.Effect{
    .name = "Call Mom",
    .description = "Remove all Chills",
    .modifiers = &call_mom_mods,
    .timing = .on_cast,
    .affects = .self,
    .duration_ms = 0, // Instant
    .is_buff = true,
};

const call_mom_effects = [_]effects.Effect{CALL_MOM_EFFECT};

// Bail Out (skill 11): Move 50% faster + block next attack
const bail_out_mods = [_]effects.Modifier{
    .{
        .effect_type = .move_speed_multiplier,
        .value = .{ .float = 1.5 }, // 50% faster
    },
    .{
        .effect_type = .block_next_attack,
        .value = .{ .float = 1.0 }, // Block 1 attack
    },
};

const BAIL_OUT_EFFECT = effects.Effect{
    .name = "Bail Out",
    .description = "Move 50% faster. Block the next attack.",
    .modifiers = &bail_out_mods,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 5000,
    .is_buff = true,
};

const bail_out_effects = [_]effects.Effect{BAIL_OUT_EFFECT};

// Severance Package (skill 16): +30 damage if below 25% energy
const severance_package_mods = [_]effects.Modifier{.{
    .effect_type = .damage_add,
    .value = .{ .float = 30.0 },
}};

const SEVERANCE_PACKAGE_EFFECT = effects.Effect{
    .name = "Severance Package",
    .description = "+30 damage when below 25% energy",
    .modifiers = &severance_package_mods,
    .timing = .on_hit,
    .affects = .target,
    .duration_ms = 0, // Instant
    .is_buff = false,
    .condition = .if_caster_below_25_percent_energy,
};

const severance_package_effects = [_]effects.Effect{SEVERANCE_PACKAGE_EFFECT};

// Trust Fund Baby (AP 2): Double max energy, +100% regen, +50% skill cost
const trust_fund_baby_mods = [_]effects.Modifier{
    .{
        .effect_type = .max_energy_multiplier,
        .value = .{ .float = 2.0 }, // Double max energy
    },
    .{
        .effect_type = .energy_regen_multiplier,
        .value = .{ .float = 2.0 }, // +100% energy regen
    },
    .{
        .effect_type = .energy_cost_multiplier,
        .value = .{ .float = 1.5 }, // Skills cost 50% more
    },
};

const TRUST_FUND_BABY_EFFECT = effects.Effect{
    .name = "Trust Fund Baby",
    .description = "Max energy doubled. Energy regen +100%. Skills cost +50%.",
    .modifiers = &trust_fund_baby_mods,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 30000,
    .is_buff = true,
};

const trust_fund_baby_effects = [_]effects.Effect{TRUST_FUND_BABY_EFFECT};

// Inherited Wealth (AP 3): Allies gain +1 energy per second
const inherited_wealth_mods = [_]effects.Modifier{.{
    .effect_type = .energy_gain_per_second,
    .value = .{ .float = 1.0 },
}};

const INHERITED_WEALTH_EFFECT = effects.Effect{
    .name = "Inherited Wealth",
    .description = "Gain +1 energy per second",
    .modifiers = &inherited_wealth_mods,
    .timing = .while_active,
    .affects = .allies_in_earshot,
    .duration_ms = 15000,
    .is_buff = true,
};

const inherited_wealth_effects = [_]effects.Effect{INHERITED_WEALTH_EFFECT};

// Hostile Takeover (AP 1): Target skills cost +3 energy (via energy cost multiplier debuff)
const hostile_takeover_mods = [_]effects.Modifier{.{
    .effect_type = .energy_cost_multiplier,
    .value = .{ .float = 1.3 }, // Approximate +3 on a 10-cost skill
}};

const HOSTILE_TAKEOVER_EFFECT = effects.Effect{
    .name = "Hostile Takeover",
    .description = "Skills cost more energy",
    .modifiers = &hostile_takeover_mods,
    .timing = .while_active,
    .affects = .target,
    .duration_ms = 10000,
    .is_buff = false,
};

const hostile_takeover_effects = [_]effects.Effect{HOSTILE_TAKEOVER_EFFECT};

// Hedge Fund (skill 15): Self takes 25% less damage, allies take 10% less
const hedge_fund_self_mods = [_]effects.Modifier{.{
    .effect_type = .damage_multiplier,
    .value = .{ .float = 0.75 }, // Take 25% less damage
}};

const HEDGE_FUND_SELF_EFFECT = effects.Effect{
    .name = "Hedge Fund",
    .description = "Take 25% less damage",
    .modifiers = &hedge_fund_self_mods,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 15000,
    .is_buff = true,
};

const hedge_fund_ally_mods = [_]effects.Modifier{.{
    .effect_type = .damage_multiplier,
    .value = .{ .float = 0.9 }, // Take 10% less damage
}};

const HEDGE_FUND_ALLY_EFFECT = effects.Effect{
    .name = "Hedge Fund Aura",
    .description = "Take 10% less damage",
    .modifiers = &hedge_fund_ally_mods,
    .timing = .while_active,
    .affects = .allies_in_earshot,
    .duration_ms = 15000,
    .is_buff = true,
};

const hedge_fund_effects = [_]effects.Effect{ HEDGE_FUND_SELF_EFFECT, HEDGE_FUND_ALLY_EFFECT };

// Compound Interest (skill 12): +1 damage per current energy
const compound_interest_mods = [_]effects.Modifier{.{
    .effect_type = .damage_per_current_energy,
    .value = .{ .float = 1.0 }, // +1 damage per energy
}};

const COMPOUND_INTEREST_EFFECT = effects.Effect{
    .name = "Compound Interest",
    .description = "+1 damage per current energy",
    .modifiers = &compound_interest_mods,
    .timing = .on_hit,
    .affects = .target,
    .duration_ms = 0,
    .is_buff = false,
};

const compound_interest_effects = [_]effects.Effect{COMPOUND_INTEREST_EFFECT};

// Portfolio Diversification (skill 14): +10% damage after using 2 different skill types, +20% after 3 different
const portfolio_diversification_2_types_mods = [_]effects.Modifier{.{
    .effect_type = .damage_multiplier,
    .value = .{ .float = 1.1 }, // +10% damage
}};

const PORTFOLIO_DIVERSIFICATION_2_TYPES_EFFECT = effects.Effect{
    .name = "Diversified",
    .description = "+10% damage (used 2 different skill types)",
    .modifiers = &portfolio_diversification_2_types_mods,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 20000,
    .is_buff = true,
    .condition = .if_last_two_skills_different_types,
};

const portfolio_diversification_3_types_mods = [_]effects.Modifier{.{
    .effect_type = .damage_multiplier,
    .value = .{ .float = 1.2 }, // +20% damage
}};

const PORTFOLIO_DIVERSIFICATION_3_TYPES_EFFECT = effects.Effect{
    .name = "Highly Diversified",
    .description = "+20% damage (used 3 different skill types)",
    .modifiers = &portfolio_diversification_3_types_mods,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 20000,
    .is_buff = true,
    .condition = .if_last_three_skills_different_types,
};

const portfolio_diversification_effects = [_]effects.Effect{ PORTFOLIO_DIVERSIFICATION_2_TYPES_EFFECT, PORTFOLIO_DIVERSIFICATION_3_TYPES_EFFECT };

// Golden Parachute (AP 4): Prevent death, heal to 50%, invulnerable
// This skill uses behavior: .prevent_death instead of modifiers - it's a whole mechanic
// The stance buff simply indicates the skill is active
const golden_parachute_mods = [_]effects.Modifier{.{
    .effect_type = .armor_add, // Placeholder - actual behavior is in skill.behavior
    .value = .{ .float = 0.0 },
}};

const GOLDEN_PARACHUTE_EFFECT = effects.Effect{
    .name = "Golden Parachute",
    .description = "When dropping below 20% Warmth, heal to 50% and become invulnerable for 3 seconds",
    .modifiers = &golden_parachute_mods,
    .timing = .while_active,
    .affects = .self,
    .duration_ms = 30000,
    .is_buff = true,
};

const golden_parachute_effects = [_]effects.Effect{GOLDEN_PARACHUTE_EFFECT};

// Behavior: When would die, heal to 50% instead (one-shot)
const GOLDEN_PARACHUTE_BEHAVIOR = types.Behavior{
    .trigger = .on_would_die,
    .response = .{ .heal_percent = .{ .percent = 0.5 } },
    .condition = .always, // Trigger already checks "would die"
    .max_activations = 1,
    .duration_ms = 30000,
};

pub const skills = [_]Skill{
    // 1. Energy management - instant energy
    .{
        .name = "Trust Fund",
        .description = "Gesture. You gain 15 energy.",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 0,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 750,
        .recharge_time_ms = 25000,
        .grants_energy_on_hit = 15, // Instant energy gain
    },

    // 2. Powerful credit attack
    .{
        .name = "Gold-Plated Throw",
        .description = "Throw. Deals 35 damage. Credit: 10 energy.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 10,
        .credit_cost = 10, // Reduces max energy by 10
        .damage = 35.0,
        .cast_range = 250.0,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 12000,
    },

    // 3. Credit AoE nuke
    .{
        .name = "Money Bomb",
        .description = "Trick. Deals 25 damage to all foes in the area. Credit: 15 energy.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 15,
        .credit_cost = 15,
        .damage = 25.0,
        .cast_range = 250.0,
        .activation_time_ms = 2000,
        .aftercast_ms = 750,
        .recharge_time_ms = 25000,
        .aoe_type = .area,
        .aoe_radius = 150.0,
    },

    // 4. Bonus skill when in debt
    .{
        .name = "Desperate Spending",
        .description = "Throw. Deals 20 damage. Deals +15 damage if you are in debt.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 5,
        .damage = 20.0,
        .cast_range = 200.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 8000,
        .bonus_if_in_debt = true,
        .effects = &desperate_spending_effects,
    },

    // 5. Defensive credit skill
    .{
        .name = "Golden Shield",
        .description = "Stance. (15 seconds.) 75% chance to block attacks. Credit: 8 energy.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 8,
        .credit_cost = 8,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 30000,
        .duration_ms = 15000,
        .cozies = &private_shield,
        .effects = &golden_shield_effects,
    },

    // 6. Healing without credit (can't afford to debt support)
    .{
        .name = "Private Nurse",
        .description = "Trick. Heals target ally for 50 Warmth.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 10,
        .healing = 50.0,
        .cast_range = 200.0,
        .target_type = .ally,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 18000,
    },

    // 7. Max warmth buff with credit
    .{
        .name = "Luxury Meal",
        .description = "Stance. (20 seconds.) You have +50 maximum Warmth. Credit: 5 energy.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 10,
        .credit_cost = 5,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 25000,
        .duration_ms = 20000,
        .cozies = &private_fortitude,
    },

    // 8. Condition removal - money solves problems
    .{
        .name = "Call Mom",
        .description = "Gesture. Heals for 30 Warmth. Removes all Chills.",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 5,
        .healing = 30.0,
        .target_type = .self,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 20000,
        .effects = &call_mom_effects,
    },

    // 9. WALL: Security Fence - expensive but sturdy wall
    .{
        .name = "Security Fence",
        .description = "Stance. Credit: 12 energy. Build a tall reinforced wall. Blocks projectiles.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 10,
        .credit_cost = 12,
        .target_type = .ground,
        .cast_range = 120.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 30000,
        .creates_wall = true,
        .wall_length = 75.0, // Longer wall
        .wall_height = 50.0, // Tallest wall - premium quality
        .wall_thickness = 30.0,
        .wall_distance_from_caster = 50.0,
        .cozies = &private_insulated, // Also grants protection buff
    },

    // 10. Emergency Funds - burst healing with credit
    .{
        .name = "Emergency Funds",
        .description = "Gesture. Credit: 8 energy. Heals for 60 Warmth.",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 10,
        .credit_cost = 8,
        .healing = 60.0,
        .target_type = .self,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 30000,
    },

    // 11. Bail Out - escape skill
    .{
        .name = "Bail Out",
        .description = "Stance. (5 seconds.) Move 50% faster. Block the next attack.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 5,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 25000,
        .duration_ms = 5000,
        .cozies = &private_shield,
        .effects = &bail_out_effects,
    },

    // 12. Compound Interest - damage scales with energy
    .{
        .name = "Compound Interest",
        .description = "Throw. Deals 10 damage +1 damage per current energy.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 8,
        .damage = 10.0,
        .cast_range = 220.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 12000,
        .effects = &compound_interest_effects,
    },

    // 13. Tax Return - energy drain
    .{
        .name = "Tax Return",
        .description = "Trick. Deals 15 damage. Steals 8 energy from target.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 10,
        .damage = 15.0,
        .cast_range = 200.0,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 20000,
        .chills = &private_brain_freeze,
        .grants_energy_on_hit = 8,
    },

    // 14. Portfolio Diversification - buff that grows
    .{
        .name = "Portfolio Diversification",
        .description = "Stance. (20 seconds.) Gain +5% damage per different skill type used.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 5,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 30000,
        .duration_ms = 20000,
        .cozies = &private_fire_inside,
        .effects = &portfolio_diversification_effects,
    },

    // 15. Hedge Fund - defensive investment
    .{
        .name = "Hedge Fund",
        .description = "Stance. Credit: 5 energy. (15 seconds.) Take 25% less damage. Allies in earshot take 10% less damage.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 8,
        .credit_cost = 5,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 35000,
        .duration_ms = 15000,
        .cozies = &private_bundled_up,
        .effects = &hedge_fund_effects,
    },

    // 16. Severance Package - strong finisher when resources depleted
    .{
        .name = "Severance Package",
        .description = "Throw. Deals 20 damage. Deals +30 damage if you are below 25% energy.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 5,
        .damage = 20.0,
        .cast_range = 200.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 15000,
        .effects = &severance_package_effects,
    },

    // ========================================================================
    // PRIVATE SCHOOL AP SKILLS (4 AP skills for 20% of 20 total)
    // ========================================================================

    // AP 1: Hostile Takeover - massive credit nuke
    .{
        .name = "Hostile Takeover",
        .description = "[AP] Trick. Credit: 20 energy. Deals 50 damage. Steals 15 energy. Target's skills cost +30% energy for 10 seconds.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 15,
        .credit_cost = 20,
        .damage = 50.0,
        .cast_range = 200.0,
        .activation_time_ms = 2000,
        .aftercast_ms = 750,
        .recharge_time_ms = 45000,
        .grants_energy_on_hit = 15,
        .is_ap = true,
        .effects = &hostile_takeover_effects,
    },

    // AP 2: Trust Fund Baby - massive energy pool manipulation
    .{
        .name = "Trust Fund Baby",
        .description = "[AP] Stance. (30 seconds.) Your max energy is doubled. Energy regen +100%. All skills cost +50% energy.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 0,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 60000,
        .duration_ms = 30000,
        .is_ap = true,
        .effects = &trust_fund_baby_effects,
    },

    // AP 3: Inherited Wealth - team energy support
    .{
        .name = "Inherited Wealth",
        .description = "[AP] Call. All allies gain 10 energy. For 15 seconds, allies gain +1 energy per second.",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 15,
        .target_type = .ally,
        .aoe_type = .area,
        .aoe_radius = 250.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 45000,
        .duration_ms = 15000,
        .cozies = &private_hot_cocoa,
        .is_ap = true,
        .effects = &inherited_wealth_effects,
    },

    // AP 4: Golden Parachute - invulnerability when "fired" (low HP)
    .{
        .name = "Golden Parachute",
        .description = "[AP] Stance. (30 seconds.) When you would drop below 20% Warmth, instead heal to 50% and become invulnerable for 3 seconds. Ends stance.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 10,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 90000,
        .duration_ms = 30000,
        .is_ap = true,
        .behavior = &GOLDEN_PARACHUTE_BEHAVIOR,
        .effects = &golden_parachute_effects,
    },

    // ========================================================================
    // PRIVATE SCHOOL SKILLS 17-20 + AP 5 - Privilege/Sneaky theme
    // ========================================================================
    // Theme: Surprise attacks, backdoor deals, exploiting advantages

    // 17. Back Door Deal - teleport attack
    .{
        .name = "Back Door Deal",
        .description = "Trick. Teleport to target foe. Your next attack within 3 seconds deals +15 damage.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 8,
        .cast_range = 200.0,
        .activation_time_ms = 250,
        .aftercast_ms = 500,
        .recharge_time_ms = 20000,
        // TODO: Teleport to target + next attack bonus
    },

    // 18. Backstab Bonus - attack from behind
    .{
        .name = "Backstab Bonus",
        .description = "Throw. Deals 18 damage. If you are behind target, deals +12 damage and steals 5 energy.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 7,
        .damage = 18.0,
        .cast_range = 150.0,
        .activation_time_ms = 500,
        .aftercast_ms = 750,
        .recharge_time_ms = 10000,
        // TODO: Behind-target conditional bonus
    },

    // 19. Short Sell - debuff that increases damage taken
    .{
        .name = "Short Sell",
        .description = "Trick. Target takes +20% damage from all sources for 8 seconds.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 8,
        .cast_range = 200.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 25000,
        .duration_ms = 8000,
        // TODO: Vulnerability debuff on target
    },

    // 20. Lucky Break - fast attack with crit chance
    .{
        .name = "Lucky Break",
        .description = "Throw. Deals 14 damage. 30% chance to deal double damage and refund energy cost.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 5,
        .damage = 14.0,
        .cast_range = 180.0,
        .activation_time_ms = 500,
        .aftercast_ms = 500,
        .recharge_time_ms = 4000,
        // TODO: Critical chance mechanic
    },

    // AP 5: Hostile Acquisition - massive burst with reset on kill
    .{
        .name = "Hostile Acquisition",
        .description = "[AP] Trick. Credit: 25 energy. Mark target for 10 seconds. If target dies while marked, reset all skill cooldowns and gain 30 energy.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 15,
        .credit_cost = 25,
        .cast_range = 200.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 500,
        .recharge_time_ms = 60000,
        .duration_ms = 10000,
        .is_ap = true,
        // TODO: Mark + reset on kill behavior
    },
};
