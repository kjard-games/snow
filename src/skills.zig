const std = @import("std");

pub const SkillTarget = enum {
    enemy,
    ally,
    self,
    ground,
};

// Skill mechanics - determines casting behavior (snowball fight timing!)
// These describe HOW the skill executes (timing), not WHAT it is (that's SkillType)
pub const SkillMechanic = enum {
    windup, // Wind up and release - projectile flies mid-animation (most throw skills)
    concentrate, // Focus required - effect at end + recovery (complex tricks)
    shout, // Quick yell - instant, no recovery needed (call skills)
    shift, // Reposition body - instant, no recovery (stance skills)
    ready, // Quick preparation - brief setup + recovery (gesture/signet skills)
    reflex, // Split-second reaction - instant, can't use while busy (future: dodges)

    pub fn hasAftercast(self: SkillMechanic) bool {
        return switch (self) {
            .windup, .concentrate, .ready => true,
            .shout, .shift, .reflex => false,
        };
    }

    pub fn canUseWhileCasting(self: SkillMechanic) bool {
        return switch (self) {
            .reflex => false, // Can't react while mid-action
            else => false, // Default: can't use while casting
        };
    }

    pub fn executesAtHalfActivation(self: SkillMechanic) bool {
        return self == .windup; // Snowball leaves hand mid-windup!
    }
};

// Thematic skill type (flavor/animation) - kept for visual variety
pub const SkillType = enum {
    throw, // Attack skills - throwing snowballs
    trick, // Magic-like abilities - special snow powers
    stance, // Movement/defensive buffs - footwork
    call, // Shouts - team buffs
    gesture, // Signets - quick utility, no energy cost
};

pub const AoeType = enum {
    single, // Single target
    adjacent, // Hits adjacent foes (like cleave)
    area, // Ground-targeted AoE
};

// Negative effects - "Chills" (debuffs)
pub const Chill = enum {
    soggy, // DoT - melting snow
    slippery, // Movement speed reduction
    numb, // Damage reduction (cold hands)
    frost_eyes, // Miss chance (snow in face)
    windburn, // DoT - cold wind
    brain_freeze, // Energy degen (ate snow)
    packed_snow, // Max health reduction
    dazed, // Attacks interrupt casts
};

// Positive effects - "Cozy" (buffs)
pub const Cozy = enum {
    bundled_up, // Damage reduction (extra layers)
    hot_cocoa, // Health regeneration over time
    fire_inside, // Increased damage output
    snow_goggles, // Cannot be blinded
    insulated, // Energy regeneration boost
    sure_footed, // Movement speed increase
    frosty_fortitude, // Max health increase
    snowball_shield, // Blocks next attack
};

pub const ChillEffect = struct {
    chill: Chill,
    duration_ms: u32, // milliseconds
    stack_intensity: u8 = 1, // some chills stack
};

pub const CozyEffect = struct {
    cozy: Cozy,
    duration_ms: u32, // milliseconds
    stack_intensity: u8 = 1, // some cozy effects stack
};

// An active chill (debuff) on a character
pub const ActiveChill = struct {
    chill: Chill,
    time_remaining_ms: u32,
    stack_intensity: u8,
    source_character_id: ?u32 = null, // who applied it (for tracking)
};

// An active cozy (buff) on a character
pub const ActiveCozy = struct {
    cozy: Cozy,
    time_remaining_ms: u32,
    stack_intensity: u8,
    source_character_id: ?u32 = null, // who applied it (for tracking)
};

pub const Skill = struct {
    name: [:0]const u8,
    skill_type: SkillType, // Thematic type (visual/animation)
    mechanic: SkillMechanic, // Mechanical type (timing behavior)
    energy_cost: u8 = 5,

    // Timing (GW1-accurate)
    activation_time_ms: u32 = 0, // 0 = instant
    aftercast_ms: u32 = 750, // Standard 3/4 second aftercast (0 for instant skills)
    recharge_time_ms: u32 = 2000, // cooldown
    duration_ms: u32 = 0, // for buffs/debuffs (0 = not applicable)

    // Damage/healing
    damage: f32 = 0.0,
    healing: f32 = 0.0,

    // Targeting
    cast_range: f32 = 200.0,
    target_type: SkillTarget = .enemy,
    aoe_type: AoeType = .single,
    aoe_radius: f32 = 0.0, // for area skills

    // Effects
    chills: []const ChillEffect = &[_]ChillEffect{}, // debuffs to apply
    cozies: []const CozyEffect = &[_]CozyEffect{}, // buffs to apply

    // Special properties
    unblockable: bool = false,
    armor_penetration: f32 = 0.0, // percentage (0.0 to 1.0)
    interrupts: bool = false, // Does this skill interrupt target's casting?
};

// Example snowball-themed skills
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
    .mechanic = .windup, // Attack skills execute at half activation
    .energy_cost = 8,
    .activation_time_ms = 1500, // 1.5 second wind-up, projectile fires at 750ms
    .aftercast_ms = 750, // Standard aftercast
    .recharge_time_ms = 5000, // 5 seconds
    .damage = 30.0,
    .cast_range = 250.0,
    .unblockable = true,
};

const soggy_chill = [_]ChillEffect{.{
    .chill = .soggy,
    .duration_ms = 5000, // 5 seconds of DoT
    .stack_intensity = 1,
}};

pub const SLUSH_BALL = Skill{
    .name = "Slush Ball",
    .skill_type = .throw,
    .mechanic = .windup, // Attack skill
    .energy_cost = 6,
    .activation_time_ms = 750, // Projectile fires at 375ms
    .aftercast_ms = 750,
    .recharge_time_ms = 8000, // 8 seconds
    .damage = 12.0,
    .cast_range = 200.0,
    .chills = &soggy_chill,
};

const frost_eyes_chill = [_]ChillEffect{.{
    .chill = .frost_eyes,
    .duration_ms = 3000, // 3 seconds of miss chance
    .stack_intensity = 1,
}};

pub const SNOW_IN_FACE = Skill{
    .name = "Snow in Face",
    .skill_type = .trick,
    .mechanic = .concentrate, // Spell - executes at end of cast
    .energy_cost = 5,
    .activation_time_ms = 500, // Cast for 500ms
    .aftercast_ms = 750, // Then 750ms aftercast
    .recharge_time_ms = 12000, // 12 seconds
    .damage = 5.0,
    .cast_range = 150.0,
    .chills = &frost_eyes_chill,
};

const slippery_chill = [_]ChillEffect{.{
    .chill = .slippery,
    .duration_ms = 4000, // 4 seconds of slow
    .stack_intensity = 1,
}};

pub const ICE_PATCH = Skill{
    .name = "Ice Patch",
    .skill_type = .trick,
    .mechanic = .concentrate,
    .energy_cost = 7,
    .activation_time_ms = 1000, // 1 second cast
    .aftercast_ms = 750,
    .recharge_time_ms = 15000, // 15 seconds
    .damage = 3.0,
    .cast_range = 300.0,
    .target_type = .ground,
    .aoe_type = .area,
    .aoe_radius = 100.0,
    .chills = &slippery_chill,
};

const snowball_shield_cozy = [_]CozyEffect{.{
    .cozy = .snowball_shield,
    .duration_ms = 5000, // 5 seconds - blocks one attack
    .stack_intensity = 1,
}};

pub const DODGE_ROLL = Skill{
    .name = "Dodge Roll",
    .skill_type = .stance,
    .mechanic = .shift, // Instant, no aftercast
    .energy_cost = 4,
    .activation_time_ms = 0, // instant
    .aftercast_ms = 0, // No aftercast for stances
    .recharge_time_ms = 8000, // 8 seconds
    .target_type = .self,
    .duration_ms = 2000, // 2 seconds of evade
    .cozies = &snowball_shield_cozy,
};

const hot_cocoa_cozy = [_]CozyEffect{.{
    .cozy = .hot_cocoa,
    .duration_ms = 10000, // 10 seconds of regen
    .stack_intensity = 1,
}};

pub const WARM_UP = Skill{
    .name = "Warm Up",
    .skill_type = .gesture,
    .mechanic = .ready, // Signets have cast time + aftercast
    .energy_cost = 0, // gestures are free
    .activation_time_ms = 0, // But this one is instant
    .aftercast_ms = 750, // Standard aftercast
    .recharge_time_ms = 20000, // 20 seconds
    .healing = 25.0,
    .target_type = .self,
    .cozies = &hot_cocoa_cozy,
};

pub const RALLY_CRY = Skill{
    .name = "Rally Cry",
    .skill_type = .call,
    .mechanic = .shout, // Shouts are instant, no aftercast
    .energy_cost = 10,
    .activation_time_ms = 0,
    .aftercast_ms = 0, // No aftercast for shouts
    .recharge_time_ms = 30000, // 30 seconds
    .healing = 15.0,
    .target_type = .ally,
    .aoe_type = .area,
    .aoe_radius = 200.0, // affects all allies in range
};

pub const PRECISION_STRIKE = Skill{
    .name = "Precision Strike",
    .skill_type = .throw,
    .mechanic = .windup, // Attack skill - executes at half activation
    .energy_cost = 7,
    .activation_time_ms = 1000, // Projectile fires at 500ms
    .aftercast_ms = 750,
    .recharge_time_ms = 10000, // 10 seconds
    .damage = 20.0,
    .cast_range = 220.0,
    .armor_penetration = 0.5, // 50% armor pen
};

const bundled_up_cozy = [_]CozyEffect{.{
    .cozy = .bundled_up,
    .duration_ms = 8000, // 8 seconds damage reduction
    .stack_intensity = 1,
}};

pub const BUNDLE_UP = Skill{
    .name = "Bundle Up",
    .skill_type = .stance,
    .mechanic = .shift, // Instant, no aftercast
    .energy_cost = 5,
    .activation_time_ms = 0,
    .aftercast_ms = 0,
    .recharge_time_ms = 15000, // 15 seconds
    .target_type = .self,
    .cozies = &bundled_up_cozy,
};

const fire_inside_cozy = [_]CozyEffect{.{
    .cozy = .fire_inside,
    .duration_ms = 12000, // 12 seconds increased damage
    .stack_intensity = 1,
}};

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

const snow_goggles_cozy = [_]CozyEffect{.{
    .cozy = .snow_goggles,
    .duration_ms = 15000, // 15 seconds blind immunity
    .stack_intensity = 1,
}};

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

const sure_footed_cozy = [_]CozyEffect{.{
    .cozy = .sure_footed,
    .duration_ms = 6000, // 6 seconds speed boost
    .stack_intensity = 1,
}};

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

// Interrupt skills - these call target.interrupt() on hit
pub const INTERRUPT_SHOT = Skill{
    .name = "Interrupt Shot",
    .skill_type = .throw,
    .mechanic = .windup, // Attack - fires at 250ms (half of 500ms)
    .energy_cost = 10,
    .activation_time_ms = 500, // Half second cast
    .aftercast_ms = 750,
    .recharge_time_ms = 10000, // 10 seconds
    .damage = 15.0,
    .cast_range = 200.0,
    .interrupts = true,
};

const dazed_chill = [_]ChillEffect{.{
    .chill = .dazed,
    .duration_ms = 5000, // 5 seconds - attacks interrupt during this time
    .stack_intensity = 1,
}};

pub const DAZING_BLOW = Skill{
    .name = "Dazing Blow",
    .skill_type = .throw,
    .mechanic = .windup,
    .energy_cost = 5,
    .activation_time_ms = 0, // Instant
    .aftercast_ms = 750,
    .recharge_time_ms = 8000, // 8 seconds
    .damage = 10.0,
    .cast_range = 180.0,
    .chills = &dazed_chill, // Applies dazed - future attacks will interrupt
};

pub const DISRUPTING_THROW = Skill{
    .name = "Disrupting Throw",
    .skill_type = .trick,
    .mechanic = .concentrate, // Spell mechanic but instant for quick interrupt
    .energy_cost = 15,
    .activation_time_ms = 0, // Instant - must be fast to interrupt
    .aftercast_ms = 750,
    .recharge_time_ms = 20000, // 20 seconds - powerful interrupt
    .damage = 5.0,
    .cast_range = 250.0,
    .interrupts = true,
    .chills = &dazed_chill,
};

// Default skill bar for new characters
pub const DEFAULT_SKILLS = [_]*const Skill{
    &QUICK_TOSS,
    &POWER_THROW,
    &SLUSH_BALL,
    &SNOW_IN_FACE,
    &BUNDLE_UP,
    &DODGE_ROLL,
    &WARM_UP,
    &GOGGLES_ON,
};
