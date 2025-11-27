const types = @import("../types.zig");
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
        .bonus_if_in_debt = true, // TODO: Add +15 damage if credit_debt > 0
    },

    // 5. Defensive credit skill
    .{
        .name = "Golden Shield",
        .description = "Stance. (15 seconds.) You block the next 3 attacks. Credit: 8 energy.",
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
        // TODO: Block next 3 attacks
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
        // TODO: Remove all chills from self
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
        // TODO: +1 damage per current energy
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
        // TODO: +30 damage if below 25% energy
    },

    // ========================================================================
    // PRIVATE SCHOOL AP SKILLS (4 AP skills for 20% of 20 total)
    // ========================================================================

    // AP 1: Hostile Takeover - massive credit nuke
    .{
        .name = "Hostile Takeover",
        .description = "[AP] Trick. Credit: 20 energy. Deals 50 damage. Steals 15 energy. Target's skills cost +3 energy for 10 seconds.",
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
    },
};
