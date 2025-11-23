const std = @import("std");
const rl = @import("raylib");
const character = @import("character.zig");
const skills = @import("skills.zig");
const effects = @import("effects.zig");
const entity_types = @import("entity.zig");
const vfx = @import("vfx.zig");
const palette = @import("color_palette.zig");

const Character = character.Character;
const Skill = character.Skill;
const Condition = skills.Condition;
const EntityId = entity_types.EntityId;
const print = std.debug.print;

pub const CastResult = enum {
    success,
    casting_started, // for skills with activation time
    no_energy,
    out_of_range,
    no_target,
    target_dead,
    caster_dead,
    on_cooldown,
    already_casting,
};

/// Attempt to start casting a skill. Performs all pre-cast checks (energy, range, cooldown, etc.)
/// Returns the result indicating success, failure reason, or that casting has started.
pub fn tryStartCast(caster: *Character, skill_index: u8, target: ?*Character, target_id: ?EntityId, rng: *std.Random, vfx_manager: *vfx.VFXManager, terrain_grid: *@import("terrain.zig").TerrainGrid) CastResult {
    // Check if caster is alive
    if (!caster.isAlive()) return .caster_dead;

    // Check if already casting or in aftercast
    if (caster.cast_state != .idle) return .already_casting;

    // Check cooldown
    if (caster.skill_cooldowns[skill_index] > 0) return .on_cooldown;

    // Get the skill
    const skill = caster.skill_bar[skill_index] orelse return .no_target;

    // Check energy
    if (caster.energy < skill.energy_cost) {
        print("{s} not enough energy ({d}/{d})\n", .{ caster.name, caster.energy, skill.energy_cost });
        return .no_energy;
    }

    // Check target requirements
    if (skill.target_type == .enemy or skill.target_type == .ally) {
        const tgt = target orelse {
            print("{s} has no target\n", .{caster.name});
            return .no_target;
        };

        // Check if target is alive
        if (!tgt.isAlive()) return .target_dead;

        // Check range
        const distance = caster.distanceTo(tgt.*);
        if (distance > skill.cast_range) {
            print("{s} target out of range ({d:.1}/{d:.1}) - queuing skill\n", .{ caster.name, distance, skill.cast_range });
            // GW1 behavior: Queue the skill and run into range
            if (target_id) |tid| {
                caster.queueSkill(skill_index, tid);
            }
            return .out_of_range;
        }
    }

    // Start casting (consumes energy, sets cast state)
    caster.startCasting(skill_index);
    caster.cast_target_id = target_id; // Store target ID for cast completion

    // If instant cast, execute immediately
    if (skill.activation_time_ms == 0) {
        executeSkill(caster, skill, target, skill_index, rng, vfx_manager, terrain_grid);
        caster.cast_target_id = null; // Clear target
        return .success;
    }

    return .casting_started;
}

/// Attempt to cast a ground-targeted skill at a specific position
/// This is used for skills with target_type = .ground (walls, terrain effects, etc.)
pub fn tryStartCastAtGround(caster: *Character, skill_index: u8, ground_position: rl.Vector3, rng: *std.Random, vfx_manager: *vfx.VFXManager, terrain_grid: *@import("terrain.zig").TerrainGrid) CastResult {
    // Check if caster is alive
    if (!caster.isAlive()) return .caster_dead;

    // Check if already casting or in aftercast
    if (caster.cast_state != .idle) return .already_casting;

    // Check cooldown
    if (caster.skill_cooldowns[skill_index] > 0) return .on_cooldown;

    // Get the skill
    const skill = caster.skill_bar[skill_index] orelse return .no_target;

    // Check energy
    if (caster.energy < skill.energy_cost) {
        print("{s} not enough energy ({d}/{d})\n", .{ caster.name, caster.energy, skill.energy_cost });
        return .no_energy;
    }

    // Check range to ground position
    const dx = ground_position.x - caster.position.x;
    const dz = ground_position.z - caster.position.z;
    const distance = @sqrt(dx * dx + dz * dz);

    if (distance > skill.cast_range) {
        print("{s} ground target out of range ({d:.1}/{d:.1})\n", .{ caster.name, distance, skill.cast_range });
        return .out_of_range;
    }

    // Start casting (consumes energy, sets cast state)
    caster.startCasting(skill_index);

    // Store ground position in the character's cast_ground_position field (we'll add this)
    // For now, we'll execute immediately since most ground skills are instant/fast

    // If instant cast, execute immediately
    if (skill.activation_time_ms == 0) {
        executeSkillAtGround(caster, skill, ground_position, skill_index, rng, vfx_manager, terrain_grid);
        return .success;
    }

    // For activation-time skills, we need to store the ground position
    // TODO: Add cast_ground_position to Character struct
    // caster.cast_ground_position = ground_position;

    // For now, execute ground skills immediately (most wall skills are instant anyway)
    executeSkillAtGround(caster, skill, ground_position, skill_index, rng, vfx_manager, terrain_grid);
    caster.cast_state = .idle;
    return .success;
}

/// Execute a ground-targeted skill at a specific position
/// This is a simplified version of executeSkill for ground-targeted abilities
fn executeSkillAtGround(caster: *Character, skill: *const Skill, ground_pos: rl.Vector3, skill_index: u8, rng: *std.Random, vfx_manager: *vfx.VFXManager, terrain_grid: *@import("terrain.zig").TerrainGrid) void {
    _ = rng;
    _ = vfx_manager;

    // Set cooldown
    caster.skill_cooldowns[skill_index] = @as(f32, @floatFromInt(skill.recharge_time_ms)) / 1000.0;

    print("{s} used {s} on ground at ({d:.1}, {d:.1})\n", .{
        caster.name,
        skill.name,
        ground_pos.x,
        ground_pos.z,
    });

    // Apply terrain effects (COMPOSITIONAL)
    const effect = skill.terrain_effect;
    if (effect.terrain_type) |terrain_type| {
        switch (effect.shape) {
            .none => {},
            .circle => {
                terrain_grid.setTerrainInRadius(ground_pos.x, ground_pos.z, skill.aoe_radius, terrain_type);
                print("  -> Created {s} circle (radius {d:.1})\n", .{ @tagName(terrain_type), skill.aoe_radius });
            },
            .cone => {
                // TODO: Implement cone shape (from caster toward target)
                terrain_grid.setTerrainInRadius(ground_pos.x, ground_pos.z, skill.aoe_radius, terrain_type);
                print("  -> Created {s} cone (radius {d:.1})\n", .{ @tagName(terrain_type), skill.aoe_radius });
            },
            .line => {
                // TODO: Implement line shape (from caster to target)
                terrain_grid.setTerrainInRadius(ground_pos.x, ground_pos.z, skill.aoe_radius, terrain_type);
                print("  -> Created {s} line (radius {d:.1})\n", .{ @tagName(terrain_type), skill.aoe_radius });
            },
            .ring => {
                // TODO: Implement ring shape (donut)
                terrain_grid.setTerrainInRadius(ground_pos.x, ground_pos.z, skill.aoe_radius, terrain_type);
                print("  -> Created {s} ring (radius {d:.1})\n", .{ @tagName(terrain_type), skill.aoe_radius });
            },
            .trail => {
                // Trails are created during movement, not on cast
                print("  -> Enabled {s} trail effect\n", .{@tagName(terrain_type)});
            },
            .square => {
                // TODO: Implement square shape
                terrain_grid.setTerrainInRadius(ground_pos.x, ground_pos.z, skill.aoe_radius, terrain_type);
                print("  -> Created {s} square (radius {d:.1})\n", .{ @tagName(terrain_type), skill.aoe_radius });
            },
            .cross => {
                // TODO: Implement cross shape
                terrain_grid.setTerrainInRadius(ground_pos.x, ground_pos.z, skill.aoe_radius, terrain_type);
                print("  -> Created {s} cross (radius {d:.1})\n", .{ @tagName(terrain_type), skill.aoe_radius });
            },
        }
    }

    // Build walls (perpendicular to caster facing)
    if (skill.creates_wall) {
        // Calculate facing angle from caster to ground position
        const dx = ground_pos.x - caster.position.x;
        const dz = ground_pos.z - caster.position.z;
        const facing_angle = std.math.atan2(dz, dx);

        terrain_grid.buildWallPerpendicular(
            caster.position.x,
            caster.position.z,
            facing_angle,
            skill.wall_distance_from_caster,
            skill.wall_length,
            skill.wall_height,
            skill.wall_thickness,
            caster.team,
        );

        print("  -> Built {d:.0}x{d:.0} wall\n", .{ skill.wall_length, skill.wall_height });
    }

    // Damage walls in area
    if (skill.destroys_walls and skill.aoe_radius > 0) {
        const wall_damage = skill.damage * skill.wall_damage_multiplier;
        terrain_grid.damageWallsInRadius(ground_pos.x, ground_pos.z, skill.aoe_radius, wall_damage);
        print("  -> Damaged walls for {d:.1}\n", .{wall_damage});
    }

    // Apply self-buffs (cozies)
    if (skill.target_type == .self) {
        for (skill.cozies) |cozy_effect| {
            caster.addCozy(cozy_effect, null);
            print("{s} gained {s} for {d}ms\n", .{
                caster.name,
                @tagName(cozy_effect.cozy),
                cozy_effect.duration_ms,
            });
        }
    }
}

/// Execute a skill's effects (damage, healing, conditions, terrain). Called after cast completes.
/// Applies all modifiers from caster and target conditions (buffs/debuffs).
pub fn executeSkill(caster: *Character, skill: *const Skill, target: ?*Character, skill_index: u8, rng: *std.Random, vfx_manager: *vfx.VFXManager, terrain_grid: *@import("terrain.zig").TerrainGrid) void {
    // Set cooldown
    caster.skill_cooldowns[skill_index] = @as(f32, @floatFromInt(skill.recharge_time_ms)) / 1000.0;

    // Get target if needed
    if (skill.target_type == .enemy or skill.target_type == .ally) {
        const tgt = target orelse return;

        // Calculate damage with modifiers
        var final_damage = skill.damage;

        // Apply chill (debuff) modifiers from caster
        if (caster.hasChill(.numb)) {
            final_damage *= 0.5; // Numb reduces damage by 50%
        }

        // Apply cozy (buff) modifiers from caster
        if (caster.hasCozy(.fire_inside)) {
            final_damage *= 1.3; // Fire Inside increases damage by 30%
        }

        // Apply target's defensive cozies
        if (tgt.hasCozy(.bundled_up)) {
            final_damage *= 0.75; // Bundled Up reduces incoming damage by 25%
        }

        // Apply armor/padding reduction (GW1-inspired formula)
        // Simplified from GW1: damage = base × strike_level / (strike_level + armor)
        // We assume constant effective strike level of 100, so:
        // damage_reduction = armor / (armor + 100)
        // final_damage = base_damage × (1 - damage_reduction)
        const target_padding = tgt.getTotalPadding();
        const armor_reduction = target_padding / (target_padding + 100.0);
        final_damage *= (1.0 - armor_reduction);

        // Apply soak (armor penetration - reduces effective armor)
        if (skill.soak > 0) {
            // Soak penetrates a percentage of armor
            // effective_armor = armor * (1 - soak)
            const effective_padding = target_padding * (1.0 - skill.soak);
            const soaked_reduction = effective_padding / (effective_padding + 100.0);
            final_damage = skill.damage * (1.0 - soaked_reduction);
            if (caster.hasCozy(.fire_inside)) {
                final_damage *= 1.3; // Re-apply fire inside bonus after soak
            }
        }

        // Apply cover mechanics (walls provide defense against direct projectiles)
        if (skill.projectile_type == .direct or skill.projectile_type == .instant) {
            // Check if target has cover from a wall
            const min_wall_height = 20.0; // Walls must be at least 20 units to provide cover
            if (terrain_grid.hasWallBetween(
                caster.position.x,
                caster.position.z,
                tgt.position.x,
                tgt.position.z,
                min_wall_height,
            )) {
                // Target has cover - reduce damage significantly
                final_damage *= 0.4; // 60% damage reduction from cover
                print("{s}'s attack reduced by cover!\n", .{caster.name});
            }
        }
        // Arcing projectiles (lobs) ignore cover - they arc over walls

        // Apply miss chance from chills
        if (caster.hasChill(.frost_eyes)) {
            // 50% miss chance
            const rand = rng.intRangeAtMost(u8, 0, 99);
            if (rand < 50) {
                // Spawn miss indicator
                vfx_manager.spawnDamageNumber(0, tgt.position, .miss);
                print("{s} missed {s} due to Frost Eyes!\n", .{ caster.name, tgt.name });
                return;
            }
        }

        // Check if target blocks with snowball shield
        if (tgt.hasCozy(.snowball_shield)) {
            print("{s}'s Snowball Shield blocked {s}!\n", .{ tgt.name, skill.name });
            // Remove the shield after blocking
            for (tgt.active_cozies[0..tgt.active_cozy_count]) |*maybe_cozy| {
                if (maybe_cozy.*) |*cozy| {
                    if (cozy.cozy == .snowball_shield) {
                        maybe_cozy.* = null;
                        break;
                    }
                }
            }
            return;
        }

        // Spawn projectile visual with caster's school/position color
        const color = palette.getCharacterColor(caster.school, caster.player_position);
        vfx_manager.spawnProjectile(caster.position, tgt.position, caster.id, tgt.id, true, color);

        // Deal damage
        if (final_damage > 0) {
            tgt.takeDamage(final_damage);

            // Record damage source for damage monitor
            tgt.recordDamageSource(skill, caster.id);

            // Spawn damage number
            vfx_manager.spawnDamageNumber(final_damage, tgt.position, .damage);

            print("{s} used {s} on {s} for {d:.1} damage! ({d:.1}/{d:.1} HP)\n", .{
                caster.name,
                skill.name,
                tgt.name,
                final_damage,
                tgt.warmth,
                tgt.max_warmth,
            });

            // Check if target is Dazed - if so, damage interrupts
            if (tgt.hasChill(.dazed)) {
                tgt.interrupt();
            }
        }

        // Check for interrupt skills
        if (skill.interrupts) {
            tgt.interrupt();
        }

        // Apply healing
        if (skill.healing > 0) {
            var healing_amount = skill.healing;

            // Boost healing if target has Hot Cocoa buff
            if (tgt.hasCozy(.hot_cocoa)) {
                healing_amount *= 1.5;
            }

            tgt.warmth = @min(tgt.max_warmth, tgt.warmth + healing_amount);

            // Spawn heal effect and number
            vfx_manager.spawnHeal(tgt.position);
            vfx_manager.spawnDamageNumber(healing_amount, tgt.position, .heal);

            print("{s} healed {s} for {d:.1}! ({d:.1}/{d:.1} HP)\n", .{
                caster.name,
                tgt.name,
                healing_amount,
                tgt.warmth,
                tgt.max_warmth,
            });
        }

        // Apply chills (debuffs)
        for (skill.chills) |chill_effect| {
            // Check if target has snow goggles (immune to frost_eyes)
            if (chill_effect.chill == .frost_eyes and tgt.hasCozy(.snow_goggles)) {
                print("{s}'s Snow Goggles protected from Frost Eyes!\n", .{tgt.name});
                continue;
            }

            tgt.addChill(chill_effect, null); // TODO: add character IDs
            print("{s} applied {s} to {s} for {d}ms\n", .{
                caster.name,
                @tagName(chill_effect.chill),
                tgt.name,
                chill_effect.duration_ms,
            });
        }

        // Apply cozies (buffs)
        for (skill.cozies) |cozy_effect| {
            tgt.addCozy(cozy_effect, null); // TODO: add character IDs
            print("{s} gave {s} {s} for {d}ms\n", .{
                caster.name,
                tgt.name,
                @tagName(cozy_effect.cozy),
                cozy_effect.duration_ms,
            });
        }

        // Apply new composable effects
        for (skill.effects) |effect| {
            // Check if condition is met
            const caster_hp_percent = caster.warmth / caster.max_warmth;
            const target_hp_percent = tgt.warmth / tgt.max_warmth;
            if (!effects.evaluateCondition(effect.condition, caster_hp_percent, target_hp_percent)) {
                continue;
            }

            // Apply effect to target
            tgt.addEffect(&effect, caster.id);

            print("{s} applied effect {s} to {s} for {d}ms\n", .{
                caster.name,
                effect.name,
                tgt.name,
                effect.duration_ms,
            });
        }

        // Handle AoE
        if (skill.aoe_type == .adjacent) {
            // TODO: implement adjacent target finding
        } else if (skill.aoe_type == .area) {
            // TODO: implement area damage
        }
    } else if (skill.target_type == .self) {
        // Self-targeted skill
        if (skill.healing > 0) {
            caster.warmth = @min(caster.max_warmth, caster.warmth + skill.healing);

            // Spawn heal effect
            vfx_manager.spawnHeal(caster.position);
            vfx_manager.spawnDamageNumber(skill.healing, caster.position, .heal);

            print("{s} healed self for {d:.1}!\n", .{ caster.name, skill.healing });
        }

        // Apply self-buffs (cozies)
        for (skill.cozies) |cozy_effect| {
            caster.addCozy(cozy_effect, null);
            print("{s} gained {s} for {d}ms\n", .{
                caster.name,
                @tagName(cozy_effect.cozy),
                cozy_effect.duration_ms,
            });
        }

        // Apply self-debuffs (chills) - some skills might have drawbacks
        for (skill.chills) |chill_effect| {
            caster.addChill(chill_effect, null);
            print("{s} gained {s} for {d}ms\n", .{
                caster.name,
                @tagName(chill_effect.chill),
                chill_effect.duration_ms,
            });
        }
    } else if (skill.target_type == .ground) {
        // Ground-targeted skill
        // Target position is stored in target character's position if provided
        const ground_pos = if (target) |tgt| tgt.position else caster.position;

        print("{s} used {s} on ground at ({d:.1}, {d:.1})\n", .{
            caster.name,
            skill.name,
            ground_pos.x,
            ground_pos.z,
        });

        // Apply terrain effects (COMPOSITIONAL)
        const effect = skill.terrain_effect;
        if (effect.terrain_type) |terrain_type| {
            switch (effect.shape) {
                .none => {},
                .circle => {
                    terrain_grid.setTerrainInRadius(ground_pos.x, ground_pos.z, skill.aoe_radius, terrain_type);
                    print("  -> Created {s} circle (radius {d:.1})\n", .{ @tagName(terrain_type), skill.aoe_radius });
                },
                .cone => {
                    // TODO: Implement cone shape (from caster toward target)
                    terrain_grid.setTerrainInRadius(ground_pos.x, ground_pos.z, skill.aoe_radius, terrain_type);
                    print("  -> Created {s} cone (radius {d:.1})\n", .{ @tagName(terrain_type), skill.aoe_radius });
                },
                .line => {
                    // TODO: Implement line shape (from caster to target)
                    terrain_grid.setTerrainInRadius(ground_pos.x, ground_pos.z, skill.aoe_radius, terrain_type);
                    print("  -> Created {s} line (radius {d:.1})\n", .{ @tagName(terrain_type), skill.aoe_radius });
                },
                .ring => {
                    // TODO: Implement ring shape (donut)
                    terrain_grid.setTerrainInRadius(ground_pos.x, ground_pos.z, skill.aoe_radius, terrain_type);
                    print("  -> Created {s} ring (radius {d:.1})\n", .{ @tagName(terrain_type), skill.aoe_radius });
                },
                .trail => {
                    // Trails are created during movement, not on cast
                    // This is handled elsewhere (movement system)
                    print("  -> Enabled {s} trail effect\n", .{@tagName(terrain_type)});
                },
                .square => {
                    // TODO: Implement square shape
                    terrain_grid.setTerrainInRadius(ground_pos.x, ground_pos.z, skill.aoe_radius, terrain_type);
                    print("  -> Created {s} square (radius {d:.1})\n", .{ @tagName(terrain_type), skill.aoe_radius });
                },
                .cross => {
                    // TODO: Implement cross shape
                    terrain_grid.setTerrainInRadius(ground_pos.x, ground_pos.z, skill.aoe_radius, terrain_type);
                    print("  -> Created {s} cross (radius {d:.1})\n", .{ @tagName(terrain_type), skill.aoe_radius });
                },
            }
        }

        // Build walls (perpendicular to caster facing)
        if (skill.creates_wall) {
            // Calculate facing angle from caster to ground position
            const dx = ground_pos.x - caster.position.x;
            const dz = ground_pos.z - caster.position.z;
            const facing_angle = std.math.atan2(dz, dx);

            terrain_grid.buildWallPerpendicular(
                caster.position.x,
                caster.position.z,
                facing_angle,
                skill.wall_distance_from_caster,
                skill.wall_length,
                skill.wall_height,
                skill.wall_thickness,
                caster.team,
            );

            print("  -> Built {d:.0}x{d:.0} wall\n", .{ skill.wall_length, skill.wall_height });
        }

        // Damage walls in area
        if (skill.destroys_walls and skill.aoe_radius > 0) {
            const wall_damage = skill.damage * skill.wall_damage_multiplier;
            terrain_grid.damageWallsInRadius(ground_pos.x, ground_pos.z, skill.aoe_radius, wall_damage);
            print("  -> Damaged walls for {d:.1}\n", .{wall_damage});
        }
    } else {
        // Non-targeted skills (shouldn't normally happen, but handle for completeness)
        // Build walls in front of caster if this is a self-targeted wall skill
        if (skill.creates_wall) {
            // Default facing forward (0 radians = east)
            const facing_angle = 0.0;
            terrain_grid.buildWallPerpendicular(
                caster.position.x,
                caster.position.z,
                facing_angle,
                skill.wall_distance_from_caster,
                skill.wall_length,
                skill.wall_height,
                skill.wall_thickness,
                caster.team,
            );

            print("{s} built {d:.0}x{d:.0} wall\n", .{ caster.name, skill.wall_length, skill.wall_height });
        }
    }
}
