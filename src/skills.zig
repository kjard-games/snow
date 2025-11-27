// ============================================================================
// SKILLS MODULE - Re-exports from skills/types.zig for backward compatibility
// ============================================================================
// The actual type definitions are in skills/types.zig
// School-specific skills are in skills/schools/*.zig
// Position-specific skills are in skills/positions/*.zig

const std = @import("std");
const types = @import("skills/types.zig");

// Import school skills
const private_skills = @import("skills/schools/private.zig");
const public_skills = @import("skills/schools/public.zig");
const montessori_skills = @import("skills/schools/montessori.zig");
const homeschool_skills = @import("skills/schools/homeschool.zig");
const waldorf_skills = @import("skills/schools/waldorf.zig");

// Import position skills
const pitcher_skills = @import("skills/positions/pitcher.zig");
const fielder_skills = @import("skills/positions/fielder.zig");
const sledder_skills = @import("skills/positions/sledder.zig");
const shoveler_skills = @import("skills/positions/shoveler.zig");
const animator_skills = @import("skills/positions/animator.zig");
const thermos_skills = @import("skills/positions/thermos.zig");

// Re-export all public types
pub const SkillTarget = types.SkillTarget;
pub const ProjectileType = types.ProjectileType;
pub const SkillMechanic = types.SkillMechanic;
pub const SkillType = types.SkillType;
pub const AoeType = types.AoeType;
pub const Chill = types.Chill;
pub const Cozy = types.Cozy;
pub const ChillEffect = types.ChillEffect;
pub const CozyEffect = types.CozyEffect;
pub const TerrainShape = types.TerrainShape;
pub const TerrainModifier = types.TerrainModifier;
pub const TerrainEffect = types.TerrainEffect;
pub const ActiveChill = types.ActiveChill;
pub const ActiveCozy = types.ActiveCozy;
pub const Skill = types.Skill;

// ============================================================================
// EXAMPLE SKILLS - Used for testing and demonstration
// ============================================================================
// These are generic skills for testing. Character builds use school/position skills.

const soggy_chill = [_]ChillEffect{.{
    .chill = .soggy,
    .duration_ms = 5000, // 5 seconds of DoT
    .stack_intensity = 1,
}};

const frost_eyes_chill = [_]ChillEffect{.{
    .chill = .frost_eyes,
    .duration_ms = 3000, // 3 seconds of miss chance
    .stack_intensity = 1,
}};

const slippery_chill = [_]ChillEffect{.{
    .chill = .slippery,
    .duration_ms = 4000, // 4 seconds of slow
    .stack_intensity = 1,
}};

const snowball_shield_cozy = [_]CozyEffect{.{
    .cozy = .snowball_shield,
    .duration_ms = 5000, // 5 seconds - blocks one attack
    .stack_intensity = 1,
}};

const hot_cocoa_cozy = [_]CozyEffect{.{
    .cozy = .hot_cocoa,
    .duration_ms = 10000, // 10 seconds of regen
    .stack_intensity = 1,
}};

const bundled_up_cozy = [_]CozyEffect{.{
    .cozy = .bundled_up,
    .duration_ms = 8000, // 8 seconds damage reduction
    .stack_intensity = 1,
}};

const fire_inside_cozy = [_]CozyEffect{.{
    .cozy = .fire_inside,
    .duration_ms = 12000, // 12 seconds increased damage
    .stack_intensity = 1,
}};

const snow_goggles_cozy = [_]CozyEffect{.{
    .cozy = .snow_goggles,
    .duration_ms = 15000, // 15 seconds blind immunity
    .stack_intensity = 1,
}};

const sure_footed_cozy = [_]CozyEffect{.{
    .cozy = .sure_footed,
    .duration_ms = 6000, // 6 seconds speed boost
    .stack_intensity = 1,
}};

pub const QUICK_TOSS = Skill{
    .name = "Quick Toss",
    .skill_type = .throw,
    .mechanic = .windup,
    .energy_cost = 3,
    .activation_time_ms = 0, // instant
    .aftercast_ms = 750, // Standard aftercast
    .recharge_time_ms = 1000, // 1 second
    .damage = 8.0,
    .cast_range = 180.0,
};

pub const POWER_THROW = Skill{
    .name = "Power Throw",
    .skill_type = .throw,
    .mechanic = .windup,
    .energy_cost = 8,
    .activation_time_ms = 1500, // 1.5 second wind-up
    .aftercast_ms = 750,
    .recharge_time_ms = 5000, // 5 seconds
    .damage = 30.0,
    .cast_range = 250.0,
    .unblockable = true,
};

pub const SLUSH_BALL = Skill{
    .name = "Slush Ball",
    .skill_type = .throw,
    .mechanic = .windup,
    .energy_cost = 6,
    .activation_time_ms = 750,
    .aftercast_ms = 750,
    .recharge_time_ms = 8000, // 8 seconds
    .damage = 12.0,
    .cast_range = 200.0,
    .chills = &soggy_chill,
};

pub const SNOW_IN_FACE = Skill{
    .name = "Snow in Face",
    .skill_type = .trick,
    .mechanic = .concentrate,
    .energy_cost = 5,
    .activation_time_ms = 500,
    .aftercast_ms = 750,
    .recharge_time_ms = 12000, // 12 seconds
    .damage = 5.0,
    .cast_range = 150.0,
    .chills = &frost_eyes_chill,
};

pub const ICE_PATCH = Skill{
    .name = "Ice Patch",
    .skill_type = .trick,
    .mechanic = .concentrate,
    .energy_cost = 7,
    .activation_time_ms = 1000,
    .aftercast_ms = 750,
    .recharge_time_ms = 15000, // 15 seconds
    .damage = 3.0,
    .cast_range = 300.0,
    .target_type = .ground,
    .aoe_type = .area,
    .aoe_radius = 100.0,
    .chills = &slippery_chill,
};

pub const DODGE_ROLL = Skill{
    .name = "Dodge Roll",
    .skill_type = .stance,
    .mechanic = .shift,
    .energy_cost = 4,
    .activation_time_ms = 0, // instant
    .aftercast_ms = 0, // No aftercast for stances
    .recharge_time_ms = 8000, // 8 seconds
    .target_type = .self,
    .duration_ms = 2000, // 2 seconds of evade
    .cozies = &snowball_shield_cozy,
};

pub const WARM_UP = Skill{
    .name = "Warm Up",
    .skill_type = .gesture,
    .mechanic = .ready,
    .energy_cost = 0, // gestures are free
    .activation_time_ms = 0,
    .aftercast_ms = 750,
    .recharge_time_ms = 20000, // 20 seconds
    .healing = 25.0,
    .target_type = .self,
    .cozies = &hot_cocoa_cozy,
};

pub const RALLY_CRY = Skill{
    .name = "Rally Cry",
    .skill_type = .call,
    .mechanic = .shout,
    .energy_cost = 10,
    .activation_time_ms = 0,
    .aftercast_ms = 0, // No aftercast for shouts
    .recharge_time_ms = 30000, // 30 seconds
    .healing = 15.0,
    .target_type = .ally,
    .aoe_type = .area,
    .aoe_radius = 200.0,
};

pub const PRECISION_STRIKE = Skill{
    .name = "Precision Strike",
    .skill_type = .throw,
    .mechanic = .windup,
    .energy_cost = 7,
    .activation_time_ms = 1000,
    .aftercast_ms = 750,
    .recharge_time_ms = 10000, // 10 seconds
    .damage = 20.0,
    .cast_range = 220.0,
    .soak = 0.5, // 50% soak
};

pub const BUNDLE_UP = Skill{
    .name = "Bundle Up",
    .skill_type = .stance,
    .mechanic = .shift,
    .energy_cost = 5,
    .activation_time_ms = 0,
    .aftercast_ms = 0,
    .recharge_time_ms = 15000, // 15 seconds
    .target_type = .self,
    .cozies = &bundled_up_cozy,
};

pub const BURNING_RAGE = Skill{
    .name = "Burning Rage",
    .skill_type = .stance,
    .mechanic = .shift,
    .energy_cost = 6,
    .activation_time_ms = 0,
    .aftercast_ms = 0,
    .recharge_time_ms = 20000, // 20 seconds
    .target_type = .self,
    .cozies = &fire_inside_cozy,
};

pub const GOGGLES_ON = Skill{
    .name = "Goggles On",
    .skill_type = .gesture,
    .mechanic = .ready,
    .energy_cost = 0,
    .activation_time_ms = 0,
    .aftercast_ms = 750,
    .recharge_time_ms = 25000, // 25 seconds
    .target_type = .self,
    .cozies = &snow_goggles_cozy,
};

pub const SPRINT = Skill{
    .name = "Sprint",
    .skill_type = .stance,
    .mechanic = .shift,
    .energy_cost = 4,
    .activation_time_ms = 0,
    .aftercast_ms = 0,
    .recharge_time_ms = 12000, // 12 seconds
    .target_type = .self,
    .cozies = &sure_footed_cozy,
};

// ============================================================================
// DEFAULT SKILL LISTS (for testing/fallback)
// ============================================================================

pub const DEFAULT_SKILLS = [_]Skill{
    QUICK_TOSS,
    POWER_THROW,
    SLUSH_BALL,
    SNOW_IN_FACE,
    ICE_PATCH,
    DODGE_ROLL,
    WARM_UP,
    RALLY_CRY,
};

// ============================================================================
// AP SKILL COLLECTION AND RANDOM SELECTION
// ============================================================================
// AP (Advanced Placement) skills are powerful build-defining abilities.
// This function collects all AP skills from all schools and positions.

const ALL_SKILL_ARRAYS = [_][]const Skill{
    // School skills
    &private_skills.skills,
    &public_skills.skills,
    &montessori_skills.skills,
    &homeschool_skills.skills,
    &waldorf_skills.skills,
    // Position skills
    &pitcher_skills.skills,
    &fielder_skills.skills,
    &sledder_skills.skills,
    &shoveler_skills.skills,
    &animator_skills.skills,
    &thermos_skills.skills,
};

// Count AP skills at comptime for array sizing
const AP_SKILL_COUNT = countAPSkills();

fn countAPSkills() usize {
    var count: usize = 0;
    for (ALL_SKILL_ARRAYS) |skill_array| {
        for (skill_array) |skill| {
            if (skill.is_ap) count += 1;
        }
    }
    return count;
}

// Build comptime array of all AP skills
const ALL_AP_SKILLS = buildAPSkillArray();

fn buildAPSkillArray() [AP_SKILL_COUNT]*const Skill {
    var ap_skills: [AP_SKILL_COUNT]*const Skill = undefined;
    var idx: usize = 0;
    for (ALL_SKILL_ARRAYS) |skill_array| {
        for (skill_array) |*skill| {
            if (skill.is_ap) {
                ap_skills[idx] = skill;
                idx += 1;
            }
        }
    }
    return ap_skills;
}

/// Returns a random AP skill from all schools and positions
pub fn getRandomAPSkill(rng: *std.Random) *const Skill {
    if (AP_SKILL_COUNT == 0) {
        // Fallback to a default skill if no AP skills exist
        return &QUICK_TOSS;
    }
    const idx = rng.intRangeAtMost(usize, 0, AP_SKILL_COUNT - 1);
    return ALL_AP_SKILLS[idx];
}
