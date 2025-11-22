const std = @import("std");
const rl = @import("raylib");
const character = @import("character.zig");
const skills = @import("skills.zig");
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

pub fn tryStartCast(caster: *Character, skill_index: u8, target: ?*Character, target_id: ?EntityId, rng: *std.Random, vfx_manager: *vfx.VFXManager) CastResult {
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
        executeSkill(caster, skill, target, skill_index, rng, vfx_manager);
        caster.cast_target_id = null; // Clear target
        return .success;
    }

    return .casting_started;
}

pub fn executeSkill(caster: *Character, skill: *const Skill, target: ?*Character, skill_index: u8, rng: *std.Random, vfx_manager: *vfx.VFXManager) void {
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

        // Apply soak (penetrates padding/layers)
        if (skill.soak > 0) {
            // TODO: implement padding system and soak mechanic
        }

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

        // Spawn projectile visual (skill is always "ranged" for now, instant travel)
        const color = if (caster.is_enemy) palette.VFX.PROJECTILE_ENEMY else palette.VFX.PROJECTILE_ALLY;
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
    }
}
