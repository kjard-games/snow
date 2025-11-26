const std = @import("std");
const rl = @import("raylib");
const character = @import("character.zig");
const skills = @import("skills.zig");
const effects = @import("effects.zig");
const vfx = @import("vfx.zig");
const terrain_mod = @import("terrain.zig");
const school = @import("school.zig");

const Character = character.Character;
const Skill = skills.Skill;
const School = school.School;
const print = std.debug.print;

// ============================================================================
// COMBAT DAMAGE - Damage calculation pipeline
// ============================================================================
// This module handles the full damage calculation pipeline:
// 1. Base damage from skill
// 2. Caster offensive modifiers (buffs, debuffs)
// 3. Target defensive modifiers (buffs, debuffs)
// 4. Armor/padding reduction (GW1-style formula)
// 5. Soak (armor penetration)
// 6. Cover mechanics (walls reduce damage)
// 7. Miss chance (Frost Eyes debuff)
// 8. Block chance (Snowball Shield)
//
// Design: Separating damage calculation allows for:
// - Damage preview (show expected damage before cast)
// - Consistent damage formula across skills and auto-attacks
// - Easy balance tuning (all damage math in one place)

// ============================================================================
// DAMAGE CONTEXT - All info needed for damage calculation
// ============================================================================

pub const DamageContext = struct {
    caster: *Character,
    target: *Character,
    skill: *const Skill,
    terrain_grid: *terrain_mod.TerrainGrid,
    rng: *std.Random,
    vfx_manager: *vfx.VFXManager,
};

// ============================================================================
// DAMAGE RESULT - Outcome of damage calculation
// ============================================================================

pub const DamageResult = struct {
    /// Final damage after all modifiers
    final_damage: f32,
    /// Whether the attack missed
    missed: bool = false,
    /// Whether the attack was blocked
    blocked: bool = false,
    /// Whether cover reduced damage
    cover_applied: bool = false,
    /// Damage multiplier from cover (1.0 = no cover)
    cover_multiplier: f32 = 1.0,

    pub fn wasNegated(self: DamageResult) bool {
        return self.missed or self.blocked;
    }
};

// ============================================================================
// MODIFIER CALCULATIONS
// ============================================================================

/// Calculate caster's offensive damage multiplier from conditions
pub fn calculateCasterOffensiveMultiplier(caster: *const Character) f32 {
    var multiplier: f32 = 1.0;

    // Chill debuffs reduce damage
    if (caster.hasChill(.numb)) {
        multiplier *= 0.5; // Numb reduces damage by 50%
    }

    // Cozy buffs increase damage
    if (caster.hasCozy(.fire_inside)) {
        multiplier *= 1.3; // Fire Inside increases damage by 30%
    }

    // Apply active effect damage multipliers
    const effect_mult = effects.calculateDamageMultiplier(
        &caster.conditions.effects.active,
        caster.conditions.effects.count,
    );
    multiplier *= effect_mult;

    // School-specific damage bonuses
    multiplier *= calculateSchoolDamageBonus(caster);

    return multiplier;
}

/// Calculate school-specific damage bonuses
pub fn calculateSchoolDamageBonus(caster: *const Character) f32 {
    var multiplier: f32 = 1.0;

    switch (caster.school) {
        .montessori => {
            // Variety bonus: Using different skill types grants damage bonus
            // 0 unique = 0%, 2 = 10%, 3 = 20%, 4 = 30%, 5 = 40-50%
            multiplier *= caster.school_resources.variety.getDamageMultiplier();
        },
        .private_school => {
            // Debt bonus: Some skills get bonus damage when in debt
            // This is skill-specific and handled in calculateDamage
            // But we can add a general small bonus for being in debt
            if (caster.school_resources.credit_debt.isInDebt()) {
                // Small general bonus for being in debt (risk/reward)
                multiplier *= 1.05; // 5% bonus damage while in debt
            }
        },
        .public_school => {
            // Grit bonus: More grit = slightly more damage (adrenaline rush)
            // Small incremental bonus based on grit stacks
            const grit_bonus = @as(f32, @floatFromInt(caster.school_resources.grit.stacks)) * 0.02;
            multiplier *= (1.0 + grit_bonus); // 2% per grit stack (up to 10% at max)
        },
        .waldorf => {
            // Rhythm bonus: Being "in rhythm" grants bonus damage
            if (caster.school_resources.rhythm.isInPerfectWindow()) {
                multiplier *= 1.1; // 10% bonus in perfect timing window
            }
        },
        .homeschool => {
            // Sacrifice bonus: Lower health = more damage (desperate power)
            const health_percent = caster.stats.warmth / caster.stats.max_warmth;
            if (health_percent < 0.5) {
                // Below 50% health: bonus damage scaling up to 20%
                const missing_health_factor = (0.5 - health_percent) * 2.0; // 0 to 1
                multiplier *= (1.0 + missing_health_factor * 0.2); // Up to 20% bonus
            }
        },
    }

    return multiplier;
}

/// Calculate target's defensive damage multiplier from conditions
pub fn calculateTargetDefensiveMultiplier(target: *const Character) f32 {
    var multiplier: f32 = 1.0;

    // Cozy buffs reduce incoming damage
    if (target.hasCozy(.bundled_up)) {
        multiplier *= 0.75; // Bundled Up reduces incoming damage by 25%
    }

    // Apply active effect damage multipliers (some make target take MORE damage)
    const effect_mult = effects.calculateDamageMultiplier(
        &target.conditions.effects.active,
        target.conditions.effects.count,
    );
    multiplier *= effect_mult;

    return multiplier;
}

/// Calculate armor reduction using GW1-inspired formula
/// Formula: damage_reduction = armor / (armor + 100)
/// Final damage = base_damage × (1 - damage_reduction)
pub fn calculateArmorReduction(target: *const Character) f32 {
    var target_padding = target.getTotalPadding();

    // Apply active effect armor multipliers
    const armor_mult = effects.calculateArmorMultiplier(
        &target.conditions.effects.active,
        target.conditions.effects.count,
    );
    target_padding *= armor_mult;

    // GW1-style armor formula
    const armor_reduction = target_padding / (target_padding + 100.0);
    return 1.0 - armor_reduction;
}

/// Calculate damage with soak (armor penetration)
/// Soak reduces effective armor before damage calculation
pub fn calculateSoakDamage(base_damage: f32, soak: f32, target: *const Character, caster: *const Character) f32 {
    if (soak <= 0) return base_damage;

    var target_padding = target.getTotalPadding();

    // Apply armor effect multipliers
    const armor_mult = effects.calculateArmorMultiplier(
        &target.conditions.effects.active,
        target.conditions.effects.count,
    );
    target_padding *= armor_mult;

    // Soak penetrates a percentage of armor
    const effective_padding = target_padding * (1.0 - soak);
    const soaked_reduction = effective_padding / (effective_padding + 100.0);
    var final_damage = base_damage * (1.0 - soaked_reduction);

    // Re-apply fire inside bonus after soak
    if (caster.hasCozy(.fire_inside)) {
        final_damage *= 1.3;
    }

    return final_damage;
}

/// Check if target has cover from a wall (for direct/instant projectiles)
pub fn checkCover(ctx: DamageContext) struct { has_cover: bool, multiplier: f32 } {
    // Only direct and instant projectiles are affected by cover
    if (ctx.skill.projectile_type != .direct and ctx.skill.projectile_type != .instant) {
        return .{ .has_cover = false, .multiplier = 1.0 };
    }

    const min_wall_height = 20.0; // Walls must be at least 20 units to provide cover
    const has_wall = ctx.terrain_grid.hasWallBetween(
        ctx.caster.position.x,
        ctx.caster.position.z,
        ctx.target.position.x,
        ctx.target.position.z,
        min_wall_height,
    );

    if (has_wall) {
        print("{s}'s attack reduced by cover!\n", .{ctx.caster.name});
        return .{ .has_cover = true, .multiplier = 0.4 }; // 60% damage reduction
    }

    return .{ .has_cover = false, .multiplier = 1.0 };
}

/// Check if attack misses due to Frost Eyes debuff
pub fn checkMiss(ctx: DamageContext) bool {
    if (!ctx.caster.hasChill(.frost_eyes)) return false;

    // 50% miss chance
    const rand = ctx.rng.intRangeAtMost(u8, 0, 99);
    if (rand < 50) {
        ctx.vfx_manager.spawnDamageNumber(0, ctx.target.position, .miss);
        print("{s} missed {s} due to Frost Eyes!\n", .{ ctx.caster.name, ctx.target.name });
        return true;
    }

    return false;
}

/// Check if attack is blocked by Snowball Shield
/// Returns true if blocked (and removes the shield)
pub fn checkBlock(target: *Character) bool {
    if (!target.hasCozy(.snowball_shield)) return false;

    // Remove the shield after blocking
    for (target.conditions.cozies.cozies[0..target.conditions.cozies.count]) |*maybe_cozy| {
        if (maybe_cozy.*) |*cozy| {
            if (cozy.cozy == .snowball_shield) {
                maybe_cozy.* = null;
                break;
            }
        }
    }

    return true;
}

// ============================================================================
// MAIN DAMAGE CALCULATION
// ============================================================================

/// Calculate final damage for a skill hit
/// This is the main entry point for damage calculation
pub fn calculateDamage(ctx: DamageContext) DamageResult {
    var result = DamageResult{
        .final_damage = ctx.skill.damage,
    };

    // No damage to calculate
    if (result.final_damage <= 0) return result;

    // Step 1: Check miss (Frost Eyes)
    if (checkMiss(ctx)) {
        result.missed = true;
        result.final_damage = 0;
        return result;
    }

    // Step 2: Check block (Snowball Shield)
    if (checkBlock(ctx.target)) {
        print("{s}'s Snowball Shield blocked {s}!\n", .{ ctx.target.name, ctx.skill.name });
        result.blocked = true;
        result.final_damage = 0;
        return result;
    }

    // Step 3: Apply caster offensive modifiers (includes school bonuses)
    result.final_damage *= calculateCasterOffensiveMultiplier(ctx.caster);

    // Step 3b: Apply skill-specific debt bonus (Private School)
    if (ctx.skill.bonus_if_in_debt and ctx.caster.school == .private_school) {
        if (ctx.caster.school_resources.credit_debt.isInDebt()) {
            result.final_damage *= 1.25; // 25% bonus for skill designed for debt play
            print("{s}'s skill enhanced by debt!\n", .{ctx.caster.name});
        }
    }

    // Step 3c: Apply warmth-conditional bonuses (GW1-style)
    result.final_damage *= calculateWarmthConditionalBonus(ctx.caster, ctx.target, ctx.skill);

    // Step 3d: Apply rhythm-consumed flat damage bonus (Waldorf Crescendo-style)
    if (ctx.skill.damage_per_rhythm_consumed > 0 and ctx.caster.school == .waldorf) {
        const rhythm_bonus = @as(f32, @floatFromInt(ctx.caster.school_resources.rhythm.last_consumed)) *
            ctx.skill.damage_per_rhythm_consumed;
        if (rhythm_bonus > 0) {
            result.final_damage += rhythm_bonus;
            print("{s}'s skill deals +{d:.0} bonus damage from {d} rhythm!\n", .{
                ctx.caster.name,
                rhythm_bonus,
                ctx.caster.school_resources.rhythm.last_consumed,
            });
        }
    }

    // Step 4: Apply target defensive modifiers
    result.final_damage *= calculateTargetDefensiveMultiplier(ctx.target);

    // Step 5: Apply armor reduction (or soak if skill has it)
    if (ctx.skill.soak > 0) {
        result.final_damage = calculateSoakDamage(
            ctx.skill.damage, // Use base damage for soak calculation
            ctx.skill.soak,
            ctx.target,
            ctx.caster,
        );
    } else {
        result.final_damage *= calculateArmorReduction(ctx.target);
    }

    // Step 6: Apply cover mechanics
    const cover = checkCover(ctx);
    if (cover.has_cover) {
        result.cover_applied = true;
        result.cover_multiplier = cover.multiplier;
        result.final_damage *= cover.multiplier;
    }

    return result;
}

/// Calculate warmth-conditional damage bonuses (GW1-style health conditionals)
fn calculateWarmthConditionalBonus(caster: *const Character, target: *const Character, skill: *const Skill) f32 {
    var multiplier: f32 = 1.0;

    const caster_health_percent = caster.stats.warmth / caster.stats.max_warmth;
    const target_health_percent = target.stats.warmth / target.stats.max_warmth;

    // Self health conditionals
    if (skill.bonus_damage_if_self_above_50_warmth > 0 and caster_health_percent > 0.5) {
        multiplier += skill.bonus_damage_if_self_above_50_warmth;
    }
    if (skill.bonus_damage_if_self_below_50_warmth > 0 and caster_health_percent < 0.5) {
        multiplier += skill.bonus_damage_if_self_below_50_warmth;
    }

    // Target health conditionals
    if (skill.bonus_damage_if_foe_above_50_warmth > 0 and target_health_percent > 0.5) {
        multiplier += skill.bonus_damage_if_foe_above_50_warmth;
    }
    if (skill.bonus_damage_if_foe_below_50_warmth > 0 and target_health_percent < 0.5) {
        multiplier += skill.bonus_damage_if_foe_below_50_warmth;
    }

    return multiplier;
}

/// Simplified damage calculation for auto-attacks (no skill context)
pub fn calculateAutoAttackDamage(
    attacker: *const Character,
    target: *Character,
    base_damage: f32,
    rng: *std.Random,
    vfx_manager: *vfx.VFXManager,
) DamageResult {
    var result = DamageResult{
        .final_damage = base_damage,
    };

    // Check miss (Frost Eyes)
    if (attacker.hasChill(.frost_eyes)) {
        const rand = rng.intRangeAtMost(u8, 0, 99);
        if (rand < 50) {
            vfx_manager.spawnDamageNumber(0, target.position, .miss);
            print("{s} auto-attack missed {s} due to Frost Eyes!\n", .{ attacker.name, target.name });
            result.missed = true;
            result.final_damage = 0;
            return result;
        }
    }

    // Check block (Snowball Shield)
    if (checkBlock(target)) {
        print("{s}'s Snowball Shield blocked {s}'s auto-attack!\n", .{ target.name, attacker.name });
        result.blocked = true;
        result.final_damage = 0;
        return result;
    }

    // Apply offensive modifiers
    result.final_damage *= calculateCasterOffensiveMultiplier(attacker);

    // Apply defensive modifiers
    result.final_damage *= calculateTargetDefensiveMultiplier(target);

    // Apply armor reduction
    result.final_damage *= calculateArmorReduction(target);

    return result;
}

// ============================================================================
// TESTS
// ============================================================================

test "armor reduction formula" {
    // At 0 armor: 0 / (0 + 100) = 0% reduction -> multiplier = 1.0
    // At 50 armor: 50 / (50 + 100) = 33% reduction -> multiplier = 0.67
    // At 100 armor: 100 / (100 + 100) = 50% reduction -> multiplier = 0.5
    // At 200 armor: 200 / (200 + 100) = 67% reduction -> multiplier = 0.33

    // These are just documentation of expected values
    // Actual test would need Character setup
}
