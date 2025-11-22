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

    // Energy generation rates and mechanics
    pub fn getEnergyRegen(self: School) f32 {
        return switch (self) {
            .private_school => 2.0, // Allowance: steady passive regen
            .public_school => 0.0, // Grit: no passive regen, combat only
            .montessori => 1.0, // Balanced regen
            .homeschool => 0.5, // Low regen, can sacrifice warmth
            .waldorf => 1.5, // Rhythm: moderate regen
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
// PRIVATE SCHOOL SKILLS - White: Order, Privilege, Resources
// ============================================================================
// Theme: High energy pool, steady regen, defensive, expensive but powerful
// Synergizes with: Defensive positions, energy management, long cooldowns
// Cooldowns: 15-30s

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
    // 1. Energy management - gain energy
    .{
        .name = "Trust Fund",
        .description = "Gesture. You gain 10 energy.",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 0,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 750,
        .recharge_time_ms = 25000,
        // TODO: Gain 10 energy immediately
    },

    // 2. Expensive powerful shield
    .{
        .name = "Hire Bodyguard",
        .description = "Stance. (10 seconds.) You block the next 3 attacks.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 15,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 30000,
        .cozies = &private_shield,
        // TODO: Block next 3 attacks
    },

    // 3. Team energy support
    .{
        .name = "Share Allowance",
        .description = "Shout. (20 seconds.) Party members in earshot have +3 energy regeneration.",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 12,
        .cast_range = 250.0,
        .target_type = .ally,
        .aoe_type = .area,
        .aoe_radius = 250.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 30000,
        .cozies = &private_insulated,
    },

    // 4. Defensive buff - padding
    .{
        .name = "Designer Jacket",
        .description = "Stance. (12 seconds.) You have +20 padding and take 33% less damage.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 10,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 20000,
        .cozies = &private_bundled_up,
    },

    // 5. Expensive AoE damage
    .{
        .name = "Hired Pitcher",
        .description = "Trick. Deals 15 damage to all foes in the area.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 18,
        .damage = 15.0,
        .cast_range = 250.0,
        .activation_time_ms = 2000,
        .aftercast_ms = 750,
        .recharge_time_ms = 25000,
        .aoe_type = .area,
        .aoe_radius = 150.0,
    },

    // 6. Healing - can afford the best
    .{
        .name = "Private Nurse",
        .description = "Trick. Heals target ally for 50 Health.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 12,
        .healing = 50.0,
        .cast_range = 200.0,
        .target_type = .ally,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 18000,
    },

    // 7. Max health buff
    .{
        .name = "Well Fed",
        .description = "Stance. (18 seconds.) You have +50 maximum Health.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 10,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 25000,
        .cozies = &private_fortitude,
    },

    // 8. Condition removal - money solves problems
    .{
        .name = "Call Mom",
        .description = "Gesture. Heals for 25 Health. Removes all chills.",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 8,
        .healing = 25.0,
        .target_type = .self,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 20000,
        // TODO: Remove all chills from self
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
    // 1. Gain energy on hit
    .{
        .name = "Scrap",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 0,
        .damage = 10.0,
        .cast_range = 180.0,
        .activation_time_ms = 500,
        .aftercast_ms = 750,
        .recharge_time_ms = 4000,
        // TODO: Gain 3 energy if this hits
    },

    // 2. Fast aggressive buff
    .{
        .name = "Riled Up",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 5,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 8000,
        .cozies = &public_fire,
    },

    // 3. DoT spam
    .{
        .name = "Dirty Snowball",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 4,
        .damage = 12.0,
        .cast_range = 160.0,
        .activation_time_ms = 500,
        .aftercast_ms = 750,
        .recharge_time_ms = 5000,
        .chills = &public_soggy,
    },

    // 4. Fast cooldown pressure
    .{
        .name = "Relentless",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 5,
        .damage = 15.0,
        .cast_range = 170.0,
        .activation_time_ms = 750,
        .aftercast_ms = 750,
        .recharge_time_ms = 3000,
    },

    // 5. Bonus damage if target damaged recently
    .{
        .name = "Pile On",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 6,
        .damage = 18.0,
        .cast_range = 180.0,
        .activation_time_ms = 750,
        .aftercast_ms = 750,
        .recharge_time_ms = 6000,
        // TODO: +10 damage if target has a chill
    },

    // 6. Knockdown effect
    .{
        .name = "Tackle",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 7,
        .damage = 14.0,
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

    // 8. All-in attack - high risk high reward
    .{
        .name = "All Out",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 10,
        .damage = 25.0,
        .cast_range = 150.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 8000,
        // TODO: Deal double damage but take double damage for 3s
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
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 5,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 15000,
        .duration_ms = 20000,
        // TODO: Next skill of each type deals +50% damage
    },

    // 2. Swiss army knife - does many things
    .{
        .name = "Versatile Throw",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 6,
        .damage = 14.0,
        .cast_range = 180.0,
        .activation_time_ms = 750,
        .aftercast_ms = 750,
        .recharge_time_ms = 8000,
        .chills = &montessori_multi_chill,
    },

    // 3. Adapts to situation
    .{
        .name = "Improvise",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 7,
        .cast_range = 200.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 12000,
        // TODO: Random beneficial effect based on situation
    },

    // 4. Movement skill
    .{
        .name = "Explore",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 4,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 10000,
        .cozies = &montessori_sure,
    },

    // 5. Learns from experience
    .{
        .name = "Growth Mindset",
        .description = "Stance. (15 seconds.) You gain +2 to all attributes.",
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
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 8,
        .cast_range = 200.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 15000,
        // TODO: Heal ally OR damage enemy
    },

    // 8. Bonus if haven't repeated skills
    .{
        .name = "Fresh Perspective",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 0,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 750,
        .recharge_time_ms = 15000,
        // TODO: Gain energy equal to number of different skill types used recently
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
    // 1. Health for damage
    .{
        .name = "Blood Pact",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 5,
        .damage = 35.0,
        .cast_range = 220.0,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 25000,
        // TODO: Sacrifice 15% max health to cast
    },

    // 2. Convert health to energy
    .{
        .name = "Isolated Study",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 0,
        .target_type = .self,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 30000,
        // TODO: Sacrifice 20% health, gain 15 energy
    },

    // 3. Crippling curse
    .{
        .name = "Malnutrition",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 10,
        .damage = 12.0,
        .cast_range = 200.0,
        .activation_time_ms = 2000,
        .aftercast_ms = 750,
        .recharge_time_ms = 30000,
        .chills = &homeschool_packed,
    },

    // 4. Execute - kills low health targets
    .{
        .name = "Final Exam",
        .description = "Throw. Deals 25 damage. Deals double damage if target foe is below 30% Health. Completely soaks through padding.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 12,
        .damage = 25.0,
        .cast_range = 220.0,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 35000,
        .soak = 1.0,
        // TODO: Deals double damage if target below 30% health
    },

    // 5. Energy drain
    .{
        .name = "Social Anxiety",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 8,
        .damage = 10.0,
        .cast_range = 200.0,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 20000,
        .chills = &homeschool_brain_freeze,
        // TODO: Steal 8 energy from target
    },

    // 6. Power at a cost
    .{
        .name = "Obsession",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 10,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 40000,
        .duration_ms = 12000,
        .cozies = &homeschool_fire,
        // TODO: +50% damage but -1 health per second
    },

    // 7. Life steal
    .{
        .name = "Vampiric Touch",
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

    // 8. Devastating AOE with health cost
    .{
        .name = "Meltdown",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 15,
        .damage = 30.0,
        .cast_range = 240.0,
        .activation_time_ms = 3000,
        .aftercast_ms = 750,
        .recharge_time_ms = 40000,
        .aoe_type = .area,
        .aoe_radius = 180.0,
        // TODO: Sacrifice 25% health to cast
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
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 5,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 20000,
        .duration_ms = 15000,
        // TODO: Alternating skill types recharge 50% faster
    },

    // 2. Team heal - harmony
    .{
        .name = "Circle Time",
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
    },

    // 3. Timing-based damage
    .{
        .name = "Perfect Pitch",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 6,
        .damage = 12.0,
        .cast_range = 200.0,
        .activation_time_ms = 750,
        .aftercast_ms = 750,
        .recharge_time_ms = 8000,
        // TODO: +100% damage if cast at exactly the right moment
    },

    // 4. Support buff
    .{
        .name = "Group Harmony",
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
        .cozies = &waldorf_hot_cocoa,
    },

    // 5. Reactive skill - counters
    .{
        .name = "Eurythmy",
        .description = "Stance. (15 seconds.) Your movement is synchronized. Move 25% faster.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 5,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 15000,
        .duration_ms = 8000,
        // TODO: Next skill instant cast
    },

    // 6. Artistic trick - control
    .{
        .name = "Flowing Motion",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 7,
        .damage = 10.0,
        .cast_range = 200.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 12000,
        .chills = &waldorf_slippery,
    },

    // 7. Vision support
    .{
        .name = "Clear Mind",
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
        .cozies = &waldorf_goggles,
    },

    // 8. Combo finisher
    .{
        .name = "Crescendo",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 10,
        .damage = 20.0,
        .cast_range = 220.0,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 15000,
        // TODO: +5 damage for each skill used in last 5 seconds
    },
};
