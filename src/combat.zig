const std = @import("std");
const rl = @import("raylib");
const character = @import("character.zig");
const skills = @import("skills.zig");
const effects = @import("effects.zig");
const entity_types = @import("entity.zig");
const vfx = @import("vfx.zig");
const palette = @import("color_palette.zig");
const telemetry = @import("telemetry.zig");
const terrain_mod = @import("terrain.zig");

// Component modules
const validation = @import("combat_validation.zig");
const damage = @import("combat_damage.zig");
const healing = @import("combat_healing.zig");
const combat_terrain = @import("combat_terrain.zig");

const Character = character.Character;
const Skill = character.Skill;
const Condition = skills.Condition;
const EntityId = entity_types.EntityId;
const MatchTelemetry = telemetry.MatchTelemetry;
const TerrainGrid = terrain_mod.TerrainGrid;
const print = std.debug.print;

// Re-export CastResult for backwards compatibility
pub const CastResult = validation.CastResult;

// ============================================================================
// COMBAT ORCHESTRATOR
// ============================================================================
// This module orchestrates combat by delegating to specialized components:
// - combat_validation.zig: Pre-cast checks
// - combat_damage.zig: Damage calculation
// - combat_healing.zig: Healing calculation
// - combat_terrain.zig: Wall/terrain effects
//
// This file handles:
// - Skill cast initiation (tryStartCast, tryStartCastAtGround)
// - Skill execution (executeSkill, executeSkillAtGround)
// - Applying conditions (chills, cozies, effects)
// - Projectile spawning

// ============================================================================
// CAST INITIATION
// ============================================================================

/// Attempt to start casting a skill. Performs all pre-cast checks (energy, range, cooldown, etc.)
/// Returns the result indicating success, failure reason, or that casting has started.
pub fn tryStartCast(
    caster: *Character,
    skill_index: u8,
    target: ?*Character,
    target_id: ?EntityId,
    rng: *std.Random,
    vfx_manager: *vfx.VFXManager,
    terrain_grid: *TerrainGrid,
    telem: ?*MatchTelemetry,
) CastResult {
    // Use validation module for pre-cast checks
    const ctx = validation.ValidationContext{
        .caster = caster,
        .skill_index = skill_index,
        .target = target,
        .target_id = target_id,
        .telem = telem,
    };

    const result = validation.validateCast(ctx);
    if (result != .success) return result;

    // Start casting (consumes energy, sets cast state)
    caster.startCasting(skill_index);
    caster.casting.cast_target_id = target_id;

    // Get skill for checking activation time
    const skill = caster.casting.skills[skill_index] orelse return .no_target;

    // If instant cast, execute immediately
    if (skill.activation_time_ms == 0) {
        executeSkill(caster, skill, target, skill_index, rng, vfx_manager, terrain_grid, telem);
        caster.casting.cast_target_id = null;
        return .success;
    }

    return .casting_started;
}

/// Attempt to cast a ground-targeted skill at a specific position
pub fn tryStartCastAtGround(
    caster: *Character,
    skill_index: u8,
    ground_position: rl.Vector3,
    rng: *std.Random,
    vfx_manager: *vfx.VFXManager,
    terrain_grid: *TerrainGrid,
    telem: ?*MatchTelemetry,
) CastResult {
    // Use validation module for pre-cast checks
    const result = validation.validateGroundCast(caster, skill_index, ground_position, telem);
    if (result != .success) return result;

    // Start casting (consumes energy, sets cast state)
    caster.startCasting(skill_index);

    // Get skill
    const skill = caster.casting.skills[skill_index] orelse return .no_target;

    // If instant cast, execute immediately
    if (skill.activation_time_ms == 0) {
        executeSkillAtGround(caster, skill, ground_position, skill_index, rng, vfx_manager, terrain_grid, telem);
        return .success;
    }

    // For activation-time skills, we need to store the ground position
    // TODO: Add cast_ground_position to Character struct
    // For now, execute ground skills immediately (most wall skills are instant anyway)
    executeSkillAtGround(caster, skill, ground_position, skill_index, rng, vfx_manager, terrain_grid, telem);
    caster.casting.state = .idle;
    return .success;
}

// ============================================================================
// SKILL EXECUTION - GROUND TARGETED
// ============================================================================

/// Execute a ground-targeted skill at a specific position
fn executeSkillAtGround(
    caster: *Character,
    skill: *const Skill,
    ground_pos: rl.Vector3,
    skill_index: u8,
    rng: *std.Random,
    vfx_manager: *vfx.VFXManager,
    terrain_grid: *TerrainGrid,
    telem: ?*MatchTelemetry,
) void {
    _ = rng;
    _ = vfx_manager;

    // Set cooldown with reduction from effects
    setCooldown(caster, skill, skill_index);

    // Record telemetry
    recordSkillCastTelemetry(caster, skill, telem);

    print("{s} used {s} on ground at ({d:.1}, {d:.1})\n", .{
        caster.name,
        skill.name,
        ground_pos.x,
        ground_pos.z,
    });

    // Apply terrain effects (walls, terrain patches) using terrain module
    combat_terrain.applySkillTerrainEffects(terrain_grid, skill, caster, ground_pos);

    // Apply self-buffs (cozies) for ground-targeted self skills
    if (skill.target_type == .self) {
        applyCozies(caster, skill, null);
    }
}

// ============================================================================
// SKILL EXECUTION - TARGETED
// ============================================================================

/// Execute a skill's effects. Called after cast completes.
pub fn executeSkill(
    caster: *Character,
    skill: *const Skill,
    target: ?*Character,
    skill_index: u8,
    rng: *std.Random,
    vfx_manager: *vfx.VFXManager,
    terrain_grid: *TerrainGrid,
    telem: ?*MatchTelemetry,
) void {
    // Set cooldown with reduction from effects
    setCooldown(caster, skill, skill_index);

    // Record telemetry
    recordSkillCastTelemetry(caster, skill, telem);

    // Handle based on target type
    switch (skill.target_type) {
        .enemy, .ally => executeTargetedSkill(caster, skill, target, rng, vfx_manager, terrain_grid, telem),
        .self => executeSelfTargetedSkill(caster, skill, vfx_manager),
        .ground => executeGroundTargetedSkill(caster, skill, target, terrain_grid),
    }
}

/// Execute a skill targeted at an enemy or ally
fn executeTargetedSkill(
    caster: *Character,
    skill: *const Skill,
    target: ?*Character,
    rng: *std.Random,
    vfx_manager: *vfx.VFXManager,
    terrain_grid: *TerrainGrid,
    telem: ?*MatchTelemetry,
) void {
    const tgt = target orelse return;

    // Calculate and apply damage
    if (skill.damage > 0) {
        const dmg_ctx = damage.DamageContext{
            .caster = caster,
            .target = tgt,
            .skill = skill,
            .terrain_grid = terrain_grid,
            .rng = rng,
            .vfx_manager = vfx_manager,
        };

        const dmg_result = damage.calculateDamage(dmg_ctx);

        // If attack was negated (missed/blocked), stop here
        if (dmg_result.wasNegated()) return;

        // Apply damage
        if (dmg_result.final_damage > 0) {
            applyDamageToTarget(caster, tgt, skill, dmg_result.final_damage, vfx_manager, telem);
        }
    }

    // Check for interrupt skills
    if (skill.interrupts) {
        tgt.interrupt();
    }

    // Apply healing
    if (skill.healing > 0) {
        _ = healing.applyHealing(caster, tgt, skill.healing, vfx_manager, telem);
    }

    // Spawn projectile visual
    const color = palette.getCharacterColor(caster.school, caster.player_position);
    vfx_manager.spawnProjectile(caster.position, tgt.position, caster.id, tgt.id, true, color);

    // Apply conditions
    applyChills(caster, tgt, skill, telem);
    applyCozies(tgt, skill, caster);
    applyEffects(caster, tgt, skill);

    // Handle AoE (TODO)
    if (skill.aoe_type == .adjacent) {
        // TODO: implement adjacent target finding
    } else if (skill.aoe_type == .area) {
        // TODO: implement area damage
    }
}

/// Execute a self-targeted skill
fn executeSelfTargetedSkill(
    caster: *Character,
    skill: *const Skill,
    vfx_manager: *vfx.VFXManager,
) void {
    // Apply self-healing
    if (skill.healing > 0) {
        _ = healing.applySelfHealing(caster, skill.healing, vfx_manager);
    }

    // Apply self-buffs (cozies)
    applyCozies(caster, skill, null);

    // Apply self-debuffs (chills) - some skills have drawbacks
    for (skill.chills) |chill_effect| {
        caster.addChill(chill_effect, null);
        print("{s} gained {s} for {d}ms\n", .{
            caster.name,
            @tagName(chill_effect.chill),
            chill_effect.duration_ms,
        });
    }
}

/// Execute a ground-targeted skill (via executeSkill path)
fn executeGroundTargetedSkill(
    caster: *Character,
    skill: *const Skill,
    target: ?*Character,
    terrain_grid: *TerrainGrid,
) void {
    // Target position from target character's position if provided
    const ground_pos = if (target) |tgt| tgt.position else caster.position;

    print("{s} used {s} on ground at ({d:.1}, {d:.1})\n", .{
        caster.name,
        skill.name,
        ground_pos.x,
        ground_pos.z,
    });

    // Apply terrain effects using terrain module
    combat_terrain.applySkillTerrainEffects(terrain_grid, skill, caster, ground_pos);
}

/// Execute a non-targeted skill (walls in front of caster)
fn executeNonTargetedSkill(
    caster: *Character,
    skill: *const Skill,
    terrain_grid: *TerrainGrid,
) void {
    // Build walls in front of caster if this is a wall skill
    if (skill.creates_wall) {
        combat_terrain.buildWallInFront(terrain_grid, skill, caster, 0.0);
    }
}

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Set cooldown with reduction from effects
fn setCooldown(caster: *Character, skill: *const Skill, skill_index: u8) void {
    var cooldown_time = @as(f32, @floatFromInt(skill.recharge_time_ms)) / 1000.0;
    const cooldown_reduction = effects.calculateCooldownReductionPercent(
        &caster.conditions.effects.active,
        caster.conditions.effects.count,
    );
    cooldown_time *= (1.0 - cooldown_reduction);
    caster.casting.cooldowns[skill_index] = cooldown_time;
}

/// Record skill cast telemetry
fn recordSkillCastTelemetry(caster: *Character, skill: *const Skill, telem: ?*MatchTelemetry) void {
    if (telem) |tel| {
        const energy_cost_mult = effects.calculateEnergyCostMultiplier(
            &caster.conditions.effects.active,
            caster.conditions.effects.count,
        );
        const adjusted_energy_cost = @as(f32, @floatFromInt(skill.energy_cost)) * energy_cost_mult;
        tel.recordSkillCast(caster.id, skill.name, adjusted_energy_cost, true);
    }
}

/// Apply damage to target with all side effects
fn applyDamageToTarget(
    caster: *Character,
    target: *Character,
    skill: *const Skill,
    final_damage: f32,
    vfx_manager: *vfx.VFXManager,
    telem: ?*MatchTelemetry,
) void {
    target.takeDamage(final_damage);

    // Record damage source for damage monitor
    target.recordDamageSource(skill, caster.id);

    // Record telemetry
    if (telem) |tel| {
        tel.recordDamage(caster.id, target.id, final_damage, target.getTotalPadding(), "physical");
    }

    // Spawn damage number
    vfx_manager.spawnDamageNumber(final_damage, target.position, .damage);

    print("{s} used {s} on {s} for {d:.1} damage! ({d:.1}/{d:.1} HP)\n", .{
        caster.name,
        skill.name,
        target.name,
        final_damage,
        target.stats.warmth,
        target.stats.max_warmth,
    });

    // Check if target is Dazed - if so, damage interrupts
    if (target.hasChill(.dazed)) {
        target.interrupt();
    }
}

/// Apply chill debuffs from skill
fn applyChills(caster: *Character, target: *Character, skill: *const Skill, telem: ?*MatchTelemetry) void {
    for (skill.chills) |chill_effect| {
        // Check if target has snow goggles (immune to frost_eyes)
        if (chill_effect.chill == .frost_eyes and target.hasCozy(.snow_goggles)) {
            print("{s}'s Snow Goggles protected from Frost Eyes!\n", .{target.name});
            continue;
        }

        target.addChill(chill_effect, null);

        // Record telemetry
        if (telem) |tel| {
            tel.recordCondition(caster.id, @tagName(chill_effect.chill));
        }

        print("{s} applied {s} to {s} for {d}ms\n", .{
            caster.name,
            @tagName(chill_effect.chill),
            target.name,
            chill_effect.duration_ms,
        });
    }
}

/// Apply cozy buffs from skill
fn applyCozies(target: *Character, skill: *const Skill, caster: ?*Character) void {
    for (skill.cozies) |cozy_effect| {
        target.addCozy(cozy_effect, null);
        if (caster) |c| {
            print("{s} gave {s} {s} for {d}ms\n", .{
                c.name,
                target.name,
                @tagName(cozy_effect.cozy),
                cozy_effect.duration_ms,
            });
        } else {
            print("{s} gained {s} for {d}ms\n", .{
                target.name,
                @tagName(cozy_effect.cozy),
                cozy_effect.duration_ms,
            });
        }
    }
}

/// Apply composable effects from skill
fn applyEffects(caster: *Character, target: *Character, skill: *const Skill) void {
    for (skill.effects) |effect| {
        // Check if condition is met
        const caster_hp_percent = caster.stats.warmth / caster.stats.max_warmth;
        const target_hp_percent = target.stats.warmth / target.stats.max_warmth;
        if (!effects.evaluateCondition(effect.condition, caster_hp_percent, target_hp_percent)) {
            continue;
        }

        // Apply effect to target
        target.addEffect(&effect, caster.id);

        print("{s} applied effect {s} to {s} for {d}ms\n", .{
            caster.name,
            effect.name,
            target.name,
            effect.duration_ms,
        });
    }
}
