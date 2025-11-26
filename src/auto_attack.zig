// Auto-attack system (Guild Wars 1 style)
//
// In GW1, auto-attacks are basic weapon swings that:
// - Cost no energy
// - Have timing based on weapon type
// - Continue automatically until stopped or target dies
// - Build adrenaline (we use grit stacks instead)

const std = @import("std");
const rl = @import("raylib");
const character = @import("character.zig");
const entity_types = @import("entity.zig");
const vfx = @import("vfx.zig");
const palette = @import("color_palette.zig");
const school_resources = @import("character_school_resources.zig");

const Character = character.Character;
const EntityId = entity_types.EntityId;
const print = std.debug.print;

/// Process auto-attacks for all characters (called every tick)
pub fn updateAutoAttacks(entities: []Character, delta_time: f32, rng: *std.Random, vfx_manager: *vfx.VFXManager) void {
    for (entities) |*ent| {
        if (!ent.isAlive()) continue;

        // Update lunge animation (return to position after lunge)
        if (ent.combat.melee_lunge.time_remaining > 0) {
            ent.combat.melee_lunge.time_remaining -= delta_time;

            // When lunge expires, smoothly return to original position
            if (ent.combat.melee_lunge.time_remaining <= 0) {
                // Interpolate back to return position over the next tick
                const lerp_factor: f32 = 0.3; // 30% per tick = smooth return
                ent.position.x += (ent.combat.melee_lunge.return_position_x - ent.position.x) * lerp_factor;
                ent.position.z += (ent.combat.melee_lunge.return_position_z - ent.position.z) * lerp_factor;

                // If very close, snap to return position
                const dist_to_return = @sqrt((ent.position.x - ent.combat.melee_lunge.return_position_x) * (ent.position.x - ent.combat.melee_lunge.return_position_x) +
                    (ent.position.z - ent.combat.melee_lunge.return_position_z) * (ent.position.z - ent.combat.melee_lunge.return_position_z));
                if (dist_to_return < 1.0) {
                    ent.position.x = ent.combat.melee_lunge.return_position_x;
                    ent.position.y = ent.combat.melee_lunge.return_position_y;
                    ent.position.z = ent.combat.melee_lunge.return_position_z;
                }
            }
        }

        if (!ent.combat.auto_attack.is_active) continue;

        // Can't auto-attack while casting or in aftercast
        if (ent.isCasting()) continue;

        // Update attack timer
        ent.combat.auto_attack.timer -= delta_time;

        // Time to attack?
        if (ent.combat.auto_attack.timer <= 0) {
            // Try to execute auto-attack
            if (tryAutoAttack(ent, entities, rng, vfx_manager)) {
                // Reset timer for next attack
                ent.combat.auto_attack.timer = ent.getAttackInterval();
            } else {
                // Failed to attack (out of range, target dead, etc.)
                // Try again next tick
                ent.combat.auto_attack.timer = 0.1; // Small delay before retry
            }
        }
    }
}

/// Attempt to execute an auto-attack
fn tryAutoAttack(attacker: *Character, entities: []Character, rng: *std.Random, vfx_manager: *vfx.VFXManager) bool {
    const target_id = attacker.combat.auto_attack.target_id orelse {
        // No target set, stop auto-attacking
        attacker.stopAutoAttack();
        return false;
    };

    // Find target entity
    var target: ?*Character = null;
    for (entities) |*ent| {
        if (ent.id == target_id) {
            target = ent;
            break;
        }
    }

    const tgt = target orelse {
        // Target not found, stop auto-attacking
        attacker.stopAutoAttack();
        return false;
    };

    // Check if target is alive
    if (!tgt.isAlive()) {
        print("{s}'s auto-attack target is dead\n", .{attacker.name});
        attacker.stopAutoAttack();
        return false;
    }

    // Check range
    const distance = attacker.distanceTo(tgt.*);
    const attack_range = attacker.getAutoAttackRange();
    if (distance > attack_range) {
        print("{s} out of range for auto-attack ({d:.1}/{d:.1})\n", .{ attacker.name, distance, attack_range });
        return false;
    }

    // Execute the auto-attack
    executeAutoAttack(attacker, tgt, rng, vfx_manager);
    return true;
}

/// Execute an auto-attack (deal damage)
fn executeAutoAttack(attacker: *Character, target: *Character, rng: *std.Random, vfx_manager: *vfx.VFXManager) void {
    // For melee attacks, create a brief lunge towards target
    const is_ranged = attacker.hasRangedAutoAttack();
    if (!is_ranged) {
        // Calculate direction to target
        const dx = target.position.x - attacker.position.x;
        const dz = target.position.z - attacker.position.z;
        const distance = @sqrt(dx * dx + dz * dz);

        if (distance > 0.1) {
            // Quick lunge forward (40% of distance, max 25 units for more visibility)
            const lunge_amount = @min(distance * 0.4, 25.0);
            print("{s} MELEE LUNGE: {d:.1} units towards {s}\n", .{
                attacker.name,
                lunge_amount,
                target.name,
            });

            // Save current position to return to
            attacker.combat.melee_lunge.return_position_x = attacker.position.x;
            attacker.combat.melee_lunge.return_position_y = attacker.position.y;
            attacker.combat.melee_lunge.return_position_z = attacker.position.z;

            // Lunge towards target
            attacker.position.x += (dx / distance) * lunge_amount;
            attacker.position.z += (dz / distance) * lunge_amount;

            // Set lunge duration (should last 2-3 frames at 60fps = 0.033-0.05 sec)
            attacker.combat.melee_lunge.time_remaining = 0.15; // 150ms lunge animation
        }
    }

    var damage = attacker.getAutoAttackDamage();

    // Apply chill (debuff) modifiers from attacker
    if (attacker.hasChill(.numb)) {
        damage *= 0.5; // Numb reduces damage by 50%
    }

    // Apply cozy (buff) modifiers from attacker
    if (attacker.hasCozy(.fire_inside)) {
        damage *= 1.3; // Fire Inside increases damage by 30%
    }

    // Apply target's defensive cozies
    if (target.hasCozy(.bundled_up)) {
        damage *= 0.75; // Bundled Up reduces incoming damage by 25%
    }

    // Spawn projectile visual
    const color = if (attacker.team == .blue) palette.VFX.PROJECTILE_AUTO_ENEMY else palette.VFX.PROJECTILE_AUTO_ALLY;
    vfx_manager.spawnProjectile(attacker.position, target.position, attacker.id, target.id, is_ranged, color);

    // Apply miss chance from chills
    if (attacker.hasChill(.frost_eyes)) {
        // 50% miss chance
        const rand = rng.intRangeAtMost(u8, 0, 99);
        if (rand < 50) {
            vfx_manager.spawnDamageNumber(0, target.position, .miss);
            print("{s} auto-attack missed {s} due to Frost Eyes!\n", .{ attacker.name, target.name });
            return;
        }
    }

    // Check if target blocks with snowball shield
    if (target.hasCozy(.snowball_shield)) {
        print("{s}'s Snowball Shield blocked {s}'s auto-attack!\n", .{ target.name, attacker.name });
        // Remove the shield after blocking
        for (target.conditions.cozies.cozies[0..target.conditions.cozies.count]) |*maybe_cozy| {
            if (maybe_cozy.*) |*cozy| {
                if (cozy.cozy == .snowball_shield) {
                    maybe_cozy.* = null;
                    break;
                }
            }
        }
        return;
    }

    // Deal damage
    target.takeDamage(damage);

    // Spawn damage number
    vfx_manager.spawnDamageNumber(damage, target.position, .damage);

    print("{s} auto-attacked {s} for {d:.1} damage! ({d:.1}/{d:.1} HP)\n", .{
        attacker.name,
        target.name,
        damage,
        target.stats.warmth,
        target.stats.max_warmth,
    });

    // Check if target is Dazed - if so, damage interrupts
    if (target.hasChill(.dazed)) {
        target.interrupt();
    }

    // Build grit stacks for Public School characters (like adrenaline in GW1)
    if (attacker.school == .public_school) {
        if (attacker.school_resources.grit.stacks < school_resources.MAX_GRIT_STACKS) {
            attacker.school_resources.grit.stacks += 1;
        }
    }
}
