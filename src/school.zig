const std = @import("std");
const color_pie = @import("color_pie.zig");
const skills = @import("skills.zig");

pub const Skill = skills.Skill;

pub const School = enum {
    private_school, // White: Order, Privilege, Resources
    public_school, // Red: Aggression, Grit, Combat
    montessori, // Green: Adaptation, Variety, Growth
    homeschool, // Black: Sacrifice, Power, Isolation
    waldorf, // Blue: Rhythm, Timing, Harmony

    // Energy generation rates (per second)
    // All schools have base regen, but some are more efficient than others
    pub fn getEnergyRegen(self: School) f32 {
        return switch (self) {
            .private_school => 1.5, // Allowance: high steady passive regen
            .public_school => 1.0, // Grit: standard regen, gains bonus from combat
            .montessori => 1.0, // Focus: balanced regen, bonus from variety
            .homeschool => 0.75, // Life Force: low regen, must sacrifice warmth
            .waldorf => 1.25, // Rhythm: good regen, bonus from rhythm stacks
        };
    }

    pub fn getMaxEnergy(self: School) u8 {
        return switch (self) {
            .private_school => 30, // High energy pool
            .public_school => 20, // Lower pool, gains from combat
            .montessori => 25, // Balanced
            .homeschool => 25, // Can convert warmth
            .waldorf => 25, // Rhythm-based
        };
    }

    pub fn getResourceName(self: School) [:0]const u8 {
        return switch (self) {
            .private_school => "Allowance",
            .public_school => "Grit",
            .montessori => "Focus",
            .homeschool => "Life Force",
            .waldorf => "Rhythm",
        };
    }

    pub fn getSecondaryMechanicName(self: School) [:0]const u8 {
        return switch (self) {
            .private_school => "Steady Income",
            .public_school => "Grit Stacks",
            .montessori => "Variety Bonus",
            .homeschool => "Sacrifice",
            .waldorf => "Perfect Timing",
        };
    }

    // Color pie access methods
    pub fn getChillAccess(self: School) color_pie.ChillAccess {
        return color_pie.getChillAccess(self);
    }

    pub fn getCozyAccess(self: School) color_pie.CozyAccess {
        return color_pie.getCozyAccess(self);
    }

    pub fn getSkillTypeAccess(self: School) color_pie.SkillTypeAccess {
        return color_pie.getSkillTypeAccess(self);
    }

    pub fn getDamageRange(self: School) color_pie.DamageRange {
        return color_pie.getDamageRange(self);
    }

    pub fn getCooldownRange(self: School) color_pie.CooldownRange {
        return color_pie.getCooldownRange(self);
    }

    pub fn getColorIdentity(self: School) [:0]const u8 {
        return switch (self) {
            .private_school => "White: Order, Privilege, Resources",
            .public_school => "Red: Aggression, Grit, Combat",
            .montessori => "Green: Adaptation, Variety, Growth",
            .homeschool => "Black: Sacrifice, Power, Isolation",
            .waldorf => "Blue: Rhythm, Timing, Harmony",
        };
    }

    pub fn getSkills(self: School) []const Skill {
        return switch (self) {
            .private_school => &private_school_skills,
            .public_school => &public_school_skills,
            .montessori => &montessori_skills,
            .homeschool => &homeschool_skills,
            .waldorf => &waldorf_skills,
        };
    }
};

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

const private_bundled_up = [_]skills.CozyEffect{.{
    .cozy = .bundled_up,
    .duration_ms = 12000,
    .stack_intensity = 1,
}};

const private_insulated = [_]skills.CozyEffect{.{
    .cozy = .insulated,
    .duration_ms = 20000,
    .stack_intensity = 1,
}};

const private_fortitude = [_]skills.CozyEffect{.{
    .cozy = .frosty_fortitude,
    .duration_ms = 18000,
    .stack_intensity = 1,
}};

const private_shield = [_]skills.CozyEffect{.{
    .cozy = .snowball_shield,
    .duration_ms = 10000,
    .stack_intensity = 1,
}};

const private_school_skills = [_]Skill{
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
};

// ============================================================================
// PUBLIC SCHOOL SKILLS - Red: Aggression, Grit, Combat
// ============================================================================
// Theme: No passive regen, gain energy from combat, fast cooldowns, high damage
// Synergizes with: Aggressive positions, damage dealers, close combat
// Cooldowns: 3-8s

const public_soggy = [_]skills.ChillEffect{.{
    .chill = .soggy,
    .duration_ms = 6000,
    .stack_intensity = 1,
}};

const public_windburn = [_]skills.ChillEffect{.{
    .chill = .windburn,
    .duration_ms = 5000,
    .stack_intensity = 1,
}};

const public_fire = [_]skills.CozyEffect{.{
    .cozy = .fire_inside,
    .duration_ms = 8000,
    .stack_intensity = 1,
}};

const public_slippery = [_]skills.ChillEffect{.{
    .chill = .slippery,
    .duration_ms = 4000,
    .stack_intensity = 1,
}};

const public_school_skills = [_]Skill{
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
};

// ============================================================================
// MONTESSORI SKILLS - Green: Adaptation, Variety, Growth
// ============================================================================
// Theme: Rewards using different skill types, versatile, scaling
// Synergizes with: Fielder, variety in skill bar, adaptation
// Cooldowns: 8-15s

const montessori_sure = [_]skills.CozyEffect{.{
    .cozy = .sure_footed,
    .duration_ms = 8000,
    .stack_intensity = 1,
}};

const montessori_multi_chill = [_]skills.ChillEffect{.{
    .chill = .slippery,
    .duration_ms = 3000,
    .stack_intensity = 1,
}};

const montessori_skills = [_]Skill{
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
};

// ============================================================================
// HOMESCHOOL SKILLS - Black: Sacrifice, Power, Isolation
// ============================================================================
// Theme: Pay health for power, devastating single-target, isolation bonuses
// Synergizes with: High damage, life sacrifice, solo play
// Cooldowns: 20-40s (long but devastating)

const homeschool_brain_freeze = [_]skills.ChillEffect{.{
    .chill = .brain_freeze,
    .duration_ms = 10000,
    .stack_intensity = 1,
}};

const homeschool_packed = [_]skills.ChillEffect{.{
    .chill = .packed_snow,
    .duration_ms = 12000,
    .stack_intensity = 1,
}};

const homeschool_fire = [_]skills.CozyEffect{.{
    .cozy = .fire_inside,
    .duration_ms = 10000,
    .stack_intensity = 1,
}};

const homeschool_skills = [_]Skill{
    // 1. Warmth for damage
    .{
        .name = "Blood Pact",
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
        .name = "Malnutrition",
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
        // TODO: -1 warmth per second while active
    },

    // 7. Life steal - no sacrifice, sustain skill
    .{
        .name = "Vampiric Touch",
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
        .name = "Blood Wall",
        .description = "Trick. Sacrifice 18% of your max Warmth. Build a tall, jagged wall of frozen blood.",
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
        // TODO: Wall damages enemies who touch it (life steal theme)
    },
};

// ============================================================================
// WALDORF SKILLS - Blue: Rhythm, Timing, Harmony
// ============================================================================
// Theme: Rewards perfect timing, rhythm-based bonuses, team harmony
// Synergizes with: Skill chaining, timing windows, support roles
// Cooldowns: Rhythmic (5-15s)

const waldorf_hot_cocoa = [_]skills.CozyEffect{.{
    .cozy = .hot_cocoa,
    .duration_ms = 12000,
    .stack_intensity = 1,
}};

const waldorf_goggles = [_]skills.CozyEffect{.{
    .cozy = .snow_goggles,
    .duration_ms = 15000,
    .stack_intensity = 1,
}};

const waldorf_slippery = [_]skills.ChillEffect{.{
    .chill = .slippery,
    .duration_ms = 5000,
    .stack_intensity = 1,
}};

const waldorf_skills = [_]Skill{
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
};
