const std = @import("std");
const skills = @import("skills.zig");
const school_mod = @import("school.zig");

pub const Skill = skills.Skill;
pub const School = school_mod.School;

pub const Position = enum {
    pitcher, // Pure Damage Dealer - the kid with the cannon arm
    fielder, // Balanced Generalist - athletic all-rounder
    sledder, // Aggressive Skirmisher - sled charge attacks
    shoveler, // Tank/Defender - digs in, builds walls
    animator, // Summoner/Necromancer - brings snowmen to life (Calvin & Hobbes style)
    thermos, // Healer/Support - brings hot cocoa and hand warmers

    pub fn getSkills(self: Position) []const Skill {
        return switch (self) {
            .pitcher => &pitcher_skills,
            .fielder => &fielder_skills,
            .sledder => &sledder_skills,
            .shoveler => &shoveler_skills,
            .animator => &animator_skills,
            .thermos => &thermos_skills,
        };
    }

    pub fn getDescription(self: Position) [:0]const u8 {
        return switch (self) {
            .pitcher => "Pure Damage Dealer - high damage, long range, fragile",
            .fielder => "Balanced Generalist - adapts to any situation",
            .sledder => "Aggressive Skirmisher - high mobility, in-your-face combat",
            .shoveler => "Tank/Defender - absorbs damage, protects others",
            .animator => "Summoner/Necromancer - brings grotesque snowmen to life",
            .thermos => "Healer/Support - shares cocoa, hand warmers, and comfort",
        };
    }

    pub fn getPrimarySchools(self: Position) []const School {
        return switch (self) {
            .pitcher => &[_]School{ .public_school, .homeschool },
            .fielder => &[_]School{ .montessori, .public_school },
            .sledder => &[_]School{ .public_school, .waldorf },
            .shoveler => &[_]School{ .private_school, .homeschool },
            .animator => &[_]School{ .homeschool, .waldorf },
            .thermos => &[_]School{ .waldorf, .private_school },
        };
    }

    pub fn getRangeMin(self: Position) f32 {
        return switch (self) {
            .pitcher => 200.0,
            .fielder => 150.0,
            .sledder => 80.0,
            .shoveler => 100.0,
            .animator => 180.0,
            .thermos => 150.0,
        };
    }

    pub fn getRangeMax(self: Position) f32 {
        return switch (self) {
            .pitcher => 300.0,
            .fielder => 220.0,
            .sledder => 150.0,
            .shoveler => 160.0,
            .animator => 240.0,
            .thermos => 200.0,
        };
    }
};

// ============================================================================
// PITCHER SKILLS - Long-range damage dealer (200-300 range)
// ============================================================================
// Synergizes with: Throw buffs, damage amplifiers, energy management
// Counterplay: Close the gap, interrupt long casts, drain energy

const windburn_chill = [_]skills.ChillEffect{.{
    .chill = .windburn,
    .duration_ms = 5000,
    .stack_intensity = 1,
}};

const soggy_chill = [_]skills.ChillEffect{.{
    .chill = .soggy,
    .duration_ms = 6000,
    .stack_intensity = 1,
}};

const pitcher_skills = [_]Skill{
    // 1. Fast, reliable damage - your bread and butter
    .{
        .name = "Fastball",
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
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 8,
        .damage = 15.0, // +15 more if target has a chill = 30 total
        .cast_range = 250.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 8000,
        // TODO: Add conditional: +15 damage if target has any chill
    },

    // 3. AoE pressure - hits adjacent foes
    .{
        .name = "Slushball Barrage",
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

    // 5. Maximum range poke - safe but slow
    .{
        .name = "Lob",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 6,
        .damage = 14.0,
        .cast_range = 300.0,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 6000,
    },

    // 6. Execute - bonus damage vs low health
    .{
        .name = "Headshot",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 12,
        .damage = 20.0, // +20 more if target below 50% = 40 total
        .cast_range = 240.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 15000,
        .armor_penetration = 0.5,
        // TODO: Add conditional: +20 damage if target below 50% health
    },

    // 7. DoT application - sustained pressure
    .{
        .name = "Windburn Throw",
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
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 3,
        .damage = 12.0,
        .cast_range = 220.0,
        .activation_time_ms = 500,
        .aftercast_ms = 750,
        .recharge_time_ms = 3000,
    },
};

// ============================================================================
// FIELDER SKILLS - Balanced generalist (150-220 range)
// ============================================================================
// Synergizes with: Variety bonuses, adaptability, versatile skill types
// Counterplay: Specialization beats generalization

const slippery_chill = [_]skills.ChillEffect{.{
    .chill = .slippery,
    .duration_ms = 4000,
    .stack_intensity = 1,
}};

const sure_footed_cozy = [_]skills.CozyEffect{.{
    .cozy = .sure_footed,
    .duration_ms = 6000,
    .stack_intensity = 1,
}};

const fielder_skills = [_]Skill{
    // 1. Versatile throw - good at everything
    .{
        .name = "All-Rounder",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 5,
        .damage = 15.0,
        .cast_range = 180.0,
        .activation_time_ms = 750,
        .aftercast_ms = 750,
        .recharge_time_ms = 5000,
    },

    // 2. Repositioning tool - mobility + utility
    .{
        .name = "Dive Roll",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 5,
        .cast_range = 0,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 10000,
        .cozies = &sure_footed_cozy,
        // TODO: Add dash/evade mechanic
    },

    // 3. Control tool - slows enemies
    .{
        .name = "Trip Up",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 6,
        .damage = 8.0,
        .cast_range = 160.0,
        .activation_time_ms = 500,
        .aftercast_ms = 750,
        .recharge_time_ms = 8000,
        .chills = &slippery_chill,
    },

    // 4. Long range option - can play like pitcher
    .{
        .name = "Long Toss",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 6,
        .damage = 13.0,
        .cast_range = 220.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 6000,
    },

    // 5. Close range option - can play like sledder
    .{
        .name = "Point Blank",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 7,
        .damage = 18.0,
        .cast_range = 150.0,
        .activation_time_ms = 500,
        .aftercast_ms = 750,
        .recharge_time_ms = 7000,
        // TODO: Bonus damage if within 100 range
    },

    // 6. Utility trick - removes chill from self
    .{
        .name = "Shake It Off",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 0,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 750,
        .recharge_time_ms = 15000,
        // TODO: Remove 1 chill from self
    },

    // 7. Team call - provides minor buff
    .{
        .name = "Rally",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 8,
        .cast_range = 200.0,
        .target_type = .ally,
        .aoe_type = .area,
        .aoe_radius = 200.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 20000,
        // TODO: Grant minor cozy to allies
    },

    // 8. Fast response - instant cast
    .{
        .name = "Snap Throw",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 4,
        .damage = 11.0,
        .cast_range = 170.0,
        .activation_time_ms = 0,
        .aftercast_ms = 750,
        .recharge_time_ms = 4000,
    },
};

// ============================================================================
// SLEDDER SKILLS - Aggressive skirmisher (80-150 range)
// ============================================================================
// Synergizes with: Movement speed, close-range damage, rhythm skills
// Counterplay: Kiting, snares, keeping distance

const fire_inside_cozy = [_]skills.CozyEffect{.{
    .cozy = .fire_inside,
    .duration_ms = 8000,
    .stack_intensity = 1,
}};

const numb_chill = [_]skills.ChillEffect{.{
    .chill = .numb,
    .duration_ms = 5000,
    .stack_intensity = 1,
}};

const sledder_skills = [_]Skill{
    // 1. Gap closer - mobility + damage
    .{
        .name = "Downhill Charge",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 8,
        .damage = 22.0,
        .cast_range = 120.0,
        .activation_time_ms = 750,
        .aftercast_ms = 750,
        .recharge_time_ms = 10000,
        // TODO: Dash toward target before damage
    },

    // 2. Melee burst - highest damage at close range
    .{
        .name = "Ram",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 10,
        .damage = 28.0,
        .cast_range = 80.0,
        .activation_time_ms = 500,
        .aftercast_ms = 750,
        .recharge_time_ms = 8000,
    },

    // 3. AoE sweep - hits all nearby
    .{
        .name = "Snow Spray",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 7,
        .damage = 12.0,
        .cast_range = 100.0,
        .activation_time_ms = 500,
        .aftercast_ms = 750,
        .recharge_time_ms = 6000,
        .aoe_type = .adjacent,
    },

    // 4. Sustained aggression buff
    .{
        .name = "Adrenaline Rush",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 6,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 15000,
        .cozies = &fire_inside_cozy,
    },

    // 5. Sliding attack - move while attacking
    .{
        .name = "Drift Strike",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 6,
        .damage = 16.0,
        .cast_range = 110.0,
        .activation_time_ms = 500,
        .aftercast_ms = 750,
        .recharge_time_ms = 5000,
        // TODO: Can move during activation
    },

    // 6. Jump attack - unblockable
    .{
        .name = "Aerial Assault",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 9,
        .damage = 20.0,
        .cast_range = 130.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 12000,
        .unblockable = true,
    },

    // 7. Debilitating strike - reduces enemy damage
    .{
        .name = "Crushing Blow",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 7,
        .damage = 14.0,
        .cast_range = 100.0,
        .activation_time_ms = 750,
        .aftercast_ms = 750,
        .recharge_time_ms = 10000,
        .chills = &numb_chill,
    },

    // 8. Speed boost stance
    .{
        .name = "Sprint",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 5,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 12000,
        .cozies = &sure_footed_cozy,
    },
};

// ============================================================================
// SHOVELER SKILLS - Tank/Defender (100-160 range)
// ============================================================================
// Synergizes with: Defensive buffs, health, fortifications
// Counterplay: Sustained damage, armor penetration, ignore and focus others

const bundled_up_cozy = [_]skills.CozyEffect{.{
    .cozy = .bundled_up,
    .duration_ms = 10000,
    .stack_intensity = 1,
}};

const frosty_fortitude_cozy = [_]skills.CozyEffect{.{
    .cozy = .frosty_fortitude,
    .duration_ms = 15000,
    .stack_intensity = 1,
}};

const snowball_shield_cozy = [_]skills.CozyEffect{.{
    .cozy = .snowball_shield,
    .duration_ms = 8000,
    .stack_intensity = 1,
}};

const shoveler_skills = [_]Skill{
    // 1. Armor stance - damage reduction
    .{
        .name = "Dig In",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 6,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 20000,
        .cozies = &bundled_up_cozy,
    },

    // 2. Health boost
    .{
        .name = "Fortify",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 8,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 25000,
        .cozies = &frosty_fortitude_cozy,
    },

    // 3. Block stance
    .{
        .name = "Snow Wall",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 7,
        .target_type = .self,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 15000,
        .cozies = &snowball_shield_cozy,
        // TODO: Blocks next N attacks
    },

    // 4. Counter attack - damage when attacked
    .{
        .name = "Retribution",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 5,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 12000,
        .duration_ms = 8000,
        // TODO: Reflect % damage back to attacker
    },

    // 5. Taunt - force enemies to target you
    .{
        .name = "Challenge",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 6,
        .cast_range = 200.0,
        .aoe_type = .area,
        .aoe_radius = 200.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 20000,
        // TODO: Taunt mechanic
    },

    // 6. Moderate damage throw
    .{
        .name = "Shovel Toss",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 5,
        .damage = 14.0,
        .cast_range = 140.0,
        .activation_time_ms = 750,
        .aftercast_ms = 750,
        .recharge_time_ms = 5000,
    },

    // 7. Ground hazard - creates defensive zone
    .{
        .name = "Ice Wall",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 10,
        .cast_range = 200.0,
        .target_type = .ground,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 30000,
        .duration_ms = 15000,
        // TODO: Creates wall terrain
    },

    // 8. Self-heal
    .{
        .name = "Second Wind",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 0,
        .healing = 40.0,
        .target_type = .self,
        .activation_time_ms = 2000,
        .aftercast_ms = 750,
        .recharge_time_ms = 20000,
    },
};

// ============================================================================
// ANIMATOR SKILLS - Summoner/Necromancer (180-240 range)
// ============================================================================
// Synergizes with: Summon buffs, corpse mechanics, isolation bonuses
// Counterplay: AoE damage, focus summons first, dispel
// TODO: Implement proper summon mechanics

const brain_freeze_chill = [_]skills.ChillEffect{.{
    .chill = .brain_freeze,
    .duration_ms = 8000,
    .stack_intensity = 1,
}};

const packed_snow_chill = [_]skills.ChillEffect{.{
    .chill = .packed_snow,
    .duration_ms = 10000,
    .stack_intensity = 1,
}};

const animator_skills = [_]Skill{
    // 1. Basic summon - weak but cheap
    .{
        .name = "Snowman Minion",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 8,
        .cast_range = 200.0,
        .target_type = .ground,
        .activation_time_ms = 2000,
        .aftercast_ms = 750,
        .recharge_time_ms = 15000,
        .duration_ms = 30000,
        // TODO: Summon level 1-5 snowman, attacks for 5 damage
    },

    // 2. Elite summon - powerful but expensive
    .{
        .name = "Grotesque Abomination",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 15,
        .cast_range = 220.0,
        .target_type = .ground,
        .activation_time_ms = 3000,
        .aftercast_ms = 750,
        .recharge_time_ms = 45000,
        .duration_ms = 45000,
        // TODO: Summon level 10-15 abomination, attacks for 15 damage
    },

    // 3. Exploding summon - dies and damages
    .{
        .name = "Suicide Snowman",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 10,
        .cast_range = 200.0,
        .target_type = .ground,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 20000,
        .duration_ms = 15000,
        // TODO: Summon snowman that explodes on death for AoE damage
    },

    // 4. Buff summons
    .{
        .name = "Unholy Strength",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 6,
        .cast_range = 300.0,
        .aoe_type = .area,
        .aoe_radius = 300.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 20000,
        .duration_ms = 10000,
        // TODO: Summons deal +50% damage
    },

    // 5. Heal summons
    .{
        .name = "Restore Construct",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 8,
        .healing = 60.0,
        .cast_range = 240.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 10000,
        // TODO: Target allied summon only
    },

    // 6. Corpse exploitation - use dead bodies
    .{
        .name = "Soul Harvest",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 5,
        .cast_range = 200.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 5000,
        // TODO: Gain energy from nearby corpses (3 per corpse)
    },

    // 7. Crippling curse
    .{
        .name = "Withering Curse",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 10,
        .damage = 8.0,
        .cast_range = 220.0,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 15000,
        .chills = &packed_snow_chill,
    },

    // 8. Energy drain
    .{
        .name = "Sap Will",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 7,
        .damage = 10.0,
        .cast_range = 200.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 12000,
        .chills = &brain_freeze_chill,
        // TODO: Steal 5 energy from target
    },
};

// ============================================================================
// THERMOS SKILLS - Healer/Support (150-200 range)
// ============================================================================
// Synergizes with: Healing bonuses, team buffs, rhythm skills
// Counterplay: Interrupt heals, focus healer first, spread damage

const hot_cocoa_cozy = [_]skills.CozyEffect{.{
    .cozy = .hot_cocoa,
    .duration_ms = 12000,
    .stack_intensity = 1,
}};

const insulated_cozy = [_]skills.CozyEffect{.{
    .cozy = .insulated,
    .duration_ms = 15000,
    .stack_intensity = 1,
}};

const snow_goggles_cozy = [_]skills.CozyEffect{.{
    .cozy = .snow_goggles,
    .duration_ms = 10000,
    .stack_intensity = 1,
}};

const frost_eyes_chill = [_]skills.ChillEffect{.{
    .chill = .frost_eyes,
    .duration_ms = 5000,
    .stack_intensity = 1,
}};

const thermos_skills = [_]Skill{
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
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 7,
        .cast_range = 180.0,
        .target_type = .ally,
        .activation_time_ms = 750,
        .aftercast_ms = 750,
        .recharge_time_ms = 10000,
        .cozies = &hot_cocoa_cozy,
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
        // TODO: Remove 1-2 chills from target
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
        // TODO: Target gains +5 energy immediately
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
};
