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

const Character = character.Character;
const EntityId = entity_types.EntityId;
const print = std.debug.print;

/// Process auto-attacks for all characters (called every tick)
pub fn updateAutoAttacks(entities: []Character, delta_time: f32, rng: *std.Random, vfx_manager: *vfx.VFXManager) void {
    for (entities) |*ent| {
        if (!ent.isAlive()) continue;
        if (!ent.is_auto_attacking) continue;

        // Can't auto-attack while casting or in aftercast
        if (ent.isCasting()) continue;

        // Update attack timer
        ent.auto_attack_timer -= delta_time;

        // Time to attack?
        if (ent.auto_attack_timer <= 0) {
            // Try to execute auto-attack
            if (tryAutoAttack(ent, entities, rng, vfx_manager)) {
                // Reset timer for next attack
                ent.auto_attack_timer = ent.getAttackInterval();
            } else {
                // Failed to attack (out of range, target dead, etc.)
                // Try again next tick
                ent.auto_attack_timer = 0.1; // Small delay before retry
            }
        }
    }
}

/// Attempt to execute an auto-attack
fn tryAutoAttack(attacker: *Character, entities: []Character, rng: *std.Random, vfx_manager: *vfx.VFXManager) bool {
    const target_id = attacker.auto_attack_target_id orelse {
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

    // Determine if ranged or melee (for now, default to ranged projectile)
    // TODO: Add equipment field to Character and check attacker.equipment.is_ranged
    const is_ranged = true;

    // Spawn projectile visual
    const color = if (attacker.is_enemy) rl.Color.orange else rl.Color.white;
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
        for (target.active_cozies[0..target.active_cozy_count]) |*maybe_cozy| {
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
        target.warmth,
        target.max_warmth,
    });

    // Check if target is Dazed - if so, damage interrupts
    if (target.hasChill(.dazed)) {
        target.interrupt();
    }

    // Build grit stacks for Public School characters (like adrenaline in GW1)
    if (attacker.school == .public_school) {
        if (attacker.grit_stacks < attacker.max_grit_stacks) {
            attacker.grit_stacks += 1;
        }
    }
}
