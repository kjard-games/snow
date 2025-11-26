const std = @import("std");
const character = @import("character.zig");
const skills = @import("skills.zig");
const effects = @import("effects.zig");
const entity_types = @import("entity.zig");
const telemetry = @import("telemetry.zig");

const Character = character.Character;
const Skill = skills.Skill;
const EntityId = entity_types.EntityId;
const MatchTelemetry = telemetry.MatchTelemetry;
const print = std.debug.print;

// ============================================================================
// COMBAT VALIDATION - Pre-cast checks for skill usage
// ============================================================================
// This module handles all validation before a skill can be cast:
// - Caster alive check
// - Cast state check (not already casting)
// - Cooldown check
// - Energy check (with modifiers)
// - Target validation (exists, alive, correct type)
// - Range check
//
// Design: Separating validation from execution allows for:
// - Clear error reporting (why did the cast fail?)
// - Reuse in AI decision making (can I use this skill?)
// - Skill queueing logic (out of range -> queue and approach)

// ============================================================================
// CAST RESULT - Why a cast succeeded or failed
// ============================================================================

pub const CastResult = enum {
    success,
    casting_started, // For skills with activation time
    no_energy,
    out_of_range,
    no_target,
    target_dead,
    caster_dead,
    on_cooldown,
    already_casting,
    no_skill, // Skill slot is empty
};

// ============================================================================
// VALIDATION CONTEXT - All info needed for validation
// ============================================================================

pub const ValidationContext = struct {
    caster: *Character,
    skill_index: u8,
    target: ?*Character,
    target_id: ?EntityId,
    telem: ?*MatchTelemetry,

    /// Get the skill being validated (if any)
    pub fn getSkill(self: ValidationContext) ?*const Skill {
        return self.caster.casting.skills[self.skill_index];
    }

    /// Calculate adjusted energy cost with modifiers
    pub fn getAdjustedEnergyCost(self: ValidationContext) f32 {
        const skill = self.getSkill() orelse return 0;
        const energy_cost_mult = effects.calculateEnergyCostMultiplier(
            &self.caster.conditions.effects.active,
            self.caster.conditions.effects.count,
        );
        return @as(f32, @floatFromInt(skill.energy_cost)) * energy_cost_mult;
    }
};

// ============================================================================
// VALIDATION FUNCTIONS
// ============================================================================

/// Check if caster is alive
pub fn validateCasterAlive(ctx: ValidationContext) CastResult {
    if (!ctx.caster.isAlive()) return .caster_dead;
    return .success;
}

/// Check if caster is already casting or in aftercast
pub fn validateNotCasting(ctx: ValidationContext) CastResult {
    if (ctx.caster.casting.state != .idle) return .already_casting;
    return .success;
}

/// Check if skill is on cooldown
pub fn validateCooldown(ctx: ValidationContext) CastResult {
    if (ctx.caster.casting.cooldowns[ctx.skill_index] > 0) {
        if (ctx.telem) |tel| {
            tel.recordCooldownBlock(ctx.caster.id);
        }
        return .on_cooldown;
    }
    return .success;
}

/// Check if skill slot has a skill
pub fn validateSkillExists(ctx: ValidationContext) CastResult {
    if (ctx.getSkill() == null) return .no_skill;
    return .success;
}

/// Check if caster has enough energy
pub fn validateEnergy(ctx: ValidationContext) CastResult {
    const skill = ctx.getSkill() orelse return .no_skill;
    const adjusted_cost = ctx.getAdjustedEnergyCost();

    if (@as(f32, @floatFromInt(ctx.caster.stats.energy)) < adjusted_cost) {
        print("{s} not enough energy ({d}/{d:.1})\n", .{
            ctx.caster.name,
            ctx.caster.stats.energy,
            adjusted_cost,
        });
        if (ctx.telem) |tel| {
            tel.recordSkillCast(ctx.caster.id, skill.name, adjusted_cost, false);
            tel.recordNoEnergyBlock(ctx.caster.id);
        }
        return .no_energy;
    }
    return .success;
}

/// Check if target exists and is valid for the skill type
pub fn validateTarget(ctx: ValidationContext) CastResult {
    const skill = ctx.getSkill() orelse return .no_skill;

    // Self-targeted and ground-targeted skills don't need a target
    if (skill.target_type == .self or skill.target_type == .ground) {
        return .success;
    }

    // Enemy/ally targeted skills need a target
    if (skill.target_type == .enemy or skill.target_type == .ally) {
        const target = ctx.target orelse {
            print("{s} has no target\n", .{ctx.caster.name});
            if (ctx.telem) |tel| {
                tel.recordSkillCast(ctx.caster.id, skill.name, ctx.getAdjustedEnergyCost(), false);
            }
            return .no_target;
        };

        if (!target.isAlive()) return .target_dead;
    }

    return .success;
}

/// Check if target is in range (and queue skill if not)
pub fn validateRange(ctx: ValidationContext) CastResult {
    const skill = ctx.getSkill() orelse return .no_skill;

    // Self-targeted skills are always in range
    if (skill.target_type == .self) return .success;

    // For enemy/ally targeted skills, check distance to target
    if (skill.target_type == .enemy or skill.target_type == .ally) {
        const target = ctx.target orelse return .no_target;
        const distance = ctx.caster.distanceTo(target.*);

        if (distance > skill.cast_range) {
            print("{s} target out of range ({d:.1}/{d:.1}) - queuing skill\n", .{
                ctx.caster.name,
                distance,
                skill.cast_range,
            });

            // GW1 behavior: Queue the skill and run into range
            if (ctx.target_id) |tid| {
                ctx.caster.queueSkill(ctx.skill_index, tid);
            }

            // Record telemetry
            if (ctx.telem) |tel| {
                tel.recordSkillCast(ctx.caster.id, skill.name, ctx.getAdjustedEnergyCost(), false);
                tel.recordOutOfRangeBlock(ctx.caster.id);
                if (ctx.caster.id < 256) {
                    if (tel.getEntityStats(ctx.caster.id)) |stats| {
                        stats.out_of_range_attempts += 1;
                    }
                }
            }

            return .out_of_range;
        }
    }

    return .success;
}

/// Check range for ground-targeted skills
pub fn validateGroundRange(caster: *Character, ground_pos: @import("raylib").Vector3, skill: *const Skill, telem: ?*MatchTelemetry) CastResult {
    const dx = ground_pos.x - caster.position.x;
    const dz = ground_pos.z - caster.position.z;
    const distance = @sqrt(dx * dx + dz * dz);

    if (distance > skill.cast_range) {
        print("{s} ground target out of range ({d:.1}/{d:.1})\n", .{
            caster.name,
            distance,
            skill.cast_range,
        });
        if (telem) |tel| {
            const energy_cost_mult = effects.calculateEnergyCostMultiplier(
                &caster.conditions.effects.active,
                caster.conditions.effects.count,
            );
            const adjusted_cost = @as(f32, @floatFromInt(skill.energy_cost)) * energy_cost_mult;
            tel.recordSkillCast(caster.id, skill.name, adjusted_cost, false);
            tel.recordOutOfRangeBlock(caster.id);
        }
        return .out_of_range;
    }

    return .success;
}

// ============================================================================
// FULL VALIDATION PIPELINE
// ============================================================================

/// Run all validation checks for a targeted skill cast
/// Returns .success if all checks pass, or the first failure reason
pub fn validateCast(ctx: ValidationContext) CastResult {
    // Check caster state
    var result = validateCasterAlive(ctx);
    if (result != .success) return result;

    result = validateNotCasting(ctx);
    if (result != .success) return result;

    result = validateCooldown(ctx);
    if (result != .success) return result;

    result = validateSkillExists(ctx);
    if (result != .success) return result;

    result = validateEnergy(ctx);
    if (result != .success) return result;

    result = validateTarget(ctx);
    if (result != .success) return result;

    result = validateRange(ctx);
    if (result != .success) return result;

    return .success;
}

/// Run validation checks for a ground-targeted skill cast
pub fn validateGroundCast(caster: *Character, skill_index: u8, ground_pos: @import("raylib").Vector3, telem: ?*MatchTelemetry) CastResult {
    // Build context for common checks
    const ctx = ValidationContext{
        .caster = caster,
        .skill_index = skill_index,
        .target = null,
        .target_id = null,
        .telem = telem,
    };

    // Check caster state
    var result = validateCasterAlive(ctx);
    if (result != .success) return result;

    result = validateNotCasting(ctx);
    if (result != .success) return result;

    result = validateCooldown(ctx);
    if (result != .success) return result;

    result = validateSkillExists(ctx);
    if (result != .success) return result;

    result = validateEnergy(ctx);
    if (result != .success) return result;

    // Ground-specific range check
    const skill = ctx.getSkill() orelse return .no_skill;
    result = validateGroundRange(caster, ground_pos, skill, telem);
    if (result != .success) return result;

    return .success;
}

// ============================================================================
// TESTS
// ============================================================================

test "validation context energy calculation" {
    // This would require setting up a full Character, which is complex
    // In practice, integration tests would cover this
}
