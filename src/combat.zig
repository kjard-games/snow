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
const school_resources = @import("character_school_resources.zig");

// Component modules
const validation = @import("combat_validation.zig");
const damage = @import("combat_damage.zig");
const healing = @import("combat_healing.zig");
const combat_terrain = @import("combat_terrain.zig");
const combat_behavior = @import("combat_behavior.zig");

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

    // Deduct school resource costs (grit, credit, warmth sacrifice)
    deductSchoolResourceCosts(caster, skill);

    // Grant resources on cast (some skills grant grit/rhythm just for casting)
    grantSchoolResourcesOnCast(caster, skill);

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

    // Deduct school resource costs (grit, credit, warmth sacrifice)
    deductSchoolResourceCosts(caster, skill);

    // Grant resources on cast (some skills grant grit/rhythm just for casting)
    grantSchoolResourcesOnCast(caster, skill);

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

    // Track if skill hit (for resource grants)
    var skill_hit = false;

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
            applyDamageToTarget(caster, tgt, skill, dmg_result.final_damage, vfx_manager, telem, null);
            skill_hit = true;
        }
    } else {
        // Non-damage skills (heals, buffs) always "hit"
        skill_hit = true;
    }

    // Grant resources on hit
    if (skill_hit) {
        grantSchoolResourcesOnHit(caster, skill);
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

    // Apply behavior if skill has one (e.g., Team Spirit on ally)
    if (skill.behavior != null) {
        // For ally-targeted skills, behavior goes on target
        // For enemy-targeted skills, behavior might go on caster (depends on design)
        if (skill.target_type == .ally) {
            if (tgt.addBehaviorFromSkill(skill, caster.id)) {
                print("{s} granted behavior from {s} to {s}!\n", .{ caster.name, skill.name, tgt.name });
            }
        }
    }

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

    // Apply behavior if skill has one (e.g., Golden Parachute)
    if (skill.behavior != null) {
        if (caster.addBehaviorFromSkill(skill, caster.id)) {
            print("{s} activated behavior from {s}!\n", .{ caster.name, skill.name });
        }
    }

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
/// Now includes behavior checks for damage interception and death prevention
fn applyDamageToTarget(
    caster: *Character,
    target: *Character,
    skill: *const Skill,
    final_damage: f32,
    vfx_manager: *vfx.VFXManager,
    telem: ?*MatchTelemetry,
    all_characters: ?[]Character,
) void {
    var damage_to_apply = final_damage;

    // Check for damage interception behaviors (on_take_damage)
    if (all_characters) |chars| {
        damage_to_apply = combat_behavior.checkDamageInterception(
            target,
            caster,
            final_damage,
            chars,
            vfx_manager,
            &target.behaviors,
        );
    }

    // If all damage was intercepted, we're done
    if (damage_to_apply <= 0) return;

    // Check if this damage would be lethal
    const would_be_lethal = damage_to_apply >= target.stats.warmth;

    if (would_be_lethal) {
        // Check for death prevention behaviors (on_would_die)
        if (all_characters) |chars| {
            const death_prevented = combat_behavior.checkDeathPrevention(
                target,
                chars,
                vfx_manager,
                &target.behaviors,
            );
            if (death_prevented) {
                // Death was prevented - target survives
                // The behavior handler already set their warmth
                // Record that we "dealt" the damage for telemetry but target lived
                if (telem) |tel| {
                    tel.recordDamage(caster.id, target.id, damage_to_apply, target.getTotalPadding(), "physical");
                }
                return;
            }
        }
    }

    // Apply damage normally
    target.takeDamage(damage_to_apply);

    // Record damage source for damage monitor
    target.recordDamageSource(skill, caster.id);

    // Record telemetry
    if (telem) |tel| {
        tel.recordDamage(caster.id, target.id, damage_to_apply, target.getTotalPadding(), "physical");
    }

    // Spawn damage number
    vfx_manager.spawnDamageNumber(damage_to_apply, target.position, .damage);

    print("{s} used {s} on {s} for {d:.1} damage! ({d:.1}/{d:.1} HP)\n", .{
        caster.name,
        skill.name,
        target.name,
        damage_to_apply,
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

// ============================================================================
// SCHOOL RESOURCE FUNCTIONS
// ============================================================================

/// Deduct school-specific resource costs when a skill is cast
/// Called after validation passes, before skill executes
pub fn deductSchoolResourceCosts(caster: *Character, skill: *const Skill) void {
    switch (caster.school) {
        .public_school => {
            // Spend grit stacks
            if (skill.grit_cost > 0) {
                if (caster.school_resources.grit.spend(skill.grit_cost)) {
                    print("{s} spent {d} grit (now {d})\n", .{
                        caster.name,
                        skill.grit_cost,
                        caster.school_resources.grit.stacks,
                    });
                }
            }
        },
        .private_school => {
            // Take on credit (reduce max energy temporarily)
            if (skill.credit_cost > 0) {
                const actual_credit = caster.school_resources.credit_debt.takeCredit(
                    skill.credit_cost,
                    caster.stats.max_energy,
                );
                if (actual_credit > 0) {
                    print("{s} took {d} credit (debt now {d})\n", .{
                        caster.name,
                        actual_credit,
                        caster.school_resources.credit_debt.debt,
                    });
                }
            }
        },
        .homeschool => {
            // Sacrifice warmth (health)
            if (skill.warmth_cost_percent > 0) {
                const warmth_cost = school_resources.SacrificeState.calculateWarmthCost(
                    skill.warmth_cost_percent,
                    caster.stats.max_warmth,
                );
                caster.stats.warmth = @max(1, caster.stats.warmth - warmth_cost);
                print("{s} sacrificed {d:.1} warmth ({d:.1}/{d:.1})\n", .{
                    caster.name,
                    warmth_cost,
                    caster.stats.warmth,
                    caster.stats.max_warmth,
                });
            }
        },
        .waldorf => {
            // Reset consumed rhythm tracker
            caster.school_resources.rhythm.last_consumed = 0;

            // Handle rhythm consumption
            if (skill.consumes_all_rhythm) {
                // Consume all rhythm (for Crescendo-style skills)
                const consumed = caster.school_resources.rhythm.consumeAll();
                caster.school_resources.rhythm.last_consumed = consumed;
                if (consumed > 0) {
                    print("{s} consumed all {d} rhythm\n", .{
                        caster.name,
                        consumed,
                    });
                }
            } else if (skill.rhythm_cost > 0) {
                // Spend specific amount of rhythm
                if (caster.school_resources.rhythm.spend(skill.rhythm_cost)) {
                    caster.school_resources.rhythm.last_consumed = skill.rhythm_cost;
                    print("{s} spent {d} rhythm (now {d})\n", .{
                        caster.name,
                        skill.rhythm_cost,
                        caster.school_resources.rhythm.charge,
                    });
                }
            }
        },
        .montessori => {
            // Variety is passive, no cost to deduct
        },
    }

    // Record skill use for school mechanics (rhythm building, variety tracking)
    caster.school_resources.onSkillUse(caster.school, skill.skill_type);
}

/// Grant school-specific resources when a skill is cast (regardless of hit)
pub fn grantSchoolResourcesOnCast(caster: *Character, skill: *const Skill) void {
    // Public School: Some skills grant grit on cast
    if (caster.school == .public_school and skill.grants_grit_on_cast > 0) {
        caster.school_resources.grit.gain(skill.grants_grit_on_cast);
        print("{s} gained {d} grit on cast (now {d})\n", .{
            caster.name,
            skill.grants_grit_on_cast,
            caster.school_resources.grit.stacks,
        });
    }

    // Waldorf: Some skills grant rhythm on cast
    if (caster.school == .waldorf and skill.grants_rhythm_on_cast > 0) {
        caster.school_resources.rhythm.grant(skill.grants_rhythm_on_cast);
        print("{s} gained {d} rhythm on cast (now {d})\n", .{
            caster.name,
            skill.grants_rhythm_on_cast,
            caster.school_resources.rhythm.charge,
        });
    }
}

/// Grant school-specific resources when a skill hits
pub fn grantSchoolResourcesOnHit(caster: *Character, skill: *const Skill) void {
    // Public School: Some skills grant grit on hit
    if (caster.school == .public_school and skill.grants_grit_on_hit > 0) {
        caster.school_resources.grit.gain(skill.grants_grit_on_hit);
        print("{s} gained {d} grit on hit (now {d})\n", .{
            caster.name,
            skill.grants_grit_on_hit,
            caster.school_resources.grit.stacks,
        });
    }

    // Use the generic onHitLanded hook for additional effects
    caster.school_resources.onHitLanded(caster.school, skill.grants_grit_on_hit);

    // Energy on hit (any school)
    if (skill.grants_energy_on_hit > 0) {
        caster.stats.energy = @min(
            caster.stats.max_energy,
            caster.stats.energy + skill.grants_energy_on_hit,
        );
        print("{s} gained {d} energy on hit (now {d})\n", .{
            caster.name,
            skill.grants_energy_on_hit,
            caster.stats.energy,
        });
    }
}
